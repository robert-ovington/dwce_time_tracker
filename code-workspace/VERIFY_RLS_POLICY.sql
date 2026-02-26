-- Verification Script for time_periods RLS Policy
-- Run this to check what policies currently exist

-- 1. Check if RLS is enabled
SELECT 
  tablename, 
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE tablename = 'time_periods';

-- 2. List all policies on time_periods
SELECT 
  policyname,
  cmd as command,
  roles,
  qual as using_expression,
  with_check
FROM pg_policies 
WHERE tablename = 'time_periods'
ORDER BY policyname;

-- 3. Check the user_id column type
SELECT 
  column_name, 
  data_type, 
  udt_name,
  is_nullable
FROM information_schema.columns 
WHERE table_name = 'time_periods' 
AND column_name = 'user_id';

-- 4. Test what auth.uid() returns (run this while authenticated)
SELECT 
  auth.uid() as current_auth_uid,
  '3ab5b7de-95cb-4e1a-833e-21fdc0fb76da'::uuid as expected_user_id,
  auth.uid() = '3ab5b7de-95cb-4e1a-833e-21fdc0fb76da'::uuid as ids_match;

-- 5. Check for any triggers that might interfere
SELECT 
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'time_periods';

