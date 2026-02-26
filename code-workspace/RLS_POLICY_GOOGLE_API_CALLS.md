# RLS Policy for `google_api_calls` Table

This file contains SQL statements to create Row-Level Security (RLS) policies for the `public.google_api_calls` table.

## Problem
When geocoding Eircodes, the app tries to save the API call results to the `google_api_calls` table for caching and tracking purposes. However, RLS is blocking these inserts with the error:
```
PostgrestException(message: new row violates row-level security policy for table "google_api_calls", code: 42501)
```

## Solution
Create RLS policies that allow authenticated users to:
- **SELECT**: Read their own API call records (optional, for auditing)
- **INSERT**: Insert new API call records (required for caching)

## SQL Statements

Run these SQL statements in your Supabase SQL Editor:

```sql
-- Enable RLS on google_api_calls table (if not already enabled)
ALTER TABLE public.google_api_calls ENABLE ROW LEVEL SECURITY;

-- Policy: Allow authenticated users to read all API calls
-- (This is useful for admin auditing, but you can restrict it if needed)
CREATE POLICY "Allow authenticated users to read google_api_calls"
ON public.google_api_calls
FOR SELECT
TO authenticated
USING (true);

-- Policy: Allow authenticated users to insert API calls
-- (This is required for the geocoding cache to work)
CREATE POLICY "Allow authenticated users to insert google_api_calls"
ON public.google_api_calls
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Optional: Allow authenticated users to update API calls
-- (Useful if you want to update the call_count field)
CREATE POLICY "Allow authenticated users to update google_api_calls"
ON public.google_api_calls
FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);
```

## Alternative: More Restrictive Policies

If you want to restrict access further (e.g., only allow security level 1 users to read):

```sql
-- Drop the permissive SELECT policy
DROP POLICY IF EXISTS "Allow authenticated users to read google_api_calls" ON public.google_api_calls;

-- Create a more restrictive SELECT policy (only security level 1)
CREATE POLICY "Allow security level 1 users to read google_api_calls"
ON public.google_api_calls
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND security = 1
  )
);
```

## Testing

After applying these policies, test by:
1. Creating a new user with an Eircode
2. Check the console - you should no longer see the RLS error
3. Verify the `google_api_calls` table has a new record with the Eircode and geocoding results

