# Projects Table - Schema Check Required

## Fields Used in Time Tracking Code

The Time Tracking page accesses the following fields from the `projects` table:

### ✅ Required Fields

1. **`id`** (uuid)
   - Used for: `project_id` in `time_periods` table
   - Code: `project['id']?.toString()`
   - Location: `_handleSaveEntry()`, `_handleFindLastJob()`

2. **`project_name`** (text)
   - Used for: Display in dropdown, lookup by name
   - Code: `project['project_name']?.toString()`
   - Location: Dropdown items, project selection, "Find Nearest" result

3. **`latitude`** (numeric/double precision)
   - Used for: "Find Nearest Job" feature - distance calculation
   - Code: `project['latitude']` (cast to double)
   - Location: `_handleFindNearestProject()`

4. **`longitude`** (numeric/double precision)
   - Used for: "Find Nearest Job" feature - distance calculation
   - Code: `project['longitude']` (cast to double)
   - Location: `_handleFindNearestProject()`

5. **`is_active`** (boolean)
   - Used for: Filtering to show only active projects
   - Code: `filterColumn: 'is_active', filterValue: true`
   - Location: `_loadProjects()`

## Code Usage Examples

### Loading Projects
```dart
final projects = await DatabaseService.read(
  'projects',
  filterColumn: 'is_active',
  filterValue: true,
);
```

### Finding Nearest Project
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
```

### Looking Up Project by Name
```dart
final project = _allProjects.firstWhere(
  (p) => p['project_name']?.toString() == _selectedProject,
);
projectId = project['id']?.toString();
```

### Looking Up Project by ID
```dart
final project = _allProjects.firstWhere(
  (p) => p['id']?.toString() == lastProjectId,
);
final projectName = project['project_name']?.toString() ?? '';
```

## Expected Schema

Please provide the `projects` table schema to verify:
- Field names match exactly
- Data types are correct
- Required fields exist
- Indexes are appropriate (especially on `project_name` and `is_active`)

## Potential Issues

1. **Missing latitude/longitude:** If these fields don't exist, "Find Nearest Job" will fail
2. **Missing is_active:** If this field doesn't exist, filtering will fail
3. **Wrong data types:** If `latitude`/`longitude` are not numeric, distance calculation will fail
4. **Missing id:** If `id` is not uuid, foreign key relationship will fail

