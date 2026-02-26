-- Revised PPE schema: ppe_list, ppe_sizes, ppe_requests, ppe_stock.
-- Enums and tables match the provided layout; FKs and view added for app use.

DO $$ BEGIN
  CREATE TYPE public.ppe_category AS ENUM ('clothing', 'footwear');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ppe_list (id, name, category, is_active)
CREATE TABLE IF NOT EXISTS public.ppe_list (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  category public.ppe_category NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT ppe_list_pkey PRIMARY KEY (id),
  CONSTRAINT ppe_list_name_key UNIQUE (name)
);

-- ppe_sizes (id, category, size_code, is_active, sort_order) – global size catalog
CREATE TABLE IF NOT EXISTS public.ppe_sizes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  category public.ppe_category NOT NULL,
  size_code text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  CONSTRAINT ppe_sizes_pkey PRIMARY KEY (id)
);

-- ppe_requests
CREATE TABLE IF NOT EXISTS public.ppe_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  manager_id uuid NOT NULL,
  ppe_id uuid NOT NULL,
  size_id uuid NOT NULL,
  reason text NULL,
  status text NOT NULL,
  requested_date timestamptz NULL,
  approved_date timestamptz NULL,
  allocated_date timestamptz NULL,
  is_active boolean NULL DEFAULT true,
  CONSTRAINT ppe_requests_pkey PRIMARY KEY (id),
  CONSTRAINT ppe_requests_ppe_id_fkey FOREIGN KEY (ppe_id) REFERENCES public.ppe_list(id) ON DELETE RESTRICT,
  CONSTRAINT ppe_requests_size_id_fkey FOREIGN KEY (size_id) REFERENCES public.ppe_sizes(id) ON DELETE RESTRICT
);

-- ppe_stock – stock movements (receive, allocation, adjustment)
CREATE TABLE IF NOT EXISTS public.ppe_stock (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  ppe_id uuid NOT NULL,
  size_id uuid NOT NULL,
  quantity integer NULL,
  price numeric(6,2) NULL,
  transaction_type text NOT NULL,
  transaction_date timestamptz NULL,
  is_active boolean NULL DEFAULT true,
  user_id uuid NULL DEFAULT auth.uid(),
  CONSTRAINT ppe_stock_pkey PRIMARY KEY (id),
  CONSTRAINT ppe_stock_ppe_id_fkey FOREIGN KEY (ppe_id) REFERENCES public.ppe_list(id) ON DELETE RESTRICT,
  CONSTRAINT ppe_stock_size_id_fkey FOREIGN KEY (size_id) REFERENCES public.ppe_sizes(id) ON DELETE RESTRICT
);

-- View: stock levels by ppe_id and size (for stock levels screen)
CREATE OR REPLACE VIEW public.ppe_stock_levels AS
SELECT s.ppe_id, s.size_id, sz.size_code, COALESCE(SUM(s.quantity), 0)::integer AS on_hand
FROM public.ppe_stock s
JOIN public.ppe_sizes sz ON sz.id = s.size_id
WHERE (s.is_active IS NULL OR s.is_active = true)
GROUP BY s.ppe_id, s.size_id, sz.size_code;
