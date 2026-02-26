-- Add quarry_travel (minutes buffer for travel time, rounded to nearest 15 min in scheduler).
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS quarry_travel integer NULL;

COMMENT ON COLUMN public.system_settings.quarry_travel IS 'Minutes added to each travel leg in concrete mix scheduler; result rounded to nearest 15.';
