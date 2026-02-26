# Time Used Large Plant Table Schema Check

## Current Status: ⚠️ **NOT YET IMPLEMENTED**

The `time_used_large_plant` table schema exists, but the code does **not yet** save or load used fleet from this table. Used fleet is currently only stored in local state, in offline queue data, and saved to `users_data` table for user preferences (not linked to time periods).

## Schema Verification

### Table Schema
```sql
create table public.time_used_large_plant (
  id uuid not null default gen_random_uuid (),
  time_period_id uuid null,
  large_plant_id uuid null,
  constraint time_used_large_plant_pkey primary key (id)
)
```

### Current Code Structure

The code uses a local `_usedFleet` list:
```dart
List<String> _usedFleet = [];
// Currently stores plant_no (text) values, but should store large_plant_id (uuid)
```

**Current behavior:**
- UI exists for "Used Fleet" (6 dropdowns)
- Data is stored in local state (`_usedFleet`)
- Data is saved to `users_data` table (fleet_1 through fleet_6) for user preferences
- Data is stored in offline queue when saving time entry
- **NOT saved to `time_used_large_plant` table when creating time_period**

### Field Mapping Required

| Code Field | Schema Field | Type | Status |
|-----------|-------------|------|--------|
| `_usedFleet[index]` (plant_no) | `large_plant_id` | uuid | ⚠️ Needs conversion |
| N/A | `time_period_id` | uuid | ⚠️ Needs to be set after time_period creation |
| N/A | `id` | uuid | ✅ Auto-generated |

## Issues Found

### 1. ⚠️ Save Functionality Not Implemented
**Location:** Line 1514-1516
```dart
// TODO: Save breaks and fleet to separate tables using timePeriodId
// await _saveBreaks(timePeriodId);
// await _saveFleet(timePeriodId);
```
**Status:** Function `_saveFleet()` or `_saveUsedFleet()` does not exist
**Issue:** Used fleet is not saved to `time_used_large_plant` table when creating time_period

### 2. ⚠️ Load Functionality Not Implemented
**Status:** No code exists to load used fleet from `time_used_large_plant` table
**Issue:** Cannot recall used fleet from previous time periods

### 3. ⚠️ Data Type Conversion Needed
**Current:** `_usedFleet` stores `plant_no` values (strings like "P001")
**Required:** Schema expects `large_plant_id` (uuid)

**Conversion needed:**
- Look up `large_plant` by `plant_no` to get `id` (uuid)
- Store `id` in `large_plant_id` field

### 4. ⚠️ Confusion with User Preferences
**Current:** Used fleet is saved to `users_data` table (fleet_1 through fleet_6)
**Purpose:** This is for user preferences/defaults, not for time period records
**Issue:** Need to distinguish between:
  - User's default/saved fleet (in `users_data`) - for convenience
  - Actual fleet used in a time period (in `time_used_large_plant`) - for records

### 5. ⚠️ TODO Comment Ambiguity
**Location:** Line 1516
```dart
// await _saveFleet(timePeriodId);
```
**Issue:** Comment doesn't specify which table(s) - could be:
  - `time_used_large_plant` (for used fleet)
  - `time_mobilised_large_plant` (for mobilised fleet)
  - Both

## Implementation Requirements

### 1. Save Used Fleet Function
```dart
Future<void> _saveUsedFleet(String timePeriodId) async {
  for (final plantNo in _usedFleet) {
    if (plantNo.isNotEmpty) {
      // Look up plant by plant_no to get id (uuid)
      try {
        final plant = _allPlant.firstWhere(
          (p) => p['plant_no']?.toString() == plantNo,
        );
        final largePlantId = plant['id']?.toString();
        
        if (largePlantId != null) {
          await DatabaseService.create('time_used_large_plant', {
            'time_period_id': timePeriodId,
            'large_plant_id': largePlantId,
          });
        }
      } catch (e) {
        print('Error saving used fleet: $e');
      }
    }
  }
}
```

### 2. Load Used Fleet Function
```dart
Future<void> _loadUsedFleet(String timePeriodId) async {
  final usedFleet = await DatabaseService.read(
    'time_used_large_plant',
    filterColumn: 'time_period_id',
    filterValue: timePeriodId,
  );
  
  setState(() {
    _usedFleet = usedFleet.map((u) {
      // Look up plant by large_plant_id to get plant_no
      final largePlantId = u['large_plant_id']?.toString();
      if (largePlantId != null) {
        try {
          final plant = _allPlant.firstWhere(
            (p) => p['id']?.toString() == largePlantId,
          );
          return plant['plant_no']?.toString() ?? '';
        } catch (e) {
          return '';
        }
      }
      return '';
    }).where((p) => p.isNotEmpty).toList();
  });
}
```

### 3. Combined Save Function (for both used and mobilised)
```dart
Future<void> _saveFleet(String timePeriodId) async {
  // Save used fleet
  await _saveUsedFleet(timePeriodId);
  
  // Save mobilised fleet
  await _saveMobilisedFleet(timePeriodId);
}
```

## Code Locations to Update

1. **Line 1514-1516:** Implement `_saveFleet()` or separate `_saveUsedFleet()` function
2. **After line 1512:** Call `_saveUsedFleet(timePeriodId)` after creating time_period
3. **Offline sync:** Update offline sync to save used fleet when processing queued entries
4. **Load last job:** Add used fleet loading when finding last job (if needed)

## Relationship to User Preferences

**Current Implementation:**
- `_handleSaveFleet()` - Saves to `users_data.fleet_1` through `fleet_6` (user preferences)
- `_handleRecallFleet()` - Loads from `users_data.fleet_1` through `fleet_6` (user preferences)

**New Implementation Needed:**
- `_saveUsedFleet(timePeriodId)` - Saves to `time_used_large_plant` (time period records)
- `_loadUsedFleet(timePeriodId)` - Loads from `time_used_large_plant` (time period records)

**Both should coexist:**
- User preferences: For convenience (quick recall of commonly used fleet)
- Time period records: For accurate historical tracking

## Summary

✅ **Schema is correct** - The table structure matches what's needed for used fleet
⚠️ **Implementation missing** - Code needs to be added to:
  - Save used fleet to `time_used_large_plant` table when creating time_period
  - Load used fleet from `time_used_large_plant` table
  - Convert plant_no to large_plant_id (uuid)
⚠️ **User preferences vs records** - Need to distinguish between:
  - User's saved fleet (in `users_data`) - convenience feature
  - Actual fleet used (in `time_used_large_plant`) - historical records

**Action Required:** 
1. Implement `_saveUsedFleet()` function
2. Implement `_loadUsedFleet()` function
3. Call `_saveUsedFleet()` after creating time_period
4. Update offline sync to save used fleet
5. Consider renaming `_saveFleet()` to `_saveFleetPreferences()` to avoid confusion

