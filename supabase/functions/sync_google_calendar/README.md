# sync_google_calendar Edge Function

Pushes events from `public.concrete_mix_calendar` to Google Calendar using the Google Calendar API. Supports **Service Account** (JSON key file) or **OAuth 2.0** (refresh token).

## Where to keep the JSON key file (Service Account)

- **On your machine:** Store it in the project `secrets` folder (ignored by git via `**/secrets/*.json`):
  - **Path:** `secrets/dwce-time-tracker-326de54ad605.json`  
  - Full path example: `C:\Users\robie\dwce_time_tracker\secrets\dwce-time-tracker-326de54ad605.json`
- **For the Edge Function:** Supabase runs in the cloud and does **not** read files from your PC. You must paste the **contents** of the JSON file into a **Supabase secret** (see below). Do **not** commit the file or put the key in source code.

## Prerequisites

1. **Google Cloud project** with Calendar API enabled.
2. **Either**:
   - **Service account (recommended):** JSON key file from APIs & Services → Credentials → Create Credentials → Service account → Keys. Share the Google Calendar with the service account email (e.g. `xxx@project.iam.gserviceaccount.com`) so it can write events.
   - **OAuth 2.0:** Client ID + Client Secret + refresh token (see OAuth 2.0 Playground with scope `https://www.googleapis.com/auth/calendar`).
3. **Calendar ID** in your app: set `concrete_mix_calendar_id` in `public.system_settings` (e.g. `xxxx@group.calendar.google.com`).

## Supabase secrets

Set in **Dashboard → Project Settings → Edge Functions → Secrets** (or via CLI).

### Option A – Service account (JSON key file)

| Secret | Description |
|--------|-------------|
| `GOOGLE_SERVICE_ACCOUNT_JSON` | **Full contents** of your JSON key file (the whole file as one string). |

**CLI:** Paste the JSON in one line or from a file (PowerShell example):

```powershell
# From the secrets folder
$json = Get-Content -Raw "C:\Users\robie\dwce_time_tracker\secrets\dwce-time-tracker-326de54ad605.json"
supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON="$json"
```

Or copy the entire contents of `secrets/dwce-time-tracker-326de54ad605.json` and in the Dashboard paste that into the value for `GOOGLE_SERVICE_ACCOUNT_JSON`.

### Option B – OAuth 2.0 (refresh token)

| Secret | Description |
|--------|-------------|
| `GOOGLE_CALENDAR_CLIENT_ID` | OAuth 2.0 Client ID |
| `GOOGLE_CALENDAR_CLIENT_SECRET` | OAuth 2.0 Client Secret |
| `GOOGLE_CALENDAR_REFRESH_TOKEN` | Refresh token for the calendar owner |

If **both** are set, the function uses **Service Account** (`GOOGLE_SERVICE_ACCOUNT_JSON`) first.

## Request body

POST JSON to the function URL:

- **By date range** (sync all events in that window):
  ```json
  { "day_start": "2025-02-01T00:00:00.000Z", "day_end": "2025-02-01T23:59:59.999Z" }
  ```
- **By event IDs** (sync specific rows from `concrete_mix_calendar`):
  ```json
  { "event_ids": ["uuid-1", "uuid-2"] }
  ```

The function uses `system_settings.concrete_mix_calendar_id` as the Google Calendar ID. Events without `google_event_id` are inserted; events with `google_event_id` are updated (PATCH). After a successful insert, `google_event_id` is updated in the database.

## Database

- Migration `20260219000000_google_calendar_sync_support.sql` adds `google_event_id` to `concrete_mix_calendar` and optionally `google_calendar_refresh_token` to `system_settings`. Prefer storing the refresh token in Edge Function secrets rather than the database.
