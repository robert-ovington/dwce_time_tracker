# Complete Time Periods Schema Summary

## Overview

This document summarizes the complete normalized schema design for time period tracking, including:
- ✅ Normalized related data (breaks, fleet, pay rates)
- ✅ 5-stage approval workflow
- ✅ Comprehensive revision tracking
- ✅ Configurable system limits
- ✅ Pay rate tracking (7 types)

---

## Complete Table Structure

### 1. Main Table: `time_periods`
Core time period record with all workflow and allowance fields.

**Key Fields:**
- Workflow: `status`, `submitted_at`, `supervisor_id`, `admin_id`, etc.
- Time tracking: `work_date`, `start_time`, `finish_time`
- Allowances: `travel_to_site_min`, `on_call`, `misc_allowance_min`, etc.
- Revision tracking: `revision_number`, `last_revised_at`, `last_revised_by`

---

### 2. Related Tables (Normalized)

#### `time_period_breaks`
- One row per break
- Unlimited breaks per time period
- Fields: `break_start`, `break_finish`, `break_reason`, `display_order`

#### `time_period_used_fleet`
- One row per fleet item used
- Unlimited items per time period
- Fields: `large_plant_id`, `display_order`
- Unique constraint prevents duplicates

#### `time_period_mobilised_fleet`
- One row per fleet item mobilised
- Unlimited items per time period
- Fields: `large_plant_id`, `display_order`
- Unique constraint prevents duplicates

#### `time_period_pay_rates` ⭐ NEW
- One row per pay rate type
- 7 pay rate types supported:
  - `ft` - Flat Time
  - `th` - Time and a Half
  - `dt` - Double Time
  - `ft_non_worked` - Flat Time Non-Worked
  - `th_non_worked` - Time and a Half Non-Worked
  - `dt_non_worked` - Double Time Non-Worked
  - `holiday_hours` - Holiday Hours
- Fields: `pay_rate_type`, `hours`, `minutes`
- Unique constraint: one row per type per time period

#### `time_period_revisions`
- One row per field change
- Tracks all changes with workflow context
- Fields: `change_type`, `is_revision`, `workflow_stage`, `field_name`, `old_value`, `new_value`

---

### 3. System Configuration: `system_settings`

**Configurable Limits:**
- `max_breaks_per_period` (default: 3)
- `max_used_fleet_per_period` (default: 6)
- `max_mobilised_fleet_per_period` (default: 4)

**Benefits:**
- Change limits without code deployment
- Centralized configuration
- Easy to adjust as business needs change

---

## Pay Rate Types Reference

| Type | Code | Description |
|------|------|-------------|
| Flat Time | `ft` | Regular worked hours |
| Time and a Half | `th` | Overtime worked hours |
| Double Time | `dt` | Premium worked hours |
| FT Non-Worked | `ft_non_worked` | Regular non-worked allowance |
| TH Non-Worked | `th_non_worked` | Time and a half non-worked allowance |
| DT Non-Worked | `dt_non_worked` | Double time non-worked allowance |
| Holiday Hours | `holiday_hours` | Holiday pay hours |

---

## Key Design Decisions

### 1. Normalized Related Data
**Why:** Eliminates numbered columns, supports unlimited items, easier queries

**Before:**
```sql
large_plant_id_1, large_plant_id_2, ..., large_plant_id_6
```

**After:**
```sql
-- Separate table with one row per item
time_period_used_fleet (time_period_id, large_plant_id, display_order)
```

### 2. Separate Pay Rates Table
**Why:** 
- Clean separation of concerns
- Easy to add new pay rate types
- Efficient storage (only non-zero values)
- Simple aggregation queries

### 3. Configurable Limits in System Settings
**Why:**
- No code changes needed to adjust limits
- Centralized configuration
- Easy to test different limits
- Supports business growth

### 4. Comprehensive Revision Tracking
**Why:**
- Full audit trail
- User education reports
- Supervisor review reports
- Pattern analysis

---

## Example Queries

### Get Complete Time Period with All Related Data

```sql
SELECT 
  tp.*,
  -- Breaks
  json_agg(DISTINCT jsonb_build_object(
    'id', tpb.id,
    'break_start', tpb.break_start,
    'break_finish', tpb.break_finish,
    'break_reason', tpb.break_reason,
    'display_order', tpb.display_order
  )) FILTER (WHERE tpb.id IS NOT NULL) as breaks,
  
  -- Used Fleet
  json_agg(DISTINCT jsonb_build_object(
    'id', tuf.id,
    'large_plant_id', tuf.large_plant_id,
    'display_order', tuf.display_order
  )) FILTER (WHERE tuf.id IS NOT NULL) as used_fleet,
  
  -- Mobilised Fleet
  json_agg(DISTINCT jsonb_build_object(
    'id', tmf.id,
    'large_plant_id', tmf.large_plant_id,
    'display_order', tmf.display_order
  )) FILTER (WHERE tmf.id IS NOT NULL) as mobilised_fleet,
  
  -- Pay Rates
  json_object_agg(
    tpr.pay_rate_type,
    json_build_object(
      'hours', tpr.hours,
      'minutes', tpr.minutes
    )
  ) FILTER (WHERE tpr.id IS NOT NULL) as pay_rates
  
FROM time_periods tp
LEFT JOIN time_period_breaks tpb ON tp.id = tpb.time_period_id
LEFT JOIN time_period_used_fleet tuf ON tp.id = tuf.time_period_id
LEFT JOIN time_period_mobilised_fleet tmf ON tp.id = tmf.time_period_id
LEFT JOIN time_period_pay_rates tpr ON tp.id = tpr.time_period_id
WHERE tp.id = 'time-period-uuid'
GROUP BY tp.id;
```

### Get Total Hours by Pay Rate Type

```sql
SELECT 
  pay_rate_type,
  SUM(hours + COALESCE(minutes, 0) / 60.0) as total_hours,
  COUNT(DISTINCT time_period_id) as period_count
FROM time_period_pay_rates
WHERE time_period_id IN (
  SELECT id FROM time_periods 
  WHERE work_date >= CURRENT_DATE - INTERVAL '30 days'
    AND status = 'admin_approved'
)
GROUP BY pay_rate_type
ORDER BY pay_rate_type;
```

### Get System Limits

```sql
SELECT 
  max_breaks_per_period,
  max_used_fleet_per_period,
  max_mobilised_fleet_per_period
FROM system_settings
LIMIT 1;
```

---

## Application Integration Points

### 1. Reading System Limits

```dart
final limits = await getSystemLimits();
final maxBreaks = limits['maxBreaks'] ?? 3;
final maxUsedFleet = limits['maxUsedFleet'] ?? 6;
final maxMobilisedFleet = limits['maxMobilisedFleet'] ?? 4;
```

### 2. Saving Pay Rates

```dart
await savePayRates(timePeriodId, {
  'ft': 8.0,
  'th': 2.5,
  'ft_non_worked': 1.0,
  'holiday_hours': 0.0,
});
```

### 3. Loading Complete Time Period

```dart
final period = await loadTimePeriodWithRelatedData(timePeriodId);
final breaks = period['breaks'] as List;
final usedFleet = period['used_fleet'] as List;
final payRates = period['pay_rates'] as Map;
```

---

## Migration Checklist

- [ ] Review all schema documents
- [ ] Test migration script in development
- [ ] Verify data migration (fleet, breaks)
- [ ] Update application code for new tables
- [ ] Test pay rate saving/loading
- [ ] Test system limits reading
- [ ] Update UI to use configurable limits
- [ ] Test complete workflow (submit → approve → edit)
- [ ] Generate test reports
- [ ] Deploy to production

---

## File Reference

1. **SCHEMA_WITH_PAY_RATES.md** - Complete schema with pay rates
2. **SCHEMA_WITH_APPROVAL_WORKFLOW.md** - Workflow and revision tracking
3. **MIGRATION_COMPLETE_SCHEMA.sql** - Complete migration script
4. **WORKFLOW_IMPLEMENTATION_GUIDE.md** - Code examples for workflow
5. **SCHEMA_COMPARISON.md** - Current vs recommended design

---

## Time Validation Rules

**Minimum Time Increment: 15 minutes (0.25 hours)**

All time values must be multiples of 15 minutes:
- Time periods: start/finish times on 15-minute boundaries
- Breaks: start/finish times on 15-minute boundaries
- Pay rates: hours must be multiples of 0.25
- Allowances: minutes must be multiples of 15

See `TIME_VALIDATION_RULES.md` for complete validation rules and implementation examples.

---

## Summary

This normalized schema design provides:

✅ **Unlimited Related Items** - No hard limits on breaks, fleet, or pay rates  
✅ **Configurable Limits** - Adjust UI limits without code changes  
✅ **Complete Workflow Tracking** - Full audit trail with revision history  
✅ **Pay Rate Flexibility** - Easy to add new pay rate types  
✅ **Reporting Support** - Optimized for user and supervisor reports  
✅ **15-Minute Validation** - Enforced at database and application levels  
✅ **Future-Proof** - Designed for growth and change  

The design follows database best practices and provides a solid foundation for your time tracking system.

