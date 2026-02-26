-- Request types (e.g. Time Off, PPE) and curated manager list per type.
-- Users pick a manager from request_manager_list for the request type instead of the full users_setup list.

-- request_type: categories for requests (Time Off, PPE, etc.)
CREATE TABLE IF NOT EXISTS public.request_type (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  display_order smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.request_type IS 'Request categories (Time Off, PPE, etc.) for manager assignment.';
COMMENT ON COLUMN public.request_type.code IS 'Programmatic code, e.g. time_off, ppe.';
COMMENT ON COLUMN public.request_type.name IS 'Display name, e.g. Time Off, PPE.';

-- request_manager_list: which managers can be chosen per request type
CREATE TABLE IF NOT EXISTS public.request_manager_list (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_type_id uuid NOT NULL REFERENCES public.request_type(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users_setup(user_id) ON DELETE CASCADE,
  display_order smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_type_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_request_manager_list_type ON public.request_manager_list(request_type_id);
CREATE INDEX IF NOT EXISTS idx_request_manager_list_user ON public.request_manager_list(user_id);

COMMENT ON TABLE public.request_manager_list IS 'Curated list of managers per request type; users select from this list only.';

-- Seed request types
INSERT INTO public.request_type (code, name, display_order)
VALUES
  ('time_off', 'Time Off', 1),
  ('ppe', 'PPE', 2)
ON CONFLICT (code) DO NOTHING;

-- RLS
ALTER TABLE public.request_type ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_manager_list ENABLE ROW LEVEL SECURITY;

-- Everyone authenticated can read types and manager list (for dropdowns)
DROP POLICY IF EXISTS "request_type_select" ON public.request_type;
CREATE POLICY "request_type_select" ON public.request_type FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "request_manager_list_select" ON public.request_manager_list;
CREATE POLICY "request_manager_list_select" ON public.request_manager_list FOR SELECT TO authenticated USING (true);

-- Only admins (security = 1) can manage types and manager list
DROP POLICY IF EXISTS "request_type_admin_all" ON public.request_type;
CREATE POLICY "request_type_admin_all" ON public.request_type FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "request_manager_list_admin_all" ON public.request_manager_list;
CREATE POLICY "request_manager_list_admin_all" ON public.request_manager_list FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- leave_requests: add manager_id so time off requests can be assigned to a manager
ALTER TABLE public.leave_requests
  ADD COLUMN IF NOT EXISTS manager_id uuid NULL REFERENCES public.users_setup(user_id) ON DELETE SET NULL;

COMMENT ON COLUMN public.leave_requests.manager_id IS 'Manager the time off request is sent to (from request_manager_list for Time Off).';
