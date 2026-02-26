# Step-by-Step: Fix Google Maps API REQUEST_DENIED Error

## Current Error
```
Geocoding failed: REQUEST_DENIED
```

This means Google Maps is rejecting your API key. Follow these steps in order:

---

## Step 1: Verify Geocoding API is Enabled

1. **Go to Google Cloud Console**: https://console.cloud.google.com/
2. **Select your project** (top dropdown)
3. **Navigate to**: APIs & Services → Library
4. **Search for**: "Geocoding API"
5. **Click on**: "Geocoding API"
6. **Check status**:
   - If it says **"API enabled"** → ✅ Skip to Step 2
   - If it says **"Enable"** button → Click it and wait 2-3 minutes
7. **Verify**: Go back to Library, search again, confirm it shows "API enabled"

---

## Step 2: Get Your API Key

1. **Navigate to**: APIs & Services → Credentials
2. **Find your API key** (or create a new one)
3. **Click on the API key** to open settings
4. **Copy the API key** (you'll need this)

---

## Step 3: Check API Key Restrictions

### A. API Restrictions (What APIs can use this key)

1. **Scroll to "API restrictions"** section
2. **Check current setting**:
   - **If "Don't restrict key"**: ✅ Good, skip to Step 3B
   - **If "Restrict key"**: 
     - Make sure **"Geocoding API"** is in the list
     - If not, click **"Restrict key"** → **"Select APIs"**
     - Check the box for **"Geocoding API"**
     - Click **Save**

### B. Application Restrictions (Where the key can be used)

1. **Scroll to "Application restrictions"** section
2. **For testing, set to "None"**:
   - Click **"Application restrictions"** dropdown
   - Select **"None"**
   - Click **Save**
3. **Note**: You can add restrictions later, but for now use "None" to test

---

## Step 4: Update Edge Function Secret

1. **Go to Supabase Dashboard**: https://supabase.com/dashboard
2. **Select your project**
3. **Navigate to**: Edge Functions → geocode_eircode_edge_function
4. **Click**: Settings tab
5. **Scroll to**: Secrets section
6. **Update GOOGLE_MAPS_API_KEY**:
   - If it exists: Click edit, paste your API key, Save
   - If it doesn't exist: Click "Add Secret", name: `GOOGLE_MAPS_API_KEY`, value: your API key, Save
7. **Important**: 
   - No spaces before/after the key
   - Copy the entire key (usually starts with "AIza...")
   - Make sure it's exactly as shown in Google Cloud Console

---

## Step 5: Test the API Key Directly

Before testing in the app, verify the key works:

1. **Open a new browser tab**
2. **Paste this URL** (replace YOUR_API_KEY with your actual key):
   ```
   https://maps.googleapis.com/maps/api/geocode/json?address=R14WN51&key=YOUR_API_KEY
   ```
3. **Check the response**:
   - **If you see JSON with "status": "OK"** → ✅ API key works!
   - **If you see "REQUEST_DENIED"** → Go back to Steps 1-3
   - **If you see "This API key is not authorized"** → Enable Geocoding API (Step 1)

---

## Step 6: Test in Your App

1. **Refresh your Flutter app**
2. **Enter an Eircode** (e.g., "R14WN51")
3. **Click "Find GPS"**
4. **Check the result**:
   - ✅ Success: Coordinates appear in lat/lng fields
   - ❌ Still REQUEST_DENIED: Check Edge Function logs (see below)

---

## Step 7: Check Edge Function Logs (If Still Failing)

1. **Supabase Dashboard** → Edge Functions → geocode_eircode_edge_function
2. **Click**: Logs tab
3. **Look for**:
   - Error messages
   - The actual API key being used (might be truncated)
   - Any other clues

---

## Common Mistakes

❌ **API key has extra spaces** → Remove all spaces  
❌ **Geocoding API not enabled** → Enable it in API Library  
❌ **API restrictions blocking** → Add Geocoding API to allowed list  
❌ **Application restrictions too strict** → Set to "None" for testing  
❌ **Wrong API key in secret** → Double-check it matches Google Cloud Console  
❌ **Billing not enabled** → Google requires billing for some APIs (though Geocoding has free tier)

---

## Still Not Working?

If you've completed all steps and still get REQUEST_DENIED:

1. **Create a new API key** in Google Cloud Console
2. **Set it to "Don't restrict key"** and **"None"** for application restrictions
3. **Update the secret** in Supabase with the new key
4. **Test again**

This will help isolate if it's a key-specific issue or a configuration issue.

