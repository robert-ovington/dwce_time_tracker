# Fix Edge Function - Add users_setup_fields Support

## The Problem
The `create_user_admin` and `update_user_admin` Edge Functions are not handling the `users_setup_fields` parameter, so menu permissions and security_limit are not being saved to `public.users_setup`.

## The Solution
Update both Edge Functions to accept and use `users_setup_fields` when inserting/updating `users_setup` records.

---

## Step 1: Update `create_user_admin` Edge Function

### Go to Supabase Dashboard
1. Open https://supabase.com/dashboard
2. Select your project
3. Click "Edge Functions" in the left sidebar
4. Click on `create_user_admin`

### Update the Code

Find this section (around line 93-105):

```typescript
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
```

**Change it to:**

```typescript
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
  users_setup_fields = {},
} = body;
```

Then find this section (around line 166-173):

```typescript
const { error: usersSetupError } = await supabase
  .from("users_setup")
  .insert({
    user_id: userId,
    display_name: display_name,
    role: role,
    security: security,
  });
```

**Change it to:**

```typescript
const usersSetupInsert = {
  user_id: userId,
  display_name: display_name,
  role: role,
  security: security,
  ...users_setup_fields, // Spread the users_setup_fields to include all menu permissions
};

const { error: usersSetupError } = await supabase
  .from("users_setup")
  .insert(usersSetupInsert);
```

Also, find this section (around line 124-132):

```typescript
const { data: authData, error: authCreateError } = await supabase.auth.admin.createUser({
  email: email,
  password: finalPassword,
  phone: phone || undefined,
  email_confirm: false,
  user_metadata: {
    display_name: display_name,
  },
});
```

**Change `email_confirm: false` to `email_confirm: true`:**

```typescript
const { data: authData, error: authCreateError } = await supabase.auth.admin.createUser({
  email: email,
  password: finalPassword,
  phone: phone || undefined,
  email_confirm: true, // Auto-confirm email so admin-created users can log in immediately
  user_metadata: {
    display_name: display_name,
  },
});
```

### Deploy
1. Click "Deploy" or "Save" button
2. Wait for deployment to complete

---

## Step 2: Update `update_user_admin` Edge Function

### Go to Supabase Dashboard
1. Open https://supabase.com/dashboard
2. Select your project
3. Click "Edge Functions" in the left sidebar
4. Click on `update_user_admin` (or create it if it doesn't exist)

### Complete Code for `update_user_admin`

If the Edge Function doesn't exist or needs a complete update, use this code:

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
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Update auth.users if email or password provided
    if (email || password) {
      const authUpdate: any = {};
      if (email) authUpdate.email = email;
      if (password) authUpdate.password = password;
      if (email_confirm !== undefined) authUpdate.email_confirm = email_confirm;

      const { error: authUpdateError } = await supabase.auth.admin.updateUserById(
        user_id,
        authUpdate
      );

      if (authUpdateError) {
        console.error("Auth update error:", authUpdateError);
        return new Response(
          JSON.stringify({ error: `Failed to update auth user: ${authUpdateError.message}` }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Update users_data if any fields provided
    if (display_name || forename || surname || initials || Object.keys(users_data_fields).length > 0) {
      const usersDataUpdate: any = {};
      if (display_name) usersDataUpdate.display_name = display_name;
      if (forename) usersDataUpdate.forename = forename;
      if (surname) usersDataUpdate.surname = surname;
      if (initials) usersDataUpdate.initials = initials;
      Object.assign(usersDataUpdate, users_data_fields);

      const { error: usersDataError } = await supabase
        .from("users_data")
        .update(usersDataUpdate)
        .eq("user_id", user_id);

      if (usersDataError) {
        console.error("Users data update error:", usersDataError);
        return new Response(
          JSON.stringify({ error: `Failed to update user data: ${usersDataError.message}` }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Update users_setup if any fields provided
    if (display_name || role || security !== undefined || Object.keys(users_setup_fields).length > 0) {
      const usersSetupUpdate: any = {};
      if (display_name) usersSetupUpdate.display_name = display_name;
      if (role) usersSetupUpdate.role = role;
      if (security !== undefined) usersSetupUpdate.security = security;
      Object.assign(usersSetupUpdate, users_setup_fields); // Include all menu permissions

      const { error: usersSetupError } = await supabase
        .from("users_setup")
        .update(usersSetupUpdate)
        .eq("user_id", user_id);

      if (usersSetupError) {
        console.error("Users setup update error:", usersSetupError);
        return new Response(
          JSON.stringify({ error: `Failed to update user setup: ${usersSetupError.message}` }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
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

### Deploy
1. Click "Deploy" or "Save" button
2. Wait for deployment to complete

---

## Step 3: Test

1. Go back to your Flutter app
2. Create a new user and uncheck some menu permissions
3. Check the `public.users_setup` table in Supabase to verify the values are saved correctly
4. Edit a user and change menu permissions
5. Verify the changes are saved in `public.users_setup`

---

## What Changed

### `create_user_admin` Edge Function:
- **Added:** `users_setup_fields = {}` to the destructured request body
- **Added:** Spread `...users_setup_fields` into `usersSetupInsert` object
- **Result:** Menu permissions and `security_limit` are now saved when creating users

### `update_user_admin` Edge Function:
- **Added:** `users_setup_fields = {}` to the destructured request body
- **Added:** `Object.assign(usersSetupUpdate, users_setup_fields)` to merge menu permissions into update object
- **Result:** Menu permissions and `security_limit` are now updated when editing users

---

## Menu Permissions Fields

The `users_setup_fields` object includes these fields:
- `security_limit` (integer, 1-9)
- `menu_clock_in` (boolean)
- `menu_time_periods` (boolean)
- `menu_plant_checks` (boolean)
- `menu_deliveries` (boolean)
- `menu_paperwork` (boolean)
- `menu_time_off` (boolean)
- `menu_sites` (boolean)
- `menu_reports` (boolean)
- `menu_payroll` (boolean)
- `menu_exports` (boolean)
- `menu_administration` (boolean)
- `dashboard` (boolean)
- `menu_training` (boolean)
- `menu_cube_test` (boolean)

All fields are optional and will default to `true` if not provided (as defined in the database schema).
