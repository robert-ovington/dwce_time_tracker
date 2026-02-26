-- ============================================================================
-- Fix RLS 403 on employees/reviews: allow security as integer OR text
-- ============================================================================
-- PostgREST error 42501 (insufficient_privilege) can occur if users_setup.security
-- is stored as text; IN (1, 2, 3) may not match. This migration recreates the
-- INSERT policies so managers (security 1, 2, or 3) are allowed whether the
-- column is integer or text.
-- ============================================================================

-- employees: insert (managers security 1–3)
DROP POLICY IF EXISTS "employees_insert_managers" ON public.employees;
CREATE POLICY "employees_insert_managers"
  ON public.employees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid()
      AND (
        us.security IN (1, 2, 3)
        OR us.security::text IN ('1', '2', '3')
      )
    )
  );

-- reviews: insert (managers security 1–3, and manager_user_id must be current user)
DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;
CREATE POLICY "reviews_insert"
  ON public.reviews FOR INSERT
  WITH CHECK (
    manager_user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid()
      AND (
        us.security IN (1, 2, 3)
        OR us.security::text IN ('1', '2', '3')
      )
    )
  );
