# Schema Alignment Summary

## ✅ Code Updated to Match Schema

The time tracking code has been updated to match your actual `time_periods` table schema.

## Key Changes Made

### 1. Field Name Mappings
- ✅ `user_id` (uuid) - Retrieved from email or stored user_id
- ✅ `project_id` (uuid) - Retrieved from project_name
- ✅ `mechanic_large_plant_id` (uuid) - For plant mode
- ✅ `work_date` (date) - Format: 'yyyy-MM-dd'
- ✅ `start_time` / `finish_time` (timestamp) - Combined from date + time
- ✅ `travel_to_site_min` / `travel_from_site_min` (integer) - Converted to minutes
- ✅ `misc_allowance_min` (integer) - Converted to minutes
- ✅ `concrete_ticket_no` (integer) - Parsed from string
- ✅ `concrete_mix_type` (text) - Direct mapping
- ✅ `concrete_qty` (numeric) - Parsed from string
- ✅ `submission_lat` / `submission_lng` (double precision)
- ✅ `submission_gps_accuracy` (integer)
- ✅ `distance_from_home` (numeric)
- ✅ `travel_time_text` (text)
- ✅ `offline_created` / `synced` (boolean)

### 2. Removed Fields (Not in Schema)
- ❌ Breaks (break_1_start, etc.) - Stored in separate table
- ❌ Fleet (fleet_1, etc.) - Stored in separate table
- ❌ Mobilised Fleet - Stored in separate table

### 3. Data Type Conversions
- **Date/Time**: Combined date string + time string → timestamp
- **Allowances**: Text input → integer (minutes)
- **GPS**: Captured as double precision with accuracy

## ⚠️ Still Need to Implement

### 1. Breaks Table
Breaks are collected in the UI but need to be saved to a separate table:
```sql
CREATE TABLE time_period_breaks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  time_period_id UUID REFERENCES time_periods(id),
  break_number INTEGER,
  start_time TIMESTAMP WITH TIME ZONE,
  finish_time TIMESTAMP WITH TIME ZONE,
  reason TEXT
);
```

### 2. Fleet Table
Fleet is collected in the UI but needs to be saved to a separate table:
```sql
CREATE TABLE time_period_fleet (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  time_period_id UUID REFERENCES time_periods(id),
  fleet_type TEXT, -- 'used' or 'mobilised'
  fleet_number INTEGER,
  plant_id UUID REFERENCES large_plant(id)
);
```

### 3. User ID Lookup
For entering time for other users, need to convert email to user_id:
- **Option 1**: Create Edge Function `get_user_id_from_email` (see `EDGE_FUNCTION_GET_USER_ID.md`)
- **Option 2**: Store email in `users_data` table and query by email

### 4. Project/Plant ID Lookup
- Projects table needs `id` (uuid) field
- Large_plant table needs `id` (uuid) field
- Code looks up by name/no and gets the `id`

## Current Status

✅ **Working:**
- Time period creation with correct field mappings
- Offline storage and sync
- GPS location capture
- Date/time handling
- Allowance conversion (basic - assumes minutes input)

⚠️ **Needs Work:**
- Breaks saving (separate table)
- Fleet saving (separate table)
- User ID lookup for other users (Edge Function)
- Travel time/distance calculation (backend)

## Testing Checklist

- [ ] Create `time_periods` table (already exists)
- [ ] Verify `projects` table has `id` field
- [ ] Verify `large_plant` table has `id` field
- [ ] Create breaks table (if needed)
- [ ] Create fleet table (if needed)
- [ ] Create Edge Function for user_id lookup (if entering for others)
- [ ] Test time period creation
- [ ] Test offline/online sync
- [ ] Test GPS capture
- [ ] Test date/time conversion

## Notes

- The code stores breaks and fleet data in offline queue for later processing
- When syncing, breaks and fleet should be saved to their respective tables
- The `offline_id` field in schema is not currently set (could use UUID for tracking)

