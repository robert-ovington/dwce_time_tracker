-- Complete RLS Policy Fix for time_periods Table
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

-- Step 3: Create INSERT policy - Allow authenticated users to insert their own records
CREATE POLICY "time_periods_insert_policy"
ON time_periods
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
);

-- Step 4: Create SELECT policy - Allow users to view their own records
CREATE POLICY "time_periods_select_policy"
ON time_periods
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);

-- Step 5: Create UPDATE policy - Allow users to update their own records
CREATE POLICY "time_periods_update_policy"
ON time_periods
FOR UPDATE
TO authenticated
USING (
  user_id = auth.uid()
)
WITH CHECK (
  user_id = auth.uid()
);

-- Step 6: Create DELETE policy - Allow users to delete their own records only if not approved
CREATE POLICY "time_periods_delete_policy"
ON time_periods
FOR DELETE
TO authenticated
USING (
  user_id = auth.uid() AND approved_by IS NULL
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

