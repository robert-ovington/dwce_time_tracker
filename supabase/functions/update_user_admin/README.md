# update_user_admin Edge Function

Updates an existing user in `auth.users`, `public.users_data`, and `public.users_setup`. Used by the User Edit screen (including menu permission changes). Includes CORS for the web app.

## Why menu edits didn't update

If the function was missing or an old version without `users_setup_fields` was deployed, the app's call to update menu items would fail or no-op. Deploy this version so that:

- `users_setup_fields` (menu_clock_in, menu_time_periods, etc.) are applied to `users_setup`.
- CORS headers are returned so the web app can call the function.

## Deploy

From the project root:

```bash
npx supabase functions deploy update_user_admin
```

Or in Supabase Dashboard: Edge Functions → update_user_admin → paste `index.ts` → Deploy.

## Request body (from Flutter)

- Required: `user_id`
- Optional: `email`, `phone`, `display_name`, `forename`, `surname`, `initials`, `role`, `security`, `password`, `email_confirm`, `users_data_fields`, `users_setup_fields`
