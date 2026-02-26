-- =============================================================================
-- Google Calendar sync support for concrete_mix_calendar
-- =============================================================================
-- 1. Store Google Calendar API event id so we can update/delete events via API.
-- 2. Optional: store OAuth refresh token in system_settings (alternative is
--    Supabase Vault or Edge Function secrets only).
-- Run in Supabase SQL Editor or via supabase db push.
-- =============================================================================

-- Column to hold the Google Calendar API event id (returned on insert, required for patch/delete).
ALTER TABLE public.concrete_mix_calendar
  ADD COLUMN IF NOT EXISTS google_event_id TEXT NULL;

COMMENT ON COLUMN public.concrete_mix_calendar.google_event_id IS
  'Google Calendar API event id; used for PATCH/DELETE. Set when event is synced to Google.';

-- Optional: columns for OAuth refresh token if you prefer DB over Edge Function secrets.
-- Prefer Supabase Dashboard > Project Settings > Edge Functions > Secrets for
-- GOOGLE_CALENDAR_CLIENT_ID, GOOGLE_CALENDAR_CLIENT_SECRET, GOOGLE_CALENDAR_REFRESH_TOKEN.
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS google_calendar_refresh_token TEXT NULL;

COMMENT ON COLUMN public.system_settings.google_calendar_refresh_token IS
  'Optional: OAuth2 refresh token for Google Calendar API. Prefer Edge Function secrets.';
