-- ============================================================================
-- Add Menu Permission Columns to users_setup Table
-- ============================================================================
-- This adds 11 boolean columns (one for each main menu item i-xi)
-- Defaults to true for existing users, allowing granular control per user
-- ============================================================================

-- Add menu permission columns
ALTER TABLE public.users_setup
ADD COLUMN IF NOT EXISTS menu_clock_in BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_time_periods BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_plant_checks BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_deliveries BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_paperwork BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_time_off BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_sites BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_reports BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_payroll BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_exports BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS menu_administration BOOLEAN DEFAULT true;

-- Add comments for documentation
COMMENT ON COLUMN public.users_setup.menu_clock_in IS 'Enable/disable Clock In menu item (i)';
COMMENT ON COLUMN public.users_setup.menu_time_periods IS 'Enable/disable Time Periods menu item (ii)';
COMMENT ON COLUMN public.users_setup.menu_plant_checks IS 'Enable/disable Plant Checks menu item (iii)';
COMMENT ON COLUMN public.users_setup.menu_deliveries IS 'Enable/disable Deliveries menu item (iv)';
COMMENT ON COLUMN public.users_setup.menu_paperwork IS 'Enable/disable Paperwork menu item (v)';
COMMENT ON COLUMN public.users_setup.menu_time_off IS 'Enable/disable Time Off menu item (vi)';
COMMENT ON COLUMN public.users_setup.menu_sites IS 'Enable/disable Sites menu item (vii)';
COMMENT ON COLUMN public.users_setup.menu_reports IS 'Enable/disable Reports menu item (viii)';
COMMENT ON COLUMN public.users_setup.menu_payroll IS 'Enable/disable Payroll menu item (ix)';
COMMENT ON COLUMN public.users_setup.menu_exports IS 'Enable/disable Exports menu item (x)';
COMMENT ON COLUMN public.users_setup.menu_administration IS 'Enable/disable Administration menu item (xi)';

-- Set all existing users to have all menus enabled by default
UPDATE public.users_setup
SET 
  menu_clock_in = COALESCE(menu_clock_in, true),
  menu_time_periods = COALESCE(menu_time_periods, true),
  menu_plant_checks = COALESCE(menu_plant_checks, true),
  menu_deliveries = COALESCE(menu_deliveries, true),
  menu_paperwork = COALESCE(menu_paperwork, true),
  menu_time_off = COALESCE(menu_time_off, true),
  menu_sites = COALESCE(menu_sites, true),
  menu_reports = COALESCE(menu_reports, true),
  menu_payroll = COALESCE(menu_payroll, true),
  menu_exports = COALESCE(menu_exports, true),
  menu_administration = COALESCE(menu_administration, true)
WHERE menu_clock_in IS NULL 
   OR menu_time_periods IS NULL
   OR menu_plant_checks IS NULL
   OR menu_deliveries IS NULL
   OR menu_paperwork IS NULL
   OR menu_time_off IS NULL
   OR menu_sites IS NULL
   OR menu_reports IS NULL
   OR menu_payroll IS NULL
   OR menu_exports IS NULL
   OR menu_administration IS NULL;
