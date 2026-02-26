-- Allow supervisors to see and act on time_periods with status 'imported' (payroll import).
-- Policy 4: Supervisor SELECT must include 'imported'.
-- Policy 5: Supervisor UPDATE (to approve) must allow rows with status 'imported'.

DROP POLICY IF EXISTS "Supervisors can view submitted time periods" ON public.time_periods;
CREATE POLICY "Supervisors can view submitted time periods"
  ON public.time_periods FOR SELECT
  USING (
    public.is_supervisor_or_manager()
    AND status IN ('submitted', 'imported', 'supervisor_approved', 'admin_approved')
  );

DROP POLICY IF EXISTS "Supervisors can update submitted time periods" ON public.time_periods;
CREATE POLICY "Supervisors can update submitted time periods"
  ON public.time_periods FOR UPDATE
  USING (
    public.is_supervisor_or_manager()
    AND status IN ('submitted', 'imported', 'supervisor_approved')
  )
  WITH CHECK (
    public.is_supervisor_or_manager()
    AND status IN ('submitted', 'imported', 'supervisor_approved')
  );
