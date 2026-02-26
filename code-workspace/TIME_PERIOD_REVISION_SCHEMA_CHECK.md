# Time Period Revision Table Schema Check

## Current Status: ⚠️ **NOT YET IMPLEMENTED**

The `time_period_revision` table schema exists, but the code does **not yet** create or use revision records. Revision tracking functionality is not implemented.

## Schema Verification

### Table Schema
```sql
create table public.time_period_revision (
  id uuid not null default gen_random_uuid (),
  revision_number integer null,
  changed_at timestamp with time zone null,
  user_name text null,
  field_name text null,
  old_value text null,
  new_value text null,
  change_reason text null,
  original_submission boolean null,
  constraint time_period_revision_pkey primary key (id)
)
```

### Current Code Structure

The code only sets `revision_number: 0` when creating new time_period entries:
```dart
'revision_number': 0,  // Line 1500 in time_tracking_screen.dart
```

**No code exists to:**
- Create revision records when time_periods are created
- Create revision records when time_periods are updated
- Track field changes (old_value, new_value)
- Store change metadata (user_name, changed_at, change_reason)

## Issues Found

### 1. ⚠️ No Revision Tracking on Create
**Status:** When creating a new time_period, no revision record is created
**Expected:** Should create a revision record with `original_submission: true`

### 2. ⚠️ No Revision Tracking on Update
**Status:** No update functionality exists for time_periods
**Expected:** When time_periods are updated, should:
  - Increment revision_number
  - Create revision records for each changed field
  - Track old_value and new_value

### 3. ⚠️ Missing Foreign Key Relationship
**Question:** The schema doesn't show a `time_period_id` foreign key
**Issue:** How are revisions linked to their time_period?
**Possible Solutions:**
  - Add `time_period_id` field to the table
  - Use `revision_number` + another identifier to link
  - Check if there's a relationship table or if it's tracked differently

### 4. ⚠️ No UI for Viewing Revisions
**Status:** No screen exists to view revision history
**Expected:** Should be able to view change history for a time_period

## Field Mapping Analysis

| Schema Field | Type | Current Usage | Status |
|-------------|------|---------------|--------|
| `id` | uuid | Auto-generated | ✅ N/A |
| `revision_number` | integer | Set to 0 in time_periods | ⚠️ Not used in revision table |
| `changed_at` | timestamp | Not set | ❌ Missing |
| `user_name` | text | Not set | ❌ Missing |
| `field_name` | text | Not set | ❌ Missing |
| `old_value` | text | Not set | ❌ Missing |
| `new_value` | text | Not set | ❌ Missing |
| `change_reason` | text | Not set | ❌ Missing |
| `original_submission` | boolean | Not set | ❌ Missing |

## Implementation Requirements

### 1. Create Revision on Initial Submission
```dart
Future<void> _createInitialRevision(String timePeriodId, Map<String, dynamic> timePeriodData) async {
  // Get current user info
  final currentUser = await AuthService.getCurrentUser();
  final userName = currentUser?['email'] ?? 'Unknown';
  
  // Create revision record for original submission
  await DatabaseService.create('time_period_revision', {
    'revision_number': 0,
    'changed_at': DateTime.now().toIso8601String(),
    'user_name': userName,
    'field_name': 'original_submission',
    'old_value': null,
    'new_value': 'created',
    'change_reason': 'Initial time entry submission',
    'original_submission': true,
  });
  
  // Note: Need to link to time_period_id - may need to add this field to schema
}
```

### 2. Create Revision on Update
```dart
Future<void> _createRevisionRecords(
  String timePeriodId,
  int currentRevisionNumber,
  Map<String, dynamic> oldData,
  Map<String, dynamic> newData,
  String? changeReason,
) async {
  final currentUser = await AuthService.getCurrentUser();
  final userName = currentUser?['email'] ?? 'Unknown';
  final newRevisionNumber = currentRevisionNumber + 1;
  final changedAt = DateTime.now().toIso8601String();
  
  // Track changes for each field
  final fieldsToTrack = [
    'work_date',
    'start_time',
    'finish_time',
    'project_id',
    'mechanic_large_plant_id',
    'status',
    'travel_to_site_min',
    'travel_from_site_min',
    'on_call',
    'misc_allowance_min',
    'concrete_ticket_no',
    'concrete_mix_type',
    'concrete_qty',
    'comments',
  ];
  
  for (final fieldName in fieldsToTrack) {
    final oldValue = oldData[fieldName]?.toString();
    final newValue = newData[fieldName]?.toString();
    
    // Only create revision if value changed
    if (oldValue != newValue) {
      await DatabaseService.create('time_period_revision', {
        'revision_number': newRevisionNumber,
        'changed_at': changedAt,
        'user_name': userName,
        'field_name': fieldName,
        'old_value': oldValue,
        'new_value': newValue,
        'change_reason': changeReason,
        'original_submission': false,
        // Note: Need time_period_id field
      });
    }
  }
  
  // Update time_period with new revision_number
  await DatabaseService.update(
    'time_periods',
    timePeriodId,
    {'revision_number': newRevisionNumber},
  );
}
```

### 3. Load Revision History
```dart
Future<List<Map<String, dynamic>>> _loadRevisionHistory(String timePeriodId) async {
  // Note: Need to filter by time_period_id or revision_number
  final revisions = await DatabaseService.read(
    'time_period_revision',
    filterColumn: 'revision_number', // Or time_period_id if added
    orderBy: 'changed_at',
    ascending: false,
  );
  
  return revisions;
}
```

## Questions to Resolve

### 1. **How are revisions linked to time_periods?**
   - The schema doesn't show a `time_period_id` foreign key
   - Is `revision_number` used to link? (But multiple time_periods could have same revision_number)
   - **Recommendation:** Add `time_period_id uuid` field to the table

### 2. **What triggers revision creation?**
   - Only on manual edits?
   - On status changes (draft → submitted → approved)?
   - On any field change?

### 3. **Should original submission create a revision?**
   - `original_submission: true` suggests yes
   - Should create revision record when time_period is first created

### 4. **What is the purpose of revision_number?**
   - Sequential number for each revision of a time_period?
   - Or global revision number across all time_periods?
   - **Likely:** Sequential per time_period (0 = original, 1 = first edit, etc.)

## Code Locations to Update

1. **Line 1511-1512:** After creating time_period, create initial revision record
2. **Future update functionality:** When time_periods are updated, create revision records
3. **New screen:** Create revision history viewer (if needed)

## Schema Recommendation

**Consider adding to `time_period_revision` table:**
```sql
ALTER TABLE public.time_period_revision 
ADD COLUMN time_period_id uuid REFERENCES public.time_periods(id);

CREATE INDEX idx_time_period_revision_time_period_id 
ON public.time_period_revision(time_period_id);
```

This would allow proper linking of revisions to their time_period records.

## Summary

✅ **Schema is correct** - The table structure is well-designed for revision tracking
⚠️ **Implementation missing** - No code exists to:
  - Create revision records on create/update
  - Track field changes
  - Store change metadata
❓ **Missing relationship** - No clear link between revisions and time_periods (may need `time_period_id` field)
⚠️ **No update functionality** - Time periods cannot be edited yet, so revision tracking isn't needed yet

**Action Required:** 
1. Clarify how revisions link to time_periods (add `time_period_id` field?)
2. Implement revision tracking when update functionality is added
3. Consider creating initial revision record on first submission

