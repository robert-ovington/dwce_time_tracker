-- Add 'imported' to approval_status enum for payroll-imported time periods
-- Supervisors can approve 'imported' and 'submitted'; once 'admin_approved', only security level 1 can edit.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'imported'
          AND enumtypid = 'public.approval_status'::regtype
    ) THEN
        ALTER TYPE public.approval_status ADD VALUE 'imported';
        RAISE NOTICE 'Added imported to approval_status enum';
    ELSE
        RAISE NOTICE 'imported already exists in approval_status enum';
    END IF;
END $$;
