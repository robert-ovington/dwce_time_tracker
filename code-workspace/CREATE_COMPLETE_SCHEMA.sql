-- ============================================================================
-- Complete Schema Creation Script
-- ============================================================================
-- This script creates the complete normalized time periods schema.
-- Since existing tables contain no data, we drop and recreate everything.
--
-- Run this script in Supabase SQL Editor or your PostgreSQL client.
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 0: Check Referenced Table Structures
-- ============================================================================

-- First, let's check what the primary key is on users_data
DO $$
DECLARE
  users_pk_column TEXT;
  users_table_exists BOOLEAN;
BEGIN
  -- Check if users_data table exists
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'users_data'
  ) INTO users_table_exists;
  
  IF NOT users_table_exists THEN
    RAISE EXCEPTION 'Table users_data does not exist. Please create it first.';
  END IF;
  
  -- Get the primary key column name
  SELECT a.attname INTO users_pk_column
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = 'public.users_data'::regclass
    AND i.indisprimary
  LIMIT 1;
  
  IF users_pk_column IS NULL THEN
    RAISE EXCEPTION 'Table users_data has no primary key. Cannot create foreign keys.';
  END IF;
  
  RAISE NOTICE 'Found primary key on users_data: %', users_pk_column;
  
  -- If it's not user_id, we need to adjust
  IF users_pk_column != 'user_id' THEN
    RAISE WARNING 'Primary key is %, not user_id. Foreign keys will reference %', users_pk_column, users_pk_column;
  END IF;
END $$;

-- ============================================================================
-- STEP 1: Drop Existing Tables (if they exist)
-- ============================================================================

DROP TABLE IF EXISTS public.time_used_large_plant CASCADE;
DROP TABLE IF EXISTS public.time_mobilised_large_plant CASCADE;
DROP TABLE IF EXISTS public.time_period_revision CASCADE;
DROP TABLE IF EXISTS public.time_periods CASCADE;

-- ============================================================================
-- STEP 2: Create Main Time Periods Table
-- ============================================================================

CREATE TABLE public.time_periods (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  project_id UUID NULL,
  mechanic_large_plant_id UUID NULL,
  
  -- Core time tracking
  work_date DATE NOT NULL,
  start_time TIMESTAMP WITH TIME ZONE NULL,
  finish_time TIMESTAMP WITH TIME ZONE NULL,
  
  -- Approval workflow status
  status public.approval_status NOT NULL DEFAULT 'draft'::approval_status,
  
  -- Approval tracking
  submitted_at TIMESTAMP WITH TIME ZONE NULL,
  submitted_by UUID NULL,
  supervisor_id UUID NULL,
  supervisor_approved_at TIMESTAMP WITH TIME ZONE NULL,
  supervisor_edited_before_approval BOOLEAN NULL DEFAULT false,
  admin_id UUID NULL,
  admin_approved_at TIMESTAMP WITH TIME ZONE NULL,
  admin_edited_before_approval BOOLEAN NULL DEFAULT false,
  approved_by UUID NULL,
  approved_at TIMESTAMP WITH TIME ZONE NULL,
  
  -- Travel allowances (stored as minutes)
  travel_to_site_min INTEGER NULL DEFAULT 0,
  travel_from_site_min INTEGER NULL DEFAULT 0,
  distance_from_home NUMERIC(10, 2) NULL,
  travel_time_text TEXT NULL,
  
  -- Other allowances
  on_call BOOLEAN NULL DEFAULT false,
  misc_allowance_min INTEGER NULL DEFAULT 0,
  allowance_holiday_hours_min INTEGER NULL DEFAULT 0,
  allowance_non_worked_ft_min INTEGER NULL DEFAULT 0,
  allowance_non_worked_th_min INTEGER NULL DEFAULT 0,
  allowance_non_worked_dt_min INTEGER NULL DEFAULT 0,
  
  -- Absenteeism
  user_absenteeism_reason TEXT NULL,
  absenteeism_notice_date DATE NULL,
  supervisor_absenteeism_reason TEXT NULL,
  
  -- Concrete/Materials
  concrete_ticket_no INTEGER NULL,
  concrete_mix_type TEXT NULL,
  concrete_qty NUMERIC(10, 2) NULL,
  
  -- Submission metadata
  comments TEXT NULL,
  submission_lat DOUBLE PRECISION NULL,
  submission_lng DOUBLE PRECISION NULL,
  submission_gps_accuracy INTEGER NULL,
  submission_datetime TIMESTAMP WITH TIME ZONE NULL DEFAULT now(),
  
  -- Revision tracking
  revision_number INTEGER NOT NULL DEFAULT 0,
  last_revised_at TIMESTAMP WITH TIME ZONE NULL,
  last_revised_by UUID NULL,
  
  -- Offline support
  offline_created BOOLEAN NULL DEFAULT false,
  synced BOOLEAN NULL DEFAULT false,
  offline_id TEXT NULL,
  
  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_periods_pkey PRIMARY KEY (id)
) TABLESPACE pg_default;

-- Add foreign keys separately (after table creation)
-- This allows us to handle cases where the primary key might be different
DO $$
DECLARE
  users_pk_column TEXT;
  projects_pk_column TEXT;
  large_plant_pk_column TEXT;
BEGIN
  -- Get primary key column for users_data
  SELECT a.attname INTO users_pk_column
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = 'public.users_data'::regclass
    AND i.indisprimary
  LIMIT 1;
  
  -- Get primary key column for projects
  SELECT a.attname INTO projects_pk_column
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = 'public.projects'::regclass
    AND i.indisprimary
  LIMIT 1;
  
  -- Get primary key column for large_plant
  SELECT a.attname INTO large_plant_pk_column
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = 'public.large_plant'::regclass
    AND i.indisprimary
  LIMIT 1;
  
  -- Add foreign keys using the actual primary key columns
  IF users_pk_column IS NOT NULL THEN
    -- Check if user_id column exists and matches the PK, or if we need to use the PK directly
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = 'public' AND table_name = 'users_data' AND column_name = 'user_id') THEN
      -- If user_id exists, try to create FK to it (might be unique even if not PK)
      BEGIN
        ALTER TABLE public.time_periods
          ADD CONSTRAINT time_periods_user_id_fkey 
          FOREIGN KEY (user_id) 
          REFERENCES public.users_data(user_id) ON DELETE RESTRICT;
        RAISE NOTICE 'Created foreign key: time_periods.user_id -> users_data.user_id';
      EXCEPTION WHEN OTHERS THEN
        -- If that fails, try using the PK column
        EXECUTE format('ALTER TABLE public.time_periods ADD CONSTRAINT time_periods_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users_data(%I) ON DELETE RESTRICT', users_pk_column);
        RAISE NOTICE 'Created foreign key: time_periods.user_id -> users_data.%', users_pk_column;
      END;
      
      -- Add other user-related foreign keys
      BEGIN
        ALTER TABLE public.time_periods
          ADD CONSTRAINT time_periods_submitted_by_fkey 
          FOREIGN KEY (submitted_by) 
          REFERENCES public.users_data(user_id) ON DELETE SET NULL;
        ALTER TABLE public.time_periods
          ADD CONSTRAINT time_periods_supervisor_id_fkey 
          FOREIGN KEY (supervisor_id) 
          REFERENCES public.users_data(user_id) ON DELETE SET NULL;
        ALTER TABLE public.time_periods
          ADD CONSTRAINT time_periods_admin_id_fkey 
          FOREIGN KEY (admin_id) 
          REFERENCES public.users_data(user_id) ON DELETE SET NULL;
        ALTER TABLE public.time_periods
          ADD CONSTRAINT time_periods_last_revised_by_fkey 
          FOREIGN KEY (last_revised_by) 
          REFERENCES public.users_data(user_id) ON DELETE SET NULL;
        RAISE NOTICE 'Created all user-related foreign keys';
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Could not create all user foreign keys: %', SQLERRM;
      END;
    END IF;
  END IF;
  
  -- Add project foreign key
  IF projects_pk_column IS NOT NULL THEN
    BEGIN
      EXECUTE format('ALTER TABLE public.time_periods ADD CONSTRAINT time_periods_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(%I) ON DELETE SET NULL', projects_pk_column);
      RAISE NOTICE 'Created foreign key: time_periods.project_id -> projects.%', projects_pk_column;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Could not create project foreign key: %', SQLERRM;
    END;
  END IF;
  
  -- Add large_plant foreign key
  IF large_plant_pk_column IS NOT NULL THEN
    BEGIN
      EXECUTE format('ALTER TABLE public.time_periods ADD CONSTRAINT time_periods_mechanic_large_plant_id_fkey FOREIGN KEY (mechanic_large_plant_id) REFERENCES public.large_plant(%I) ON DELETE SET NULL', large_plant_pk_column);
      RAISE NOTICE 'Created foreign key: time_periods.mechanic_large_plant_id -> large_plant.%', large_plant_pk_column;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Could not create large_plant foreign key: %', SQLERRM;
    END;
  END IF;
END $$;

-- Add check constraints for time_periods
ALTER TABLE public.time_periods
  ADD CONSTRAINT time_periods_finish_after_start CHECK (
    finish_time IS NULL OR start_time IS NULL OR finish_time >= start_time
  );

ALTER TABLE public.time_periods
  ADD CONSTRAINT time_periods_same_day CHECK (
    finish_time IS NULL OR start_time IS NULL OR 
    DATE(finish_time) = DATE(start_time)
  );

-- ============================================================================
-- STEP 3: Create Related Tables
-- ============================================================================

-- Breaks Table
CREATE TABLE public.time_period_breaks (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  break_start TIMESTAMP WITH TIME ZONE NOT NULL,
  break_finish TIMESTAMP WITH TIME ZONE NULL,
  break_reason TEXT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_breaks_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_breaks_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_breaks_finish_after_start CHECK (
    break_finish IS NULL OR break_start IS NULL OR break_finish >= break_start
  )
) TABLESPACE pg_default;

-- Used Fleet Table
CREATE TABLE public.time_period_used_fleet (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  large_plant_id UUID NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_used_fleet_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_used_fleet_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_used_fleet_unique_per_period UNIQUE (time_period_id, large_plant_id)
) TABLESPACE pg_default;

-- Add large_plant foreign key separately
DO $$
DECLARE
  large_plant_pk_column TEXT;
BEGIN
  SELECT a.attname INTO large_plant_pk_column
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = 'public.large_plant'::regclass
    AND i.indisprimary
  LIMIT 1;
  
  IF large_plant_pk_column IS NOT NULL THEN
    BEGIN
      EXECUTE format('ALTER TABLE public.time_period_used_fleet ADD CONSTRAINT time_period_used_fleet_large_plant_id_fkey FOREIGN KEY (large_plant_id) REFERENCES public.large_plant(%I) ON DELETE RESTRICT', large_plant_pk_column);
      RAISE NOTICE 'Created foreign key: time_period_used_fleet.large_plant_id -> large_plant.%', large_plant_pk_column;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Could not create large_plant foreign key for used_fleet: %', SQLERRM;
    END;
  END IF;
END $$;

-- Mobilised Fleet Table
CREATE TABLE public.time_period_mobilised_fleet (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  large_plant_id UUID NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_mobilised_fleet_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_mobilised_fleet_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_mobilised_fleet_unique_per_period UNIQUE (time_period_id, large_plant_id)
) TABLESPACE pg_default;

-- Add large_plant foreign key separately
DO $$
DECLARE
  large_plant_pk_column TEXT;
BEGIN
  SELECT a.attname INTO large_plant_pk_column
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = 'public.large_plant'::regclass
    AND i.indisprimary
  LIMIT 1;
  
  IF large_plant_pk_column IS NOT NULL THEN
    BEGIN
      EXECUTE format('ALTER TABLE public.time_period_mobilised_fleet ADD CONSTRAINT time_period_mobilised_fleet_large_plant_id_fkey FOREIGN KEY (large_plant_id) REFERENCES public.large_plant(%I) ON DELETE RESTRICT', large_plant_pk_column);
      RAISE NOTICE 'Created foreign key: time_period_mobilised_fleet.large_plant_id -> large_plant.%', large_plant_pk_column;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Could not create large_plant foreign key for mobilised_fleet: %', SQLERRM;
    END;
  END IF;
END $$;

-- Pay Rates Table (15-minute increment validation)
CREATE TABLE public.time_period_pay_rates (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  pay_rate_type TEXT NOT NULL,
  hours NUMERIC(10, 2) NOT NULL DEFAULT 0,
  minutes INTEGER NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_pay_rates_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_pay_rates_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_pay_rates_unique_per_period UNIQUE (time_period_id, pay_rate_type),
  CONSTRAINT time_period_pay_rates_type_check CHECK (
    pay_rate_type IN ('ft', 'th', 'dt', 'ft_non_worked', 'th_non_worked', 'dt_non_worked', 'holiday_hours')
  ),
  CONSTRAINT time_period_pay_rates_hours_positive CHECK (hours >= 0),
  CONSTRAINT time_period_pay_rates_minutes_valid CHECK (
    minutes IS NULL OR minutes IN (0, 15, 30, 45)
  ),
  CONSTRAINT time_period_pay_rates_15min_increment CHECK (
    (hours * 4)::INTEGER = (hours * 4) AND
    (minutes IS NULL OR minutes IN (0, 15, 30, 45))
  )
) TABLESPACE pg_default;

-- Revisions Table
CREATE TABLE public.time_period_revisions (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  revision_number INTEGER NOT NULL,
  changed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  changed_by UUID NOT NULL,
  changed_by_name TEXT NULL,
  changed_by_role TEXT NULL,
  change_type TEXT NOT NULL,
  workflow_stage TEXT NOT NULL,
  field_name TEXT NOT NULL,
  old_value TEXT NULL,
  new_value TEXT NULL,
  change_reason TEXT NULL,
  is_revision BOOLEAN NOT NULL DEFAULT false,
  is_approval BOOLEAN NOT NULL DEFAULT false,
  is_edit BOOLEAN NOT NULL DEFAULT false,
  original_submission BOOLEAN NOT NULL DEFAULT false,
  
  CONSTRAINT time_period_revisions_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_revisions_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_revisions_change_type_check CHECK (
    change_type IN ('user_edit', 'supervisor_edit', 'admin_edit', 
                    'supervisor_approval', 'admin_approval', 'user_submission')
  ),
  CONSTRAINT time_period_revisions_workflow_stage_check CHECK (
    workflow_stage IN ('draft', 'submitted', 'supervisor_review', 'admin_review', 'approved')
  )
) TABLESPACE pg_default;

-- Add foreign key for changed_by separately
DO $$
DECLARE
  users_pk_column TEXT;
BEGIN
  SELECT a.attname INTO users_pk_column
  FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
  WHERE i.indrelid = 'public.users_data'::regclass
    AND i.indisprimary
  LIMIT 1;
  
  IF users_pk_column IS NOT NULL THEN
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_schema = 'public' AND table_name = 'users_data' AND column_name = 'user_id') THEN
        BEGIN
          ALTER TABLE public.time_period_revisions
            ADD CONSTRAINT time_period_revisions_changed_by_fkey 
            FOREIGN KEY (changed_by) 
            REFERENCES public.users_data(user_id) ON DELETE RESTRICT;
          RAISE NOTICE 'Created foreign key: time_period_revisions.changed_by -> users_data.user_id';
        EXCEPTION WHEN OTHERS THEN
          EXECUTE format('ALTER TABLE public.time_period_revisions ADD CONSTRAINT time_period_revisions_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users_data(%I) ON DELETE RESTRICT', users_pk_column);
          RAISE NOTICE 'Created foreign key: time_period_revisions.changed_by -> users_data.%', users_pk_column;
        END;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Could not create changed_by foreign key: %', SQLERRM;
    END;
  END IF;
END $$;

-- ============================================================================
-- STEP 4: Create Indexes
-- ============================================================================

-- Time Periods Indexes
CREATE INDEX idx_time_periods_user_id ON public.time_periods USING btree (user_id);
CREATE INDEX idx_time_periods_project_id ON public.time_periods USING btree (project_id);
CREATE INDEX idx_time_periods_work_date ON public.time_periods USING btree (work_date DESC);
CREATE INDEX idx_time_periods_status ON public.time_periods USING btree (status);
CREATE INDEX idx_time_periods_submitted_at ON public.time_periods USING btree (submitted_at DESC) WHERE submitted_at IS NOT NULL;
CREATE INDEX idx_time_periods_supervisor_pending ON public.time_periods USING btree (status, submitted_at) WHERE status = 'submitted';
CREATE INDEX idx_time_periods_mechanic_large_plant_id ON public.time_periods USING btree (mechanic_large_plant_id);
CREATE INDEX idx_time_periods_offline_sync ON public.time_periods USING btree (offline_created, synced) WHERE offline_created = true AND synced = false;

-- Breaks Indexes
CREATE INDEX idx_time_period_breaks_time_period_id ON public.time_period_breaks USING btree (time_period_id);
CREATE INDEX idx_time_period_breaks_display_order ON public.time_period_breaks USING btree (time_period_id, display_order);

-- Used Fleet Indexes
CREATE INDEX idx_time_period_used_fleet_time_period_id ON public.time_period_used_fleet USING btree (time_period_id);
CREATE INDEX idx_time_period_used_fleet_large_plant_id ON public.time_period_used_fleet USING btree (large_plant_id);
CREATE INDEX idx_time_period_used_fleet_display_order ON public.time_period_used_fleet USING btree (time_period_id, display_order);

-- Mobilised Fleet Indexes
CREATE INDEX idx_time_period_mobilised_fleet_time_period_id ON public.time_period_mobilised_fleet USING btree (time_period_id);
CREATE INDEX idx_time_period_mobilised_fleet_large_plant_id ON public.time_period_mobilised_fleet USING btree (large_plant_id);
CREATE INDEX idx_time_period_mobilised_fleet_display_order ON public.time_period_mobilised_fleet USING btree (time_period_id, display_order);

-- Pay Rates Indexes
CREATE INDEX idx_time_period_pay_rates_time_period_id ON public.time_period_pay_rates USING btree (time_period_id);
CREATE INDEX idx_time_period_pay_rates_type ON public.time_period_pay_rates USING btree (pay_rate_type);
CREATE INDEX idx_time_period_pay_rates_time_period_type ON public.time_period_pay_rates USING btree (time_period_id, pay_rate_type);

-- Revisions Indexes
CREATE INDEX idx_time_period_revisions_time_period_id ON public.time_period_revisions USING btree (time_period_id);
CREATE INDEX idx_time_period_revisions_revision_number ON public.time_period_revisions USING btree (time_period_id, revision_number DESC);
CREATE INDEX idx_time_period_revisions_changed_at ON public.time_period_revisions USING btree (changed_at DESC);
CREATE INDEX idx_time_period_revisions_changed_by ON public.time_period_revisions USING btree (changed_by);
CREATE INDEX idx_time_period_revisions_is_revision ON public.time_period_revisions USING btree (time_period_id, is_revision) WHERE is_revision = true;
CREATE INDEX idx_time_period_revisions_change_type ON public.time_period_revisions USING btree (time_period_id, change_type);

-- ============================================================================
-- STEP 5: Update System Settings
-- ============================================================================

-- Add limit columns
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS max_breaks_per_period INTEGER NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS max_used_fleet_per_period INTEGER NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS max_mobilised_fleet_per_period INTEGER NULL DEFAULT 4;

-- Add constraints
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'system_settings_max_breaks_check') THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_breaks_check 
      CHECK (max_breaks_per_period IS NULL OR max_breaks_per_period > 0);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'system_settings_max_used_fleet_check') THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_used_fleet_check 
      CHECK (max_used_fleet_per_period IS NULL OR max_used_fleet_per_period > 0);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'system_settings_max_mobilised_fleet_check') THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_mobilised_fleet_check 
      CHECK (max_mobilised_fleet_per_period IS NULL OR max_mobilised_fleet_per_period > 0);
  END IF;
END $$;

-- Set default values
UPDATE public.system_settings
SET 
  max_breaks_per_period = COALESCE(max_breaks_per_period, 3),
  max_used_fleet_per_period = COALESCE(max_used_fleet_per_period, 6),
  max_mobilised_fleet_per_period = COALESCE(max_mobilised_fleet_per_period, 4)
WHERE max_breaks_per_period IS NULL 
   OR max_used_fleet_per_period IS NULL 
   OR max_mobilised_fleet_per_period IS NULL;

-- ============================================================================
-- STEP 6: Verification
-- ============================================================================

DO $$
DECLARE
  table_count INTEGER;
  index_count INTEGER;
  fk_count INTEGER;
BEGIN
  -- Count tables
  SELECT COUNT(*) INTO table_count
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN (
      'time_periods',
      'time_period_breaks',
      'time_period_used_fleet',
      'time_period_mobilised_fleet',
      'time_period_pay_rates',
      'time_period_revisions'
    );
  
  -- Count indexes
  SELECT COUNT(*) INTO index_count
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND tablename LIKE 'time_period%';
  
  -- Count foreign keys
  SELECT COUNT(*) INTO fk_count
  FROM information_schema.table_constraints
  WHERE table_schema = 'public'
    AND constraint_type = 'FOREIGN KEY'
    AND table_name LIKE 'time_period%';
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Schema Creation Summary:';
  RAISE NOTICE '  Tables Created: %', table_count;
  RAISE NOTICE '  Indexes Created: %', index_count;
  RAISE NOTICE '  Foreign Keys Created: %', fk_count;
  RAISE NOTICE '========================================';
  
  IF table_count != 6 THEN
    RAISE WARNING 'Expected 6 tables, found %', table_count;
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- SUCCESS!
-- ============================================================================
-- Schema creation complete. Next steps:
-- 1. Set up Row-Level Security (RLS) policies
-- 2. Update your Flutter application code
-- 3. Test the complete workflow
-- ============================================================================

