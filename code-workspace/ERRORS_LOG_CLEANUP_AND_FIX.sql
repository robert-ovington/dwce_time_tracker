-- Cleanup and Fix Script for errors_log table
-- This script fixes naming inconsistencies and removes duplicates

-- 1. Fix constraint names (from errros_log to errors_log)
-- Note: PostgreSQL doesn't support renaming constraints directly, so we need to drop and recreate

-- Drop old primary key constraint and recreate with correct name (only if old one exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'errros_log_pkey' AND conrelid = 'public.errors_log'::regclass
  ) THEN
    ALTER TABLE public.errors_log DROP CONSTRAINT errros_log_pkey;
    ALTER TABLE public.errors_log ADD CONSTRAINT errors_log_pkey PRIMARY KEY (id);
  END IF;
END $$;

-- Drop old platform check constraint and recreate with correct name (only if old one exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'errros_log_platform_check' AND conrelid = 'public.errors_log'::regclass
  ) THEN
    ALTER TABLE public.errors_log DROP CONSTRAINT errros_log_platform_check;
    ALTER TABLE public.errors_log 
    ADD CONSTRAINT errors_log_platform_check 
    CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text, 'web'::text]));
  END IF;
END $$;

-- 2. Remove duplicate indexes (keep the ones with correct naming)
-- Drop old indexes with misspelled names
DROP INDEX IF EXISTS public.errros_log_user_id_idx;
DROP INDEX IF EXISTS public.errros_log_created_at_idx;

-- 3. Ensure all required indexes exist (they should already exist, but this ensures they do)
CREATE INDEX IF NOT EXISTS errors_log_user_id_idx 
  ON public.errors_log USING btree (user_id) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS errors_log_created_at_idx 
  ON public.errors_log USING btree (created_at DESC) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS errors_log_type_idx 
  ON public.errors_log USING btree (type) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS errors_log_location_idx 
  ON public.errors_log USING btree (location) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS errors_log_severity_idx 
  ON public.errors_log USING btree (severity) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS errors_log_error_code_idx 
  ON public.errors_log USING btree (error_code) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS errors_log_resolved_idx 
  ON public.errors_log USING btree (resolved, created_at DESC) TABLESPACE pg_default;

-- 4. Verify severity check constraint exists (it should already exist, but verify)
-- The constraint already exists from your schema, so we don't need to add it

-- 5. Add foreign key constraint for resolved_by if it doesn't exist
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

