-- =====================================================
-- UPDATE APPROVAL STATUS ENUM
-- =====================================================
-- This script adds the approval workflow stages to the existing enum
-- 
-- Three approval stages:
-- 1. 'submitted' - Submitted by User
-- 2. 'supervisor_approved' - Approved by Manager or Supervisor
-- 3. 'admin_approved' - Approved by Admin (final approval)
--
-- Note: 'draft' and 'rejected' will remain in the enum for backward compatibility
-- but won't be used in the new workflow
-- =====================================================

-- Add 'supervisor_approved' to the enum if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumlabel = 'supervisor_approved' 
        AND enumtypid = 'public.approval_status'::regtype
    ) THEN
        ALTER TYPE public.approval_status ADD VALUE 'supervisor_approved';
        RAISE NOTICE 'Added supervisor_approved to approval_status enum';
    ELSE
        RAISE NOTICE 'supervisor_approved already exists in approval_status enum';
    END IF;
END $$;

-- Add 'admin_approved' to the enum if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumlabel = 'admin_approved' 
        AND enumtypid = 'public.approval_status'::regtype
    ) THEN
        ALTER TYPE public.approval_status ADD VALUE 'admin_approved';
        RAISE NOTICE 'Added admin_approved to approval_status enum';
    ELSE
        RAISE NOTICE 'admin_approved already exists in approval_status enum';
    END IF;
END $$;

-- Update the default value for time_periods.status to 'submitted' (since we don't use draft)
ALTER TABLE public.time_periods 
  ALTER COLUMN status SET DEFAULT 'submitted'::approval_status;

-- Verify the enum values and show success message
DO $$ 
DECLARE
  rec RECORD;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Approval status enum updated successfully';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Current approval_status enum values:';
  
  FOR rec IN 
    SELECT enumlabel AS status_value, enumsortorder AS sort_order
    FROM pg_enum 
    WHERE enumtypid = 'public.approval_status'::regtype
    ORDER BY enumsortorder
  LOOP
    RAISE NOTICE '  - %', rec.status_value;
  END LOOP;
  
  RAISE NOTICE '========================================';
END $$;

