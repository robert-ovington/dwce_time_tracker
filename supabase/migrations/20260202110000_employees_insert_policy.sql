-- Allow managers (security 1–3) to insert into employees so the Submit Employee Review
-- screen can add users when the list is loaded from users_data fallback.
DROP POLICY IF EXISTS "employees_insert_managers" ON public.employees;
CREATE POLICY "employees_insert_managers"
  ON public.employees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid() AND us.security IN (1, 2, 3)
    )
  );
