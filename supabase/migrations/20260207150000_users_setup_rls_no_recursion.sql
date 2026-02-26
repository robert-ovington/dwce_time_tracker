-- ============================================================================
-- Fix "infinite recursion detected in policy for relation users_setup"
-- ============================================================================
-- RLS policies on users_setup must NOT subquery users_setup (e.g. to get the
-- current user's security). That causes infinite recursion. Use this
-- SECURITY DEFINER function instead: it reads the current user's row while
-- bypassing RLS, so policies can use it without recursion.
--
-- You must update every users_setup policy that currently does:
--   EXISTS (SELECT 1 FROM users_setup us WHERE us.user_id = auth.uid() AND ...)
-- to use these helpers instead, e.g.:
--   get_my_users_setup_security() BETWEEN 1 AND 2
--   get_my_users_setup_security() IN (1, 2, 3)
-- ============================================================================

-- Returns the current user's security value (integer or NULL). Safe to use in RLS.
-- Handles security stored as integer or text.
CREATE OR REPLACE FUNCTION public.get_my_users_setup_security()
RETURNS smallint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (security::text)::smallint FROM public.users_setup WHERE user_id = auth.uid() LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_my_users_setup_security() IS
  'Returns current user security from users_setup. Use in RLS to avoid recursion.';

-- Optional: returns true if current user's security is in the given range (inclusive).
CREATE OR REPLACE FUNCTION public.get_my_security_between(low smallint, high smallint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (SELECT security FROM public.users_setup WHERE user_id = auth.uid() LIMIT 1) BETWEEN low AND high;
$$;

COMMENT ON FUNCTION public.get_my_security_between(smallint, smallint) IS
  'Returns true if current user security is between low and high. Use in RLS to avoid recursion.';

-- ============================================================================
-- YOU MUST UPDATE YOUR users_setup POLICIES to use these functions
-- ============================================================================
-- Replace any condition that subqueries users_setup with auth.uid(), e.g.:
--
--   EXISTS (SELECT 1 FROM public.users_setup us WHERE us.user_id = auth.uid() AND us.security BETWEEN 1 AND 2)
-- becomes:
--   get_my_users_setup_security() BETWEEN 1 AND 2
--
--   EXISTS (SELECT 1 FROM public.users_setup us WHERE us.user_id = auth.uid() AND us.security IN (1, 2, 3))
-- becomes:
--   get_my_users_setup_security() IN (1, 2, 3)
--
--   user_id = auth.uid()  (for "own row" policy) is fine and does NOT cause recursion.
-- Only subqueries like "SELECT ... FROM users_setup WHERE user_id = auth.uid()"
-- cause recursion and must be replaced with get_my_users_setup_security() or
-- get_my_security_between(low, high).
-- ============================================================================
