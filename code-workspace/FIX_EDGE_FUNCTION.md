# Fix Edge Function - Complete Code

## The Problem
Your Edge Function is checking for both email AND password, but password is optional. The error shows:
- Email is present: `"email":"patbyrne.dwce@gmail.com"`
- Password is empty: `"password":""`
- Error: `Missing email or password`

## The Solution
Replace your Edge Function code with the code below. It only checks for email and automatically generates a random password if none is provided.

---

## Step 1: Go to Supabase Dashboard

1. Open https://supabase.com/dashboard
2. Select your project
3. Click "Edge Functions" in the left sidebar
4. Click on `create_user_admin` (or create it if it doesn't exist)

## Step 2: Replace ALL Code

Delete everything in the editor, then paste this COMPLETE code:

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
    
    const {
      data: { user: callerUser },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !callerUser) {
      console.error("Auth error:", authError);
      return new Response(
        JSON.stringify({ error: "Invalid token or user not found" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: callerSetup, error: setupError } = await supabase
      .from("users_setup")
      .select("security, role")
      .eq("user_id", callerUser.id)
      .single();

    if (setupError || !callerSetup) {
      console.error("Setup error:", setupError);
      return new Response(
        JSON.stringify({ error: "Caller setup not found" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const callerSecurity = callerSetup.security;
    const isAdminRole = callerSetup.role === "Admin";

    if (callerSecurity !== 1 && !isAdminRole) {
      return new Response(
        JSON.stringify({ error: "Insufficient permissions. Security level 1 required." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const {
      email,
      password,
      phone,
      display_name,
      forename,
      surname,
      initials,
      role,
      security,
      users_data_fields = {},
    } = body;

    if (!email) {
      return new Response(
        JSON.stringify({ error: "Missing email" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let finalPassword = password;
    if (!finalPassword || finalPassword.trim() === "") {
      const randomBytes = new Uint8Array(16);
      crypto.getRandomValues(randomBytes);
      finalPassword = Array.from(randomBytes)
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      console.log("Generated random password for user:", email);
    }

    const { data: authData, error: authCreateError } = await supabase.auth.admin.createUser({
      email: email,
      password: finalPassword,
      phone: phone || undefined,
      email_confirm: false,
      user_metadata: {
        display_name: display_name,
      },
    });

    if (authCreateError || !authData.user) {
      console.error("Auth create error:", authCreateError);
      return new Response(
        JSON.stringify({ error: `Failed to create user: ${authCreateError?.message || "Unknown error"}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userId = authData.user.id;

    const usersDataInsert = {
      user_id: userId,
      display_name: display_name,
      forename: forename,
      surname: surname,
      initials: initials,
      ...users_data_fields,
    };

    const { error: usersDataError } = await supabase
      .from("users_data")
      .insert(usersDataInsert);

    if (usersDataError) {
      console.error("Users data insert error:", usersDataError);
      await supabase.auth.admin.deleteUser(userId);
      return new Response(
        JSON.stringify({ error: `Failed to create user data: ${usersDataError.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { error: usersSetupError } = await supabase
      .from("users_setup")
      .insert({
        user_id: userId,
        display_name: display_name,
        role: role,
        security: security,
      });

    if (usersSetupError) {
      console.error("Users setup insert error:", usersSetupError);
      await supabase.from("users_data").delete().eq("user_id", userId);
      await supabase.auth.admin.deleteUser(userId);
      return new Response(
        JSON.stringify({ error: `Failed to create user setup: ${usersSetupError.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        user: {
          id: userId,
          email: email,
          display_name: display_name,
        },
        message: "User created successfully",
      }),
      {
        status: 201,
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

## Step 3: Deploy

1. Click "Deploy" or "Save" button
2. Wait for deployment to complete
3. You should see "Deployed successfully" or similar message

## Step 4: Test

1. Go back to your Flutter app
2. Try creating a user again (with empty password)
3. Should work now!

---

## Also Fix: RLS Policy for google_api_calls

You're also getting an RLS error for the geocoding cache. Run this SQL in Supabase SQL Editor:

```sql
ALTER TABLE public.google_api_calls ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow authenticated users to insert google_api_calls"
ON public.google_api_calls
FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Allow authenticated users to read google_api_calls"
ON public.google_api_calls
FOR SELECT
TO authenticated
USING (true);
```

---

## What Changed

The key fix is on these lines:
- **OLD:** Checked for both `!email || !password`
- **NEW:** Only checks for `!email`, then generates random password if empty

This allows the Flutter app to send `password: ""` and the Edge Function will handle it correctly.

