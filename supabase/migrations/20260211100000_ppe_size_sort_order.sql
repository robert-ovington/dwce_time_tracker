-- Add sort_order to size catalog tables so sizes display in logical order
-- (clothing: S, M, L, XL, 2XL, 3XL; footwear: 7, 8, ..., 13).

-- ppe_size_catalog: add column and backfill
ALTER TABLE public.ppe_size_catalog
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;
COMMENT ON COLUMN public.ppe_size_catalog.sort_order IS 'Display order: lower first (e.g. S=1, M=2, ..., 7=1, 8=2 for footwear).';

UPDATE public.ppe_size_catalog SET sort_order = 1 WHERE category = 'clothing' AND size_code = 'S';
UPDATE public.ppe_size_catalog SET sort_order = 2 WHERE category = 'clothing' AND size_code = 'M';
UPDATE public.ppe_size_catalog SET sort_order = 3 WHERE category = 'clothing' AND size_code = 'L';
UPDATE public.ppe_size_catalog SET sort_order = 4 WHERE category = 'clothing' AND size_code = 'XL';
UPDATE public.ppe_size_catalog SET sort_order = 5 WHERE category = 'clothing' AND size_code = '2XL';
UPDATE public.ppe_size_catalog SET sort_order = 6 WHERE category = 'clothing' AND size_code = '3XL';
UPDATE public.ppe_size_catalog SET sort_order = 1 WHERE category = 'footwear' AND size_code = '7';
UPDATE public.ppe_size_catalog SET sort_order = 2 WHERE category = 'footwear' AND size_code = '8';
UPDATE public.ppe_size_catalog SET sort_order = 3 WHERE category = 'footwear' AND size_code = '9';
UPDATE public.ppe_size_catalog SET sort_order = 4 WHERE category = 'footwear' AND size_code = '10';
UPDATE public.ppe_size_catalog SET sort_order = 5 WHERE category = 'footwear' AND size_code = '11';
UPDATE public.ppe_size_catalog SET sort_order = 6 WHERE category = 'footwear' AND size_code = '12';
UPDATE public.ppe_size_catalog SET sort_order = 7 WHERE category = 'footwear' AND size_code = '13';

-- ppe_item_size_policy: add column and backfill from catalog (by item category)
ALTER TABLE public.ppe_item_size_policy
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;

UPDATE public.ppe_item_size_policy p
SET sort_order = c.sort_order
FROM public.ppe_size_catalog c,
     public.ppe_list l
WHERE p.ppe_id = l.id
  AND l.category = c.category
  AND p.size_code = c.size_code;

-- Optional: index for ordering (small tables, may not be needed)
CREATE INDEX IF NOT EXISTS idx_ppe_size_catalog_category_sort
  ON public.ppe_size_catalog(category, sort_order)
  WHERE is_active = true;
