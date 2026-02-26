# RLS Policy Troubleshooting for time_periods

## Current Status
- ✅ User ID matches: `3ab5b7de-95cb-4e1a-833e-21fdc0fb76da`
- ❌ Still getting RLS policy violation error
- ❌ Policy was added but not working

## Step 1: Verify the Policy Exists

Run this SQL in Supabase SQL Editor to check existing policies:

```sql
-- Check all policies on time_periods table
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'time_periods';
```

## Step 2: Check if RLS is Enabled

```sql
-- Check if RLS is enabled on the table
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'time_periods';

-- If rowsecurity is false, enable it:
ALTER TABLE time_periods ENABLE ROW LEVEL SECURITY;
```

## Step 3: Create/Replace the Policy Correctly

Try this exact SQL (make sure to drop any existing policies first):

```sql
-- First, drop ALL existing policies on time_periods
DROP POLICY IF EXISTS "Users can insert their own time periods" ON time_periods;
DROP POLICY IF EXISTS "time_periods_insert_policy" ON time_periods;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON time_periods;
-- Add any other policy names you might have created

-- Ensure RLS is enabled
ALTER TABLE time_periods ENABLE ROW LEVEL SECURITY;

-- Create the INSERT policy with explicit role
CREATE POLICY "Users can insert their own time periods"
ON time_periods
FOR INSERT
TO authenticated
WITH CHECK (
  (user_id)::text = (auth.uid())::text
);
```

**Note**: The `::text` cast ensures UUID comparison works correctly.

## Step 4: Alternative Policy (More Permissive for Testing)

If the above doesn't work, try this more permissive policy for testing:

```sql
-- Drop existing
DROP POLICY IF EXISTS "Users can insert their own time periods" ON time_periods;

-- More permissive policy (for testing only)
CREATE POLICY "Allow authenticated inserts"
ON time_periods
FOR INSERT
TO authenticated
WITH CHECK (true);
```

**⚠️ WARNING**: This allows any authenticated user to insert any record. Only use for testing!

## Step 5: Check Table Schema

Verify the `user_id` column type matches:

```sql
-- Check column types
SELECT 
  column_name, 
  data_type, 
  udt_name
FROM information_schema.columns 
WHERE table_name = 'time_periods' 
AND column_name = 'user_id';
```

The `user_id` should be of type `uuid` or `text`. If it's `uuid`, the policy should work with UUID comparison.

## Step 6: Test the Policy Directly

Test if you can insert directly via SQL (this bypasses the app):

```sql
-- This should work if the policy is correct
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
  auth.uid(),  -- This uses your current authenticated user ID
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
```

If this SQL insert works, the policy is correct and the issue is elsewhere.
If this SQL insert fails, the policy needs to be fixed.

## Step 7: Check for Triggers or Constraints

Sometimes triggers or check constraints can cause issues:

```sql
-- Check for triggers
SELECT 
  trigger_name,
  event_manipulation,
  action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'time_periods';

-- Check for check constraints
SELECT 
  constraint_name,
  check_clause
FROM information_schema.check_constraints
WHERE constraint_name LIKE '%time_periods%';
```

## Step 8: Verify Current User Context

Check what `auth.uid()` returns for your session:

```sql
-- This should return your user ID
SELECT auth.uid() as current_user_id;
```

Compare this with the `user_id` being sent: `3ab5b7de-95cb-4e1a-833e-21fdc0fb76da`

## Most Likely Issue

Based on the error, the most common causes are:

1. **Policy not created correctly** - The policy might have a syntax error
2. **RLS not enabled** - RLS must be explicitly enabled on the table
3. **UUID type mismatch** - The policy might need explicit UUID casting
4. **Policy role mismatch** - The policy might be for a different role

## Recommended Fix (Try This First)

Run this complete setup:

```sql
-- Step 1: Enable RLS
ALTER TABLE time_periods ENABLE ROW LEVEL SECURITY;

-- Step 2: Drop all existing policies
DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'time_periods') 
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON time_periods';
    END LOOP;
END $$;

-- Step 3: Create INSERT policy with UUID casting
CREATE POLICY "time_periods_insert_policy"
ON time_periods
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
);

-- Step 4: Verify it was created
SELECT policyname, cmd, with_check 
FROM pg_policies 
WHERE tablename = 'time_periods';
```

After running this, try saving a time period again in the app.

