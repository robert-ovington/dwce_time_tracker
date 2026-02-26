# create_user_admin Edge Function

Creates a new user in `auth.users`, `public.users_data`, and `public.users_setup`. Used by the User Creation screen in the Flutter app.

## CORS

This function returns **CORS headers** on every response and handles **OPTIONS** preflight so the web app at `https://dwce-time-tracker.web.app` can call it. If you see:

```text
Access to fetch at '.../create_user_admin' from origin 'https://dwce-time-tracker.web.app' has been blocked by CORS policy
```

the deployed function is likely an older version without CORS. Redeploy this version.

## Deploy

From the project root (where `supabase` folder is):

```bash
npx supabase functions deploy create_user_admin
```

Or in Supabase Dashboard: Edge Functions → create_user_admin → paste the contents of `index.ts` → Deploy.

## Request body (from Flutter)

- `email`, `display_name`, `forename`, `surname`, `initials`, `role`, `security`, `email_confirm`
- Optional: `password`, `phone`, `users_data_fields`, `users_setup_fields`
