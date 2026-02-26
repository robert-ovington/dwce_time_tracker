// Edge Function: create_user_admin
// Creates a new auth user and inserts users_data + users_setup.
// Called from Flutter User Creation screen. Requires CORS for web app (dwce-time-tracker.web.app).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, x-client-version, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  // CORS preflight – must return CORS headers so browser allows the actual POST from web app
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
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
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
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
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const callerSecurity = callerSetup.security;
    const isAdminRole = callerSetup.role === "Admin";

    if (callerSecurity !== 1 && !isAdminRole) {
      return new Response(
        JSON.stringify({ error: "Insufficient permissions. Security level 1 required." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
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
      email_confirm = true,
      users_data_fields = {},
      users_setup_fields = {},
    } = body;

    if (!email) {
      return new Response(
        JSON.stringify({ error: "Missing email" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    let finalPassword = password;
    if (!finalPassword || String(finalPassword).trim() === "") {
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
      email_confirm: !!email_confirm,
      user_metadata: {
        display_name: display_name,
      },
    });

    if (authCreateError || !authData.user) {
      console.error("Auth create error:", authCreateError);
      return new Response(
        JSON.stringify({
          error: `Failed to create user: ${authCreateError?.message || "Unknown error"}`,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
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

    const { error: usersDataError } = await supabase.from("users_data").insert(usersDataInsert);

    if (usersDataError) {
      console.error("Users data insert error:", usersDataError);
      await supabase.auth.admin.deleteUser(userId);
      return new Response(
        JSON.stringify({
          error: `Failed to create user data: ${usersDataError.message}`,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const usersSetupInsert = {
      user_id: userId,
      display_name: display_name,
      role: role,
      security: security,
      ...users_setup_fields,
    };

    const { error: usersSetupError } = await supabase
      .from("users_setup")
      .insert(usersSetupInsert);

    if (usersSetupError) {
      console.error("Users setup insert error:", usersSetupError);
      await supabase.from("users_data").delete().eq("user_id", userId);
      await supabase.auth.admin.deleteUser(userId);
      return new Response(
        JSON.stringify({
          error: `Failed to create user setup: ${usersSetupError.message}`,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
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
      },
    );
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({ error: `Unexpected error: ${(error as Error).message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
