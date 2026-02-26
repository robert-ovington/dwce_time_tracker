-- Check RLS Policies for large_plant table
-- The foreign key constraint might be failing due to RLS policies

-- Check if RLS is enabled
SELECT 
  tablename, 
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE tablename = 'large_plant';

-- Check all RLS policies
SELECT 
  policyname,
  cmd as command,
  roles,
  qual as using_expression,
  with_check
FROM pg_policies 
WHERE tablename = 'large_plant'
ORDER BY policyname;

-- Check if the specific plant ID exists (run as authenticated user)
SELECT 
  id,
  plant_no,
  short_description,
  is_active
FROM large_plant
WHERE id = 'de8af748-a192-42a0-aaee-6f74ae02b0a2';

-- If the above returns no rows, the RLS policy might be blocking it
-- Foreign key constraints check with the same user context, so if RLS blocks
-- the SELECT, it will also block the foreign key validation

-- Solution: Ensure the foreign key constraint can access the referenced row
-- This might require:
-- 1. A SELECT policy that allows reading all plants (or at least the referenced ones)
-- 2. Or using SECURITY DEFINER for the foreign key check (not possible with standard FKs)
-- 3. Or ensuring the RLS policy allows the authenticated user to read the plant

