# Fixing Employer Type Issues

## Issue 1: Check Constraint Violation
The CSV contains employer types ("Contractor", "Agency") that don't exist in the `employer_type` table.

## Issue 2: Dropdown Not Populating
The employer type dropdown is not loading from the `employer_type` table.

## Solutions

### Step 1: Add Missing Employer Types to Database

Run this SQL in your Supabase SQL Editor:

```sql
-- Check current employer types
SELECT * FROM public.employer_type;

-- Add missing employer types
INSERT INTO public.employer_type (employer_type) 
VALUES 
  ('Contractor'),
  ('Agency'),
  ('Subcontractor')
ON CONFLICT (employer_type) DO NOTHING;

-- Verify they were added
SELECT * FROM public.employer_type ORDER BY employer_type;
```

**Note:** If your table has a different structure or primary key, adjust the INSERT statement accordingly.

### Step 2: Check RLS Policies on employer_type Table

The dropdown might not be populating due to RLS policies blocking reads. Check if RLS is enabled:

```sql
-- Check if RLS is enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename = 'employer_type';
```

If RLS is enabled and you're getting no results, create a policy to allow reads:

```sql
-- Enable RLS (if not already enabled)
ALTER TABLE public.employer_type ENABLE ROW LEVEL SECURITY;

-- Policy: Allow all authenticated users to read employer types
CREATE POLICY "Allow authenticated users to read employer types"
ON public.employer_type
FOR SELECT
TO authenticated
USING (true);
```

### Step 3: Verify Table Structure

Make sure the table structure matches what the code expects:

```sql
-- Check table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'employer_type';
```

The code expects:
- Table name: `employer_type` (singular)
- Column name: `employer_type` (same as table name)

If your table/column names are different, you may need to update the code in `employer_service.dart`.

### Step 4: Test the Query

After adding the types and setting up RLS, test the query directly:

```sql
-- Test query (should return results)
SELECT employer_type 
FROM public.employer_type 
ORDER BY employer_type;
```

If this returns results but the app doesn't, check the browser console for the debug logs I added. They will show:
- What the query returns
- Any errors that occur
- The number of types loaded

## Quick Fix Summary

1. **Add employer types to database:**
   ```sql
   INSERT INTO public.employer_type (employer_type) 
   VALUES ('Contractor'), ('Agency'), ('Subcontractor')
   ON CONFLICT DO NOTHING;
   ```

2. **Add RLS policy for reads (if needed):**
   ```sql
   CREATE POLICY "Allow authenticated users to read employer types"
   ON public.employer_type FOR SELECT TO authenticated USING (true);
   ```

3. **Reload the app** and check the console logs for debug information.

