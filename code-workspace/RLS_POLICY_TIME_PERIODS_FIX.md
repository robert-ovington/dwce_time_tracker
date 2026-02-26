# RLS Policy Fix for time_periods Table

## Problem
The `time_periods` table is blocking inserts with error: "new row violates row-level security policy for table 'time_periods'"

## Solution
You need to create or update the RLS policy on the `time_periods` table in Supabase to allow authenticated users to insert their own records.

## Steps to Fix

1. Go to your Supabase Dashboard
2. Navigate to **Table Editor** → **time_periods**
3. Click on **Policies** tab
4. Check if there's an INSERT policy. If not, create one.

## SQL to Create/Update RLS Policy

Run this SQL in the Supabase SQL Editor:

```sql
-- Enable RLS on time_periods table (if not already enabled)
ALTER TABLE time_periods ENABLE ROW LEVEL SECURITY;

-- Drop existing INSERT policy if it exists (optional, only if you want to replace it)
DROP POLICY IF EXISTS "Users can insert their own time periods" ON time_periods;

-- Create INSERT policy: Allow authenticated users to insert their own time periods
CREATE POLICY "Users can insert their own time periods"
ON time_periods
FOR INSERT
TO authenticated
WITH CHECK (
  -- User can only insert records where user_id matches their authenticated user ID
  user_id = auth.uid()
);

-- Optional: Also create SELECT policy if users need to read their own records
DROP POLICY IF EXISTS "Users can view their own time periods" ON time_periods;

CREATE POLICY "Users can view their own time periods"
ON time_periods
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);

-- Optional: UPDATE policy if users need to update their own records
DROP POLICY IF EXISTS "Users can update their own time periods" ON time_periods;

CREATE POLICY "Users can update their own time periods"
ON time_periods
FOR UPDATE
TO authenticated
USING (
  user_id = auth.uid()
)
WITH CHECK (
  user_id = auth.uid()
);

-- Optional: DELETE policy if users need to delete their own records
DROP POLICY IF EXISTS "Users can delete their own time periods" ON time_periods;

CREATE POLICY "Users can delete their own time periods"
ON time_periods
FOR DELETE
TO authenticated
USING (
  user_id = auth.uid()
);
```

## For Admin Users (Optional)

If you want admins to be able to create time periods for other employees, you can create an additional policy:

```sql
-- First, check if user is admin (you'll need to join with users_setup or similar table)
-- This is more complex and requires a function or additional check

-- Option 1: Use a function to check admin status
CREATE OR REPLACE FUNCTION is_admin(user_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM users_setup 
    WHERE user_id = user_uuid 
    AND (role = 'Admin' OR security <= 2)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Then create policy for admins
CREATE POLICY "Admins can insert time periods for any user"
ON time_periods
FOR INSERT
TO authenticated
WITH CHECK (
  is_admin(auth.uid())
);
```

## Verification

After creating the policies, test by:
1. Trying to save a time period in the app
2. Check the Supabase logs to see if the insert succeeds
3. Verify the record appears in the `time_periods` table

## Current Status

- **Authenticated User ID**: `3ab5b7de-95cb-4e1a-833e-21fdc0fb76da`
- **User ID in Request**: `3ab5b7de-95cb-4e1a-833e-21fdc0fb76da` ✅ (matches)
- **Error**: RLS policy blocking insert

The code is correctly sending the authenticated user's ID, so the issue is purely with the RLS policy configuration in Supabase.

