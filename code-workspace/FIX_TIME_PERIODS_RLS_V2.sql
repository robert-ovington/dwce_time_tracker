-- Complete RLS Policy Fix for time_periods Table (Version 2)
-- This version uses explicit UUID casting to ensure compatibility
-- Run this entire script in Supabase SQL Editor

-- Step 1: Enable RLS (if not already enabled)
ALTER TABLE time_periods ENABLE ROW LEVEL SECURITY;

-- Step 2: Drop ALL existing policies on time_periods
DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'time_periods') 
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON time_periods';
    END LOOP;
END $$;

-- Step 3: Create INSERT policy with explicit UUID casting
-- This ensures the comparison works correctly regardless of column type
CREATE POLICY "time_periods_insert_policy"
ON time_periods
FOR INSERT
TO authenticated
WITH CHECK (
  (user_id::text) = (auth.uid()::text)
);

-- Alternative INSERT policy (if above doesn't work, try this one):
-- CREATE POLICY "time_periods_insert_policy"
-- ON time_periods
-- FOR INSERT
-- TO authenticated
-- WITH CHECK (
--   user_id = auth.uid()
-- );

-- Step 4: Create SELECT policy
CREATE POLICY "time_periods_select_policy"
ON time_periods
FOR SELECT
TO authenticated
USING (
  (user_id::text) = (auth.uid()::text)
);

-- Step 5: Create UPDATE policy
CREATE POLICY "time_periods_update_policy"
ON time_periods
FOR UPDATE
TO authenticated
USING (
  (user_id::text) = (auth.uid()::text)
)
WITH CHECK (
  (user_id::text) = (auth.uid()::text)
);

-- Step 6: Create DELETE policy - Only allow deletion if not approved
CREATE POLICY "time_periods_delete_policy"
ON time_periods
FOR DELETE
TO authenticated
USING (
  (user_id::text) = (auth.uid()::text) AND approved_by IS NULL
);

-- Step 7: Verify policies were created
SELECT 
  policyname,
  cmd as command,
  roles,
  qual as using_expression,
  with_check
FROM pg_policies 
WHERE tablename = 'time_periods'
ORDER BY policyname;

-- Expected output should show 4 policies (INSERT, SELECT, UPDATE, DELETE)

-- Step 8: Test the policy (optional - uncomment to test)
-- This should work if you're authenticated as user 3ab5b7de-95cb-4e1a-833e-21fdc0fb76da
/*
INSERT INTO time_periods (
  user_id,
  project_id,
  work_date,
  start_time,
  finish_time,
  status,
  travel_to_site_min,
  travel_from_site_min,
  on_call,
  misc_allowance_min,
  revision_number,
  offline_created,
  synced
) VALUES (
  auth.uid(),
  'f0863393-b49d-43b1-ac6e-3bf4a9e2a1db'::uuid,
  '2025-12-01',
  '2025-12-01T05:30:00.000'::timestamp,
  '2025-12-01T06:00:00.000'::timestamp,
  'draft',
  0,
  0,
  false,
  0,
  0,
  false,
  true
);
*/

