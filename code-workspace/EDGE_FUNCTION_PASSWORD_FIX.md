# Edge Function Password Fix

## Problem
The `create_user_admin` Edge Function is returning:
```
FunctionException(status: 400, details: {error: Missing email or password})
```

This occurs even when email is provided and password is intentionally left empty (optional field).

## Root Cause
The Edge Function validation is checking for the presence of both `email` and `password` fields, but when password is optional, it's not being sent in the request body, causing the validation to fail.

## Solution Options

### Option 1: Update Edge Function (Recommended)
Modify the Edge Function to handle optional passwords by checking if password is empty/null and generating a random one:

```typescript
// In supabase/functions/create_user_admin/index.ts

// Instead of:
if (!email || !password) {
  return new Response(
    JSON.stringify({ error: 'Missing email or password' }),
    { status: 400, headers: corsHeaders }
  );
}

// Use:
if (!email) {
  return new Response(
    JSON.stringify({ error: 'Missing email' }),
    { status: 400, headers: corsHeaders }
  );
}

// Generate random password if not provided
if (!password || password.trim() === '') {
  // Generate a secure random password
  password = crypto.randomBytes(16).toString('hex');
  // User will need to reset password via email
}
```

### Option 2: Always Send Password Field (Current Implementation)
The Flutter code has been updated to always send the `password` field (as empty string if not provided). The Edge Function should then:
1. Check if password is empty
2. If empty, generate a random password
3. Set `email_confirm: false` so user must verify email and set password

## Testing
After applying the fix:
1. Try creating a user **without** a password - should succeed
2. Try creating a user **with** a password - should succeed
3. Check that users without passwords can reset via email link

## Current Flutter Implementation
The Flutter code now always sends the `password` field:
- If password is provided: sends the actual password
- If password is empty/null: sends empty string `''`

The Edge Function should handle the empty string case.

