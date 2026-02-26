-- ============================================================================
-- Complete Migration Script: Normalized Time Periods Schema
-- Includes: Workflow, Pay Rates, and Configurable Limits
-- ============================================================================
-- This script migrates to a complete normalized schema that supports:
-- 1. 5-stage approval workflow
-- 2. Pay rate tracking (7 types)
-- 3. Configurable limits for breaks and fleet
--
-- IMPORTANT: Review and test this script in a development environment first!
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: Update time_periods Table with Workflow Fields
-- ============================================================================

-- Add workflow tracking columns
ALTER TABLE public.time_periods
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMP WITH TIME ZONE NULL,
  ADD COLUMN IF NOT EXISTS submitted_by UUID NULL,
  ADD COLUMN IF NOT EXISTS supervisor_edited_before_approval BOOLEAN NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS admin_edited_before_approval BOOLEAN NULL DEFAULT false,
  
  -- Add missing allowance fields
  ADD COLUMN IF NOT EXISTS supervisor_id UUID NULL,
  ADD COLUMN IF NOT EXISTS supervisor_approved_at TIMESTAMP WITH TIME ZONE NULL,
  ADD COLUMN IF NOT EXISTS admin_id UUID NULL,
  ADD COLUMN IF NOT EXISTS admin_approved_at TIMESTAMP WITH TIME ZONE NULL,
  ADD COLUMN IF NOT EXISTS user_absenteeism_reason TEXT NULL,
  ADD COLUMN IF NOT EXISTS absenteeism_notice_date DATE NULL,
  ADD COLUMN IF NOT EXISTS supervisor_absenteeism_reason TEXT NULL,
  ADD COLUMN IF NOT EXISTS allowance_holiday_hours_min INTEGER NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS allowance_non_worked_ft_min INTEGER NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS allowance_non_worked_th_min INTEGER NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS allowance_non_worked_dt_min INTEGER NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS submission_datetime TIMESTAMP WITH TIME ZONE NULL DEFAULT now();

-- Add foreign keys for new columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'time_periods_submitted_by_fkey'
  ) THEN
    ALTER TABLE public.time_periods
      ADD CONSTRAINT time_periods_submitted_by_fkey 
      FOREIGN KEY (submitted_by) 
      REFERENCES public.users_data(user_id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'time_periods_supervisor_id_fkey'
  ) THEN
    ALTER TABLE public.time_periods
      ADD CONSTRAINT time_periods_supervisor_id_fkey 
      FOREIGN KEY (supervisor_id) 
      REFERENCES public.users_data(user_id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'time_periods_admin_id_fkey'
  ) THEN
    ALTER TABLE public.time_periods
      ADD CONSTRAINT time_periods_admin_id_fkey 
      FOREIGN KEY (admin_id) 
      REFERENCES public.users_data(user_id) ON DELETE SET NULL;
  END IF;
END $$;

-- Add workflow indexes
CREATE INDEX IF NOT EXISTS idx_time_periods_submitted_at 
  ON public.time_periods USING btree (submitted_at DESC) 
  WHERE submitted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_time_periods_supervisor_pending 
  ON public.time_periods USING btree (status, submitted_at) 
  WHERE status = 'submitted';

-- ============================================================================
-- STEP 2: Create/Update Revision Table with Workflow Support
-- ============================================================================

-- Create new revision table with workflow support
CREATE TABLE IF NOT EXISTS public.time_period_revisions (
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
  CONSTRAINT time_period_revisions_changed_by_fkey FOREIGN KEY (changed_by) 
    REFERENCES public.users_data(user_id) ON DELETE RESTRICT,
  CONSTRAINT time_period_revisions_change_type_check CHECK (
    change_type IN ('user_edit', 'supervisor_edit', 'admin_edit', 
                    'supervisor_approval', 'admin_approval', 'user_submission')
  ),
  CONSTRAINT time_period_revisions_workflow_stage_check CHECK (
    workflow_stage IN ('draft', 'submitted', 'supervisor_review', 'admin_review', 'approved')
  )
) TABLESPACE pg_default;

-- Migrate data from old revision table (if exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables 
             WHERE table_schema = 'public' 
             AND table_name = 'time_period_revision') THEN
    
    INSERT INTO public.time_period_revisions (
      time_period_id,
      revision_number,
      changed_at,
      changed_by,
      changed_by_name,
      change_type,
      workflow_stage,
      field_name,
      old_value,
      new_value,
      change_reason,
      is_revision,
      original_submission
    )
    SELECT 
      tr.time_period_id,
      tr.revision_number,
      tr.changed_at,
      COALESCE(
        (SELECT user_id FROM users_data WHERE display_name = tr.user_name LIMIT 1),
        (SELECT user_id FROM users_setup WHERE display_name = tr.user_name LIMIT 1)
      ) as changed_by,
      tr.user_name as changed_by_name,
      CASE 
        WHEN tr.original_submission = true THEN 'user_submission'
        ELSE 'user_edit'
      END as change_type,
      'submitted' as workflow_stage,
      tr.field_name,
      tr.old_value,
      tr.new_value,
      tr.change_reason,
      true as is_revision,
      tr.original_submission
    FROM public.time_period_revision tr
    WHERE tr.time_period_id IS NOT NULL
    ON CONFLICT DO NOTHING;
    
    RAISE NOTICE 'Migrated % records from time_period_revision to time_period_revisions', 
      (SELECT COUNT(*) FROM public.time_period_revision);
  END IF;
END $$;

-- ============================================================================
-- STEP 3: Create Normalized Related Tables
-- ============================================================================

-- 3.1 Create breaks table
CREATE TABLE IF NOT EXISTS public.time_period_breaks (
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

-- 3.2 Create normalized used fleet table
CREATE TABLE IF NOT EXISTS public.time_period_used_fleet (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  large_plant_id UUID NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT time_period_used_fleet_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_used_fleet_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_used_fleet_large_plant_id_fkey FOREIGN KEY (large_plant_id) 
    REFERENCES public.large_plant(id) ON DELETE RESTRICT,
  CONSTRAINT time_period_used_fleet_unique_per_period UNIQUE (time_period_id, large_plant_id)
) TABLESPACE pg_default;

-- 3.3 Create normalized mobilised fleet table
CREATE TABLE IF NOT EXISTS public.time_period_mobilised_fleet (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  large_plant_id UUID NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT time_period_mobilised_fleet_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_mobilised_fleet_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_mobilised_fleet_large_plant_id_fkey FOREIGN KEY (large_plant_id) 
    REFERENCES public.large_plant(id) ON DELETE RESTRICT,
  CONSTRAINT time_period_mobilised_fleet_unique_per_period UNIQUE (time_period_id, large_plant_id)
) TABLESPACE pg_default;

-- 3.4 Create pay rates table (NEW)
-- Note: Minimum time increment is 15 minutes (0.25 hours)
CREATE TABLE IF NOT EXISTS public.time_period_pay_rates (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  pay_rate_type TEXT NOT NULL,
  hours NUMERIC(10, 2) NOT NULL DEFAULT 0, -- Must be multiple of 0.25
  minutes INTEGER NULL, -- Must be 0, 15, 30, or 45 if provided
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
  -- Ensure hours are multiples of 0.25 (15 minutes)
  CONSTRAINT time_period_pay_rates_15min_increment CHECK (
    (hours * 4)::INTEGER = (hours * 4) AND -- Hours must be multiple of 0.25
    (minutes IS NULL OR minutes IN (0, 15, 30, 45))
  )
) TABLESPACE pg_default;

-- ============================================================================
-- STEP 4: Create Indexes
-- ============================================================================

-- Breaks indexes
CREATE INDEX IF NOT EXISTS idx_time_period_breaks_time_period_id 
  ON public.time_period_breaks USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_breaks_display_order 
  ON public.time_period_breaks USING btree (time_period_id, display_order);

-- Used fleet indexes
CREATE INDEX IF NOT EXISTS idx_time_period_used_fleet_time_period_id 
  ON public.time_period_used_fleet USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_used_fleet_large_plant_id 
  ON public.time_period_used_fleet USING btree (large_plant_id);
CREATE INDEX IF NOT EXISTS idx_time_period_used_fleet_display_order 
  ON public.time_period_used_fleet USING btree (time_period_id, display_order);

-- Mobilised fleet indexes
CREATE INDEX IF NOT EXISTS idx_time_period_mobilised_fleet_time_period_id 
  ON public.time_period_mobilised_fleet USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_mobilised_fleet_large_plant_id 
  ON public.time_period_mobilised_fleet USING btree (large_plant_id);
CREATE INDEX IF NOT EXISTS idx_time_period_mobilised_fleet_display_order 
  ON public.time_period_mobilised_fleet USING btree (time_period_id, display_order);

-- Pay rates indexes
CREATE INDEX IF NOT EXISTS idx_time_period_pay_rates_time_period_id 
  ON public.time_period_pay_rates USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_pay_rates_type 
  ON public.time_period_pay_rates USING btree (pay_rate_type);
CREATE INDEX IF NOT EXISTS idx_time_period_pay_rates_time_period_type 
  ON public.time_period_pay_rates USING btree (time_period_id, pay_rate_type);

-- Revision indexes for reporting
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_time_period_id 
  ON public.time_period_revisions USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_revision_number 
  ON public.time_period_revisions USING btree (time_period_id, revision_number DESC);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_changed_at 
  ON public.time_period_revisions USING btree (changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_changed_by 
  ON public.time_period_revisions USING btree (changed_by);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_is_revision 
  ON public.time_period_revisions USING btree (time_period_id, is_revision) 
  WHERE is_revision = true;
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_change_type 
  ON public.time_period_revisions USING btree (time_period_id, change_type);

-- ============================================================================
-- STEP 5: Update System Settings with Configurable Limits
-- ============================================================================

-- Add limit columns to system_settings
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS max_breaks_per_period INTEGER NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS max_used_fleet_per_period INTEGER NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS max_mobilised_fleet_per_period INTEGER NULL DEFAULT 4;

-- Add check constraints
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'system_settings_max_breaks_check'
  ) THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_breaks_check 
      CHECK (max_breaks_per_period IS NULL OR max_breaks_per_period > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'system_settings_max_used_fleet_check'
  ) THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_used_fleet_check 
      CHECK (max_used_fleet_per_period IS NULL OR max_used_fleet_per_period > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'system_settings_max_mobilised_fleet_check'
  ) THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_mobilised_fleet_check 
      CHECK (max_mobilised_fleet_per_period IS NULL OR max_mobilised_fleet_per_period > 0);
  END IF;
END $$;

-- Set default values if not already set
UPDATE public.system_settings
SET 
  max_breaks_per_period = COALESCE(max_breaks_per_period, 3),
  max_used_fleet_per_period = COALESCE(max_used_fleet_per_period, 6),
  max_mobilised_fleet_per_period = COALESCE(max_mobilised_fleet_per_period, 4)
WHERE max_breaks_per_period IS NULL 
   OR max_used_fleet_per_period IS NULL 
   OR max_mobilised_fleet_per_period IS NULL;

-- ============================================================================
-- STEP 6: Migrate Existing Data
-- ============================================================================

-- 6.1 Migrate used fleet from time_used_large_plant (numbered columns)
DO $$
DECLARE
  migrated_count INTEGER := 0;
BEGIN
  INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_id_1, 1
  FROM public.time_used_large_plant
  WHERE large_plant_id_1 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % used fleet items from column 1', migrated_count;

  INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_id_2, 2
  FROM public.time_used_large_plant
  WHERE large_plant_id_2 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % used fleet items from column 2', migrated_count;

  INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_id_3, 3
  FROM public.time_used_large_plant
  WHERE large_plant_id_3 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % used fleet items from column 3', migrated_count;

  INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_id_4, 4
  FROM public.time_used_large_plant
  WHERE large_plant_id_4 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % used fleet items from column 4', migrated_count;

  INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_id_5, 5
  FROM public.time_used_large_plant
  WHERE large_plant_id_5 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % used fleet items from column 5', migrated_count;

  INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_id_6, 6
  FROM public.time_used_large_plant
  WHERE large_plant_id_6 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % used fleet items from column 6', migrated_count;
END $$;

-- 6.2 Migrate mobilised fleet from time_mobilised_large_plant (numbered columns)
DO $$
DECLARE
  migrated_count INTEGER := 0;
BEGIN
  INSERT INTO public.time_period_mobilised_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_no_1, 1
  FROM public.time_mobilised_large_plant
  WHERE large_plant_no_1 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % mobilised fleet items from column 1', migrated_count;

  INSERT INTO public.time_period_mobilised_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_no_2, 2
  FROM public.time_mobilised_large_plant
  WHERE large_plant_no_2 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % mobilised fleet items from column 2', migrated_count;

  INSERT INTO public.time_period_mobilised_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_no_3, 3
  FROM public.time_mobilised_large_plant
  WHERE large_plant_no_3 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % mobilised fleet items from column 3', migrated_count;

  INSERT INTO public.time_period_mobilised_fleet (time_period_id, large_plant_id, display_order)
  SELECT time_period_id, large_plant_no_4, 4
  FROM public.time_mobilised_large_plant
  WHERE large_plant_no_4 IS NOT NULL
  ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;
  GET DIAGNOSTICS migrated_count = ROW_COUNT;
  RAISE NOTICE 'Migrated % mobilised fleet items from column 4', migrated_count;
END $$;

-- 6.3 Populate workflow fields from existing data
UPDATE public.time_periods
SET submitted_at = COALESCE(submitted_at, created_at),
    submitted_by = COALESCE(submitted_by, user_id)
WHERE status != 'draft' 
  AND submitted_at IS NULL;

-- Set supervisor/admin approval timestamps if they exist
UPDATE public.time_periods
SET supervisor_approved_at = approved_at,
    supervisor_id = approved_by
WHERE status IN ('supervisor_approved', 'admin_approved')
  AND supervisor_approved_at IS NULL
  AND approved_by IS NOT NULL
  AND approved_by != user_id;

UPDATE public.time_periods
SET admin_approved_at = approved_at,
    admin_id = approved_by
WHERE status = 'admin_approved'
  AND admin_approved_at IS NULL
  AND approved_by IS NOT NULL;

-- ============================================================================
-- STEP 7: Verify Migration
-- ============================================================================

DO $$
DECLARE
  used_fleet_count INTEGER;
  mobilised_fleet_count INTEGER;
  breaks_count INTEGER;
  pay_rates_count INTEGER;
  revisions_count INTEGER;
  periods_with_workflow INTEGER;
  system_limits RECORD;
BEGIN
  SELECT COUNT(*) INTO used_fleet_count FROM public.time_period_used_fleet;
  SELECT COUNT(*) INTO mobilised_fleet_count FROM public.time_period_mobilised_fleet;
  SELECT COUNT(*) INTO breaks_count FROM public.time_period_breaks;
  SELECT COUNT(*) INTO pay_rates_count FROM public.time_period_pay_rates;
  SELECT COUNT(*) INTO revisions_count FROM public.time_period_revisions;
  SELECT COUNT(*) INTO periods_with_workflow FROM public.time_periods 
    WHERE submitted_at IS NOT NULL;
  
  SELECT 
    max_breaks_per_period,
    max_used_fleet_per_period,
    max_mobilised_fleet_per_period
  INTO system_limits
  FROM public.system_settings
  LIMIT 1;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Migration Summary:';
  RAISE NOTICE '  Used Fleet Records: %', used_fleet_count;
  RAISE NOTICE '  Mobilised Fleet Records: %', mobilised_fleet_count;
  RAISE NOTICE '  Breaks Records: %', breaks_count;
  RAISE NOTICE '  Pay Rates Records: %', pay_rates_count;
  RAISE NOTICE '  Revision Records: %', revisions_count;
  RAISE NOTICE '  Time Periods with Workflow Data: %', periods_with_workflow;
  RAISE NOTICE '';
  RAISE NOTICE 'System Limits:';
  RAISE NOTICE '  Max Breaks: %', system_limits.max_breaks_per_period;
  RAISE NOTICE '  Max Used Fleet: %', system_limits.max_used_fleet_per_period;
  RAISE NOTICE '  Max Mobilised Fleet: %', system_limits.max_mobilised_fleet_per_period;
  RAISE NOTICE '========================================';
END $$;

COMMIT;

-- ============================================================================
-- NOTES:
-- ============================================================================
-- 1. This migration preserves all existing data
-- 2. Old tables (time_used_large_plant, time_mobilised_large_plant) are kept
--    Drop them only after verifying the new schema works correctly
-- 3. Update your application code to use the new normalized tables
-- 4. Test thoroughly before dropping old tables
-- 5. Consider adding RLS policies for the new tables
-- 6. Review migrated revision data - change_type may need manual adjustment
-- 7. Pay rates table is new - no migration needed, just start using it
-- 8. System limits can be adjusted in system_settings table without code changes
-- ============================================================================

