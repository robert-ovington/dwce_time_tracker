-- ============================================================================
-- users_setup: allow managers (security 1–3) to SELECT all rows for employee list
-- ============================================================================
-- Submit Employee Review screen loads the employee dropdown from users_setup
-- (user_id, display_name). If RLS on users_setup only allows "own row", managers
-- see only themselves. This migration adds a policy so users with security 1, 2,
-- or 3 can SELECT all rows from users_setup (needed for the review employee list).
-- Also ensure users can always SELECT their own row (for profile/settings).
-- ============================================================================

-- Ensure RLS is enabled on users_setup (no-op if already enabled)
ALTER TABLE public.users_setup ENABLE ROW LEVEL SECURITY;

-- Drop if exists so migration is idempotent
DROP POLICY IF EXISTS "users_setup_select_managers" ON public.users_setup;
DROP POLICY IF EXISTS "users_setup_select_own" ON public.users_setup;

-- Managers (security 1, 2, 3) can SELECT all rows (for employee list, dropdowns, etc.)
CREATE POLICY "users_setup_select_managers"
  ON public.users_setup FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid()
      AND (
        us.security IN (1, 2, 3)
        OR us.security::text IN ('1', '2', '3')
      )
    )
  );

-- Users can always SELECT their own row (for profile, settings, getCurrentUserData)
CREATE POLICY "users_setup_select_own"
  ON public.users_setup FOR SELECT
  USING (user_id = auth.uid());
