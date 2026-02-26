-- Add RLS Policies for Fleet Tables
-- Run this in Supabase SQL Editor to fix the "new row violates row-level security policy" error

-- Enable RLS on all fleet-related tables
ALTER TABLE time_used_large_plant ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_mobilised_large_plant ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_breaks ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (optional - only if you want to replace them)
DROP POLICY IF EXISTS "time_used_large_plant_insert_policy" ON time_used_large_plant;
DROP POLICY IF EXISTS "time_mobilised_large_plant_insert_policy" ON time_mobilised_large_plant;
DROP POLICY IF EXISTS "time_breaks_insert_policy" ON time_breaks;

-- Policies for time_used_large_plant
CREATE POLICY "time_used_large_plant_insert_policy"
ON time_used_large_plant
FOR INSERT
TO authenticated
WITH CHECK (
  -- Allow insert if the time_period belongs to the authenticated user
  EXISTS (
    SELECT 1 FROM time_periods 
    WHERE time_periods.id = time_used_large_plant.time_period_id 
    AND time_periods.user_id = auth.uid()
  )
);

CREATE POLICY "time_used_large_plant_select_policy"
ON time_used_large_plant
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM time_periods 
    WHERE time_periods.id = time_used_large_plant.time_period_id 
    AND time_periods.user_id = auth.uid()
  )
);

-- Policies for time_mobilised_large_plant
CREATE POLICY "time_mobilised_large_plant_insert_policy"
ON time_mobilised_large_plant
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM time_periods 
    WHERE time_periods.id = time_mobilised_large_plant.time_period_id 
    AND time_periods.user_id = auth.uid()
  )
);

CREATE POLICY "time_mobilised_large_plant_select_policy"
ON time_mobilised_large_plant
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM time_periods 
    WHERE time_periods.id = time_mobilised_large_plant.time_period_id 
    AND time_periods.user_id = auth.uid()
  )
);

-- Policies for time_breaks (if not already created)
CREATE POLICY "time_breaks_insert_policy"
ON time_breaks
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM time_periods 
    WHERE time_periods.id = time_breaks.time_period_id 
    AND time_periods.user_id = auth.uid()
  )
);

CREATE POLICY "time_breaks_select_policy"
ON time_breaks
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM time_periods 
    WHERE time_periods.id = time_breaks.time_period_id 
    AND time_periods.user_id = auth.uid()
  )
);

-- Verify policies were created
SELECT 
  tablename,
  policyname,
  cmd as command,
  roles
FROM pg_policies 
WHERE tablename IN ('time_used_large_plant', 'time_mobilised_large_plant', 'time_breaks')
ORDER BY tablename, policyname;

-- Expected output: 6 policies total (2 for each table: INSERT and SELECT)

