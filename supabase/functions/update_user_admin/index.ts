// Edge Function: update_user_admin
// Updates auth.users, public.users_data, and public.users_setup (including menu permissions).
// Called from Flutter User Edit screen. Requires CORS for web app.

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
      user_id,
      email,
      phone,
      display_name,
      forename,
      surname,
      initials,
      role,
      security,
      password,
      users_data_fields = {},
      users_setup_fields = {},
      email_confirm,
    } = body;

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: "Missing user_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Update auth.users if email or password provided
    if (email != null || (password != null && String(password).trim() !== "")) {
      const authUpdate: Record<string, unknown> = {};
      if (email != null && String(email).trim() !== "") authUpdate.email = email;
      if (password != null && String(password).trim() !== "") authUpdate.password = password;
      if (email_confirm !== undefined) authUpdate.email_confirm = !!email_confirm;

      if (Object.keys(authUpdate).length > 0) {
        const { error: authUpdateError } = await supabase.auth.admin.updateUserById(
          user_id,
          authUpdate,
        );

        if (authUpdateError) {
          console.error("Auth update error:", authUpdateError);
          return new Response(
            JSON.stringify({
              error: `Failed to update auth user: ${authUpdateError.message}`,
            }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
      }
    }

    // Update users_data if any fields provided
    const hasUsersDataFields =
      display_name != null ||
      forename != null ||
      surname != null ||
      initials != null ||
      Object.keys(users_data_fields).length > 0;

    if (hasUsersDataFields) {
      const usersDataUpdate: Record<string, unknown> = { ...users_data_fields };
      if (display_name != null && String(display_name).trim() !== "")
        usersDataUpdate.display_name = display_name;
      if (forename != null && String(forename).trim() !== "") usersDataUpdate.forename = forename;
      if (surname != null && String(surname).trim() !== "") usersDataUpdate.surname = surname;
      if (initials != null && String(initials).trim() !== "") usersDataUpdate.initials = initials;

      const { error: usersDataError } = await supabase
        .from("users_data")
        .update(usersDataUpdate)
        .eq("user_id", user_id);

      if (usersDataError) {
        console.error("Users data update error:", usersDataError);
        return new Response(
          JSON.stringify({
            error: `Failed to update user data: ${usersDataError.message}`,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // Update users_setup: always apply when any of role, security, display_name or users_setup_fields are present (menu items)
    const hasUsersSetupFields =
      (display_name != null && String(display_name).trim() !== "") ||
      (role != null && String(role).trim() !== "") ||
      security !== undefined ||
      Object.keys(users_setup_fields).length > 0;

    if (hasUsersSetupFields) {
      const usersSetupUpdate: Record<string, unknown> = { ...users_setup_fields };
      if (display_name != null && String(display_name).trim() !== "")
        usersSetupUpdate.display_name = display_name;
      if (role != null && String(role).trim() !== "") usersSetupUpdate.role = role;
      if (security !== undefined) usersSetupUpdate.security = security;

      const { error: usersSetupError } = await supabase
        .from("users_setup")
        .update(usersSetupUpdate)
        .eq("user_id", user_id);

      if (usersSetupError) {
        console.error("Users setup update error:", usersSetupError);
        return new Response(
          JSON.stringify({
            error: `Failed to update user setup: ${usersSetupError.message}`,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: "User updated successfully",
      }),
      {
        status: 200,
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
