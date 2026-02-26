# Fix RLS Policy Error

## The Problem

You're seeing this error:
```
❌ Error: new row violates row-level security policy for table "projects"
```

This happens because you're using the **anon key** which is restricted by Row Level Security (RLS) policies.

## The Solution

**Use the service_role key instead of the anon key.**

The service_role key has full database access and bypasses RLS policies, which is required for automated bulk syncs like this.

## How to Fix

### Step 1: Get Your Service Role Key

1. Go to your Supabase Dashboard: https://app.supabase.com
2. Select your project
3. Go to **Settings** → **API**
4. Scroll down to find **Project API keys**
5. Find the **`service_role`** key (it's labeled as "secret" - keep it secret!)
6. Copy the key (it's a long string starting with `eyJ...`)

### Step 2: Update the Script

1. Open `sync_projects_access_to_supabase.py`
2. Find this line (around line 25-26):
   ```python
   SUPABASE_KEY = "your-supabase-anon-key"
   ```
3. Replace it with:
   ```python
   SUPABASE_KEY = "your-service-role-key-here"  # Use service_role key, not anon key
   ```
4. Paste your service_role key in place of `your-service-role-key-here`

### Step 3: Run the Script Again

```bash
python sync_projects_access_to_supabase.py
```

It should now work without RLS errors!

## Important Security Notes

⚠️ **CRITICAL**: The service_role key has FULL database access

- **Never** commit it to Git or public repositories
- **Never** use it in client-side code (Flutter app, web app, etc.)
- **Only** use it in secure server-side scripts like this sync script
- Treat it like a password - keep it secret!

## Alternative Solution: Update RLS Policies (Not Recommended)

If you want to keep using the anon key, you'd need to update the RLS policies on the `projects` table. However, this is **not recommended** for bulk sync operations because:

1. It's more complex to set up correctly
2. You'd need policies for inserts AND updates
3. It's less secure than using service_role for automated scripts
4. It can cause issues with your app's normal users

**For automated sync scripts, always use the service_role key.**

## Verify It's Working

After updating to the service_role key, you should see:

```
✅ Successfully synced 482 projects to Supabase
   - Updated: X
   - Inserted: Y
```

Instead of all those RLS errors.

## Still Having Issues?

If you're still getting errors after using the service_role key:

1. Double-check you copied the entire key (it's very long)
2. Make sure there are no extra spaces or quotes
3. Verify the SUPABASE_URL is correct
4. Check that the `projects` table exists in Supabase
5. Ensure you have the correct permissions in Supabase
