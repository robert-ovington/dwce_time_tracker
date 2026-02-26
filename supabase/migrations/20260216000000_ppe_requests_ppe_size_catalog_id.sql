-- Add ppe_size_catalog_id to ppe_requests so clients send catalog id instead of size text.
-- Schema uses ppe_size_catalog_id FK to ppe_size_catalog(id); no requested_size_code column.

ALTER TABLE public.ppe_requests
  ADD COLUMN IF NOT EXISTS ppe_size_catalog_id uuid NULL REFERENCES public.ppe_size_catalog(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.ppe_requests.ppe_size_catalog_id IS 'Size chosen by catalog id (references ppe_size_catalog.id).';

-- Remove trigger/function if they existed from an earlier migration (they referenced requested_size_code).
DROP TRIGGER IF EXISTS trg_ppe_requests_set_size_from_catalog ON public.ppe_requests;
DROP FUNCTION IF EXISTS public.ppe_requests_set_size_from_catalog();
