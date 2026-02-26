-- Wash time (minutes) after each on-site or quarry delivery; shown in scheduler, not uploaded to calendar.
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS wash_time integer NULL;
COMMENT ON COLUMN public.system_settings.wash_time IS 'Minutes for vehicle wash after each on-site or quarry delivery; displayed in schedule only, not in calendar.';

-- Loading at quarry duration (minutes); used for all loading blocks regardless of quantity.
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS loading_time integer NULL;
COMMENT ON COLUMN public.system_settings.loading_time IS 'Minutes for loading at quarry in concrete mix scheduler; used for all loading blocks.';
