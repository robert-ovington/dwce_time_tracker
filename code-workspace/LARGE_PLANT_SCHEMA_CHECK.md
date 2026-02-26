# large_plant Schema Alignment Check

## Schema Fields

### Primary Key
- `id` (uuid) - Primary key ✅

### Text Fields
- `plant_no` (text) - Unique index ✅
- `plant_description` (text) ✅
- `short_description` (text) ✅
- `charge_type` (text) - Check constraint: 'Hour', 'Day', 'No.' ✅
- `clock_unit` (text) - Check constraint: 'Hours', 'Kilometres', 'Miles' ✅

### Boolean Fields
- `has_clock` (boolean) ✅
- `ticket_1_required` (text) ✅
- `ticket_2_required` (text) ✅
- `category_1` through `category_6` (boolean) ✅
- `is_active` (boolean, default true) ✅

## Code References Check

### ✅ time_tracking_screen.dart

**Loading Plant:**
```dart
final plant = await DatabaseService.read('large_plant');
```
- ✅ Table name correct: `large_plant`
- ⚠️ **Issue:** Not filtering by `is_active = true` (should only show active plants)

**Using Plant Data:**
- ✅ `plant['plant_no']` - Correct field name
- ✅ `plant['short_description']` - Correct field name (with fallback to plant_no)
- ✅ `plant['id']` - Correct for `mechanic_large_plant_id` lookup

**Plant Selection Dropdown:**
```dart
_allPlant.map((plant) {
  final plantNo = plant['plant_no']?.toString() ?? '';
  final desc = plant['short_description'] ?? plantNo;
  return DropdownMenuItem(
    value: plantNo,
    child: Text('$plantNo - $desc'),
  );
})
```
- ✅ Using `plant_no` as value (correct for lookup)
- ✅ Using `short_description` for display (correct)

**Finding Plant by plant_no:**
```dart
final plant = _allPlant.firstWhere(
  (p) => p['plant_no']?.toString() == _selectedProject,
);
mechanicLargePlantId = plant['id']?.toString();
```
- ✅ Correct lookup by `plant_no`
- ✅ Correct extraction of `id` for `mechanic_large_plant_id`

### ✅ user_edit_screen.dart

**Loading Stock Locations:**
```dart
.from('large_plant')
.select('plant_description')
.order('plant_description');
```
- ✅ Table name correct: `large_plant`
- ✅ Field name correct: `plant_description`
- ⚠️ **Issue:** Not filtering by `is_active = true` (should only show active plants)

## Recommendations

### 1. Filter by is_active

Both plant loading functions should filter to only show active plants:

**time_tracking_screen.dart:**
```dart
Future<void> _loadPlant() async {
  try {
    final plant = await DatabaseService.read(
      'large_plant',
      filterColumn: 'is_active',
      filterValue: true,
    );
    setState(() {
      _allPlant = plant;
    });
  } catch (e) {
    print('❌ Error loading plant: $e');
  }
}
```

**user_edit_screen.dart:**
```dart
final response = await SupabaseService.client
    .from('large_plant')
    .select('plant_description')
    .eq('is_active', true)  // Add this filter
    .order('plant_description');
```

### 2. Fields Not Currently Used

These fields exist in the schema but aren't used in the current code:
- `charge_type` - Could be useful for display
- `clock_unit` - Could be useful for display
- `has_clock` - Could be useful for validation
- `ticket_1_required`, `ticket_2_required` - Could be useful for validation
- `category_1` through `category_6` - Reserved for future use

## Summary

✅ **All field references are correct:**
- `id` ✅
- `plant_no` ✅
- `plant_description` ✅
- `short_description` ✅

⚠️ **Recommendation:**
- Add `is_active = true` filter when loading plants to only show active entries

