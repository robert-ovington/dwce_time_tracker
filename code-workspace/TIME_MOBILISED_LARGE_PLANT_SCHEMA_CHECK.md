# Time Mobilised Large Plant Table Schema Check

## Current Status: ⚠️ **NOT YET IMPLEMENTED**

The `time_mobilised_large_plant` table schema exists, but the code does **not yet** save or load mobilised fleet from this table. Mobilised fleet is currently only stored in local state and in offline queue data.

## Schema Verification

### Table Schema
```sql
create table public.time_mobilised_large_plant (
  id uuid not null default gen_random_uuid (),
  time_period_id uuid null,
  large_plant_id uuid null,
  constraint time_mobilised_large_plant_pkey primary key (id)
)
```

### Current Code Structure

The code uses a local `_mobilisedFleet` list:
```dart
List<String> _mobilisedFleet = [];
// Currently stores plant_no (text) values, but should store large_plant_id (uuid)
```

### Field Mapping Required

| Code Field | Schema Field | Type | Status |
|-----------|-------------|------|--------|
| `_mobilisedFleet[index]` (plant_no) | `large_plant_id` | uuid | ⚠️ Needs conversion |
| N/A | `time_period_id` | uuid | ⚠️ Needs to be set after time_period creation |
| N/A | `id` | uuid | ✅ Auto-generated |

## Issues Found

### 1. ❌ No UI for Mobilised Fleet
**Status:** `_mobilisedFleet` is declared but has no UI components
**Location:** Only "Used Fleet" section exists in `_buildFleetSection()`
**Issue:** Users cannot input mobilised fleet data

### 2. ❌ Incorrect Table Name in Comment
**Location:** Line 1503 in `time_tracking_screen.dart`
```dart
// Note: breaks and fleet are stored in separate tables (time_breaks, time_period_fleet)
```
**Issue:** Comment says `time_period_fleet` but actual table is `time_mobilised_large_plant`
**Fix:** Update comment to use correct table name

### 3. ⚠️ Save Functionality Not Implemented
**Location:** Line 1514-1516
```dart
// TODO: Save breaks and fleet to separate tables using timePeriodId
// await _saveBreaks(timePeriodId);
// await _saveFleet(timePeriodId);
```
**Status:** Function `_saveFleet()` or `_saveMobilisedFleet()` does not exist

### 4. ⚠️ Load Functionality Not Implemented
**Status:** No code exists to load mobilised fleet from `time_mobilised_large_plant` table

### 5. ⚠️ Data Type Conversion Needed
**Current:** `_mobilisedFleet` stores `plant_no` values (strings like "P001")
**Required:** Schema expects `large_plant_id` (uuid)

**Conversion needed:**
- Look up `large_plant` by `plant_no` to get `id` (uuid)
- Store `id` in `large_plant_id` field

### 6. ⚠️ "Used Fleet" Also Needs Implementation
**Status:** "Used Fleet" (`_usedFleet`) also stores `plant_no` values but is not saved to any table
**Question:** Is there a separate table for "used fleet" (e.g., `time_used_large_plant`), or should both use the same table with a type field?

## Implementation Requirements

### 1. Add UI for Mobilised Fleet
```dart
// In _buildFleetSection(), add after "Used Fleet" section:
const SizedBox(height: 16),
const Text('Mobilised Fleet:', style: TextStyle(fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
...List.generate(4, (index) {  // Typically 1-4 mobilised items
  return Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: DropdownButtonFormField<String>(
      value: index < _mobilisedFleet.length && _mobilisedFleet[index].isNotEmpty
          ? _mobilisedFleet[index]
          : null,
      decoration: InputDecoration(
        labelText: 'Mobilised Fleet ${index + 1}',
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      items: _allPlant.map((plant) {
        final plantNo = plant['plant_no']?.toString() ?? '';
        final desc = plant['short_description'] ?? plantNo;
        return DropdownMenuItem(
          value: plantNo,
          child: Text('$plantNo - $desc'),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          while (_mobilisedFleet.length <= index) {
            _mobilisedFleet.add('');
          }
          _mobilisedFleet[index] = value ?? '';
        });
      },
    ),
  );
}),
```

### 2. Save Mobilised Fleet Function
```dart
Future<void> _saveMobilisedFleet(String timePeriodId) async {
  for (final plantNo in _mobilisedFleet) {
    if (plantNo.isNotEmpty) {
      // Look up plant by plant_no to get id (uuid)
      try {
        final plant = _allPlant.firstWhere(
          (p) => p['plant_no']?.toString() == plantNo,
        );
        final largePlantId = plant['id']?.toString();
        
        if (largePlantId != null) {
          await DatabaseService.create('time_mobilised_large_plant', {
            'time_period_id': timePeriodId,
            'large_plant_id': largePlantId,
          });
        }
      } catch (e) {
        print('Error saving mobilised fleet: $e');
      }
    }
  }
}
```

### 3. Load Mobilised Fleet Function
```dart
Future<void> _loadMobilisedFleet(String timePeriodId) async {
  final mobilisedFleet = await DatabaseService.read(
    'time_mobilised_large_plant',
    filterColumn: 'time_period_id',
    filterValue: timePeriodId,
  );
  
  setState(() {
    _mobilisedFleet = mobilisedFleet.map((m) {
      // Look up plant by large_plant_id to get plant_no
      final largePlantId = m['large_plant_id']?.toString();
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

## Code Locations to Update

1. **Line 1503:** Fix table name in comment (change `time_period_fleet` to `time_mobilised_large_plant`)
2. **Line 1015-1040:** Add UI for mobilised fleet section
3. **Line 1514-1516:** Implement `_saveMobilisedFleet()` function call
4. **After line 1512:** Call `_saveMobilisedFleet(timePeriodId)` after creating time_period
5. **Offline sync:** Update offline sync to save mobilised fleet when processing queued entries
6. **Load last job:** Add mobilised fleet loading when finding last job (if needed)

## Questions to Resolve

1. **Is there a separate table for "Used Fleet"?**
   - Current code has `_usedFleet` but no table reference
   - Should "Used Fleet" also be saved to a table like `time_used_large_plant`?
   - Or should both use the same table with a type/status field?

2. **What is the difference between "Used Fleet" and "Mobilised Fleet"?**
   - Used Fleet: Equipment used during the work period?
   - Mobilised Fleet: Equipment mobilized/transported to the site?

## Summary

✅ **Schema is correct** - The table structure matches what's needed for mobilised fleet
⚠️ **Implementation missing** - Code needs to be added to:
  - Add UI for mobilised fleet input
  - Save/load mobilised fleet from database
  - Convert plant_no to large_plant_id (uuid)
❌ **Comment incorrect** - Table name in comment is wrong
⚠️ **Used Fleet unclear** - Need to determine if "Used Fleet" also needs a database table

**Action Required:** 
1. Clarify if "Used Fleet" needs a separate table
2. Implement mobilised fleet UI and save/load functionality
3. Fix the comment

