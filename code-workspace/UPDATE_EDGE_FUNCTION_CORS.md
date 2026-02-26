# Quick Fix: Update CORS Headers in Edge Function

## The Problem
The Edge Function is blocking requests because it doesn't allow the `x-client-info` header that Supabase Flutter SDK sends.

## The Solution
Update the CORS headers in your `geocode_eircode_edge_function` Edge Function.

## Steps:

1. **Go to Supabase Dashboard** → Edge Functions → `geocode_eircode_edge_function`

2. **Click "Edit Function"**

3. **Find this line** (around line 12):
   ```typescript
   'Access-Control-Allow-Headers': 'Content-Type, Authorization',
   ```

4. **Replace it with**:
   ```typescript
   'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-client-info, apikey, x-client-version',
   ```

5. **Save and Deploy** the function

## That's it!

After updating and deploying, the "Find GPS" button should work without CORS errors.

---

## Full Updated corsHeaders Object

If you want to see the full context, here's the complete `corsHeaders` object that should be in your function:

```typescript
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-client-info, apikey, x-client-version',
};
```

Make sure this appears in **both** places:
1. In the `OPTIONS` handler (for preflight requests)
2. In all response headers (for actual requests)

