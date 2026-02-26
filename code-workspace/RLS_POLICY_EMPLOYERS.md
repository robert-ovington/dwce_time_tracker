# RLS Policies for Employers Table

## Problem
The `employers` table has RLS enabled but no policies, causing 403 errors when trying to create/update/delete employers.

## Solution
Run these SQL statements in your Supabase SQL Editor to create the necessary RLS policies.

## SQL Statements

```sql
-- Enable RLS on employers table (if not already enabled)
ALTER TABLE public.employers ENABLE ROW LEVEL SECURITY;

-- Policy: Allow SELECT for all authenticated users
CREATE POLICY "Allow authenticated users to read employers"
ON public.employers
FOR SELECT
TO authenticated
USING (true);

-- Policy: Allow INSERT for users with security level 1 (admins)
CREATE POLICY "Allow security level 1 users to insert employers"
ON public.employers
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.users_setup
    WHERE users_setup.user_id = auth.uid()
    AND users_setup.security = 1
  )
);

-- Policy: Allow UPDATE for users with security level 1 (admins)
CREATE POLICY "Allow security level 1 users to update employers"
ON public.employers
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.users_setup
    WHERE users_setup.user_id = auth.uid()
    AND users_setup.security = 1
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.users_setup
    WHERE users_setup.user_id = auth.uid()
    AND users_setup.security = 1
  )
);

-- Policy: Allow DELETE for users with security level 1 (admins)
CREATE POLICY "Allow security level 1 users to delete employers"
ON public.employers
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.users_setup
    WHERE users_setup.user_id = auth.uid()
    AND users_setup.security = 1
  )
);
```

## Alternative: Using Helper Function (if you have it)

If you already have the `public.user_has_security_1(user_uuid UUID)` helper function from the users_setup RLS setup, you can use it instead:

```sql
-- Policy: Allow INSERT for users with security level 1 (admins)
CREATE POLICY "Allow security level 1 users to insert employers"
ON public.employers
FOR INSERT
TO authenticated
WITH CHECK (public.user_has_security_1(auth.uid()));

-- Policy: Allow UPDATE for users with security level 1 (admins)
CREATE POLICY "Allow security level 1 users to update employers"
ON public.employers
FOR UPDATE
TO authenticated
USING (public.user_has_security_1(auth.uid()))
WITH CHECK (public.user_has_security_1(auth.uid()));

-- Policy: Allow DELETE for users with security level 1 (admins)
CREATE POLICY "Allow security level 1 users to delete employers"
ON public.employers
FOR DELETE
TO authenticated
USING (public.user_has_security_1(auth.uid()));
```

## Verification

After running the policies, verify they exist:

```sql
SELECT * FROM pg_policies WHERE tablename = 'employers';
```

## Notes

- All authenticated users can READ employers (SELECT)
- Only users with security level 1 (admins) can CREATE, UPDATE, or DELETE employers
- Make sure the `users_setup` table has a record for your user with `security = 1`

