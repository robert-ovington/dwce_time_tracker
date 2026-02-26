# Time Tracking Page - Tables Summary

## Tables Already Checked ✅

1. **`time_periods`** - Main time entry table ✅
2. **`users_data`** - User profile data (breaks, fleet, flags) ✅
3. **`large_plant`** - Plant/equipment data ✅
4. **`concrete_mix`** - Concrete mix types ✅

## Tables That Need Checking ❌

### 1. `projects` Table
**Used for:**
- Project selection dropdown
- "Find Nearest Job" feature (uses latitude/longitude)
- "Find Last Job" feature
- Saving `project_id` to `time_periods`

**Fields accessed in code:**
- `id` (uuid) - For `project_id` in time_periods
- `project_name` (text) - For display and lookup
- `latitude` (numeric/double) - For distance calculation
- `longitude` (numeric/double) - For distance calculation
- `is_active` (boolean) - For filtering active projects

**Code locations:**
- `_loadProjects()` - Loads projects filtered by `is_active = true`
- `_handleFindNearestProject()` - Uses `latitude` and `longitude` to find nearest
- `_handleFindLastJob()` - Looks up project by `id` from `project_id`
- `_handleSaveEntry()` - Looks up project by `project_name` to get `id`

## Tables Mentioned But Not Yet Implemented ⚠️

### 2. `time_period_breaks` Table
**Purpose:** Store breaks separately from time_periods
**Status:** Mentioned in code comments, not yet implemented
**Fields needed (estimated):**
- `id` (uuid)
- `time_period_id` (uuid) - FK to time_periods
- `break_number` (integer) - 1, 2, or 3
- `start_time` (timestamp)
- `finish_time` (timestamp)
- `reason` (text)

### 3. `time_period_fleet` Table
**Purpose:** Store fleet separately from time_periods
**Status:** Mentioned in code comments, not yet implemented
**Fields needed (estimated):**
- `id` (uuid)
- `time_period_id` (uuid) - FK to time_periods
- `fleet_type` (text) - 'used' or 'mobilised'
- `fleet_number` (integer) - 1-6 for used, 1-4 for mobilised
- `plant_id` (uuid) - FK to large_plant (if applicable)
- `fleet_text` (text) - The actual fleet identifier

## Other Tables Referenced (Indirectly)

### 4. `users_setup` Table
**Used for:** User permissions/security (via UserService)
**Status:** Already checked in user management screens ✅

### 5. `employers` Table
**Used for:** Employer selection (via users_data.employer_name)
**Status:** Already checked in employer management screen ✅

### 6. `google_api_calls` Table
**Used for:** Caching geocoding results (via Edge Function)
**Status:** Already checked in user creation/edit screens ✅

## Action Required

**Need to check `projects` table schema** to ensure:
- `id` field exists and is uuid
- `project_name` field exists and is text
- `latitude` and `longitude` fields exist and are numeric/double
- `is_active` field exists and is boolean

