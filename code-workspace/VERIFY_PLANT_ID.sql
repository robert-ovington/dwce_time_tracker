-- Verification Script: Check if plant ID exists in large_plant table
-- Run this to verify the UUID from the error

-- Check if the specific plant ID exists
SELECT 
  id,
  plant_no,
  short_description,
  is_active
FROM large_plant
WHERE id = 'de8af748-a192-42a0-aaee-6f74ae02b0a2';

-- Check if plant_no 227 exists and what its ID is
SELECT 
  id,
  plant_no,
  short_description,
  is_active
FROM large_plant
WHERE plant_no = '227';

-- Check RLS policies on large_plant table
SELECT 
  policyname,
  cmd as command,
  roles,
  qual as using_expression,
  with_check
FROM pg_policies 
WHERE tablename = 'large_plant'
ORDER BY policyname;

-- Check if RLS is enabled
SELECT 
  tablename, 
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE tablename = 'large_plant';

