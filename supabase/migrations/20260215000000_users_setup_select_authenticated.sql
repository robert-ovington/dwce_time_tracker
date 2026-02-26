-- Allow all authenticated users to SELECT from users_setup (for display names in dropdowns).
-- Without this, security 4+ cannot see users_setup rows when loading request_manager_list
-- with expand users_setup(display_name), so the Manager List on PPE Request / Request Time Off
-- appears empty for them. PPE Managers (security 2-3) already had access via
-- users_setup_select_supervisors_and_above.

DROP POLICY IF EXISTS "users_setup_select_authenticated" ON public.users_setup;
CREATE POLICY "users_setup_select_authenticated"
  ON public.users_setup FOR SELECT TO authenticated
  USING (true);

COMMENT ON POLICY "users_setup_select_authenticated" ON public.users_setup IS
  'Any logged-in user can read users_setup (e.g. display_name for request manager list, dropdowns).';
