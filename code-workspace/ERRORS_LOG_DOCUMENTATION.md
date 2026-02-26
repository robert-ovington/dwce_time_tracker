# Errors Log Table - Documentation

## Overview

The `public.errors_log` table is a centralized error tracking system that captures all errors, exceptions, and issues across the Flutter application. It provides comprehensive error tracking with categorization, severity levels, and resolution tracking.

## Table Schema

```sql
create table public.errors_log (
  id bigserial not null,
  user_id uuid null,
  platform text not null,
  location text null,
  type text not null,
  description text not null,
  created_at timestamp with time zone not null default now(),
  stack_trace text null,
  severity text not null default 'error'::text,
  error_code text null,
  resolved boolean not null default false,
  resolved_at timestamp with time zone null,
  resolved_by uuid null,
  resolution_notes text null,
  occurrence_count integer not null default 1,
  constraint errors_log_pkey primary key (id),
  constraint errors_log_resolved_by_fkey foreign KEY (resolved_by) references auth.users (id),
  constraint errors_log_platform_check check (
    platform = any (array['ios'::text, 'android'::text, 'web'::text])
  ),
  constraint errors_log_severity_check check (
    severity = any (array['critical'::text, 'error'::text, 'warning'::text, 'info'::text])
  )
);
```

### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigserial | Primary key, auto-incrementing |
| `user_id` | uuid | User who encountered the error (nullable) |
| `platform` | text | Platform where error occurred: 'web', 'android', or 'ios' |
| `location` | text | Screen/component where error occurred (e.g., "Timesheet Screen - Save Entry") |
| `type` | text | Error category: 'GPS', 'Validation', 'Database', 'Authentication', 'Network', 'UI', 'Data Processing', 'Storage', 'File Processing' |
| `description` | text | Detailed error message |
| `created_at` | timestamp | When the error occurred (auto-set) |
| `stack_trace` | text | Full stack trace (separate from description, up to 5000 chars) |
| `severity` | text | Severity level: 'critical', 'error', 'warning', or 'info' (defaults to 'error') |
| `error_code` | text | Standardized error code for pattern matching (e.g., "GPS_TIMEOUT", "DB_CONNECTION_FAILED") |
| `resolved` | boolean | Whether error has been resolved (defaults to false) |
| `resolved_at` | timestamp | When error was marked as resolved |
| `resolved_by` | uuid | User who resolved the error (references auth.users) |
| `resolution_notes` | text | Notes about how/why error was resolved |
| `occurrence_count` | integer | Number of times this error occurred (defaults to 1) |

## How the Table is Populated

### Automatic Population

The table is automatically populated through the `ErrorLogService` class, which is integrated throughout the application:

1. **ErrorLogService.logError()** - Central logging method called from catch blocks
2. **Automatic User Detection** - User ID is automatically retrieved from the current session
3. **Platform Detection** - Platform is automatically detected (web/android/ios)
4. **Stack Trace Capture** - Stack traces are automatically captured when available

### Integration Points

Error logging is integrated in the following screens:

- **Timesheet Screen** (`timesheet_screen.dart`)
  - GPS errors
  - Validation errors
  - Database errors
  - Travel calculation errors
  - Form submission errors

- **Login Screen** (`login_screen.dart`)
  - Authentication errors
  - Credential storage errors
  - Password reset errors

- **User Edit Screen** (`user_edit_screen.dart`)
  - Database errors
  - GPS lookup errors
  - API counter errors
  - Cache save errors

- **User Creation Screen** (`user_creation_screen.dart`)
  - User creation errors
  - CSV import errors
  - Database errors

- **Employer Management Screen** (`employer_management_screen.dart`)
  - CRUD operation errors
  - CSV import errors
  - Database errors

### Example Usage

```dart
// Basic error logging
await ErrorLogService.logError(
  location: 'Timesheet Screen - Save Entry',
  type: 'Validation',
  description: 'Failed to validate time period: missing start time',
);

// With stack trace
await ErrorLogService.logError(
  location: 'User Edit Screen - Find GPS',
  type: 'GPS',
  description: 'Failed to get GPS coordinates for eircode R14 YD28',
  stackTrace: stackTrace,
);

// With severity and error code
await ErrorLogService.logError(
  location: 'Timesheet Screen - Travel Calculation',
  type: 'GPS',
  description: 'Google Maps API quota exceeded',
  severity: 'critical',
  errorCode: 'GOOGLE_API_QUOTA_EXCEEDED',
  stackTrace: stackTrace,
);
```

### Error Types Used

- **GPS** - GPS location, geocoding, and travel calculation errors
- **Validation** - Form validation, data validation errors
- **Database** - Database connection, query, RLS policy errors
- **Authentication** - Login, password reset, session errors
- **Network** - API calls, connectivity errors
- **UI** - Dialog, screen rendering errors
- **Data Processing** - Data parsing, transformation errors
- **Storage** - Local storage, credential storage errors
- **File Processing** - CSV import, file parsing errors

## Monitoring the Errors Log

### 1. Supabase Dashboard

Access the table directly in Supabase Dashboard:
- Navigate to **Table Editor** → `errors_log`
- View, filter, and sort errors
- Use the SQL Editor for custom queries

### 2. Useful SQL Queries

#### Get Recent Errors (Last 24 Hours)
```sql
SELECT 
  id,
  created_at,
  severity,
  type,
  location,
  description,
  platform,
  user_id
FROM public.errors_log
WHERE created_at >= NOW() - INTERVAL '24 hours'
  AND resolved = false
ORDER BY created_at DESC
LIMIT 100;
```

#### Get Critical Errors
```sql
SELECT 
  id,
  created_at,
  type,
  location,
  description,
  error_code,
  platform
FROM public.errors_log
WHERE severity = 'critical'
  AND resolved = false
ORDER BY created_at DESC;
```

#### Get Errors by Type
```sql
SELECT 
  type,
  COUNT(*) as error_count,
  COUNT(DISTINCT user_id) as affected_users
FROM public.errors_log
WHERE created_at >= NOW() - INTERVAL '7 days'
  AND resolved = false
GROUP BY type
ORDER BY error_count DESC;
```

#### Get Errors by Location (Screen)
```sql
SELECT 
  location,
  COUNT(*) as error_count,
  MAX(created_at) as last_occurrence
FROM public.errors_log
WHERE created_at >= NOW() - INTERVAL '7 days'
  AND resolved = false
GROUP BY location
ORDER BY error_count DESC;
```

#### Get Errors by Platform
```sql
SELECT 
  platform,
  severity,
  COUNT(*) as error_count
FROM public.errors_log
WHERE created_at >= NOW() - INTERVAL '7 days'
  AND resolved = false
GROUP BY platform, severity
ORDER BY platform, severity;
```

#### Get Most Common Errors (by error_code)
```sql
SELECT 
  error_code,
  location,
  COUNT(*) as occurrence_count,
  MAX(created_at) as last_occurrence
FROM public.errors_log
WHERE error_code IS NOT NULL
  AND created_at >= NOW() - INTERVAL '30 days'
  AND resolved = false
GROUP BY error_code, location
ORDER BY occurrence_count DESC
LIMIT 20;
```

#### Get Errors Affecting Specific User
```sql
SELECT 
  id,
  created_at,
  severity,
  type,
  location,
  description
FROM public.errors_log
WHERE user_id = 'USER_UUID_HERE'
  AND resolved = false
ORDER BY created_at DESC;
```

### 3. Create a View for Active Errors

```sql
CREATE OR REPLACE VIEW public.active_errors AS
SELECT 
  id,
  created_at,
  severity,
  type,
  location,
  error_code,
  description,
  platform,
  user_id,
  occurrence_count
FROM public.errors_log
WHERE resolved = false
ORDER BY 
  CASE severity
    WHEN 'critical' THEN 1
    WHEN 'error' THEN 2
    WHEN 'warning' THEN 3
    WHEN 'info' THEN 4
  END,
  created_at DESC;
```

### 4. Set Up Alerts (Supabase Pro/Team)

For Supabase Pro/Team plans, you can set up:
- Database webhooks for critical errors
- Email notifications for error thresholds
- Slack/Discord integrations

## Weekly Error Reports

### Option 1: Supabase Edge Function (Recommended)

Create a scheduled Edge Function that generates and sends weekly reports:

#### Step 1: Create the Edge Function

Create `supabase/functions/weekly_error_report/index.ts`:

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get date range (last 7 days)
    const endDate = new Date();
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 7);

    // Get error statistics
    const { data: errors, error } = await supabase
      .from('errors_log')
      .select('*')
      .gte('created_at', startDate.toISOString())
      .lte('created_at', endDate.toISOString())
      .order('created_at', { ascending: false });

    if (error) throw error;

    // Calculate statistics
    const totalErrors = errors.length;
    const criticalErrors = errors.filter(e => e.severity === 'critical').length;
    const errorErrors = errors.filter(e => e.severity === 'error').length;
    const warningErrors = errors.filter(e => e.severity === 'warning').length;
    const infoErrors = errors.filter(e => e.severity === 'info').length;

    // Group by type
    const errorsByType = errors.reduce((acc, error) => {
      acc[error.type] = (acc[error.type] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    // Group by location
    const errorsByLocation = errors.reduce((acc, error) => {
      acc[error.location || 'Unknown'] = (acc[error.location || 'Unknown'] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    // Group by platform
    const errorsByPlatform = errors.reduce((acc, error) => {
      acc[error.platform] = (acc[error.platform] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    // Get top 10 most common errors
    const errorCodeCounts = errors
      .filter(e => e.error_code)
      .reduce((acc, error) => {
        const key = `${error.error_code} - ${error.location}`;
        acc[key] = (acc[key] || 0) + 1;
        return acc;
      }, {} as Record<string, number>);

    const topErrors = Object.entries(errorCodeCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([error, count]) => ({ error, count }));

    // Generate report
    const report = {
      period: {
        start: startDate.toISOString(),
        end: endDate.toISOString(),
      },
      summary: {
        total_errors: totalErrors,
        critical: criticalErrors,
        error: errorErrors,
        warning: warningErrors,
        info: infoErrors,
      },
      by_type: errorsByType,
      by_location: errorsByLocation,
      by_platform: errorsByPlatform,
      top_errors: topErrors,
      unresolved_errors: errors.filter(e => !e.resolved).length,
    };

    // TODO: Send email or save to a reports table
    // For now, return the report
    return new Response(
      JSON.stringify(report, null, 2),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
```

#### Step 2: Schedule with pg_cron (PostgreSQL Extension)

```sql
-- Enable pg_cron extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule weekly report (runs every Monday at 9 AM)
SELECT cron.schedule(
  'weekly-error-report',
  '0 9 * * 1', -- Every Monday at 9 AM
  $$
  SELECT net.http_post(
    url := 'https://YOUR_PROJECT.supabase.co/functions/v1/weekly_error_report',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
```

### Option 2: Supabase Scheduled Functions (Supabase Pro/Team)

If you have Supabase Pro/Team, you can use scheduled functions directly in the dashboard.

### Option 3: External Cron Job

Set up an external cron job (e.g., GitHub Actions, AWS Lambda, etc.) to call the Edge Function weekly.

### Option 4: Manual SQL Report

Run this SQL query weekly to generate a report:

```sql
-- Weekly Error Report
WITH error_stats AS (
  SELECT 
    DATE_TRUNC('day', created_at) as error_date,
    severity,
    type,
    location,
    platform,
    COUNT(*) as error_count
  FROM public.errors_log
  WHERE created_at >= NOW() - INTERVAL '7 days'
  GROUP BY DATE_TRUNC('day', created_at), severity, type, location, platform
)
SELECT 
  error_date,
  severity,
  type,
  location,
  platform,
  error_count
FROM error_stats
ORDER BY error_date DESC, error_count DESC;
```

## Resolving Errors

### Mark Error as Resolved

```sql
UPDATE public.errors_log
SET 
  resolved = true,
  resolved_at = NOW(),
  resolved_by = 'USER_UUID_HERE',
  resolution_notes = 'Fixed by updating GPS timeout handling'
WHERE id = ERROR_ID_HERE;
```

### Bulk Resolve Errors

```sql
-- Resolve all instances of a specific error code
UPDATE public.errors_log
SET 
  resolved = true,
  resolved_at = NOW(),
  resolved_by = 'USER_UUID_HERE',
  resolution_notes = 'Fixed in version 1.2.0'
WHERE error_code = 'GPS_TIMEOUT'
  AND resolved = false;
```

## Best Practices

1. **Use Error Codes** - Assign standardized error codes for common errors to enable pattern matching
2. **Set Appropriate Severity** - Use 'critical' for blocking issues, 'error' for failures, 'warning' for non-blocking issues
3. **Include Context** - Provide detailed descriptions with relevant context (user actions, input values, etc.)
4. **Regular Monitoring** - Review errors weekly to identify patterns and prioritize fixes
5. **Resolution Tracking** - Mark errors as resolved with notes explaining the fix
6. **Clean Up Old Errors** - Archive or delete resolved errors older than 90 days to keep the table manageable

## Maintenance

### Archive Old Resolved Errors

```sql
-- Create archive table (run once)
CREATE TABLE IF NOT EXISTS public.errors_log_archive (
  LIKE public.errors_log INCLUDING ALL
);

-- Archive resolved errors older than 90 days
INSERT INTO public.errors_log_archive
SELECT * FROM public.errors_log
WHERE resolved = true
  AND resolved_at < NOW() - INTERVAL '90 days';

-- Delete archived errors
DELETE FROM public.errors_log
WHERE resolved = true
  AND resolved_at < NOW() - INTERVAL '90 days';
```

### Clean Up Test Data

```sql
-- Delete errors from test users or specific time periods
DELETE FROM public.errors_log
WHERE created_at < '2024-01-01'
  OR user_id IN (SELECT id FROM auth.users WHERE email LIKE '%test%');
```

## Indexes

The table has the following indexes for optimal query performance:

- `errors_log_user_id_idx` - Fast user-specific queries
- `errors_log_created_at_idx` - Fast time-based queries
- `errors_log_type_idx` - Fast filtering by error type
- `errors_log_location_idx` - Fast filtering by screen/location
- `errors_log_severity_idx` - Fast filtering by severity
- `errors_log_error_code_idx` - Fast filtering by error code
- `errors_log_resolved_idx` - Fast filtering of unresolved errors

## Security (RLS Policies)

Ensure appropriate Row-Level Security (RLS) policies are set:

```sql
-- Allow authenticated users to read their own errors
CREATE POLICY "Users can view their own errors"
ON public.errors_log
FOR SELECT
USING (auth.uid() = user_id);

-- Allow admins to view all errors
CREATE POLICY "Admins can view all errors"
ON public.errors_log
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND security <= 2
  )
);

-- Only service role can insert (via ErrorLogService)
-- This is typically handled by the application, not direct user inserts
```

