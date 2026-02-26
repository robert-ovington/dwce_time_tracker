# Approval Workflow Implementation Guide

## Overview

This guide explains how to implement the 5-stage approval workflow for time periods, including when revisions are triggered and how to generate reports.

---

## Workflow Stages

### Stage 1: User Submits/Edits (No Revision)
- **Status**: `draft` → `submitted`
- **Action**: User can edit freely without triggering revisions
- **Revision Tracking**: Logged as `user_edit` with `is_revision = false`

### Stage 2: Supervisor Approves (No Revision)
- **Status**: `submitted` → `supervisor_approved`
- **Action**: Supervisor approves without making changes
- **Revision Tracking**: Logged as `supervisor_approval` with `is_revision = false`

### Stage 3: Supervisor Edits Before Approval (Triggers Revision)
- **Status**: `submitted` → `supervisor_approved`
- **Action**: Supervisor makes changes before approving
- **Revision Tracking**: 
  - Increment `revision_number`
  - Set `supervisor_edited_before_approval = true`
  - Log each change as `supervisor_edit` with `is_revision = true`

### Stage 4: Admin Approves (No Revision)
- **Status**: `supervisor_approved` → `admin_approved`
- **Action**: Admin approves supervisor-approved period
- **Revision Tracking**: Logged as `admin_approval` with `is_revision = false`

### Stage 5: Admin Edits Before Approval (Triggers Revision)
- **Status**: `supervisor_approved` → `admin_approved`
- **Action**: Admin makes changes before approving
- **Revision Tracking**:
  - Increment `revision_number`
  - Set `admin_edited_before_approval = true`
  - Log each change as `admin_edit` with `is_revision = true`

---

## Implementation Code Examples

### Stage 1: User Submits Time Period

```dart
Future<void> submitTimePeriod(String timePeriodId, String userId) async {
  final now = DateTime.now();
  
  // Update time period status
  await SupabaseService.client
    .from('time_periods')
    .update({
      'status': 'submitted',
      'submitted_at': now.toIso8601String(),
      'submitted_by': userId,
      'updated_at': now.toIso8601String(),
    })
    .eq('id', timePeriodId);
  
  // Log submission (not a revision)
  await SupabaseService.client
    .from('time_period_revisions')
    .insert({
      'time_period_id': timePeriodId,
      'revision_number': 0, // No revision for submission
      'changed_at': now.toIso8601String(),
      'changed_by': userId,
      'change_type': 'user_submission',
      'workflow_stage': 'submitted',
      'field_name': 'status',
      'old_value': 'draft',
      'new_value': 'submitted',
      'is_revision': false,
      'is_approval': false,
      'is_edit': false,
    });
}
```

### Stage 2: Supervisor Approves (No Edits)

```dart
Future<void> supervisorApprove(String timePeriodId, String supervisorId) async {
  final now = DateTime.now();
  
  // Update time period
  await SupabaseService.client
    .from('time_periods')
    .update({
      'status': 'supervisor_approved',
      'supervisor_id': supervisorId,
      'supervisor_approved_at': now.toIso8601String(),
      'approved_by': supervisorId,
      'approved_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    })
    .eq('id', timePeriodId);
  
  // Log approval (not a revision)
  await SupabaseService.client
    .from('time_period_revisions')
    .insert({
      'time_period_id': timePeriodId,
      'revision_number': 0, // No revision for approval
      'changed_at': now.toIso8601String(),
      'changed_by': supervisorId,
      'change_type': 'supervisor_approval',
      'workflow_stage': 'supervisor_review',
      'field_name': 'status',
      'old_value': 'submitted',
      'new_value': 'supervisor_approved',
      'is_revision': false,
      'is_approval': true,
      'is_edit': false,
    });
}
```

### Stage 3: Supervisor Edits Before Approval (Triggers Revision)

```dart
Future<void> supervisorEditAndApprove(
  String timePeriodId,
  String supervisorId,
  Map<String, dynamic> changes,
) async {
  final now = DateTime.now();
  
  // Get current revision number
  final period = await SupabaseService.client
    .from('time_periods')
    .select('revision_number')
    .eq('id', timePeriodId)
    .single();
  
  final newRevisionNumber = (period['revision_number'] as int) + 1;
  
  // Update time period with changes
  final updateData = {
    ...changes,
    'revision_number': newRevisionNumber,
    'last_revised_at': now.toIso8601String(),
    'last_revised_by': supervisorId,
    'supervisor_edited_before_approval': true,
    'status': 'supervisor_approved',
    'supervisor_id': supervisorId,
    'supervisor_approved_at': now.toIso8601String(),
    'approved_by': supervisorId,
    'approved_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  };
  
  await SupabaseService.client
    .from('time_periods')
    .update(updateData)
    .eq('id', timePeriodId);
  
  // Log each field change as a revision
  for (final entry in changes.entries) {
    if (entry.key == 'revision_number' || entry.key == 'updated_at') continue;
    
    // Get old value (you may need to fetch this first)
    final oldValue = await _getOldValue(timePeriodId, entry.key);
    
    await SupabaseService.client
      .from('time_period_revisions')
      .insert({
        'time_period_id': timePeriodId,
        'revision_number': newRevisionNumber,
        'changed_at': now.toIso8601String(),
        'changed_by': supervisorId,
        'change_type': 'supervisor_edit',
        'workflow_stage': 'supervisor_review',
        'field_name': entry.key,
        'old_value': oldValue?.toString(),
        'new_value': entry.value?.toString(),
        'is_revision': true, // ✅ This triggers a revision
        'is_approval': false,
        'is_edit': true,
      });
  }
}
```

### Stage 4: Admin Approves (No Edits)

```dart
Future<void> adminApprove(String timePeriodId, String adminId) async {
  final now = DateTime.now();
  
  await SupabaseService.client
    .from('time_periods')
    .update({
      'status': 'admin_approved',
      'admin_id': adminId,
      'admin_approved_at': now.toIso8601String(),
      'approved_by': adminId,
      'approved_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    })
    .eq('id', timePeriodId);
  
  // Log approval (not a revision)
  await SupabaseService.client
    .from('time_period_revisions')
    .insert({
      'time_period_id': timePeriodId,
      'revision_number': 0,
      'changed_at': now.toIso8601String(),
      'changed_by': adminId,
      'change_type': 'admin_approval',
      'workflow_stage': 'admin_review',
      'field_name': 'status',
      'old_value': 'supervisor_approved',
      'new_value': 'admin_approved',
      'is_revision': false,
      'is_approval': true,
      'is_edit': false,
    });
}
```

### Stage 5: Admin Edits Before Approval (Triggers Revision)

```dart
Future<void> adminEditAndApprove(
  String timePeriodId,
  String adminId,
  Map<String, dynamic> changes,
) async {
  final now = DateTime.now();
  
  // Get current revision number
  final period = await SupabaseService.client
    .from('time_periods')
    .select('revision_number')
    .eq('id', timePeriodId)
    .single();
  
  final newRevisionNumber = (period['revision_number'] as int) + 1;
  
  // Update time period
  final updateData = {
    ...changes,
    'revision_number': newRevisionNumber,
    'last_revised_at': now.toIso8601String(),
    'last_revised_by': adminId,
    'admin_edited_before_approval': true,
    'status': 'admin_approved',
    'admin_id': adminId,
    'admin_approved_at': now.toIso8601String(),
    'approved_by': adminId,
    'approved_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  };
  
  await SupabaseService.client
    .from('time_periods')
    .update(updateData)
    .eq('id', timePeriodId);
  
  // Log each field change as a revision
  for (final entry in changes.entries) {
    if (entry.key == 'revision_number' || entry.key == 'updated_at') continue;
    
    final oldValue = await _getOldValue(timePeriodId, entry.key);
    
    await SupabaseService.client
      .from('time_period_revisions')
      .insert({
        'time_period_id': timePeriodId,
        'revision_number': newRevisionNumber,
        'changed_at': now.toIso8601String(),
        'changed_by': adminId,
        'change_type': 'admin_edit',
        'workflow_stage': 'admin_review',
        'field_name': entry.key,
        'old_value': oldValue?.toString(),
        'new_value': entry.value?.toString(),
        'is_revision': true, // ✅ This triggers a revision
        'is_approval': false,
        'is_edit': true,
      });
  }
}
```

---

## Report Generation

### User Report: "Changes Made to My Submission"

```dart
Future<List<Map<String, dynamic>>> getUserChangesReport(String userId) async {
  final response = await SupabaseService.client
    .from('time_period_revisions')
    .select('''
      *,
      time_periods!inner(
        id,
        work_date,
        status,
        user_id
      )
    ''')
    .eq('time_periods.user_id', userId)
    .eq('is_revision', true) // Only show revision-triggering changes
    .order('time_periods.work_date', ascending: false)
    .order('changed_at', ascending: false);
  
  return List<Map<String, dynamic>>.from(response);
}
```

### Supervisor Report: "Pending Approvals"

```dart
Future<List<Map<String, dynamic>>> getPendingApprovalsReport() async {
  final response = await SupabaseService.client
    .from('time_periods')
    .select('''
      *,
      users_data!time_periods_user_id_fkey(display_name),
      time_period_revisions!inner(
        id,
        is_revision,
        changed_at
      )
    ''')
    .eq('status', 'submitted')
    .order('submitted_at', ascending: true);
  
  return List<Map<String, dynamic>>.from(response);
}
```

### Supervisor Report: "Changes I Made During Review"

```dart
Future<List<Map<String, dynamic>>> getSupervisorChangesReport(String supervisorId) async {
  final response = await SupabaseService.client
    .from('time_period_revisions')
    .select('''
      *,
      time_periods!inner(
        id,
        work_date,
        users_data!time_periods_user_id_fkey(display_name)
      )
    ''')
    .eq('changed_by', supervisorId)
    .eq('change_type', 'supervisor_edit')
    .eq('is_revision', true)
    .order('time_periods.work_date', ascending: false)
    .order('changed_at', ascending: false);
  
  return List<Map<String, dynamic>>.from(response);
}
```

---

## Key Points

1. **Revision Number**: Only incremented when supervisor/admin edits (stages 3 & 5)
2. **is_revision Flag**: `true` only for supervisor/admin edits, `false` for approvals and user edits
3. **Edit Flags**: `supervisor_edited_before_approval` and `admin_edited_before_approval` track if edits were made
4. **Reporting**: Use `is_revision = true` to filter for changes that require user education
5. **Workflow Stage**: Tracks where in the process the change occurred

---

## Testing Checklist

- [ ] User can submit time period without triggering revision
- [ ] User can edit draft without triggering revision
- [ ] Supervisor can approve without triggering revision
- [ ] Supervisor edits trigger revision and increment revision_number
- [ ] Admin can approve without triggering revision
- [ ] Admin edits trigger revision and increment revision_number
- [ ] Reports show only revision-triggering changes for users
- [ ] Reports show pending approvals for supervisors
- [ ] All changes are logged to revisions table

