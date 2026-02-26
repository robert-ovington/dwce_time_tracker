-- ============================================================================
-- Add lite column to screen_platforms (bare-minimum for lite mobile app)
-- ============================================================================

ALTER TABLE public.screen_platforms
ADD COLUMN IF NOT EXISTS lite boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.screen_platforms.lite IS 'Include in lite mobile build (bare minimum for basic users)';

-- Set lite=true for bare-minimum screens
UPDATE public.screen_platforms SET lite = true
WHERE screen_id IN (
  'messages', 'clock_in_out', 'my_clockings', 'time_tracking', 'my_time_periods', 'time_clocking',
  'dashboard', 'coming_soon', 'login', 'main_menu'
);

-- Insert platform_config if not present (for Platform Config screen)
INSERT INTO public.screen_platforms (screen_id, display_name, android, ios, web, windows, lite)
VALUES ('platform_config', 'Platform Config', true, true, true, true, false)
ON CONFLICT (screen_id) DO NOTHING;
