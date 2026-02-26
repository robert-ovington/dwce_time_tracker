# Errors Log Schema Improvements

## Current Schema Assessment

The current schema is **functional and adequate** for basic error tracking, but could be enhanced for better analysis and management.

## Recommended Improvements

### 1. **Separate Stack Trace Column** (HIGH PRIORITY)
**Current:** Stack trace is appended to `description` field  
**Recommended:** Add separate `stack_trace` column

**Benefits:**
- Easier to query errors without stack traces
- Better for pattern analysis (same error, different stack traces)
- Can filter out verbose stack traces when viewing errors

```sql
ALTER TABLE public.errors_log 
ADD COLUMN stack_trace text NULL;
```

### 2. **Error Severity/Level** (MEDIUM PRIORITY)
**Recommended:** Add `severity` column with check constraint

**Benefits:**
- Categorize errors by importance (critical, error, warning, info)
- Filter critical errors for immediate attention
- Better reporting and alerting

```sql
ALTER TABLE public.errors_log 
ADD COLUMN severity text NOT NULL DEFAULT 'error'
  CHECK (severity IN ('critical', 'error', 'warning', 'info'));

CREATE INDEX errors_log_severity_idx ON public.errors_log(severity);
```

### 3. **Error Code** (MEDIUM PRIORITY)
**Recommended:** Add `error_code` column for standardized error identification

**Benefits:**
- Group identical errors together (e.g., "GPS_TIMEOUT", "VALIDATION_MISSING_FIELD")
- Easier to track specific error patterns
- Can link to documentation or known issues

```sql
ALTER TABLE public.errors_log 
ADD COLUMN error_code text NULL;

CREATE INDEX errors_log_error_code_idx ON public.errors_log(error_code);
```

### 4. **Resolution Tracking** (LOW PRIORITY - for admin use)
**Recommended:** Add fields to track error resolution

**Benefits:**
- Mark errors as resolved/fixed
- Track who resolved them and when
- Filter out resolved errors from active error lists

```sql
ALTER TABLE public.errors_log 
ADD COLUMN resolved boolean NOT NULL DEFAULT false,
ADD COLUMN resolved_at timestamp with time zone NULL,
ADD COLUMN resolved_by uuid NULL REFERENCES auth.users(id),
ADD COLUMN resolution_notes text NULL;

CREATE INDEX errors_log_resolved_idx ON public.errors_log(resolved, created_at DESC);
```

### 5. **Additional Indexes** (MEDIUM PRIORITY)
**Recommended:** Add indexes on commonly filtered columns

**Benefits:**
- Faster queries when filtering by type or location
- Better performance for error analysis dashboards

```sql
CREATE INDEX errors_log_type_idx ON public.errors_log(type);
CREATE INDEX errors_log_location_idx ON public.errors_log(location);
```

### 6. **Occurrence Count** (OPTIONAL - can be calculated)
**Note:** This can be calculated with SQL queries, but storing it might be useful for frequently occurring errors.

```sql
ALTER TABLE public.errors_log 
ADD COLUMN occurrence_count integer NOT NULL DEFAULT 1;
```

## Recommended Implementation Order

1. **Phase 1 (Essential):**
   - Separate `stack_trace` column
   - Index on `type` column

2. **Phase 2 (Useful):**
   - `severity` column
   - `error_code` column
   - Index on `location` column

3. **Phase 3 (Nice to have):**
   - Resolution tracking fields
   - Additional indexes as needed

## Complete Enhanced Schema Example

```sql
-- Enhanced errors_log table
CREATE TABLE IF NOT EXISTS public.errors_log (
  id bigserial NOT NULL,
  user_id uuid NULL,
  platform text NOT NULL,
  location text NULL,
  type text NOT NULL,
  severity text NOT NULL DEFAULT 'error',
  error_code text NULL,
  description text NOT NULL,
  stack_trace text NULL,
  resolved boolean NOT NULL DEFAULT false,
  resolved_at timestamp with time zone NULL,
  resolved_by uuid NULL REFERENCES auth.users(id),
  resolution_notes text NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT errors_log_pkey PRIMARY KEY (id),
  CONSTRAINT errors_log_platform_check CHECK (
    platform = ANY (ARRAY['ios'::text, 'android'::text, 'web'::text])
  ),
  CONSTRAINT errors_log_severity_check CHECK (
    severity = ANY (ARRAY['critical'::text, 'error'::text, 'warning'::text, 'info'::text])
  )
) TABLESPACE pg_default;

-- Indexes
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
```

## Migration Script for Existing Table

If you want to add these columns to your existing table:

```sql
-- Add new columns
ALTER TABLE public.errors_log 
ADD COLUMN IF NOT EXISTS stack_trace text NULL,
ADD COLUMN IF NOT EXISTS severity text NOT NULL DEFAULT 'error',
ADD COLUMN IF NOT EXISTS error_code text NULL,
ADD COLUMN IF NOT EXISTS resolved boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS resolved_at timestamp with time zone NULL,
ADD COLUMN IF NOT EXISTS resolved_by uuid NULL,
ADD COLUMN IF NOT EXISTS resolution_notes text NULL;

-- Add check constraint for severity
ALTER TABLE public.errors_log 
ADD CONSTRAINT errors_log_severity_check 
CHECK (severity = ANY (ARRAY['critical'::text, 'error'::text, 'warning'::text, 'info'::text]));

-- Add indexes
CREATE INDEX IF NOT EXISTS errors_log_type_idx ON public.errors_log(type);
CREATE INDEX IF NOT EXISTS errors_log_location_idx ON public.errors_log(location);
CREATE INDEX IF NOT EXISTS errors_log_severity_idx ON public.errors_log(severity);
CREATE INDEX IF NOT EXISTS errors_log_error_code_idx ON public.errors_log(error_code);
CREATE INDEX IF NOT EXISTS errors_log_resolved_idx ON public.errors_log(resolved, created_at DESC);
```

## Code Changes Required

If you implement these changes, you'll need to update `ErrorLogService` to:
1. Store stack trace in separate column
2. Accept optional `severity` and `error_code` parameters
3. Update the insert statement to include new fields

