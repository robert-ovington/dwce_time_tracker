# Flutter Code Migration Guide for New Schema

## Overview
This guide documents the changes needed in the Flutter app to work with the new normalized database schema and 3-stage approval workflow.

## Database Schema Changes

### 1. Main Table: `time_periods`
- **Status field changed**: Now uses only 3 values:
  - `submitted` - User submits (default)
  - `supervisor_approved` - Supervisor/Manager approved
  - `admin_approved` - Admin final approval
- **No more `draft` status**: All new entries start as `submitted`

### 2. New Normalized Tables

#### `time_period_breaks` (replaces break columns in time_periods)
```dart
{
  'id': UUID (auto-generated),
  'time_period_id': UUID (foreign key),
  'break_start': TIMESTAMP WITH TIME ZONE,
  'break_end': TIMESTAMP WITH TIME ZONE,
  'break_duration_min': INTEGER,
  'created_at': TIMESTAMP,
  'updated_at': TIMESTAMP
}
```

#### `time_period_used_fleet` (replaces time_used_large_plant)
```dart
{
  'id': UUID (auto-generated),
  'time_period_id': UUID (foreign key),
  'large_plant_id': UUID (foreign key to large_plant),
  'plant_number': TEXT,
  'created_at': TIMESTAMP,
  'updated_at': TIMESTAMP
}
```

#### `time_period_mobilised_fleet` (replaces time_mobilised_large_plant)
```dart
{
  'id': UUID (auto-generated),
  'time_period_id': UUID (foreign key),
  'large_plant_id': UUID (foreign key to large_plant),
  'plant_number': TEXT,
  'distance_km': NUMERIC(10,2) (optional),
  'created_at': TIMESTAMP,
  'updated_at': TIMESTAMP
}
```

#### `time_period_pay_rates` (NEW - for pay rate allocation)
```dart
{
  'id': UUID (auto-generated),
  'time_period_id': UUID (foreign key),
  'pay_rate_type': TEXT, // 'ft', 'th', 'dt', 'ft_non_worked', 'th_non_worked', 'dt_non_worked', 'holiday_hours'
  'hours': NUMERIC(10,2),
  'minutes': INTEGER (0, 15, 30, 45),
  'created_at': TIMESTAMP,
  'updated_at': TIMESTAMP
}
```

#### `time_period_revisions` (for audit trail)
- System table - automatically populated when supervisors/admins edit
- Users can view their own revisions to see what changed

## Code Changes Required

### 1. Update Status Value
**File**: `timesheet_screen.dart`
**Line**: 3552

```dart
// OLD:
'status': 'draft',

// NEW:
'status': 'submitted',
```

### 2. Update Break Saving Logic
**Current**: Breaks are saved as columns in time_periods table  
**New**: Each break is a separate row in `time_period_breaks`

```dart
Future<void> _saveBreaks(String timePeriodId, List<Map<String, dynamic>> breaks) async {
  for (final breakItem in breaks) {
    final breakData = {
      'time_period_id': timePeriodId,
      'break_start': breakItem['start'], // ISO 8601 string
      'break_end': breakItem['end'],     // ISO 8601 string
      'break_duration_min': breakItem['duration_minutes'],
    };
    
    await DatabaseService.create('time_period_breaks', breakData);
  }
}
```

### 3. Update Used Fleet Saving Logic
**Current**: Saves numbered columns (large_plant_id_1, large_plant_id_2, etc.)  
**New**: One row per fleet item

```dart
Future<void> _saveUsedFleet(String timePeriodId, List<String> usedFleet) async {
  for (final plantNo in usedFleet) {
    if (plantNo.trim().isEmpty) continue;
    
    // Look up plant ID
    final plant = _allPlant.firstWhere(
      (p) => p['plant_no']?.toString().toUpperCase().trim() == plantNo.toUpperCase().trim(),
      orElse: () => {},
    );
    
    final fleetData = {
      'time_period_id': timePeriodId,
      'large_plant_id': plant['id'], // Foreign key
      'plant_number': plantNo.toUpperCase().trim(),
    };
    
    await DatabaseService.create('time_period_used_fleet', fleetData);
  }
}
```

### 4. Update Mobilised Fleet Saving Logic
**Current**: Saves numbered columns (large_plant_no_1, large_plant_no_2, etc.)  
**New**: One row per fleet item

```dart
Future<void> _saveMobilisedFleet(String timePeriodId, List<String> mobilisedFleet) async {
  for (final plantNo in mobilisedFleet) {
    if (plantNo.trim().isEmpty) continue;
    
    // Look up plant ID
    final plant = _allPlant.firstWhere(
      (p) => p['plant_no']?.toString().toUpperCase().trim() == plantNo.toUpperCase().trim(),
      orElse: () => {},
    );
    
    final fleetData = {
      'time_period_id': timePeriodId,
      'large_plant_id': plant['id'],
      'plant_number': plantNo.toUpperCase().trim(),
      // 'distance_km': null, // Optional - can add distance tracking later
    };
    
    await DatabaseService.create('time_period_mobilised_fleet', fleetData);
  }
}
```

### 5. Add Pay Rate Saving Logic (NEW)
This is new functionality to support pay rate allocation.

```dart
Future<void> _savePayRates(String timePeriodId, Map<String, double> payRates) async {
  // Example payRates: {'ft': 8.0, 'th': 2.0, 'dt': 0.0, ...}
  
  for (final entry in payRates.entries) {
    if (entry.value <= 0) continue; // Skip zero hours
    
    final hours = entry.value.floor();
    final minutesFraction = (entry.value - hours) * 60;
    final minutes = (minutesFraction / 15).round() * 15; // Round to nearest 15 min
    
    final payRateData = {
      'time_period_id': timePeriodId,
      'pay_rate_type': entry.key, // 'ft', 'th', 'dt', etc.
      'hours': hours + (minutes / 60), // Store as decimal hours
      'minutes': minutes,
    };
    
    await DatabaseService.create('time_period_pay_rates', payRateData);
  }
}
```

### 6. Update Main Save Flow
After creating the time_period, save related data:

```dart
// Create time period
final result = await DatabaseService.create('time_periods', timePeriodData);
final timePeriodId = result['id']?.toString();

if (timePeriodId != null) {
  // Save breaks (if any)
  if (_breaks.isNotEmpty) {
    await _saveBreaks(timePeriodId, _breaks);
  }
  
  // Save used fleet (if any)
  if (_usedFleet.any((f) => f.isNotEmpty)) {
    await _saveUsedFleet(timePeriodId, _usedFleet);
  }
  
  // Save mobilised fleet (if any)
  if (_mobilisedFleet.any((f) => f.isNotEmpty)) {
    await _saveMobilisedFleet(timePeriodId, _mobilisedFleet);
  }
  
  // Save pay rates (if implemented)
  // await _savePayRates(timePeriodId, calculatedPayRates);
}
```

## 15-Minute Time Increment Validation

All time values should be validated to ensure they are in 15-minute increments:

```dart
bool _isValid15MinuteIncrement(DateTime time) {
  return time.minute % 15 == 0;
}

// Validate start and finish times
if (!_isValid15MinuteIncrement(startTimestamp!) || 
    !_isValid15MinuteIncrement(finishTimestamp!)) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Times must be in 15-minute increments (e.g., 08:00, 08:15, 08:30, 08:45)'),
      backgroundColor: Colors.red,
    ),
  );
  return;
}
```

## Reading Data Back

When reading time periods, you'll need to join with the related tables:

```dart
// Read time period
final timePeriod = await DatabaseService.read(
  'time_periods',
  filterColumn: 'id',
  filterValue: timePeriodId,
  limit: 1,
);

// Read breaks
final breaks = await DatabaseService.read(
  'time_period_breaks',
  filterColumn: 'time_period_id',
  filterValue: timePeriodId,
);

// Read used fleet
final usedFleet = await DatabaseService.read(
  'time_period_used_fleet',
  filterColumn: 'time_period_id',
  filterValue: timePeriodId,
);

// Read mobilised fleet
final mobilisedFleet = await DatabaseService.read(
  'time_period_mobilised_fleet',
  filterColumn: 'time_period_id',
  filterValue: timePeriodId,
);

// Read pay rates
final payRates = await DatabaseService.read(
  'time_period_pay_rates',
  filterColumn: 'time_period_id',
  filterValue: timePeriodId,
);
```

## System Settings for Limits

The configurable limits are now stored in `system_settings`:
- `max_breaks_per_period` (default: 3)
- `max_used_fleet_per_period` (default: 6)
- `max_mobilised_fleet_per_period` (default: 4)

These can be read and used for validation:

```dart
Future<Map<String, int>> _getSystemLimits() async {
  final settings = await DatabaseService.read('system_settings', limit: 1);
  
  if (settings.isEmpty) {
    return {
      'max_breaks': 3,
      'max_used_fleet': 6,
      'max_mobilised_fleet': 4,
    };
  }
  
  return {
    'max_breaks': settings[0]['max_breaks_per_period'] ?? 3,
    'max_used_fleet': settings[0]['max_used_fleet_per_period'] ?? 6,
    'max_mobilised_fleet': settings[0]['max_mobilised_fleet_per_period'] ?? 4,
  };
}
```

## Testing Checklist

- [ ] Create new time period with status 'submitted'
- [ ] Save breaks to `time_period_breaks` table
- [ ] Save used fleet to `time_period_used_fleet` table
- [ ] Save mobilised fleet to `time_period_mobilised_fleet` table
- [ ] Validate 15-minute time increments
- [ ] Test offline mode (if applicable)
- [ ] Test RLS policies (user can only edit their own 'submitted' entries)
- [ ] Test reading data back from normalized tables
- [ ] Test validation limits from system_settings

## Migration Strategy

1. Update status value from 'draft' to 'submitted'
2. Update break saving to use new table
3. Update fleet saving to use new tables
4. Add 15-minute validation
5. Test thoroughly with new schema
6. (Optional) Add pay rate allocation UI and logic

