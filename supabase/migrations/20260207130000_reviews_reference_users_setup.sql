-- ============================================================================
-- reviews.employee_user_id: reference users_setup instead of employees
-- ============================================================================
-- The employee list is obtained from users_setup (user_id, display_name).
-- So reviews should allow any user_id that exists in users_setup as the
-- employee being reviewed.
-- ============================================================================

ALTER TABLE public.reviews
  DROP CONSTRAINT IF EXISTS reviews_employee_user_id_fkey;

ALTER TABLE public.reviews
  ADD CONSTRAINT reviews_employee_user_id_fkey
  FOREIGN KEY (employee_user_id)
  REFERENCES public.users_setup(user_id) ON DELETE CASCADE;
