# Time Periods Schema Notes

## Schema Alignment

The code has been updated to match the actual `time_periods` table schema. Here are the key changes:

## Field Mappings

### ✅ Correctly Mapped Fields

| Code Field | Database Field | Type | Notes |
|------------|---------------|------|-------|
| `user_id` | `user_id` | uuid | Retrieved from user email |
| `project_id` | `project_id` | uuid | Retrieved from project_name |
| `mechanic_large_plant_id` | `mechanic_large_plant_id` | uuid | For plant mode, retrieved from plant_no |
| `work_date` | `work_date` | date | Format: 'yyyy-MM-dd' |
| `start_time` | `start_time` | timestamp | Combined from date + time string |
| `finish_time` | `finish_time` | timestamp | Combined from date + time string |
| `status` | `status` | approval_status | Set to 'draft' |
| `travel_to_site_min` | `travel_to_site_min` | integer | Converted from text to minutes |
| `travel_from_site_min` | `travel_from_site_min` | integer | Converted from text to minutes |
| `on_call` | `on_call` | boolean | Direct mapping |
| `misc_allowance_min` | `misc_allowance_min` | integer | Converted from text to minutes |
| `concrete_ticket_no` | `concrete_ticket_no` | integer | Parsed from string |
| `concrete_mix_type` | `concrete_mix_type` | text | Direct mapping |
| `concrete_qty` | `concrete_qty` | numeric | Parsed from string |
| `comments` | `comments` | text | Direct mapping |
| `submission_lat` | `submission_lat` | double precision | GPS latitude |
| `submission_lng` | `submission_lng` | double precision | GPS longitude |
| `submission_gps_accuracy` | `submission_gps_accuracy` | integer | GPS accuracy in meters |
| `distance_from_home` | `distance_from_home` | numeric | Parsed from calculated distance |
| `travel_time_text` | `travel_time_text` | text | Travel time as text |
| `revision_number` | `revision_number` | integer | Set to 0 for new entries |
| `offline_created` | `offline_created` | boolean | true if saved offline |
| `synced` | `synced` | boolean | true if synced to Supabase |

## ⚠️ Fields NOT in time_periods Table

The following fields are collected in the UI but are **NOT** stored in `time_periods`:

### Breaks
- `break_1_start`, `break_1_finish`, `break_1_reason`
- `break_2_start`, `break_2_finish`, `break_2_reason`
- `break_3_start`, `break_3_finish`, `break_3_reason`

**Action Required:** Breaks are likely stored in a separate table (e.g., `time_period_breaks`). You'll need to:
1. Create the breaks table if it doesn't exist
2. Save breaks separately after creating the time_period
3. Link breaks to time_period via `time_period_id`

### Fleet
- `fleet_1` through `fleet_6`
- `mobilised_fleet_1` through `mobilised_fleet_4`

**Action Required:** Fleet is likely stored in a separate table (e.g., `time_period_fleet`). You'll need to:
1. Create the fleet table if it doesn't exist
2. Save fleet separately after creating the time_period
3. Link fleet to time_period via `time_period_id`

## Data Type Conversions

### Date/Time Handling
- **Input:** Date string (`yyyy-MM-dd`) + Time string (`HH:mm`)
- **Output:** Combined into timestamp for `start_time` and `finish_time`
- **Example:** `2024-01-15` + `09:00` → `2024-01-15T09:00:00Z`

### Allowance Conversion
- **Input:** Text field (user enters minutes or time)
- **Output:** Integer (minutes)
- **Current Implementation:** Tries to parse as integer directly
- **Note:** If users enter time format (e.g., "1:30"), you may need to convert to minutes

## Required Lookups

### User ID Lookup
The code needs to convert `user_email` to `user_id` (uuid). This is done by:
1. Checking `_allUsers` list (from `users_data` table)
2. Checking `_currentUser` (from auth)
3. Querying `users_data` table if not found

**Ensure:** `users_data` table has a `user_id` field that matches `auth.users.id`

### Project ID Lookup
The code needs to convert `project_name` to `project_id` (uuid). This is done by:
1. Finding project in `_allProjects` list where `project_name` matches
2. Extracting `id` field from the project

**Ensure:** `projects` table has:
- `id` (uuid, primary key)
- `project_name` (text)
- `latitude`, `longitude` (for Find Nearest feature)

### Plant ID Lookup
The code needs to convert `plant_no` to `mechanic_large_plant_id` (uuid). This is done by:
1. Finding plant in `_allPlant` list where `plant_no` matches
2. Extracting `id` field from the plant

**Ensure:** `large_plant` table has:
- `id` (uuid, primary key)
- `plant_no` (text/number)
- `short_description` (text)

## Status Field

The `status` field uses an enum type `approval_status`. The code sets it to `'draft'`.

**Ensure:** The enum exists in PostgreSQL:
```sql
CREATE TYPE approval_status AS ENUM ('draft', 'submitted', 'approved', 'rejected');
```

## Offline ID

The schema includes `offline_id` (text) field. This should be set when creating entries offline to track them before sync.

**Current Implementation:** Not set. Consider adding a UUID for offline entries.

## Next Steps

1. **Create Breaks Table** (if not exists):
   ```sql
   CREATE TABLE time_period_breaks (
     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     time_period_id UUID REFERENCES time_periods(id),
     break_number INTEGER,
     start_time TIMESTAMP WITH TIME ZONE,
     finish_time TIMESTAMP WITH TIME ZONE,
     reason TEXT,
     created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
   );
   ```

2. **Create Fleet Table** (if not exists):
   ```sql
   CREATE TABLE time_period_fleet (
     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     time_period_id UUID REFERENCES time_periods(id),
     fleet_type TEXT, -- 'used' or 'mobilised'
     fleet_number INTEGER, -- 1-6 for used, 1-4 for mobilised
     plant_id UUID REFERENCES large_plant(id),
     created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
   );
   ```

3. **Update Code** to save breaks and fleet to separate tables after creating time_period

4. **Test** the field mappings with actual data

