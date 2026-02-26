-- ============================================================================
-- PPE Module: schema, enums, helper, tables, triggers, view, RLS
-- ============================================================================
-- 1. users_setup.ppe_manager column
-- 2. Enums and is_ppe_manager()
-- 3. Tables: ppe_list, ppe_sizes, ppe_purchases, ppe_ledger, ppe_user_preferences,
--    ppe_allocations, ppe_requests, ppe_request_approvals
-- 4. Triggers and functions
-- 5. View ppe_stock_levels
-- 6. RLS on all tables
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. users_setup: add ppe_manager (visible to users with this true for PPE Management menu)
-- ----------------------------------------------------------------------------
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS ppe_manager boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.users_setup.ppe_manager IS 'Enable PPE Management menu and allocation write access when true (with security 1-3).';

-- ----------------------------------------------------------------------------
-- 2. Enums
-- ----------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.ppe_category AS ENUM ('clothing', 'footwear');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.ppe_dispatch_status AS ENUM ('pending', 'dispatched', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.ppe_request_status AS ENUM (
    'submitted', 'manager_approved', 'purchasing_approved', 'dispatched', 'rejected', 'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.ppe_approval_stage AS ENUM ('manager', 'purchasing');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.ppe_ledger_reason AS ENUM ('delivery', 'allocation', 'adjustment');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- Helper: is_ppe_manager() - true when user has security 1-3 AND ppe_manager = true
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_ppe_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND (security::text)::smallint BETWEEN 1 AND 3
    AND ppe_manager = true
  );
$$;
COMMENT ON FUNCTION public.is_ppe_manager() IS 'True when current user has security 1-3 and users_setup.ppe_manager = true.';

-- ----------------------------------------------------------------------------
-- Generic set_updated_at trigger (used by ppe_list, ppe_user_preferences, ppe_requests)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Validate size per category (clothing: S,M,L,XL,2XL,3XL; footwear: 7-13). Used on ppe_sizes only.
CREATE OR REPLACE FUNCTION public.ppe_validate_size_fk()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  code text;
  cat public.ppe_category;
BEGIN
  IF TG_TABLE_NAME = 'ppe_sizes' THEN
    code := NEW.size_code;
    SELECT category INTO cat FROM public.ppe_list WHERE id = NEW.ppe_id;
    IF cat = 'clothing' AND code NOT IN ('S', 'M', 'L', 'XL', '2XL', '3XL') THEN
      RAISE EXCEPTION 'ppe_validate_size: clothing size must be S, M, L, XL, 2XL, 3XL';
    END IF;
    IF cat = 'footwear' THEN
      IF code !~ '^\d+$' THEN
        RAISE EXCEPTION 'ppe_validate_size: footwear size must be numeric';
      END IF;
      IF code::int < 7 OR code::int > 13 THEN
        RAISE EXCEPTION 'ppe_validate_size: footwear size must be 7-13; got %', code;
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Tables
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ppe_list (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  category public.ppe_category NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ppe_sizes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ppe_id uuid NOT NULL REFERENCES public.ppe_list(id) ON DELETE CASCADE,
  size_code text NOT NULL,
  UNIQUE(ppe_id, size_code)
);

CREATE TABLE IF NOT EXISTS public.ppe_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ppe_id uuid NOT NULL REFERENCES public.ppe_list(id) ON DELETE RESTRICT,
  size_code text NOT NULL,
  change_qty integer NOT NULL,
  reason public.ppe_ledger_reason NOT NULL,
  reference_id uuid NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  CONSTRAINT fk_ppe_ledger_size FOREIGN KEY (ppe_id, size_code) REFERENCES public.ppe_sizes(ppe_id, size_code) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.ppe_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ppe_id uuid NOT NULL REFERENCES public.ppe_list(id) ON DELETE RESTRICT,
  size_code text NOT NULL,
  quantity_received integer NOT NULL CHECK (quantity_received >= 0),
  unit_cost numeric(12,2) NOT NULL CHECK (unit_cost >= 0),
  received_at timestamptz NOT NULL DEFAULT now(),
  received_by uuid NOT NULL,
  notes text NULL,
  CONSTRAINT fk_ppe_purchases_size FOREIGN KEY (ppe_id, size_code) REFERENCES public.ppe_sizes(ppe_id, size_code) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.ppe_user_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  ppe_id uuid NOT NULL REFERENCES public.ppe_list(id) ON DELETE CASCADE,
  preferred_size_code text NOT NULL,
  notes text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, ppe_id),
  CONSTRAINT fk_ppe_user_pref_size FOREIGN KEY (ppe_id, preferred_size_code) REFERENCES public.ppe_sizes(ppe_id, size_code) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.ppe_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  ppe_id uuid NOT NULL REFERENCES public.ppe_list(id) ON DELETE RESTRICT,
  size_code text NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  unit_cost numeric(12,2) NOT NULL CHECK (unit_cost >= 0),
  allocated_at timestamptz NOT NULL DEFAULT now(),
  allocated_by uuid NOT NULL,
  dispatch_status public.ppe_dispatch_status NOT NULL DEFAULT 'pending',
  dispatched_at timestamptz NULL,
  dispatched_by uuid NULL,
  dispatch_notes text NULL,
  notes text NULL,
  CONSTRAINT fk_ppe_alloc_size FOREIGN KEY (ppe_id, size_code) REFERENCES public.ppe_sizes(ppe_id, size_code) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.ppe_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  ppe_id uuid NOT NULL REFERENCES public.ppe_list(id) ON DELETE RESTRICT,
  requested_size_code text NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  reason text NULL,
  status public.ppe_request_status NOT NULL DEFAULT 'submitted',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fk_ppe_requests_size FOREIGN KEY (ppe_id, requested_size_code) REFERENCES public.ppe_sizes(ppe_id, size_code) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.ppe_request_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ppe_requests(id) ON DELETE CASCADE,
  stage public.ppe_approval_stage NOT NULL,
  approved boolean NOT NULL,
  approved_by uuid NOT NULL,
  approved_at timestamptz NOT NULL DEFAULT now(),
  notes text NULL,
  UNIQUE(request_id, stage)
);

-- Triggers: set_updated_at on ppe_list, ppe_user_preferences, ppe_requests
DROP TRIGGER IF EXISTS set_updated_at_ppe_list ON public.ppe_list;
CREATE TRIGGER set_updated_at_ppe_list BEFORE UPDATE ON public.ppe_list FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_updated_at_ppe_user_preferences ON public.ppe_user_preferences;
CREATE TRIGGER set_updated_at_ppe_user_preferences BEFORE UPDATE ON public.ppe_user_preferences FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_updated_at_ppe_requests ON public.ppe_requests;
CREATE TRIGGER set_updated_at_ppe_requests BEFORE UPDATE ON public.ppe_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ppe_validate_size on ppe_sizes
DROP TRIGGER IF EXISTS ppe_validate_size_sizes ON public.ppe_sizes;
CREATE TRIGGER ppe_validate_size_sizes BEFORE INSERT OR UPDATE ON public.ppe_sizes FOR EACH ROW EXECUTE FUNCTION public.ppe_validate_size_fk();

-- After INSERT on ppe_purchases -> ledger
CREATE OR REPLACE FUNCTION public.ppe_purchase_to_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ppe_ledger (ppe_id, size_code, change_qty, reason, reference_id, created_by)
  VALUES (NEW.ppe_id, NEW.size_code, NEW.quantity_received, 'delivery'::public.ppe_ledger_reason, NEW.id, NEW.received_by);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS ppe_purchase_to_ledger ON public.ppe_purchases;
CREATE TRIGGER ppe_purchase_to_ledger AFTER INSERT ON public.ppe_purchases FOR EACH ROW EXECUTE FUNCTION public.ppe_purchase_to_ledger();

-- After INSERT on ppe_allocations -> ledger
CREATE OR REPLACE FUNCTION public.ppe_allocation_to_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.ppe_ledger (ppe_id, size_code, change_qty, reason, reference_id, created_by)
  VALUES (NEW.ppe_id, NEW.size_code, -NEW.quantity, 'allocation'::public.ppe_ledger_reason, NEW.id, NEW.allocated_by);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS ppe_allocation_to_ledger ON public.ppe_allocations;
CREATE TRIGGER ppe_allocation_to_ledger AFTER INSERT ON public.ppe_allocations FOR EACH ROW EXECUTE FUNCTION public.ppe_allocation_to_ledger();

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ppe_sizes_ppe_id_size ON public.ppe_sizes(ppe_id, size_code);
CREATE INDEX IF NOT EXISTS idx_ppe_ledger_ppe_size ON public.ppe_ledger(ppe_id, size_code);
CREATE INDEX IF NOT EXISTS idx_ppe_allocations_user ON public.ppe_allocations(user_id);
CREATE INDEX IF NOT EXISTS idx_ppe_requests_user ON public.ppe_requests(user_id);

-- ----------------------------------------------------------------------------
-- View: ppe_stock_levels
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.ppe_stock_levels AS
SELECT ppe_id, size_code, COALESCE(SUM(change_qty), 0) AS on_hand
FROM public.ppe_ledger
GROUP BY ppe_id, size_code;

-- ----------------------------------------------------------------------------
-- 6. RLS
-- ----------------------------------------------------------------------------
ALTER TABLE public.ppe_list ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ppe_sizes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ppe_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ppe_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ppe_user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ppe_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ppe_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ppe_request_approvals ENABLE ROW LEVEL SECURITY;

-- ppe_list: SELECT all authenticated; ALL if security 1-3
DROP POLICY IF EXISTS "ppe_list_select_authenticated" ON public.ppe_list;
CREATE POLICY "ppe_list_select_authenticated" ON public.ppe_list FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "ppe_list_all_managers" ON public.ppe_list;
CREATE POLICY "ppe_list_all_managers" ON public.ppe_list FOR ALL TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint))
  WITH CHECK (public.get_my_security_between(1::smallint, 3::smallint));

-- ppe_sizes: SELECT all; ALL if security 1-3
DROP POLICY IF EXISTS "ppe_sizes_select_authenticated" ON public.ppe_sizes;
CREATE POLICY "ppe_sizes_select_authenticated" ON public.ppe_sizes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "ppe_sizes_all_managers" ON public.ppe_sizes;
CREATE POLICY "ppe_sizes_all_managers" ON public.ppe_sizes FOR ALL TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint))
  WITH CHECK (public.get_my_security_between(1::smallint, 3::smallint));

-- ppe_purchases: managers only
DROP POLICY IF EXISTS "ppe_purchases_managers" ON public.ppe_purchases;
CREATE POLICY "ppe_purchases_managers" ON public.ppe_purchases FOR ALL TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint))
  WITH CHECK (public.get_my_security_between(1::smallint, 3::smallint));

-- ppe_ledger: managers only
DROP POLICY IF EXISTS "ppe_ledger_managers" ON public.ppe_ledger;
CREATE POLICY "ppe_ledger_managers" ON public.ppe_ledger FOR ALL TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint))
  WITH CHECK (public.get_my_security_between(1::smallint, 3::smallint));

-- ppe_user_preferences: own row CRUD; managers can SELECT all
DROP POLICY IF EXISTS "ppe_user_preferences_own" ON public.ppe_user_preferences;
CREATE POLICY "ppe_user_preferences_own" ON public.ppe_user_preferences FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "ppe_user_preferences_managers_select" ON public.ppe_user_preferences;
CREATE POLICY "ppe_user_preferences_managers_select" ON public.ppe_user_preferences FOR SELECT TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint));

-- ppe_allocations: user sees own; managers see all; INSERT/UPDATE only is_ppe_manager()
DROP POLICY IF EXISTS "ppe_allocations_own_select" ON public.ppe_allocations;
CREATE POLICY "ppe_allocations_own_select" ON public.ppe_allocations FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "ppe_allocations_managers_select" ON public.ppe_allocations;
CREATE POLICY "ppe_allocations_managers_select" ON public.ppe_allocations FOR SELECT TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint));
DROP POLICY IF EXISTS "ppe_allocations_ppe_manager_write" ON public.ppe_allocations;
CREATE POLICY "ppe_allocations_ppe_manager_write" ON public.ppe_allocations FOR INSERT TO authenticated
  WITH CHECK (public.is_ppe_manager());
CREATE POLICY "ppe_allocations_ppe_manager_update" ON public.ppe_allocations FOR UPDATE TO authenticated
  USING (public.is_ppe_manager()) WITH CHECK (public.is_ppe_manager());

-- ppe_requests: user own CRUD (insert, select own, update own when submitted); managers all
DROP POLICY IF EXISTS "ppe_requests_own" ON public.ppe_requests;
CREATE POLICY "ppe_requests_own" ON public.ppe_requests FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "ppe_requests_own_select" ON public.ppe_requests FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "ppe_requests_own_update_submitted" ON public.ppe_requests;
CREATE POLICY "ppe_requests_own_update_submitted" ON public.ppe_requests FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status = 'submitted')
  WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "ppe_requests_managers" ON public.ppe_requests;
CREATE POLICY "ppe_requests_managers" ON public.ppe_requests FOR SELECT TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint));
CREATE POLICY "ppe_requests_managers_update" ON public.ppe_requests FOR UPDATE TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint))
  WITH CHECK (true);

-- ppe_request_approvals: managers full; user can SELECT if owns request
DROP POLICY IF EXISTS "ppe_request_approvals_managers" ON public.ppe_request_approvals;
CREATE POLICY "ppe_request_approvals_managers" ON public.ppe_request_approvals FOR ALL TO authenticated
  USING (public.get_my_security_between(1::smallint, 3::smallint))
  WITH CHECK (public.get_my_security_between(1::smallint, 3::smallint));
DROP POLICY IF EXISTS "ppe_request_approvals_own_select" ON public.ppe_request_approvals;
CREATE POLICY "ppe_request_approvals_own_select" ON public.ppe_request_approvals FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.ppe_requests r WHERE r.id = request_id AND r.user_id = auth.uid())
  );

-- Grant usage on view (reads via ppe_ledger RLS)
GRANT SELECT ON public.ppe_stock_levels TO authenticated;
