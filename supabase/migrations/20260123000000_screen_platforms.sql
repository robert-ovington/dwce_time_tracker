-- ============================================================================
-- screen_platforms: which screens are included in each platform build
-- ============================================================================
-- When a screen is created or removed in the Flutter app, update this table.
-- Flutter can sync from this table or use it at runtime to show/hide menu items.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.screen_platforms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  screen_id text NOT NULL UNIQUE,
  display_name text,
  android boolean NOT NULL DEFAULT true,
  ios boolean NOT NULL DEFAULT true,
  web boolean NOT NULL DEFAULT true,
  windows boolean NOT NULL DEFAULT true,
  lite boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.screen_platforms IS 'Which app screens are included in Android, iOS, Web, and Windows builds. Update when screens are created or removed.';

-- Trigger: set updated_at on UPDATE
CREATE OR REPLACE FUNCTION public.set_screen_platforms_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS screen_platforms_updated_at ON public.screen_platforms;
CREATE TRIGGER screen_platforms_updated_at
  BEFORE UPDATE ON public.screen_platforms
  FOR EACH ROW EXECUTE FUNCTION public.set_screen_platforms_updated_at();

-- RLS
ALTER TABLE public.screen_platforms ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read (app needs to know which screens are on which platform)
CREATE POLICY "screen_platforms_select_authenticated"
  ON public.screen_platforms FOR SELECT
  TO authenticated
  USING (true);

-- Only service_role can insert/update/delete (or add an admin policy if you use app-side admin)
CREATE POLICY "screen_platforms_all_service_role"
  ON public.screen_platforms FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Seed: current screens; Messenger screens are Web/Windows only; lite = bare minimum for lite app
INSERT INTO public.screen_platforms (screen_id, display_name, android, ios, web, windows, lite)
VALUES
  ('messages', 'Messages', true, true, true, true, true),
  ('new_message', 'New Message', false, false, true, true, false),
  ('message_log', 'Message Log', false, false, true, true, false),
  ('message_template', 'Message Template', false, false, true, true, false),
  ('recipient_selection', 'Recipient Selection', false, false, true, true, false),
  ('clock_in_out', 'Clock In/Out', true, true, true, true, true),
  ('my_clockings', 'My Clockings', true, true, true, true, true),
  ('clock_office', 'Clock Office', true, true, true, true, false),
  ('admin_staff_attendance', 'Attendance', true, true, true, true, false),
  ('admin_staff_summary', 'Summary', true, true, true, true, false),
  ('time_tracking', 'Time Tracking', true, true, true, true, false),
  ('my_time_periods', 'My Time Periods', true, true, true, true, true),
  ('time_clocking', 'Time Clocking', true, true, true, true, true),
  ('asset_check', 'Asset Check', true, true, true, true, false),
  ('my_checks', 'My Checks', true, true, true, true, false),
  ('delivery', 'Delivery', true, true, true, true, false),
  ('dashboard', 'Dashboard', true, true, true, true, true),
  ('admin', 'Admin', true, true, true, true, false),
  ('user_creation', 'Create User', true, true, true, true, false),
  ('user_edit', 'Edit User', true, true, true, true, false),
  ('employer_management', 'Employer', true, true, true, true, false),
  ('supervisor_approval', 'Timesheets', true, true, true, true, false),
  ('plant_location_report', 'Small Plant Location Report', true, true, true, true, false),
  ('fault_management_report', 'Small Plant Fault Management', true, true, true, true, false),
  ('stock_locations_management', 'Stock Locations', true, true, true, true, false),
  ('cube_details', 'Cube Details', true, true, true, true, false),
  ('coming_soon', 'Coming Soon', true, true, true, true, true),
  ('login', 'Login', true, true, true, true, true),
  ('main_menu', 'Main Menu', true, true, true, true, true),
  ('platform_config', 'Platform Config', true, true, true, true, false)
ON CONFLICT (screen_id) DO NOTHING;
