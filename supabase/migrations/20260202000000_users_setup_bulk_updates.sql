-- ============================================================================
-- Bulk updates to users_setup (menu permissions, security_limit)
-- ============================================================================
-- Run order: statements are independent; security_limit and role-based
-- updates use CASE/WHERE as specified.
-- ============================================================================

-- 1. menu_time_off = TRUE for all users
UPDATE public.users_setup
SET menu_time_off = true;

-- 2. security 2–4: set security_limit to 5
UPDATE public.users_setup
SET security_limit = 5
WHERE security BETWEEN 2 AND 4;

-- 3. security 5–9: set security_limit to NULL
UPDATE public.users_setup
SET security_limit = NULL
WHERE security BETWEEN 5 AND 9;

-- 4. Truck Operator / Excavator-Truck roles: menu_deliveries = TRUE
--    (covers both "Operator" and "Operative" spellings if present)
UPDATE public.users_setup
SET menu_deliveries = true
WHERE role IN (
  'Truck Operator',
  'Excavator/Truck Operator',
  'Truck Operative',
  'Excavator/Truck Operative'
);

-- 5. menu_sites: TRUE for security 1–3, NULL otherwise
UPDATE public.users_setup
SET menu_sites = CASE WHEN security BETWEEN 1 AND 3 THEN true ELSE NULL END;

-- 6. menu_reports: TRUE for security 1–3, NULL otherwise
UPDATE public.users_setup
SET menu_reports = CASE WHEN security BETWEEN 1 AND 3 THEN true ELSE NULL END;

-- 7. menu_managers: TRUE for security 1–3, NULL otherwise
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS menu_managers BOOLEAN;
UPDATE public.users_setup
SET menu_managers = CASE WHEN security BETWEEN 1 AND 3 THEN true ELSE NULL END;

-- 8. menu_administration: TRUE for security 1 only, NULL otherwise
UPDATE public.users_setup
SET menu_administration = CASE WHEN security = 1 THEN true ELSE NULL END;

-- 9. dashboard: TRUE for security 1 only, NULL otherwise
UPDATE public.users_setup
SET dashboard = CASE WHEN security = 1 THEN true ELSE NULL END;

-- 10. menu_training: TRUE for security 1 only, NULL otherwise
UPDATE public.users_setup
SET menu_training = CASE WHEN security = 1 THEN true ELSE NULL END;

-- 11. menu_cube_test: TRUE for security 1 only, NULL otherwise
--     (column name is menu_cube_test in app/schema; user ref: menu_cube_tests)
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS menu_cube_test BOOLEAN;
UPDATE public.users_setup
SET menu_cube_test = CASE WHEN security = 1 THEN true ELSE NULL END;

-- 12. menu_office: TRUE for security 1 only, NULL otherwise
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS menu_office BOOLEAN;
UPDATE public.users_setup
SET menu_office = CASE WHEN security = 1 THEN true ELSE NULL END;

-- 13. menu_office_admin: TRUE for security 1 only, NULL otherwise
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS menu_office_admin BOOLEAN;
UPDATE public.users_setup
SET menu_office_admin = CASE WHEN security = 1 THEN true ELSE NULL END;

-- 14. menu_office_project: TRUE for security 1 only, NULL otherwise
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS menu_office_project BOOLEAN;
UPDATE public.users_setup
SET menu_office_project = CASE WHEN security = 1 THEN true ELSE NULL END;

-- 15. menu_messages = TRUE for all users
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS menu_messages BOOLEAN;
UPDATE public.users_setup
SET menu_messages = true;

-- 16. menu_messenger: TRUE for security 1 only, NULL otherwise
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS menu_messenger BOOLEAN;
UPDATE public.users_setup
SET menu_messenger = CASE WHEN security = 1 THEN true ELSE NULL END;

-- 17. menu_dashboard: TRUE for security 1 only, NULL otherwise
--     (if your table uses "dashboard" only, this will fail until column exists;
--      add column if you use menu_dashboard in app)
ALTER TABLE public.users_setup
  ADD COLUMN IF NOT EXISTS menu_dashboard BOOLEAN;
UPDATE public.users_setup
SET menu_dashboard = CASE WHEN security = 1 THEN true ELSE NULL END;
