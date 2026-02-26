-- Add supervisor_approved to ppe_request_status enum (between submitted and manager_approved in flow).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'ppe_request_status' AND e.enumlabel = 'supervisor_approved'
  ) THEN
    ALTER TYPE public.ppe_request_status ADD VALUE 'supervisor_approved';
  END IF;
END
$$;
