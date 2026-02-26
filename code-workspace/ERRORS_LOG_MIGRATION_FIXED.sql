-- Fixed Migration Script for errors_log table
-- This version checks if constraints/indexes exist before creating them

-- Add new columns (IF NOT EXISTS is supported for columns in PostgreSQL 9.6+)
ALTER TABLE public.errors_log 
ADD COLUMN IF NOT EXISTS stack_trace text NULL,
ADD COLUMN IF NOT EXISTS severity text NOT NULL DEFAULT 'error',
ADD COLUMN IF NOT EXISTS error_code text NULL,
ADD COLUMN IF NOT EXISTS resolved boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS resolved_at timestamp with time zone NULL,
ADD COLUMN IF NOT EXISTS resolved_by uuid NULL,
ADD COLUMN IF NOT EXISTS resolution_notes text NULL,
ADD COLUMN IF NOT EXISTS occurrence_count integer NOT NULL DEFAULT 1;

-- Add check constraint for severity (only if it doesn't exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'errors_log_severity_check' 
    AND conrelid = 'public.errors_log'::regclass
  ) THEN
    ALTER TABLE public.errors_log 
    ADD CONSTRAINT errors_log_severity_check 
    CHECK (severity = ANY (ARRAY['critical'::text, 'error'::text, 'warning'::text, 'info'::text]));
  END IF;
END $$;

-- Add indexes (IF NOT EXISTS is supported for indexes)
CREATE INDEX IF NOT EXISTS errors_log_type_idx ON public.errors_log(type);
CREATE INDEX IF NOT EXISTS errors_log_location_idx ON public.errors_log(location);
CREATE INDEX IF NOT EXISTS errors_log_severity_idx ON public.errors_log(severity);
CREATE INDEX IF NOT EXISTS errors_log_error_code_idx ON public.errors_log(error_code);
CREATE INDEX IF NOT EXISTS errors_log_resolved_idx ON public.errors_log(resolved, created_at DESC);

-- Add foreign key constraint for resolved_by (only if it doesn't exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'errors_log_resolved_by_fkey'
  ) THEN
    ALTER TABLE public.errors_log 
    ADD CONSTRAINT errors_log_resolved_by_fkey 
    FOREIGN KEY (resolved_by) REFERENCES auth.users(id);
  END IF;
END $$;

