-- =====================================================
-- RECREATE APPROVAL STATUS ENUM
-- =====================================================
-- This script recreates the approval_status enum with only 3 values:
-- 1. submitted
-- 2. supervisor_approved
-- 3. admin_approved
-- =====================================================

BEGIN;

-- Step 1: Drop and recreate the time_periods table status column constraints
-- First, let's find and drop any check constraints on status
DO $$
DECLARE
  constraint_name TEXT;
BEGIN
  FOR constraint_name IN 
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    WHERE rel.relname = 'time_periods'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) LIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.time_periods DROP CONSTRAINT IF EXISTS %I', constraint_name);
    RAISE NOTICE 'Dropped constraint: %', constraint_name;
  END LOOP;
END $$;

-- Step 2: Create a temporary column
ALTER TABLE public.time_periods 
  ADD COLUMN status_temp TEXT;

-- Step 3: Copy current status values to temp column
UPDATE public.time_periods 
  SET status_temp = status::TEXT;

-- Step 4: Drop the old status column
ALTER TABLE public.time_periods 
  DROP COLUMN status;

-- Step 5: Drop the old enum type
DROP TYPE IF EXISTS public.approval_status CASCADE;

-- Step 6: Create new enum with only the 3 values you need
CREATE TYPE public.approval_status AS ENUM (
  'submitted',
  'supervisor_approved',
  'admin_approved'
);

-- Step 7: Recreate the status column with the new enum type
ALTER TABLE public.time_periods 
  ADD COLUMN status public.approval_status NOT NULL DEFAULT 'submitted'::approval_status;

-- Step 8: Copy values back from temp column (if any data exists)
DO $$
BEGIN
  -- Only update if there's data and the values are valid
  UPDATE public.time_periods 
    SET status = status_temp::public.approval_status
    WHERE status_temp IN ('submitted', 'supervisor_approved', 'admin_approved');
    
  -- Log if any rows couldn't be converted
  IF EXISTS (
    SELECT 1 FROM public.time_periods 
    WHERE status_temp IS NOT NULL 
      AND status_temp NOT IN ('submitted', 'supervisor_approved', 'admin_approved')
  ) THEN
    RAISE WARNING 'Some rows had invalid status values and were set to default (submitted)';
  END IF;
END $$;

-- Step 9: Drop the temporary column
ALTER TABLE public.time_periods 
  DROP COLUMN status_temp;

-- Verification
DO $$ 
DECLARE
  rec RECORD;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Approval status enum recreated successfully';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'New approval_status enum values:';
  
  FOR rec IN 
    SELECT enumlabel AS status_value, enumsortorder AS sort_order
    FROM pg_enum 
    WHERE enumtypid = 'public.approval_status'::regtype
    ORDER BY enumsortorder
  LOOP
    RAISE NOTICE '  %: %', rec.sort_order, rec.status_value;
  END LOOP;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Workflow stages:';
  RAISE NOTICE '  Stage 1: submitted (User submits)';
  RAISE NOTICE '  Stage 2: supervisor_approved (Supervisor/Manager approves)';
  RAISE NOTICE '  Stage 3: admin_approved (Admin final approval)';
  RAISE NOTICE '========================================';
END $$;

COMMIT;
