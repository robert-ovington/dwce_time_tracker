-- ============================================================================
-- Employee Review: employees, reviews, review_categories, review_scores + RLS
-- ============================================================================

-- employees: users who can be reviewed (user_id = auth user id)
CREATE TABLE IF NOT EXISTS public.employees (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE
);

COMMENT ON TABLE public.employees IS 'Users who are reviewable (employee side of reviews)';

-- Seed employees with all current users in users_setup (so they can be reviewed)
INSERT INTO public.employees (user_id)
  SELECT user_id FROM public.users_setup
  ON CONFLICT (user_id) DO NOTHING;

-- review_categories: 7 fixed categories
CREATE TABLE IF NOT EXISTS public.review_categories (
  id smallint PRIMARY KEY,
  name text NOT NULL UNIQUE
);

COMMENT ON TABLE public.review_categories IS 'Fixed categories for review scores';

INSERT INTO public.review_categories (id, name) VALUES
  (1, 'Health & Safety'),
  (2, 'Organisation Efficiency'),
  (3, 'Workmanship'),
  (4, 'Reliability & Dependability'),
  (5, 'Maintenance of Plant'),
  (6, 'Cooperation & Attitude'),
  (7, 'Paperwork')
ON CONFLICT (id) DO NOTHING;

-- reviews: one per employee/manager/date
CREATE TABLE IF NOT EXISTS public.reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_user_id uuid NOT NULL REFERENCES public.employees(user_id) ON DELETE CASCADE,
  manager_user_id uuid NOT NULL REFERENCES public.users_setup(user_id) ON DELETE CASCADE,
  review_date date NOT NULL,
  review_week date GENERATED ALWAYS AS (date_trunc('week', review_date)::date) STORED,
  submitted_at timestamptz DEFAULT now(),
  UNIQUE (employee_user_id, manager_user_id, review_date)
);

COMMENT ON TABLE public.reviews IS 'Daily employee review header (one per employee/manager/date)';

CREATE INDEX IF NOT EXISTS idx_reviews_employee_manager_date
  ON public.reviews (employee_user_id, manager_user_id, review_date);

-- review_scores: one row per review per category (7 per review)
CREATE TABLE IF NOT EXISTS public.review_scores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
  category_id smallint NOT NULL REFERENCES public.review_categories(id),
  score smallint NOT NULL CHECK (score IN (1, 2, 3)),
  comment text,
  UNIQUE (review_id, category_id),
  CONSTRAINT chk_comment_required CHECK (
    (score IN (1, 3) AND comment IS NOT NULL AND trim(comment) <> '')
    OR (score = 2 AND (comment IS NULL OR trim(comment) = ''))
  )
);

COMMENT ON TABLE public.review_scores IS 'Per-category score and optional comment for a review';

CREATE INDEX IF NOT EXISTS idx_review_scores_review_id ON public.review_scores (review_id);

-- ============================================================================
-- RLS
-- ============================================================================

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_scores ENABLE ROW LEVEL SECURITY;

-- review_categories: read-only for everyone who can read reviews
CREATE POLICY "review_categories_select"
  ON public.review_categories FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid() AND us.security IN (1, 2, 3)
    )
  );

-- employees: select for security 1–3 (managers)
CREATE POLICY "employees_select_managers"
  ON public.employees FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid() AND us.security IN (1, 2, 3)
    )
  );

-- employees: insert so managers can add a user as employee when submitting a review (e.g. if list was from users_data fallback)
CREATE POLICY "employees_insert_managers"
  ON public.employees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid() AND us.security IN (1, 2, 3)
    )
  );

-- reviews: select – security 1 all; security 2–3 own (as manager or employee)
CREATE POLICY "reviews_select"
  ON public.reviews FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid()
      AND (
        us.security = 1
        OR (us.security IN (2, 3) AND (manager_user_id = auth.uid() OR employee_user_id = auth.uid()))
      )
    )
  );

-- reviews: insert – security 1–3 as manager (manager_user_id = auth.uid())
CREATE POLICY "reviews_insert"
  ON public.reviews FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users_setup us
      WHERE us.user_id = auth.uid() AND us.security IN (1, 2, 3)
    )
    AND manager_user_id = auth.uid()
  );

-- review_scores: select same as reviews (via review_id)
CREATE POLICY "review_scores_select"
  ON public.review_scores FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.reviews r
      JOIN public.users_setup us ON us.user_id = auth.uid()
      WHERE r.id = review_scores.review_id
      AND (
        us.security = 1
        OR (us.security IN (2, 3) AND (r.manager_user_id = auth.uid() OR r.employee_user_id = auth.uid()))
      )
    )
  );

-- review_scores: insert for review owned by current user as manager
CREATE POLICY "review_scores_insert"
  ON public.review_scores FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.reviews r
      WHERE r.id = review_id AND r.manager_user_id = auth.uid()
    )
  );
