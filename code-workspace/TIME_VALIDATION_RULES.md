# Time Validation Rules

## Overview

This document defines the time validation rules for the time tracking system, specifically the **15-minute (0.25 hours) minimum increment** requirement.

---

## Core Rule

**Minimum Time Increment: 15 minutes (0.25 hours)**

All time values in the system must be multiples of 15 minutes:
- ✅ Valid: 0.25, 0.50, 0.75, 1.00, 1.25, 2.50, 8.00 hours
- ❌ Invalid: 0.10, 0.33, 1.17, 2.83 hours

---

## Where This Applies

### 1. Time Period Duration
- `start_time` and `finish_time` must be on 15-minute boundaries
- Duration must be a multiple of 15 minutes
- Minimum duration: 15 minutes

### 2. Break Times
- `break_start` and `break_finish` must be on 15-minute boundaries
- Break duration must be a multiple of 15 minutes

### 3. Pay Rate Hours
- All pay rate hours must be multiples of 0.25 hours
- `hours` field: must be multiple of 0.25
- `minutes` field: must be 0, 15, 30, or 45 (if used)

### 4. Travel Allowances
- `travel_to_site_min` and `travel_from_site_min` must be multiples of 15
- Minimum: 15 minutes

### 5. Other Allowances
- `misc_allowance_min` must be multiple of 15
- `allowance_holiday_hours_min` must be multiple of 15
- `allowance_non_worked_ft_min` must be multiple of 15
- `allowance_non_worked_th_min` must be multiple of 15
- `allowance_non_worked_dt_min` must be multiple of 15

---

## Database Constraints

### Time Periods Table

```sql
-- Note: Time validation is primarily enforced at application level
-- Database constraints ensure data integrity but may not catch all edge cases

-- Ensure finish_time >= start_time
CONSTRAINT time_periods_finish_after_start CHECK (
  finish_time IS NULL OR start_time IS NULL OR finish_time >= start_time
)

-- Ensure same day
CONSTRAINT time_periods_same_day CHECK (
  finish_time IS NULL OR start_time IS NULL OR 
  DATE(finish_time) = DATE(start_time)
)
```

### Pay Rates Table

```sql
-- Ensure minutes are valid 15-minute increments
CONSTRAINT time_period_pay_rates_minutes_valid CHECK (
  minutes IS NULL OR minutes IN (0, 15, 30, 45)
)

-- Ensure hours are multiples of 0.25
CONSTRAINT time_period_pay_rates_15min_increment CHECK (
  (hours * 4)::INTEGER = (hours * 4) AND -- Hours must be multiple of 0.25
  (minutes IS NULL OR minutes IN (0, 15, 30, 45))
)
```

### Breaks Table

```sql
-- Ensure break times are valid
CONSTRAINT time_period_breaks_finish_after_start CHECK (
  break_finish IS NULL OR break_start IS NULL OR break_finish >= break_start
)
-- Note: 15-minute validation enforced at application level
```

---

## Application-Level Validation

### Dart/Flutter Helper Functions

```dart
/// Round time to nearest 15-minute increment
DateTime roundTo15Minutes(DateTime dateTime) {
  final minutes = dateTime.minute;
  final roundedMinutes = ((minutes / 15).round() * 15) % 60;
  final hoursToAdd = (minutes / 15).round() ~/ 4;
  
  return DateTime(
    dateTime.year,
    dateTime.month,
    dateTime.day,
    dateTime.hour + hoursToAdd,
    roundedMinutes,
    0,
    0,
  );
}

/// Check if time is on 15-minute boundary
bool is15MinuteIncrement(DateTime dateTime) {
  return dateTime.minute % 15 == 0 && dateTime.second == 0;
}

/// Validate that hours are multiple of 0.25
bool isValidHours(double hours) {
  // Check if hours is multiple of 0.25
  final quarters = (hours * 4).round();
  return (quarters / 4.0 - hours).abs() < 0.001; // Account for floating point
}

/// Convert minutes to hours (ensuring 15-minute increments)
double minutesToHours(int minutes) {
  if (minutes % 15 != 0) {
    throw ArgumentError('Minutes must be multiple of 15');
  }
  return minutes / 60.0;
}

/// Convert hours to minutes (rounding to 15-minute increments)
int hoursToMinutes(double hours) {
  if (!isValidHours(hours)) {
    throw ArgumentError('Hours must be multiple of 0.25');
  }
  return (hours * 60).round();
}

/// Format hours as "H:MM" ensuring 15-minute increments
String formatHours(double hours) {
  if (!isValidHours(hours)) {
    throw ArgumentError('Hours must be multiple of 0.25');
  }
  
  final wholeHours = hours.floor();
  final minutes = ((hours - wholeHours) * 60).round();
  
  return '${wholeHours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

/// Parse time string and ensure 15-minute increment
DateTime parseAndRoundTime(String timeString) {
  final parts = timeString.split(':');
  if (parts.length != 2) {
    throw FormatException('Invalid time format: $timeString');
  }
  
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  
  if (minute % 15 != 0) {
    throw ArgumentError('Time must be on 15-minute boundary: $timeString');
  }
  
  return DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, hour, minute);
}
```

### Time Period Validation

```dart
/// Validate time period duration
bool validateTimePeriod(DateTime startTime, DateTime finishTime) {
  // Ensure times are on 15-minute boundaries
  if (!is15MinuteIncrement(startTime) || !is15MinuteIncrement(finishTime)) {
    return false;
  }
  
  // Ensure finish is after start
  if (finishTime.isBefore(startTime) || finishTime.isAtSameMomentAs(startTime)) {
    return false;
  }
  
  // Calculate duration
  final duration = finishTime.difference(startTime);
  final minutes = duration.inMinutes;
  
  // Ensure duration is at least 15 minutes
  if (minutes < 15) {
    return false;
  }
  
  // Ensure duration is multiple of 15 minutes
  if (minutes % 15 != 0) {
    return false;
  }
  
  return true;
}

/// Get duration in hours (ensuring 15-minute increments)
double getDurationHours(DateTime startTime, DateTime finishTime) {
  if (!validateTimePeriod(startTime, finishTime)) {
    throw ArgumentError('Invalid time period');
  }
  
  final duration = finishTime.difference(startTime);
  return duration.inMinutes / 60.0;
}
```

### Pay Rate Validation

```dart
/// Validate pay rate hours
bool validatePayRateHours(double hours, int? minutes) {
  // Validate hours
  if (!isValidHours(hours)) {
    return false;
  }
  
  // Validate minutes if provided
  if (minutes != null) {
    if (minutes !in [0, 15, 30, 45]) {
      return false;
    }
  }
  
  return true;
}

/// Save pay rate with validation
Future<void> savePayRateWithValidation(
  String timePeriodId,
  String payRateType,
  double hours,
  int? minutes,
) async {
  // Validate
  if (!validatePayRateHours(hours, minutes)) {
    throw ArgumentError(
      'Pay rate hours must be multiple of 0.25 hours. '
      'Minutes must be 0, 15, 30, or 45.'
    );
  }
  
  // Ensure hours is properly rounded
  final roundedHours = (hours * 4).round() / 4.0;
  
  // Save to database
  await SupabaseService.client
    .from('time_period_pay_rates')
    .upsert({
      'time_period_id': timePeriodId,
      'pay_rate_type': payRateType,
      'hours': roundedHours,
      'minutes': minutes,
    }, onConflict: 'time_period_id,pay_rate_type');
}
```

### Break Validation

```dart
/// Validate break times
bool validateBreak(DateTime breakStart, DateTime? breakFinish) {
  // Ensure start is on 15-minute boundary
  if (!is15MinuteIncrement(breakStart)) {
    return false;
  }
  
  // If finish is provided, validate it
  if (breakFinish != null) {
    if (!is15MinuteIncrement(breakFinish)) {
      return false;
    }
    
    if (breakFinish.isBefore(breakStart)) {
      return false;
    }
    
    final duration = breakFinish.difference(breakStart);
    if (duration.inMinutes % 15 != 0) {
      return false;
    }
  }
  
  return true;
}
```

---

## UI Time Picker Configuration

### Flutter Time Picker

```dart
Future<TimeOfDay?> show15MinuteTimePicker(BuildContext context, TimeOfDay initialTime) async {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          alwaysUse24HourFormat: true,
        ),
        child: child!,
      );
    },
  )?.then((time) {
    if (time == null) return null;
    
    // Round to nearest 15 minutes
    final roundedMinutes = ((time.minute / 15).round() * 15) % 60;
    final hoursToAdd = (time.minute / 15).round() ~/ 4;
    
    return TimeOfDay(
      hour: (time.hour + hoursToAdd) % 24,
      minute: roundedMinutes,
    );
  });
}
```

### Custom 15-Minute Time Picker Widget

```dart
class FifteenMinuteTimePicker extends StatelessWidget {
  final TimeOfDay? selectedTime;
  final ValueChanged<TimeOfDay> onTimeSelected;
  
  const FifteenMinuteTimePicker({
    Key? key,
    this.selectedTime,
    required this.onTimeSelected,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final hours = List.generate(24, (i) => i);
    final minutes = [0, 15, 30, 45];
    
    return Column(
      children: [
        // Hour selector
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: hours.map((hour) {
            final isSelected = selectedTime?.hour == hour;
            return GestureDetector(
              onTap: () {
                onTimeSelected(TimeOfDay(
                  hour: hour,
                  minute: selectedTime?.minute ?? 0,
                ));
              },
              child: Container(
                margin: EdgeInsets.all(4),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hour.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 16),
        // Minute selector (15-minute increments)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: minutes.map((minute) {
            final isSelected = selectedTime?.minute == minute;
            return GestureDetector(
              onTap: () {
                onTimeSelected(TimeOfDay(
                  hour: selectedTime?.hour ?? 0,
                  minute: minute,
                ));
              },
              child: Container(
                margin: EdgeInsets.all(4),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  minute.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
```

---

## SQL Validation Functions

### PostgreSQL Function to Validate 15-Minute Increment

```sql
-- Function to check if a time is on 15-minute boundary
CREATE OR REPLACE FUNCTION is_15_minute_increment(timestamp_with_time_zone)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXTRACT(MINUTE FROM $1) % 15 = 0 
     AND EXTRACT(SECOND FROM $1) = 0;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to round time to nearest 15 minutes
CREATE OR REPLACE FUNCTION round_to_15_minutes(timestamp_with_time_zone)
RETURNS timestamp_with_time_zone AS $$
BEGIN
  RETURN date_trunc('hour', $1) + 
         (EXTRACT(MINUTE FROM $1)::INTEGER / 15 * 15) * INTERVAL '1 minute';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to validate hours are multiple of 0.25
CREATE OR REPLACE FUNCTION is_valid_hours(numeric)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN ($1 * 4)::INTEGER = ($1 * 4);
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

---

## Summary

### Key Points

1. **Minimum Increment**: 15 minutes (0.25 hours)
2. **Validation**: Enforced at both database and application levels
3. **Time Boundaries**: All times must be on 15-minute boundaries (00, 15, 30, 45)
4. **Duration**: All durations must be multiples of 15 minutes
5. **Pay Rates**: All pay rate hours must be multiples of 0.25 hours

### Implementation Checklist

- [ ] Add database constraints for pay rates
- [ ] Implement application-level validation functions
- [ ] Update UI time pickers to enforce 15-minute increments
- [ ] Add validation to time period save logic
- [ ] Add validation to pay rate save logic
- [ ] Add validation to break save logic
- [ ] Test all time inputs with invalid values
- [ ] Add user-friendly error messages

---

## Examples

### Valid Time Periods
- 08:00 - 17:00 (9 hours)
- 08:15 - 12:30 (4.25 hours)
- 09:00 - 09:15 (0.25 hours - minimum)

### Invalid Time Periods
- 08:07 - 17:00 ❌ (start not on 15-minute boundary)
- 08:00 - 17:03 ❌ (finish not on 15-minute boundary)
- 08:00 - 08:05 ❌ (duration less than 15 minutes)
- 08:00 - 08:17 ❌ (duration not multiple of 15 minutes)

### Valid Pay Rates
- 8.00 hours ✅
- 2.25 hours ✅
- 0.50 hours ✅
- 1.75 hours ✅

### Invalid Pay Rates
- 8.10 hours ❌
- 2.33 hours ❌
- 0.17 hours ❌

