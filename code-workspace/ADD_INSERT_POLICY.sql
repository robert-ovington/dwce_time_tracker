-- Add the missing INSERT policy for time_periods table
-- Run this in Supabase SQL Editor

-- Create INSERT policy - Allow authenticated users to insert their own records
CREATE POLICY "time_periods_insert_policy"
ON time_periods
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
);

-- Verify it was created
SELECT 
  policyname,
  cmd as command,
  roles,
  qual as using_expression,
  with_check
FROM pg_policies 
WHERE tablename = 'time_periods'
ORDER BY policyname;

-- You should now see 4 policies: INSERT, SELECT, UPDATE, DELETE

