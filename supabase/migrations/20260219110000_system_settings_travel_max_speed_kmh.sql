-- Add max_speed_for_travel: cap average speed (km/h) for travel time (e.g. 50 = assume no faster than 50 km/h; helps account for traffic).
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS max_speed_for_travel integer NULL;

COMMENT ON COLUMN public.system_settings.max_speed_for_travel IS 'Max average speed (km/h) for concrete mix scheduler travel; if set, travel time is at least distance_km/max_speed. Null = use API duration only.';
