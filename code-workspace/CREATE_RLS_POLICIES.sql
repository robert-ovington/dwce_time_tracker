-- ============================================================================
-- Row-Level Security (RLS) Policies for Time Periods Tables
-- ============================================================================
-- This script creates RLS policies for all 6 time period related tables.
-- Policies are designed to support the 3-stage approval workflow:
--   Stage 1: 'submitted' - User submits time period
--   Stage 2: 'supervisor_approved' - Supervisor/Manager approves
--   Stage 3: 'admin_approved' - Admin gives final approval
--
-- IMPORTANT: Run UPDATE_APPROVAL_STATUS_ENUM.sql first to add the new enum values
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: Enable RLS on All Tables
-- ============================================================================

ALTER TABLE public.time_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_breaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_used_fleet ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_mobilised_fleet ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_pay_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_revisions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 2: Helper Functions to Check User Roles
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_supervisor_or_manager()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND (
      role IN ('Supervisor', 'Manager', 'Admin')
      OR security <= 4
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND (
      role = 'Admin'
      OR security <= 1
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- STEP 3: RLS Policies for time_periods Table
-- ============================================================================

-- Policy 1: Users can view their own time periods (all stages)
DROP POLICY IF EXISTS "Users can view own time periods" ON public.time_periods;
CREATE POLICY "Users can view own time periods"
  ON public.time_periods FOR SELECT
  USING (auth.uid() = user_id);

-- Policy 2: Users can insert their own time periods (status: submitted)
DROP POLICY IF EXISTS "Users can insert own time periods" ON public.time_periods;
CREATE POLICY "Users can insert own time periods"
  ON public.time_periods FOR INSERT
  WITH CHECK (
    auth.uid() = user_id 
    AND status = 'submitted'
  );

-- Policy 3: Users can update their own submitted time periods (Stage 1 only)
DROP POLICY IF EXISTS "Users can update own submitted time periods" ON public.time_periods;
CREATE POLICY "Users can update own submitted time periods"
  ON public.time_periods FOR UPDATE
  USING (
    auth.uid() = user_id 
    AND status = 'submitted'
  )
  WITH CHECK (
    auth.uid() = user_id 
    AND status = 'submitted'
  );

-- Policy 4: Supervisors can view submitted and supervisor_approved time periods
DROP POLICY IF EXISTS "Supervisors can view submitted time periods" ON public.time_periods;
CREATE POLICY "Supervisors can view submitted time periods"
  ON public.time_periods FOR SELECT
  USING (
    public.is_supervisor_or_manager()
    AND status IN ('submitted', 'supervisor_approved', 'admin_approved')
  );

-- Policy 5: Supervisors can update submitted time periods (to approve or edit)
DROP POLICY IF EXISTS "Supervisors can update submitted time periods" ON public.time_periods;
CREATE POLICY "Supervisors can update submitted time periods"
  ON public.time_periods FOR UPDATE
  USING (
    public.is_supervisor_or_manager()
    AND status = 'submitted'
  )
  WITH CHECK (
    public.is_supervisor_or_manager()
    AND status IN ('submitted', 'supervisor_approved')
  );

-- Policy 6: Admins can view all time periods
DROP POLICY IF EXISTS "Admins can view all time periods" ON public.time_periods;
CREATE POLICY "Admins can view all time periods"
  ON public.time_periods FOR SELECT
  USING (public.is_admin());

-- Policy 7: Admins can update supervisor_approved time periods (to final approval)
DROP POLICY IF EXISTS "Admins can update time periods" ON public.time_periods;
CREATE POLICY "Admins can update time periods"
  ON public.time_periods FOR UPDATE
  USING (
    public.is_admin()
    AND status IN ('submitted', 'supervisor_approved')
  )
  WITH CHECK (
    public.is_admin()
    AND status IN ('submitted', 'supervisor_approved', 'admin_approved')
  );

-- Policy 8: High-level users can insert time periods for others
DROP POLICY IF EXISTS "High-level users can insert for others" ON public.time_periods;
CREATE POLICY "High-level users can insert for others"
  ON public.time_periods FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    OR (
      EXISTS (
        SELECT 1 FROM public.users_setup
        WHERE user_id = auth.uid()
        AND security <= 4
      )
    )
  );

-- ============================================================================
-- STEP 4: RLS Policies for time_period_breaks Table
-- ============================================================================

-- Policy 1: Users can view breaks for their own time periods
DROP POLICY IF EXISTS "Users can view own breaks" ON public.time_period_breaks;
CREATE POLICY "Users can view own breaks"
  ON public.time_period_breaks FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_breaks.time_period_id
      AND user_id = auth.uid()
    )
  );

-- Policy 2: Users can manage breaks for their own submitted time periods
DROP POLICY IF EXISTS "Users can manage breaks for submitted periods" ON public.time_period_breaks;
CREATE POLICY "Users can manage breaks for submitted periods"
  ON public.time_period_breaks FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_breaks.time_period_id
      AND user_id = auth.uid()
      AND status = 'submitted'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_breaks.time_period_id
      AND user_id = auth.uid()
      AND status = 'submitted'
    )
  );

-- Policy 3: Supervisors can view breaks for submitted and approved time periods
DROP POLICY IF EXISTS "Supervisors can view breaks" ON public.time_period_breaks;
CREATE POLICY "Supervisors can view breaks"
  ON public.time_period_breaks FOR SELECT
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_breaks.time_period_id
      AND status IN ('submitted', 'supervisor_approved', 'admin_approved')
    )
  );

-- Policy 4: Supervisors can modify breaks for submitted time periods
DROP POLICY IF EXISTS "Supervisors can modify breaks" ON public.time_period_breaks;
CREATE POLICY "Supervisors can modify breaks"
  ON public.time_period_breaks FOR ALL
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_breaks.time_period_id
      AND status = 'submitted'
    )
  );

-- Policy 5: Admins can view and modify all breaks
DROP POLICY IF EXISTS "Admins can manage all breaks" ON public.time_period_breaks;
CREATE POLICY "Admins can manage all breaks"
  ON public.time_period_breaks FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================================================
-- STEP 5: RLS Policies for time_period_used_fleet Table
-- ============================================================================

-- Policy 1: Users can view used fleet for their own time periods
DROP POLICY IF EXISTS "Users can view own used fleet" ON public.time_period_used_fleet;
CREATE POLICY "Users can view own used fleet"
  ON public.time_period_used_fleet FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_used_fleet.time_period_id
      AND user_id = auth.uid()
    )
  );

-- Policy 2: Users can manage used fleet for their own submitted time periods
DROP POLICY IF EXISTS "Users can manage used fleet for submitted periods" ON public.time_period_used_fleet;
CREATE POLICY "Users can manage used fleet for submitted periods"
  ON public.time_period_used_fleet FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_used_fleet.time_period_id
      AND user_id = auth.uid()
      AND status = 'submitted'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_used_fleet.time_period_id
      AND user_id = auth.uid()
      AND status = 'submitted'
    )
  );

-- Policy 3: Supervisors can view used fleet
DROP POLICY IF EXISTS "Supervisors can view used fleet" ON public.time_period_used_fleet;
CREATE POLICY "Supervisors can view used fleet"
  ON public.time_period_used_fleet FOR SELECT
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_used_fleet.time_period_id
      AND status IN ('submitted', 'supervisor_approved', 'admin_approved')
    )
  );

-- Policy 4: Supervisors can modify used fleet for submitted time periods
DROP POLICY IF EXISTS "Supervisors can modify used fleet" ON public.time_period_used_fleet;
CREATE POLICY "Supervisors can modify used fleet"
  ON public.time_period_used_fleet FOR ALL
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_used_fleet.time_period_id
      AND status = 'submitted'
    )
  );

-- Policy 5: Admins can manage all used fleet
DROP POLICY IF EXISTS "Admins can manage all used fleet" ON public.time_period_used_fleet;
CREATE POLICY "Admins can manage all used fleet"
  ON public.time_period_used_fleet FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================================================
-- STEP 6: RLS Policies for time_period_mobilised_fleet Table
-- ============================================================================

-- Policy 1: Users can view mobilised fleet for their own time periods
DROP POLICY IF EXISTS "Users can view own mobilised fleet" ON public.time_period_mobilised_fleet;
CREATE POLICY "Users can view own mobilised fleet"
  ON public.time_period_mobilised_fleet FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_mobilised_fleet.time_period_id
      AND user_id = auth.uid()
    )
  );

-- Policy 2: Users can manage mobilised fleet for their own submitted time periods
DROP POLICY IF EXISTS "Users can manage mobilised fleet for submitted periods" ON public.time_period_mobilised_fleet;
CREATE POLICY "Users can manage mobilised fleet for submitted periods"
  ON public.time_period_mobilised_fleet FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_mobilised_fleet.time_period_id
      AND user_id = auth.uid()
      AND status = 'submitted'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_mobilised_fleet.time_period_id
      AND user_id = auth.uid()
      AND status = 'submitted'
    )
  );

-- Policy 3: Supervisors can view mobilised fleet
DROP POLICY IF EXISTS "Supervisors can view mobilised fleet" ON public.time_period_mobilised_fleet;
CREATE POLICY "Supervisors can view mobilised fleet"
  ON public.time_period_mobilised_fleet FOR SELECT
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_mobilised_fleet.time_period_id
      AND status IN ('submitted', 'supervisor_approved', 'admin_approved')
    )
  );

-- Policy 4: Supervisors can modify mobilised fleet for submitted time periods
DROP POLICY IF EXISTS "Supervisors can modify mobilised fleet" ON public.time_period_mobilised_fleet;
CREATE POLICY "Supervisors can modify mobilised fleet"
  ON public.time_period_mobilised_fleet FOR ALL
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_mobilised_fleet.time_period_id
      AND status = 'submitted'
    )
  );

-- Policy 5: Admins can manage all mobilised fleet
DROP POLICY IF EXISTS "Admins can manage all mobilised fleet" ON public.time_period_mobilised_fleet;
CREATE POLICY "Admins can manage all mobilised fleet"
  ON public.time_period_mobilised_fleet FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================================================
-- STEP 7: RLS Policies for time_period_pay_rates Table
-- ============================================================================

-- Policy 1: Users can view pay rates for their own time periods
DROP POLICY IF EXISTS "Users can view own pay rates" ON public.time_period_pay_rates;
CREATE POLICY "Users can view own pay rates"
  ON public.time_period_pay_rates FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_pay_rates.time_period_id
      AND user_id = auth.uid()
    )
  );

-- Policy 2: Users can manage pay rates for their own submitted time periods
DROP POLICY IF EXISTS "Users can manage pay rates for submitted periods" ON public.time_period_pay_rates;
CREATE POLICY "Users can manage pay rates for submitted periods"
  ON public.time_period_pay_rates FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_pay_rates.time_period_id
      AND user_id = auth.uid()
      AND status = 'submitted'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_pay_rates.time_period_id
      AND user_id = auth.uid()
      AND status = 'submitted'
    )
  );

-- Policy 3: Supervisors can view pay rates
DROP POLICY IF EXISTS "Supervisors can view pay rates" ON public.time_period_pay_rates;
CREATE POLICY "Supervisors can view pay rates"
  ON public.time_period_pay_rates FOR SELECT
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_pay_rates.time_period_id
      AND status IN ('submitted', 'supervisor_approved', 'admin_approved')
    )
  );

-- Policy 4: Supervisors can modify pay rates for submitted time periods
DROP POLICY IF EXISTS "Supervisors can modify pay rates" ON public.time_period_pay_rates;
CREATE POLICY "Supervisors can modify pay rates"
  ON public.time_period_pay_rates FOR ALL
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_pay_rates.time_period_id
      AND status = 'submitted'
    )
  );

-- Policy 5: Admins can manage all pay rates
DROP POLICY IF EXISTS "Admins can manage all pay rates" ON public.time_period_pay_rates;
CREATE POLICY "Admins can manage all pay rates"
  ON public.time_period_pay_rates FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================================================
-- STEP 8: RLS Policies for time_period_revisions Table
-- ============================================================================

-- Policy 1: Users can view revisions for their own time periods
DROP POLICY IF EXISTS "Users can view own revisions" ON public.time_period_revisions;
CREATE POLICY "Users can view own revisions"
  ON public.time_period_revisions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_revisions.time_period_id
      AND user_id = auth.uid()
    )
  );

-- Policy 2: System can insert revisions (for audit trail)
DROP POLICY IF EXISTS "System can insert revisions" ON public.time_period_revisions;
CREATE POLICY "System can insert revisions"
  ON public.time_period_revisions FOR INSERT
  WITH CHECK (true);

-- Policy 3: Supervisors can view revisions
DROP POLICY IF EXISTS "Supervisors can view revisions" ON public.time_period_revisions;
CREATE POLICY "Supervisors can view revisions"
  ON public.time_period_revisions FOR SELECT
  USING (
    public.is_supervisor_or_manager()
    AND EXISTS (
      SELECT 1 FROM public.time_periods
      WHERE id = time_period_revisions.time_period_id
      AND status IN ('submitted', 'supervisor_approved', 'admin_approved')
    )
  );

-- Policy 4: Admins can view all revisions
DROP POLICY IF EXISTS "Admins can view all revisions" ON public.time_period_revisions;
CREATE POLICY "Admins can view all revisions"
  ON public.time_period_revisions FOR SELECT
  USING (public.is_admin());

-- Policy 5: Revisions are immutable (no updates or deletes)
DROP POLICY IF EXISTS "No updates to revisions" ON public.time_period_revisions;
CREATE POLICY "No updates to revisions"
  ON public.time_period_revisions FOR UPDATE
  USING (false);

DROP POLICY IF EXISTS "No deletes to revisions" ON public.time_period_revisions;
CREATE POLICY "No deletes to revisions"
  ON public.time_period_revisions FOR DELETE
  USING (false);

-- ============================================================================
-- STEP 9: Verification
-- ============================================================================

DO $$
DECLARE
  rec RECORD;
  policy_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO policy_count
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename LIKE 'time_period%';
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'RLS Policies Created Successfully';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Total policies: %', policy_count;
  RAISE NOTICE '';
  RAISE NOTICE 'Policies by table:';
  
  FOR rec IN 
    SELECT tablename, COUNT(*) as count
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename LIKE 'time_period%'
    GROUP BY tablename
    ORDER BY tablename
  LOOP
    RAISE NOTICE '  %: % policies', rec.tablename, rec.count;
  END LOOP;
  
  RAISE NOTICE '========================================';
END $$;

COMMIT;

-- ============================================================================
-- WORKFLOW SUMMARY
-- ============================================================================
-- Stage 1 (submitted): User creates and can edit their time period
--   - User has full control over their submitted time periods
--   - Supervisors and Admins can view these entries
--
-- Stage 2 (supervisor_approved): Supervisor/Manager approves
--   - Supervisor can edit before approving (triggers revision)
--   - Or approve without editing (no revision)
--   - User can no longer edit once supervisor_approved
--   - Admins can still edit/approve
--
-- Stage 3 (admin_approved): Admin gives final approval
--   - Admin can edit before approving (triggers revision)
--   - Or approve without editing (no revision)
--   - Final state - no further edits allowed
-- ============================================================================
