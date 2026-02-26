-- ============================================================================
-- time_attendance: allow users to SELECT their own rows (for My Clockings screen)
-- ============================================================================
-- If My Clockings shows no entries, RLS was likely blocking SELECT. This policy
-- lets authenticated users read rows where user_id = auth.uid().
-- ============================================================================

ALTER TABLE IF EXISTS public.time_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own time_attendance" ON public.time_attendance;
CREATE POLICY "Users can view own time_attendance"
  ON public.time_attendance
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());
