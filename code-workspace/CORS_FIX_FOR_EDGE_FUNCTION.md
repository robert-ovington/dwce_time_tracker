# CORS Fix for geocode_eircode_edge_function

## Issue
The Edge Function is blocking requests from the Flutter web app due to missing CORS headers for `x-client-info` and other Supabase SDK headers.

## Solution
Update the CORS headers in your Edge Function to include all necessary headers.

## Updated Edge Function Code

Replace the `corsHeaders` object in your `geocode_eircode_edge_function` with:

```typescript
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-client-info, apikey, x-client-version',
};
```

## Full Updated Function

Here's the complete function with the corrected CORS headers:

```typescript
// geocode_eircode_edge_function
// Improved Supabase Edge Function using Deno.serve and inline CORS

interface GeoResponse {
  success: boolean;
  lat?: number;
  lng?: number;
  formatted_address?: string;
  error?: string;
}

console.info('geocode_eircode_edge_function starting');

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-client-info, apikey, x-client-version',
  };

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const contentType = req.headers.get('content-type') || '';
    let payload: any = {};

    if (req.method === 'GET') {
      const url = new URL(req.url);
      payload.eircode = url.searchParams.get('eircode') || undefined;
    } else {
      if (contentType.includes('application/json')) {
        payload = await req.json();
      } else {
        // attempt to parse as form data
        const form = await req.formData();
        payload.eircode = form.get('eircode')?.toString();
      }
    }

    const eircode = typeof payload?.eircode === 'string' ? payload.eircode.trim() : undefined;

    if (!eircode) {
      const body: GeoResponse = { success: false, error: 'Eircode is required' };
      return new Response(JSON.stringify(body), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const apiKey = Deno.env.get('GOOGLE_MAPS_API_KEY');
    if (!apiKey) {
      console.error('GOOGLE_MAPS_API_KEY secret not found');
      const body: GeoResponse = { success: false, error: 'Google Maps API key not configured' };
      return new Response(JSON.stringify(body), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(eircode)}&key=${apiKey}`;
    console.info(`Calling Google Maps API for eircode: ${eircode}`);
    const resp = await fetch(url);
    const data = await resp.json();

    if (data.status === 'OK' && data.results && data.results.length > 0) {
      const location = data.results[0].geometry.location;
      const lat = Number(location.lat);
      const lng = Number(location.lng);
      console.info(`Found coordinates: ${lat}, ${lng}`);
      const body: GeoResponse = { success: true, lat, lng, formatted_address: data.results[0].formatted_address };
      return new Response(JSON.stringify(body), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Handle specific Google API error statuses
    const apiStatus = data.status || 'UNKNOWN_ERROR';
    console.warn(`Geocoding API returned status: ${apiStatus}`);

    if (apiStatus === 'ZERO_RESULTS') {
      const body: GeoResponse = { success: false, error: 'No results found for provided Eircode' };
      return new Response(JSON.stringify(body), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (apiStatus === 'OVER_QUERY_LIMIT' || apiStatus === 'REQUEST_DENIED' || apiStatus === 'INVALID_REQUEST' || apiStatus === 'UNKNOWN_ERROR') {
      const body: GeoResponse = { success: false, error: `Geocoding failed: ${apiStatus}` };
      return new Response(JSON.stringify(body), { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Fallback
    const body: GeoResponse = { success: false, error: `Could not find GPS coordinates. Status: ${apiStatus}` };
    return new Response(JSON.stringify(body), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (err: any) {
    console.error('Error in geocode_eircode_edge_function:', err);
    const body = { success: false, error: err?.message || 'Internal server error' };
    return new Response(JSON.stringify(body), { status: 500, headers: { 'Content-Type': 'application/json', ...corsHeaders } });
  }
});
```

## Steps to Update

1. Go to Supabase Dashboard → Edge Functions → `geocode_eircode_edge_function`
2. Click "Edit Function"
3. Replace the `corsHeaders` line with the updated version above
4. Deploy the function

## Alternative: Quick Fix

If you just want to update the CORS headers line, change:

```typescript
'Access-Control-Allow-Headers': 'Content-Type, Authorization',
```

To:

```typescript
'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-client-info, apikey, x-client-version',
```

This will allow the Supabase Flutter SDK to make requests from web browsers.

