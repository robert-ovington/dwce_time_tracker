-- PPE requests: manager assignment and PPE Manager "User Setup" (request on behalf, bypass approval)
-- 1. ppe_requests.manager_id: manager the request is sent to (users_setup.role = 'Manager')
-- 2. RLS: allow PPE managers to INSERT ppe_requests on behalf of any user with status manager_approved

ALTER TABLE public.ppe_requests
  ADD COLUMN IF NOT EXISTS manager_id uuid NULL REFERENCES public.users_setup(user_id) ON DELETE SET NULL;
COMMENT ON COLUMN public.ppe_requests.manager_id IS 'Manager the request is sent to for approval (users_setup.role = Manager).';

-- Allow PPE managers to insert requests on behalf of any user with status manager_approved (User Setup flow)
DROP POLICY IF EXISTS "ppe_requests_own" ON public.ppe_requests;
CREATE POLICY "ppe_requests_own" ON public.ppe_requests FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR (public.is_ppe_manager() AND status = 'manager_approved')
  );
