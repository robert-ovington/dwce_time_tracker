-- ============================================================================
-- Migration Script: Normalized Time Periods Schema
-- ============================================================================
-- This script migrates from the current fragmented schema to a properly
-- normalized schema that eliminates numbered columns and supports unlimited
-- related items (fleet, breaks).
--
-- IMPORTANT: Review and test this script in a development environment first!
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: Create New Normalized Tables
-- ============================================================================

-- 1.1 Update time_periods table (add missing columns, keep existing data)
ALTER TABLE public.time_periods
  ADD COLUMN IF NOT EXISTS supervisor_id UUID NULL,
  ADD COLUMN IF NOT EXISTS supervisor_time_stamp TIMESTAMP WITH TIME ZONE NULL,
  ADD COLUMN IF NOT EXISTS admin_id UUID NULL,
  ADD COLUMN IF NOT EXISTS admin_time_stamp TIMESTAMP WITH TIME ZONE NULL,
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

-- 1.2 Create normalized breaks table
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

-- 1.3 Create normalized used fleet table
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

-- 1.4 Create normalized mobilised fleet table
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

-- 1.5 Update revision table (add time_period_id link)
ALTER TABLE public.time_period_revision
  ADD COLUMN IF NOT EXISTS time_period_id UUID NULL,
  ADD COLUMN IF NOT EXISTS changed_by UUID NULL;

-- Add foreign keys for revision table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'time_period_revision_time_period_id_fkey'
  ) THEN
    ALTER TABLE public.time_period_revision
      ADD CONSTRAINT time_period_revision_time_period_id_fkey 
      FOREIGN KEY (time_period_id) 
      REFERENCES public.time_periods(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'time_period_revision_changed_by_fkey'
  ) THEN
    ALTER TABLE public.time_period_revision
      ADD CONSTRAINT time_period_revision_changed_by_fkey 
      FOREIGN KEY (changed_by) 
      REFERENCES public.users_data(user_id) ON DELETE RESTRICT;
  END IF;
END $$;

-- ============================================================================
-- STEP 2: Create Indexes
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

-- Revision indexes
CREATE INDEX IF NOT EXISTS idx_time_period_revision_time_period_id 
  ON public.time_period_revision USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_revision_changed_by 
  ON public.time_period_revision USING btree (changed_by);

-- ============================================================================
-- STEP 3: Migrate Existing Data (if any)
-- ============================================================================

-- 3.1 Migrate used fleet from time_used_large_plant (numbered columns)
INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_id_1,
  1
FROM public.time_used_large_plant
WHERE large_plant_id_1 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_id_2,
  2
FROM public.time_used_large_plant
WHERE large_plant_id_2 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_id_3,
  3
FROM public.time_used_large_plant
WHERE large_plant_id_3 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_id_4,
  4
FROM public.time_used_large_plant
WHERE large_plant_id_4 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_id_5,
  5
FROM public.time_used_large_plant
WHERE large_plant_id_5 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

INSERT INTO public.time_period_used_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_id_6,
  6
FROM public.time_used_large_plant
WHERE large_plant_id_6 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

-- 3.2 Migrate mobilised fleet from time_mobilised_large_plant (numbered columns)
INSERT INTO public.time_period_mobilised_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_no_1,
  1
FROM public.time_mobilised_large_plant
WHERE large_plant_no_1 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

INSERT INTO public.time_period_mobilised_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_no_2,
  2
FROM public.time_mobilised_large_plant
WHERE large_plant_no_2 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

INSERT INTO public.time_period_mobilised_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_no_3,
  3
FROM public.time_mobilised_large_plant
WHERE large_plant_no_3 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

INSERT INTO public.time_period_mobilised_fleet (time_period_id, large_plant_id, display_order)
SELECT 
  time_period_id,
  large_plant_no_4,
  4
FROM public.time_mobilised_large_plant
WHERE large_plant_no_4 IS NOT NULL
ON CONFLICT (time_period_id, large_plant_id) DO NOTHING;

-- 3.3 Update revision table to link to time_period_id
-- Note: This assumes revisions can be linked by revision_number matching
-- You may need to adjust this based on your actual data structure
UPDATE public.time_period_revision tr
SET time_period_id = tp.id
FROM public.time_periods tp
WHERE tr.revision_number = tp.revision_number
  AND tr.time_period_id IS NULL
  AND tp.user_id::text = tr.user_name -- Adjust this join condition based on your data
LIMIT 1000; -- Safety limit, adjust as needed

-- ============================================================================
-- STEP 4: Verify Migration
-- ============================================================================

-- Count records in new tables
DO $$
DECLARE
  used_fleet_count INTEGER;
  mobilised_fleet_count INTEGER;
  breaks_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO used_fleet_count FROM public.time_period_used_fleet;
  SELECT COUNT(*) INTO mobilised_fleet_count FROM public.time_period_mobilised_fleet;
  SELECT COUNT(*) INTO breaks_count FROM public.time_period_breaks;
  
  RAISE NOTICE 'Migration Summary:';
  RAISE NOTICE '  Used Fleet Records: %', used_fleet_count;
  RAISE NOTICE '  Mobilised Fleet Records: %', mobilised_fleet_count;
  RAISE NOTICE '  Breaks Records: %', breaks_count;
END $$;

-- ============================================================================
-- STEP 5: Optional - Drop Old Tables (ONLY AFTER VERIFYING NEW SCHEMA WORKS)
-- ============================================================================

-- UNCOMMENT THESE LINES ONLY AFTER YOU'VE VERIFIED THE NEW SCHEMA WORKS CORRECTLY
-- AND UPDATED YOUR APPLICATION CODE TO USE THE NEW TABLES

-- DROP TABLE IF EXISTS public.time_used_large_plant CASCADE;
-- DROP TABLE IF EXISTS public.time_mobilised_large_plant CASCADE;

COMMIT;

-- ============================================================================
-- NOTES:
-- ============================================================================
-- 1. This migration preserves all existing data
-- 2. Old tables are kept for safety - drop them only after verification
-- 3. Update your application code to use the new normalized tables
-- 4. Test thoroughly before dropping old tables
-- 5. Consider adding RLS policies for the new tables
-- ============================================================================

