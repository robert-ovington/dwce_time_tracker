-- ============================================================================
-- Add Dashboard Permission Column to users_setup Table
-- ============================================================================
-- Adds a boolean column to control dashboard visibility per user
-- Defaults to true (null defaults to true)
-- ============================================================================

-- Add dashboard permission column
ALTER TABLE public.users_setup
ADD COLUMN IF NOT EXISTS dashboard BOOLEAN DEFAULT true;

-- Add comment for documentation
COMMENT ON COLUMN public.users_setup.dashboard IS 'Enable/disable Dashboard display for user. Defaults to true.';

-- Set all existing users to have dashboard enabled by default
UPDATE public.users_setup
SET dashboard = COALESCE(dashboard, true)
WHERE dashboard IS NULL;
