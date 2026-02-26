# RLS Policy Check for Fleet Tables

## Tables That Need RLS Policies

After fixing the code to look up plant IDs, you may also need RLS policies on these tables:

1. **time_used_large_plant** - Stores used fleet items
2. **time_mobilised_large_plant** - Stores mobilised fleet items
3. **time_breaks** - Stores break times (already being saved)

## Check Current Policies

Run this SQL to check if policies exist:

```sql
-- Check policies on fleet tables
SELECT 
  tablename,
  policyname,
  cmd as command,
  roles,
  qual as using_expression,
  with_check
FROM pg_policies 
WHERE tablename IN ('time_used_large_plant', 'time_mobilised_large_plant', 'time_breaks')
ORDER BY tablename, policyname;
```

## Create Policies If Missing

If policies are missing, run this SQL:

```sql
-- Enable RLS on all three tables
ALTER TABLE time_used_large_plant ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_mobilised_large_plant ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_breaks ENABLE ROW LEVEL SECURITY;

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
```

## What Changed in the Code

The code now:
1. ✅ Looks up plant IDs from the `large_plant` table using plant numbers
2. ✅ Stores UUID IDs instead of plant number strings in `large_plant_id_X` columns
3. ✅ Stores UUID IDs in `large_plant_no_X` columns (for mobilised fleet)
4. ✅ Adds better error handling and user-facing error messages
5. ✅ Logs detailed information for debugging

## Testing

After applying the code changes and RLS policies:
1. Try saving a time period with fleet items
2. Check the console logs for:
   - "✅ Found plant ID for [plant_no]: [id]"
   - "✅ Saved X used fleet item(s) to time_used_large_plant"
3. Verify the data in Supabase:
   - Check `time_used_large_plant` table for the saved records
   - Verify `large_plant_id_1`, `large_plant_id_2`, etc. contain UUIDs, not plant numbers

