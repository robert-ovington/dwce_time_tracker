# Fix REQUEST_DENIED Error from Google Maps API

## Error Message
```
Geocoding failed: REQUEST_DENIED
```

## What This Means
The Google Maps API key is being rejected. This is usually due to:
1. **Geocoding API not enabled** for your API key
2. **API key restrictions** blocking the request
3. **Invalid or expired** API key

## Solution Steps

### Step 1: Enable Geocoding API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project
3. Go to **APIs & Services** → **Library**
4. Search for **"Geocoding API"**
5. Click on it
6. Click **Enable** button
7. Wait a few minutes for it to activate

### Step 2: Check API Key Restrictions

1. Go to **APIs & Services** → **Credentials**
2. Click on your API key
3. Check the **API restrictions** section:
   - If it says **"Restrict key"**, make sure **Geocoding API** is in the allowed list
   - Or temporarily set it to **"Don't restrict key"** for testing
4. Check the **Application restrictions** section:
   - If set to **"HTTP referrers"**, the Edge Function domain might not be allowed
   - For Edge Functions, you may need to:
     - Set to **"None"** (for testing)
     - Or add your Supabase project domain: `*.supabase.co`
5. Click **Save**

### Step 3: Verify API Key in Edge Function

1. Go to **Supabase Dashboard** → **Edge Functions** → **geocode_eircode_edge_function**
2. Go to **Settings** → **Secrets**
3. Verify `GOOGLE_MAPS_API_KEY` is set correctly
4. Make sure there are no extra spaces or characters

### Step 4: Test Again

1. Try the "Find GPS" button again
2. Check the browser console for the response
3. If still getting `REQUEST_DENIED`, check Google Cloud Console logs:
   - Go to **APIs & Services** → **Dashboard**
   - Look for any error messages or quota issues

## Quick Test: Temporarily Remove Restrictions

For testing purposes, you can temporarily:
1. Set **API restrictions** to **"Don't restrict key"**
2. Set **Application restrictions** to **"None"**
3. Test the function
4. Once working, add back appropriate restrictions

## Common Issues

### Issue: API Key Works in Browser but Not in Edge Function
- **Solution**: The Edge Function makes requests from Supabase's servers, not your browser
- You may need to allow the Supabase domain or remove IP restrictions

### Issue: "This API key is not authorized"
- **Solution**: Make sure Geocoding API is enabled in the API Library

### Issue: Quota Exceeded
- **Solution**: Check your Google Cloud billing and quotas
- Free tier allows 40,000 requests per month

## After Fixing

Once the API key is properly configured:
- The Edge Function should return status 200
- You should see coordinates in the latitude/longitude fields
- The status message should show: "✅ GPS coordinates found: [lat], [lng]"

