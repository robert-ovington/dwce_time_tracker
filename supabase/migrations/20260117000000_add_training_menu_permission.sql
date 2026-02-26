-- ============================================================================
-- Add Training Menu Permission Column to users_setup Table
-- ============================================================================
-- This adds a boolean column for the Training menu item
-- Defaults to true for existing users
-- ============================================================================

-- Add menu permission column
ALTER TABLE public.users_setup
ADD COLUMN IF NOT EXISTS menu_training BOOLEAN DEFAULT true;

-- Add comment for documentation
COMMENT ON COLUMN public.users_setup.menu_training IS 'Enable/disable Training menu item';

-- Set all existing users to have training menu enabled by default
UPDATE public.users_setup
SET menu_training = COALESCE(menu_training, true)
WHERE menu_training IS NULL;
