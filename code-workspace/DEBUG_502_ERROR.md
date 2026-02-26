# Debugging 502 Error from Edge Function

## Status
✅ CORS issue is **FIXED** - the function is now being called successfully!
❌ Getting **502 error** - this means the function is running but encountering an error

## Common Causes of 502 Error

1. **Google Maps API Key not configured** (most likely)
2. **Invalid API key**
3. **API key doesn't have Geocoding API enabled**
4. **Error in Edge Function code**

## How to Fix

### Step 1: Check if API Key Secret is Set

1. Go to **Supabase Dashboard** → **Edge Functions** → **geocode_eircode_edge_function**
2. Click on **Settings** tab
3. Look for **Secrets** section
4. Check if `GOOGLE_MAPS_API_KEY` is listed
5. If it's **NOT there**, add it:
   - Click **Add Secret**
   - Name: `GOOGLE_MAPS_API_KEY`
   - Value: Your Google Maps API key
   - Click **Save**

### Step 2: Verify Your Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project
3. Go to **APIs & Services** → **Credentials**
4. Find your API key
5. Make sure **Geocoding API** is enabled:
   - Go to **APIs & Services** → **Library**
   - Search for "Geocoding API"
   - Click on it and make sure it's **Enabled**

### Step 3: Check Edge Function Logs

1. Go to **Supabase Dashboard** → **Edge Functions** → **geocode_eircode_edge_function**
2. Click on **Logs** tab
3. Look for error messages
4. Common errors you might see:
   - `GOOGLE_MAPS_API_KEY secret not found` → Secret not configured
   - `REQUEST_DENIED` → API key doesn't have permission
   - `OVER_QUERY_LIMIT` → API quota exceeded
   - `INVALID_REQUEST` → Invalid eircode format

### Step 4: Test the Function Directly

You can test the Edge Function directly from Supabase Dashboard:

1. Go to **Edge Functions** → **geocode_eircode_edge_function**
2. Click **Invoke** tab
3. Enter test payload:
   ```json
   {
     "eircode": "D02 AF30"
   }
   ```
4. Click **Invoke**
5. Check the response and logs

## Expected Behavior

When working correctly, you should see:
- **Status**: 200
- **Response**: 
  ```json
  {
    "success": true,
    "lat": 53.3331,
    "lng": -6.2489,
    "formatted_address": "Dublin, Ireland"
  }
  ```

## Quick Checklist

- [ ] `GOOGLE_MAPS_API_KEY` secret is added in Edge Function settings
- [ ] Google Maps API key is valid and active
- [ ] Geocoding API is enabled in Google Cloud Console
- [ ] API key has proper restrictions (or no restrictions for testing)
- [ ] Check Edge Function logs for specific error messages

## If Still Getting 502

Check the Edge Function logs - they will show the exact error. The most common issues are:
1. Secret not configured → Add `GOOGLE_MAPS_API_KEY` secret
2. API key invalid → Regenerate key in Google Cloud Console
3. Geocoding API not enabled → Enable it in Google Cloud Console

