# Edge Function: get_user_id_from_email

## Purpose
Get `user_id` (UUID from `auth.users`) from an email address. This is needed when entering time for other users.

## Why It's Needed

The `time_periods` table uses `user_id` (UUID) which references `auth.users.id`, not email. When an admin enters time for another user, we need to convert the email to `user_id`.

## Complete Code

Create this file: `supabase/functions/get_user_id_from_email/index.ts`

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, x-client-version, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const token = authHeader.replace("Bearer ", "");
    
    // Verify caller
    const {
      data: { user: callerUser },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !callerUser) {
      return new Response(
        JSON.stringify({ error: "Invalid token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const { email } = body;

    if (!email) {
      return new Response(
        JSON.stringify({ error: "Missing email" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get user from auth.users by email (requires admin access)
    const { data: { users }, error: listError } = await supabase.auth.admin.listUsers();

    if (listError) {
      return new Response(
        JSON.stringify({ error: `Failed to list users: ${listError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const user = users.find((u) => u.email === email);

    if (!user) {
      return new Response(
        JSON.stringify({ error: "User not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        user_id: user.id,
        email: user.email,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({ error: `Unexpected error: ${error.message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
```

## Deployment

1. Go to Supabase Dashboard → Edge Functions
2. Create new function: `get_user_id_from_email`
3. Paste the code above
4. Deploy

## Alternative: Store Email Mapping

If you don't want to create an Edge Function, you could:
1. Store email in `users_data` table (add `email` column)
2. Query `users_data` by email to get `user_id`
3. This requires a database migration

## Usage in Flutter

The code already calls this Edge Function in `_getUserIdFromEmail()`. If the function doesn't exist, it will gracefully fail and show an error.

