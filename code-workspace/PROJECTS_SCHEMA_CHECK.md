# Projects Table Schema Check

## Schema Verification ✅

The `projects` table schema is **correctly referenced** in the Time Tracking code.

### Fields Used in Code

| Schema Field | Type | Code Usage | Status |
|-------------|------|------------|--------|
| `id` | uuid not null | `project['id']?.toString()` | ✅ Correct |
| `project_name` | text not null | `project['project_name']?.toString() ?? ''` | ✅ Correct |
| `latitude` | double precision null | `project['latitude']` (cast to double) | ✅ Correct |
| `longitude` | double precision null | `project['longitude']` (cast to double) | ✅ Correct |
| `is_active` | boolean null default true | `filterColumn: 'is_active', filterValue: true` | ✅ Correct |

### Fields NOT Used (Available but Unused)

These fields exist in the schema but are not currently used in the Time Tracking code:
- `project_number` (text null)
- `client_name` (text null)
- `county` (text null)
- `town` (text null)
- `townland` (text null)
- `address` (text null)
- `description_of_work` (text null)
- `completion_date` (date null)
- `created_at` (timestamp with time zone)
- `updated_at` (timestamp with time zone)

## Code Locations

### 1. Loading Projects (`_loadProjects()`)
```dart
final projects = await DatabaseService.read(
  'projects',
  filterColumn: 'is_active',
  filterValue: true,
);
```
✅ **Correct:** Filters by `is_active = true` to show only active projects

### 2. Project Dropdown (`_buildProjectSection()`)
```dart
_allProjects.map((project) {
  final name = project['project_name']?.toString() ?? '';
  return DropdownMenuItem(
    value: name,
    child: Text(name),
  );
}).toList()
```
✅ **Correct:** Uses `project_name` for display and as the selected value

### 3. Saving Time Entry (`_handleSaveEntry()`)
```dart
final project = _allProjects.firstWhere(
  (p) => p['project_name']?.toString() == _selectedProject,
);
projectId = project['id']?.toString();
```
✅ **Correct:** 
- Looks up project by `project_name` (text not null, so always exists)
- Extracts `id` (uuid) to save as `project_id` in `time_periods`

### 4. Find Nearest Project (`_handleFindNearestProject()`)
```dart
for (final project in _allProjects) {
  final lat = project['latitude'];
  final lng = project['longitude'];
  if (lat != null && lng != null) {
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      (lat as num).toDouble(),
      (lng as num).toDouble(),
    );
    // ... find nearest
  }
}
final projectName = nearestProject!['project_name']?.toString() ?? '';
```
✅ **Correct:**
- Uses `latitude` and `longitude` (double precision) for distance calculation
- Handles null values correctly (projects without location data are skipped)
- Uses `project_name` for display

### 5. Find Last Job (`_handleFindLastJob()`)
```dart
final lastProjectId = timePeriods.first['project_id']?.toString();
final project = _allProjects.firstWhere(
  (p) => p['id']?.toString() == lastProjectId,
  orElse: () => {},
);
final projectName = project['project_name']?.toString() ?? '';
```
✅ **Correct:**
- Looks up project by `id` (uuid) from `project_id` in `time_periods`
- Uses `project_name` for display
- Handles missing project gracefully with `orElse`

## Data Type Handling

### UUID Handling
- ✅ Code correctly converts UUID to string: `project['id']?.toString()`
- ✅ Code correctly compares UUIDs as strings: `p['id']?.toString() == lastProjectId`

### Double Precision Handling
- ✅ Code correctly handles nullable doubles: `project['latitude']` (can be null)
- ✅ Code correctly casts to double: `(lat as num).toDouble()`
- ✅ Code checks for null before using: `if (lat != null && lng != null)`

### Boolean Handling
- ✅ Code correctly filters by boolean: `filterValue: true`
- ✅ Schema default is `true`, so filtering works correctly

### Text Handling
- ✅ Code correctly handles `project_name` as text: `project['project_name']?.toString() ?? ''`
- ✅ Schema has `not null` constraint, but code safely handles with `?? ''` as fallback

## Indexes

The schema includes appropriate indexes:
- ✅ `idx_projects_project_name` - Used for lookup by name
- ✅ `idx_projects_is_active` - Used for filtering active projects
- ✅ `idx_projects_project_number` - Available but not currently used

## Summary

✅ **All field references are correct**
✅ **Data types match schema expectations**
✅ **Null handling is appropriate**
✅ **Indexes support the queries being made**

**No changes needed** - The code correctly references the `projects` table schema.

