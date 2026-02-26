// sync_google_calendar Edge Function
// Pushes concrete_mix_calendar events to Google Calendar via API.
// Supports either:
//   A) Service account: set GOOGLE_SERVICE_ACCOUNT_JSON to the full JSON key file contents.
//   B) OAuth2: set GOOGLE_CALENDAR_CLIENT_ID, GOOGLE_CALENDAR_CLIENT_SECRET, GOOGLE_CALENDAR_REFRESH_TOKEN.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SignJWT, importPKCS8 } from 'https://esm.sh/jose@5.2.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-client-info, apikey',
};

interface SyncPayload {
  day_start?: string;
  day_end?: string;
  event_ids?: string[];
}

interface GoogleTokenResponse {
  access_token: string;
  expires_in?: number;
}

interface ServiceAccountKey {
  type?: string;
  project_id?: string;
  private_key_id?: string;
  private_key: string;
  client_email: string;
  client_id?: string;
  auth_uri?: string;
  token_uri?: string;
}

async function getAccessTokenWithServiceAccount(jsonStr: string): Promise<string> {
  let key: ServiceAccountKey;
  try {
    key = JSON.parse(jsonStr) as ServiceAccountKey;
  } catch {
    throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON');
  }
  if (!key.client_email || !key.private_key) {
    throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON must include client_email and private_key');
  }
  const scope = 'https://www.googleapis.com/auth/calendar';
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: key.client_email,
    scope,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const privateKey = await importPKCS8(key.private_key, 'RS256');
  const jwt = await new SignJWT({ scope })
    .setProtectedHeader({ alg: 'RS256' })
    .setIssuer(key.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now)
    .setExpirationTime('1h')
    .sign(privateKey);

  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: jwt,
  });
  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Google token (service account) failed: ${resp.status} ${text}`);
  }
  const data = (await resp.json()) as GoogleTokenResponse;
  if (!data.access_token) throw new Error('No access_token in Google response');
  return data.access_token;
}

async function getAccessTokenWithRefreshToken(): Promise<string> {
  const clientId = Deno.env.get('GOOGLE_CALENDAR_CLIENT_ID');
  const clientSecret = Deno.env.get('GOOGLE_CALENDAR_CLIENT_SECRET');
  const refreshToken = Deno.env.get('GOOGLE_CALENDAR_REFRESH_TOKEN');
  if (!clientId || !clientSecret || !refreshToken) {
    throw new Error(
      'Missing OAuth secrets. Set GOOGLE_CALENDAR_CLIENT_ID, GOOGLE_CALENDAR_CLIENT_SECRET, GOOGLE_CALENDAR_REFRESH_TOKEN.'
    );
  }
  const body = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    refresh_token: refreshToken,
    grant_type: 'refresh_token',
  });
  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Google OAuth token failed: ${resp.status} ${text}`);
  }
  const data = (await resp.json()) as GoogleTokenResponse;
  if (!data.access_token) throw new Error('No access_token in Google response');
  return data.access_token;
}

async function getAccessToken(): Promise<string> {
  const serviceAccountJson = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  if (serviceAccountJson && serviceAccountJson.trim()) {
    return getAccessTokenWithServiceAccount(serviceAccountJson);
  }
  return getAccessTokenWithRefreshToken();
}

function toRFC3339(dt: string): string {
  const d = new Date(dt);
  if (isNaN(d.getTime())) return dt;
  return d.toISOString();
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    if (!supabaseUrl || !serviceKey) {
      return new Response(
        JSON.stringify({ success: false, error: 'Server configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    let payload: SyncPayload = {};
    if (req.method === 'POST' && req.headers.get('content-type')?.includes('application/json')) {
      payload = (await req.json()) as SyncPayload;
    }

    // Load calendar ID from system_settings
    const { data: settingsRow } = await supabase
      .from('system_settings')
      .select('concrete_mix_calendar_id')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    const calendarId = (settingsRow as { concrete_mix_calendar_id?: string } | null)?.concrete_mix_calendar_id;
    if (!calendarId || !calendarId.trim()) {
      return new Response(
        JSON.stringify({ success: false, error: 'concrete_mix_calendar_id not set in system_settings' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Select columns needed for Google Calendar API (including location and color_id).
    const selectCols = 'id, summary, description, location, start_datetime, end_datetime, google_event_id, color_id';
    type CalendarEvent = { id: string; summary: string; description: string | null; location: string | null; start_datetime: string; end_datetime: string; google_event_id: string | null; color_id?: string | null };
    let events: CalendarEvent[];

    // Sync 'On Site' and 'Break' events to Google Calendar; other task types (Loading, Travelling, Wash, Waiting) stay in DB only.
    if (payload.event_ids && payload.event_ids.length > 0) {
      const { data: rows, error } = await supabase
        .from('concrete_mix_calendar')
        .select(selectCols)
        .in('id', payload.event_ids)
        .in('task_type', ['On Site', 'Break']);
      if (error) {
        return new Response(
          JSON.stringify({ success: false, error: error.message }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      events = (rows ?? []) as CalendarEvent[];
    } else if (payload.day_start && payload.day_end) {
      const { data: rows, error } = await supabase
        .from('concrete_mix_calendar')
        .select(selectCols)
        .gte('start_datetime', payload.day_start)
        .lte('start_datetime', payload.day_end)
        .in('task_type', ['On Site', 'Break'])
        .order('start_datetime');
      if (error) {
        return new Response(
          JSON.stringify({ success: false, error: error.message }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
      events = (rows ?? []) as CalendarEvent[];
    } else {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Provide either day_start + day_end (ISO strings) or event_ids (array of UUIDs) in JSON body.',
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (events.length === 0) {
      return new Response(
        JSON.stringify({ success: true, synced: 0, inserted: 0, updated: 0, message: 'No events to sync' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const accessToken = await getAccessToken();
    const timeZone = 'UTC';
    let inserted = 0;
    let updated = 0;

    for (const ev of events) {
      const start = toRFC3339(ev.start_datetime);
      const end = toRFC3339(ev.end_datetime);
      const body: Record<string, unknown> = {
        summary: ev.summary ?? 'Event',
        description: ev.description ?? undefined,
        start: { dateTime: start, timeZone },
        end: { dateTime: end, timeZone },
        status: 'confirmed' as const,
      };
      if (ev.location != null && String(ev.location).trim() !== '') {
        body.location = ev.location;
      }
      if (ev.color_id != null && String(ev.color_id).trim() !== '') {
        body.colorId = ev.color_id;
      }

      if (ev.google_event_id) {
        const patchResp = await fetch(
          `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(ev.google_event_id)}`,
          {
            method: 'PATCH',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify(body),
          }
        );
        if (patchResp.ok) {
          updated++;
        } else {
          const errText = await patchResp.text();
          console.error(`PATCH event ${ev.id} failed: ${patchResp.status} ${errText}`);
          if (patchResp.status === 404) {
            // Event was deleted on Google; re-insert and save new id
            const insertResp = await fetch(
              `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`,
              {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${accessToken}`,
                  'Content-Type': 'application/json',
                },
                body: JSON.stringify(body),
              }
            );
            if (insertResp.ok) {
              const created = (await insertResp.json()) as { id: string };
              await supabase.from('concrete_mix_calendar').update({ google_event_id: created.id }).eq('id', ev.id);
              inserted++;
            }
          }
        }
      } else {
        const insertResp = await fetch(
          `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify(body),
          }
        );
        if (insertResp.ok) {
          const created = (await insertResp.json()) as { id: string };
          await supabase.from('concrete_mix_calendar').update({ google_event_id: created.id }).eq('id', ev.id);
          inserted++;
        } else {
          const errText = await insertResp.text();
          console.error(`INSERT event ${ev.id} failed: ${insertResp.status} ${errText}`);
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        synced: events.length,
        inserted,
        updated,
        calendarId,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('sync_google_calendar error:', message);
    return new Response(
      JSON.stringify({ success: false, error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
