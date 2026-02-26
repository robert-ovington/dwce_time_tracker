-- Remove all references to public.ppe_sizes. Size is defined in public.ppe_size_catalog (id, size_code).
-- ppe_requests uses ppe_size_catalog_id; ledger, purchases, allocations, user_preferences use size_code text only.

-- 1. Drop foreign keys from other tables that reference ppe_sizes
ALTER TABLE public.ppe_ledger   DROP CONSTRAINT IF EXISTS fk_ppe_ledger_size;
ALTER TABLE public.ppe_purchases DROP CONSTRAINT IF EXISTS fk_ppe_purchases_size;
ALTER TABLE public.ppe_user_preferences DROP CONSTRAINT IF EXISTS fk_ppe_user_pref_size;
ALTER TABLE public.ppe_allocations DROP CONSTRAINT IF EXISTS fk_ppe_alloc_size;
ALTER TABLE public.ppe_requests DROP CONSTRAINT IF EXISTS fk_ppe_requests_size;

-- 2. If ppe_requests still has requested_size_code column, drop it (size comes from ppe_size_catalog_id only)
ALTER TABLE public.ppe_requests DROP COLUMN IF EXISTS requested_size_code;

-- 3. Drop trigger and then table ppe_sizes
DROP TRIGGER IF EXISTS ppe_validate_size_sizes ON public.ppe_sizes;
DROP POLICY IF EXISTS "ppe_sizes_select_authenticated" ON public.ppe_sizes;
DROP POLICY IF EXISTS "ppe_sizes_all_managers" ON public.ppe_sizes;
DROP POLICY IF EXISTS "p_ppe_sizes_read" ON public.ppe_sizes;
DROP POLICY IF EXISTS "p_ppe_sizes_write" ON public.ppe_sizes;
DROP TABLE IF EXISTS public.ppe_sizes;

-- 4. Drop the size-validation function (only used by ppe_sizes trigger)
DROP FUNCTION IF EXISTS public.ppe_validate_size_fk();
