-- Run this in Supabase Dashboard → SQL Editor if you get 400 with error 42703 on POST ppe_requests.
-- 42703 = undefined_column: the app sends manager_id but the column does not exist yet.
-- This adds the column and updates the insert policy. Safe to run multiple times (IF NOT EXISTS / DROP IF EXISTS).

ALTER TABLE public.ppe_requests
  ADD COLUMN IF NOT EXISTS manager_id uuid NULL REFERENCES public.users_setup(user_id) ON DELETE SET NULL;

COMMENT ON COLUMN public.ppe_requests.manager_id IS 'Manager the request is sent to for approval (users_setup.role = Manager).';

DROP POLICY IF EXISTS "ppe_requests_own" ON public.ppe_requests;
CREATE POLICY "ppe_requests_own" ON public.ppe_requests FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR (public.is_ppe_manager() AND status = 'manager_approved')
  );
