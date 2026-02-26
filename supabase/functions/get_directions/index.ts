// get_directions_edge_function
// Supabase Edge Function for Google Maps Directions API
// Returns travel time and distance between two points

interface DirectionsResponse {
  success: boolean;
  travel_time_minutes?: number;
  distance_kilometers?: number;
  distance_text?: string;
  travel_time_formatted?: string;
  error?: string;
}

console.info('get_directions_edge_function starting');

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
      payload.home_latitude = url.searchParams.get('home_latitude');
      payload.home_longitude = url.searchParams.get('home_longitude');
      payload.project_latitude = url.searchParams.get('project_latitude');
      payload.project_longitude = url.searchParams.get('project_longitude');
      payload.departure_time = url.searchParams.get('departure_time');
      payload.traffic_model = url.searchParams.get('traffic_model');
    } else {
      if (contentType.includes('application/json')) {
        payload = await req.json();
      } else {
        // attempt to parse as form data
        const form = await req.formData();
        payload.home_latitude = form.get('home_latitude')?.toString();
        payload.home_longitude = form.get('home_longitude')?.toString();
        payload.project_latitude = form.get('project_latitude')?.toString();
        payload.project_longitude = form.get('project_longitude')?.toString();
        payload.departure_time = form.get('departure_time')?.toString();
        payload.traffic_model = form.get('traffic_model')?.toString();
      }
    }

    // Optional: departure_time (Unix seconds or "now") for traffic-aware duration_in_traffic
    const departureTimeRaw = payload?.departure_time;
    const trafficModel = (payload?.traffic_model as string)?.toLowerCase();
    const validTrafficModels = ['best_guess', 'pessimistic', 'optimistic'];
    const trafficModelParam = trafficModel && validTrafficModels.includes(trafficModel) ? trafficModel : 'best_guess';

    // Validate required parameters
    const homeLat = payload?.home_latitude ? parseFloat(payload.home_latitude) : undefined;
    const homeLng = payload?.home_longitude ? parseFloat(payload.home_longitude) : undefined;
    const projectLat = payload?.project_latitude ? parseFloat(payload.project_latitude) : undefined;
    const projectLng = payload?.project_longitude ? parseFloat(payload.project_longitude) : undefined;

    if (homeLat === undefined || homeLng === undefined || projectLat === undefined || projectLng === undefined) {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'home_latitude, home_longitude, project_latitude, and project_longitude are required' 
      };
      return new Response(JSON.stringify(body), { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    // Validate coordinates are within valid ranges
    if (isNaN(homeLat) || isNaN(homeLng) || isNaN(projectLat) || isNaN(projectLng)) {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'Invalid coordinate values' 
      };
      return new Response(JSON.stringify(body), { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    if (homeLat < -90 || homeLat > 90 || projectLat < -90 || projectLat > 90) {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'Latitude must be between -90 and 90' 
      };
      return new Response(JSON.stringify(body), { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    if (homeLng < -180 || homeLng > 180 || projectLng < -180 || projectLng > 180) {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'Longitude must be between -180 and 180' 
      };
      return new Response(JSON.stringify(body), { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    const apiKey = Deno.env.get('GOOGLE_MAPS_API_KEY');
    if (!apiKey) {
      console.error('GOOGLE_MAPS_API_KEY secret not found');
      const body: DirectionsResponse = { 
        success: false, 
        error: 'Google Maps API key not configured' 
      };
      return new Response(JSON.stringify(body), { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    // Build Google Maps Directions API URL
    // Optional departure_time: use duration_in_traffic when available (traffic-aware estimate)
    const origin = `${homeLat},${homeLng}`;
    const destination = `${projectLat},${projectLng}`;
    let url = `https://maps.googleapis.com/maps/api/directions/json?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}&mode=driving&key=${apiKey}`;
    if (departureTimeRaw !== undefined && departureTimeRaw !== null && departureTimeRaw !== '') {
      const dep = departureTimeRaw === 'now' ? 'now' : String(Math.floor(Number(departureTimeRaw)));
      url += `&departure_time=${dep}`;
      url += `&traffic_model=${trafficModelParam}`;
    }
    console.info(`Calling Google Maps Directions API: origin=${origin}, destination=${destination}, departure_time=${departureTimeRaw ?? 'none'}`);
    const resp = await fetch(url);
    const data = await resp.json();

    // Check API response status
    if (data.status === 'OK' && data.routes && data.routes.length > 0) {
      const route = data.routes[0];
      const leg = route.legs[0]; // Get first leg (for simple point-to-point, there's only one leg)
      
      // Extract distance (in meters)
      const distanceMeters = leg.distance.value;
      const distanceKm = distanceMeters / 1000;
      const distanceText = leg.distance.text; // e.g., "15.2 km"
      
      // Use duration_in_traffic when we requested departure_time and it is present (traffic-aware)
      const durationInTraffic = leg.duration_in_traffic?.value;
      const durationSeconds = (departureTimeRaw != null && durationInTraffic != null) ? durationInTraffic : leg.duration.value;
      const travelTimeMinutes = Math.round(durationSeconds / 60);
      
      // Format travel time as HH:MM
      const hours = Math.floor(travelTimeMinutes / 60);
      const minutes = travelTimeMinutes % 60;
      const travelTimeFormatted = `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}`;
      
      console.info(`Directions found: ${distanceText}, ${travelTimeMinutes} minutes`);
      
      const body: DirectionsResponse = { 
        success: true,
        travel_time_minutes: travelTimeMinutes,
        distance_kilometers: parseFloat(distanceKm.toFixed(2)),
        distance_text: distanceText,
        travel_time_formatted: travelTimeFormatted,
      };
      return new Response(JSON.stringify(body), { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    // Handle specific Google API error statuses
    const apiStatus = data.status || 'UNKNOWN_ERROR';
    console.warn(`Directions API returned status: ${apiStatus}`);

    if (apiStatus === 'ZERO_RESULTS') {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'No route found between the specified locations' 
      };
      return new Response(JSON.stringify(body), { 
        status: 404, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    if (apiStatus === 'NOT_FOUND') {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'Origin or destination not found' 
      };
      return new Response(JSON.stringify(body), { 
        status: 404, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    if (apiStatus === 'OVER_QUERY_LIMIT') {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'Google Maps API quota exceeded' 
      };
      return new Response(JSON.stringify(body), { 
        status: 429, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    if (apiStatus === 'REQUEST_DENIED') {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'Google Maps API request denied. Check API key and restrictions.' 
      };
      return new Response(JSON.stringify(body), { 
        status: 403, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    if (apiStatus === 'INVALID_REQUEST') {
      const body: DirectionsResponse = { 
        success: false, 
        error: 'Invalid request parameters' 
      };
      return new Response(JSON.stringify(body), { 
        status: 400, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      });
    }

    // Fallback for unknown errors
    const body: DirectionsResponse = { 
      success: false, 
      error: `Directions API error: ${apiStatus}` 
    };
    return new Response(JSON.stringify(body), { 
      status: 502, 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    });

  } catch (err: any) {
    console.error('Error in get_directions_edge_function:', err);
    const body: DirectionsResponse = { 
      success: false, 
      error: err?.message || 'Internal server error' 
    };
    return new Response(JSON.stringify(body), { 
      status: 500, 
      headers: { 
        'Content-Type': 'application/json', 
        'Access-Control-Allow-Origin': '*' 
      } 
    });
  }
});

