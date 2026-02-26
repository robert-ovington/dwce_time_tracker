# Time Breaks Table Schema Check

## Current Status: ⚠️ **NOT YET IMPLEMENTED**

The `time_breaks` table schema exists, but the code does **not yet** save or load breaks from this table. Breaks are currently only stored in local state and in offline queue data.

## Schema Verification

### Table Schema
```sql
create table public.time_breaks (
  id uuid not null default gen_random_uuid (),
  time_period_id uuid null,
  break_start timestamp with time zone null,
  break_end timestamp with time zone null,
  reason text null,
  constraint time_breaks_pkey primary key (id)
)
```

### Current Code Structure

The code uses a local `_breaks` list with this structure:
```dart
List<Map<String, dynamic>> _breaks = [];
// Each break: {'start': '', 'finish': '', 'reason': ''}
```

### Field Mapping Required

| Code Field | Schema Field | Type | Status |
|-----------|-------------|------|--------|
| `start` | `break_start` | timestamp with time zone | ⚠️ Needs conversion |
| `finish` | `break_end` | timestamp with time zone | ⚠️ Needs conversion |
| `reason` | `reason` | text | ✅ Matches |
| N/A | `time_period_id` | uuid | ⚠️ Needs to be set after time_period creation |
| N/A | `id` | uuid | ✅ Auto-generated |

## Issues Found

### 1. ❌ Incorrect Table Name in Comment
**Location:** Line 1503 in `time_tracking_screen.dart`
```dart
// Note: breaks and fleet are stored in separate tables (time_period_breaks, time_period_fleet)
```
**Issue:** Comment says `time_period_breaks` but actual table is `time_breaks`
**Fix:** Update comment to use correct table name

### 2. ⚠️ Save Functionality Not Implemented
**Location:** Line 1514-1515
```dart
// TODO: Save breaks and fleet to separate tables using timePeriodId
// await _saveBreaks(timePeriodId);
```
**Status:** Function `_saveBreaks()` does not exist

### 3. ⚠️ Load Functionality Not Implemented
**Status:** No code exists to load breaks from `time_breaks` table when loading a time period

### 4. ⚠️ Data Type Conversion Needed
**Current:** Breaks store `start` and `finish` as strings (time strings like "12:00")
**Required:** Schema expects `break_start` and `break_end` as `timestamp with time zone`

**Conversion needed:**
- Parse time strings (e.g., "12:00") 
- Combine with work date to create full timestamp
- Convert to ISO 8601 format for database

## Implementation Requirements

### 1. Save Breaks Function
```dart
Future<void> _saveBreaks(String timePeriodId) async {
  for (final breakData in _breaks) {
    if (breakData['start']?.toString().isNotEmpty == true &&
        breakData['finish']?.toString().isNotEmpty == true) {
      
      // Parse start time (e.g., "12:00") and combine with work date
      final startTime = _parseBreakTime(_date, breakData['start']);
      final endTime = _parseBreakTime(_date, breakData['finish']);
      
      await DatabaseService.create('time_breaks', {
        'time_period_id': timePeriodId,
        'break_start': startTime?.toIso8601String(),
        'break_end': endTime?.toIso8601String(),
        'reason': breakData['reason']?.toString() ?? '',
      });
    }
  }
}
```

### 2. Load Breaks Function
```dart
Future<void> _loadBreaks(String timePeriodId) async {
  final breaks = await DatabaseService.read(
    'time_breaks',
    filterColumn: 'time_period_id',
    filterValue: timePeriodId,
    orderBy: 'break_start',
    ascending: true,
  );
  
  setState(() {
    _breaks = breaks.map((b) => {
      'start': _formatBreakTime(b['break_start']),
      'finish': _formatBreakTime(b['break_end']),
      'reason': b['reason']?.toString() ?? '',
    }).toList();
  });
}
```

### 3. Time Parsing Helper
```dart
DateTime? _parseBreakTime(String workDate, String timeString) {
  if (timeString.isEmpty) return null;
  
  try {
    // Parse time string (e.g., "12:00" or "12:00:00")
    final timeParts = timeString.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
    
    // Combine with work date
    final dateTime = DateTime.parse(workDate);
    return DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
      hour,
      minute,
    );
  } catch (e) {
    return null;
  }
}

String _formatBreakTime(dynamic timestamp) {
  if (timestamp == null) return '';
  
  try {
    final dt = timestamp is String 
        ? DateTime.parse(timestamp)
        : timestamp as DateTime;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (e) {
    return '';
  }
}
```

## Code Locations to Update

1. **Line 1503:** Fix table name in comment
2. **Line 1514-1516:** Implement `_saveBreaks()` function call
3. **After line 1512:** Call `_saveBreaks(timePeriodId)` after creating time_period
4. **Offline sync:** Update offline sync to save breaks when processing queued entries
5. **Load last job:** Add break loading when finding last job (if needed)

## Summary

✅ **Schema is correct** - The table structure matches what's needed
⚠️ **Implementation missing** - Code needs to be added to save/load breaks
❌ **Comment incorrect** - Table name in comment is wrong
⚠️ **Data conversion needed** - Time strings need to be converted to timestamps

**Action Required:** Implement the save/load functionality and fix the comment.

