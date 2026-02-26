-- ============================================================================
-- RLS: determine supervisor/admin access by SECURITY LEVEL only (not role)
-- ============================================================================
-- Supervisor approval screen was missing Employee, Role, and Used Plant & Equipment
-- for some users. Access must be determined only by users_setup.security, not by
-- users_setup.role. This migration:
-- 1. is_supervisor_or_manager(): true when security between 2 and 3 (no role check).
-- 2. is_admin(): true when security = 1 (no role check).
-- 3. users_setup SELECT: allow security 2–3 to SELECT all rows (for dropdowns and
--    RPC joins). Security 1 (admin) has full access via other policies.
-- 4. time_period_used_fleet: ensure supervisors (2–3) can SELECT used fleet for
--    periods they can see (submitted, supervisor_approved, admin_approved).
-- ============================================================================

-- Helper: supervisor-level access by security only (2–3). Used by time_periods,
-- time_period_used_fleet, time_period_breaks, time_period_mobilised_fleet RLS.
CREATE OR REPLACE FUNCTION public.is_supervisor_or_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_my_security_between(2::smallint, 3::smallint);
$$;

COMMENT ON FUNCTION public.is_supervisor_or_manager() IS
  'True if current user has supervisor-level access by security level only (security between 2 and 3). Role is not used.';

-- Helper: admin-level access by security only (1).
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_my_security_between(1::smallint, 1::smallint);
$$;

COMMENT ON FUNCTION public.is_admin() IS
  'True if current user has admin access by security level only (security = 1). Role is not used.';

-- ============================================================================
-- users_setup: allow security 2–3 (supervisors/managers) to SELECT all rows
-- ============================================================================
-- Required for supervisor approval screen (employee/role from joined users_setup)
-- and for Submit Employee Review dropdown. Security 1 (admin) can see all via
-- other mechanisms; 2–3 need this for dropdowns and RPC joins.
-- ============================================================================

DROP POLICY IF EXISTS "users_setup_select_managers" ON public.users_setup;
DROP POLICY IF EXISTS "users_setup_select_supervisors_and_above" ON public.users_setup;

-- Admins (security 1) can SELECT all rows
CREATE POLICY "users_setup_select_admins"
  ON public.users_setup FOR SELECT
  USING (public.is_admin());

-- Supervisors/managers (security 2–3) can SELECT all rows (dropdowns, RPC joins)
CREATE POLICY "users_setup_select_supervisors_and_above"
  ON public.users_setup FOR SELECT
  USING (public.get_my_security_between(2::smallint, 3::smallint));

-- Keep "users_setup_select_own" so users with security > 3 can see their own row.

-- ============================================================================
-- time_period_used_fleet: supervisors (2–3) can view used fleet for visible periods
-- ============================================================================
-- Ensures "Used Plant & Equipment" populates for security 2–3 on supervisor approval
-- screen. Policy may be missing if only code-workspace RLS was applied.
-- ============================================================================

ALTER TABLE public.time_period_used_fleet ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Supervisors can view used fleet" ON public.time_period_used_fleet;
CREATE POLICY "Supervisors can view used fleet"
  ON public.time_period_used_fleet FOR SELECT
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods tp
      WHERE tp.id = time_period_used_fleet.time_period_id
      AND tp.status IN ('submitted', 'imported', 'supervisor_approved', 'admin_approved')
    )
  );
