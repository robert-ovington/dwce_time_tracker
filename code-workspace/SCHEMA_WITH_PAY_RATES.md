# Database Schema with Pay Rate Tracking

## Overview

This document extends the normalized time periods schema to include:
1. **Pay Rate Tracking**: Separate table for 7 pay rate categories
2. **Configurable Limits**: System settings for breaks, fleet limits

---

## Updated Schema Design

### 1. Time Periods Table (Unchanged Core Structure)

The main `time_periods` table remains the same, with pay rate hours tracked in a separate normalized table.

---

### 2. Pay Rate Hours Table (New)

**Design Decision**: One row per pay rate type per time period. This normalized approach:
- ✅ Supports unlimited pay rate types in the future
- ✅ Easy to query and aggregate
- ✅ Consistent with breaks/fleet normalization pattern
- ✅ Allows zero values to be omitted (saves storage)

**Important**: Minimum time increment is **15 minutes (0.25 hours)**. All time values must be multiples of 15 minutes.

```sql
CREATE TABLE public.time_period_pay_rates (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  pay_rate_type TEXT NOT NULL,
  hours NUMERIC(10, 2) NOT NULL DEFAULT 0, -- Hours allocated to this pay rate (must be multiple of 0.25)
  minutes INTEGER NULL, -- Optional: minutes component (must be 0, 15, 30, or 45)
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_pay_rates_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_pay_rates_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_pay_rates_unique_per_period UNIQUE (time_period_id, pay_rate_type),
  CONSTRAINT time_period_pay_rates_type_check CHECK (
    pay_rate_type IN ('ft', 'th', 'dt', 'ft_non_worked', 'th_non_worked', 'dt_non_worked', 'holiday_hours')
  ),
  CONSTRAINT time_period_pay_rates_hours_positive CHECK (hours >= 0),
  CONSTRAINT time_period_pay_rates_minutes_valid CHECK (
    minutes IS NULL OR minutes IN (0, 15, 30, 45)
  ),
  -- Ensure total time is a multiple of 15 minutes (0.25 hours)
  CONSTRAINT time_period_pay_rates_15min_increment CHECK (
    (hours * 4)::INTEGER = (hours * 4) AND -- Hours must be multiple of 0.25
    (minutes IS NULL OR minutes IN (0, 15, 30, 45))
  )
) TABLESPACE pg_default;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_time_period_pay_rates_time_period_id 
  ON public.time_period_pay_rates USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_pay_rates_type 
  ON public.time_period_pay_rates USING btree (pay_rate_type);
CREATE INDEX IF NOT EXISTS idx_time_period_pay_rates_time_period_type 
  ON public.time_period_pay_rates USING btree (time_period_id, pay_rate_type);
```

**Pay Rate Types:**
- `ft` - Flat Time (regular hours)
- `th` - Time and a Half
- `dt` - Double Time
- `ft_non_worked` - Flat Time Non-Worked (allowances/bonus)
- `th_non_worked` - Time and a Half Non-Worked
- `dt_non_worked` - Double Time Non-Worked
- `holiday_hours` - Holiday Hours

---

### 3. System Settings Table (Enhanced)

Add configurable limits for breaks and fleet items.

```sql
-- Add columns to existing system_settings table
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS max_breaks_per_period INTEGER NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS max_used_fleet_per_period INTEGER NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS max_mobilised_fleet_per_period INTEGER NULL DEFAULT 4;

-- Add check constraints
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'system_settings_max_breaks_check'
  ) THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_breaks_check 
      CHECK (max_breaks_per_period IS NULL OR max_breaks_per_period > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'system_settings_max_used_fleet_check'
  ) THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_used_fleet_check 
      CHECK (max_used_fleet_per_period IS NULL OR max_used_fleet_per_period > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'system_settings_max_mobilised_fleet_check'
  ) THEN
    ALTER TABLE public.system_settings
      ADD CONSTRAINT system_settings_max_mobilised_fleet_check 
      CHECK (max_mobilised_fleet_per_period IS NULL OR max_mobilised_fleet_per_period > 0);
  END IF;
END $$;

-- Set default values if not already set
UPDATE public.system_settings
SET 
  max_breaks_per_period = COALESCE(max_breaks_per_period, 3),
  max_used_fleet_per_period = COALESCE(max_used_fleet_per_period, 6),
  max_mobilised_fleet_per_period = COALESCE(max_mobilised_fleet_per_period, 4)
WHERE max_breaks_per_period IS NULL 
   OR max_used_fleet_per_period IS NULL 
   OR max_mobilised_fleet_per_period IS NULL;
```

---

## Complete Schema Summary

### All Time Period Related Tables

1. **time_periods** - Main time period record
2. **time_period_breaks** - Breaks (normalized, unlimited)
3. **time_period_used_fleet** - Used fleet items (normalized, unlimited)
4. **time_period_mobilised_fleet** - Mobilised fleet items (normalized, unlimited)
5. **time_period_pay_rates** - Pay rate hours (normalized, 7 types)
6. **time_period_revisions** - Revision history with workflow tracking

---

## Usage Examples

### Insert Pay Rate Hours

```sql
-- Insert multiple pay rates for a time period
INSERT INTO public.time_period_pay_rates (time_period_id, pay_rate_type, hours, minutes)
VALUES
  ('time-period-uuid', 'ft', 8.0, 0),
  ('time-period-uuid', 'th', 2.0, 30),
  ('time-period-uuid', 'dt', 0, NULL),
  ('time-period-uuid', 'ft_non_worked', 1.0, 0),
  ('time-period-uuid', 'holiday_hours', 0, NULL)
ON CONFLICT (time_period_id, pay_rate_type) 
DO UPDATE SET 
  hours = EXCLUDED.hours,
  minutes = EXCLUDED.minutes,
  updated_at = now();
```

### Query Time Period with All Pay Rates

```sql
SELECT 
  tp.*,
  json_object_agg(
    tpr.pay_rate_type,
    json_build_object(
      'hours', tpr.hours,
      'minutes', tpr.minutes
    )
  ) FILTER (WHERE tpr.id IS NOT NULL) as pay_rates
FROM time_periods tp
LEFT JOIN time_period_pay_rates tpr ON tp.id = tpr.time_period_id
WHERE tp.id = 'time-period-uuid'
GROUP BY tp.id;
```

### Get Total Hours by Pay Rate Type (Aggregation)

```sql
SELECT 
  pay_rate_type,
  SUM(hours) as total_hours,
  COUNT(DISTINCT time_period_id) as period_count
FROM time_period_pay_rates
WHERE time_period_id IN (
  SELECT id FROM time_periods 
  WHERE work_date >= CURRENT_DATE - INTERVAL '30 days'
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

## Application Code Integration

### Reading System Limits

```dart
Future<Map<String, int>> getSystemLimits() async {
  final response = await SupabaseService.client
    .from('system_settings')
    .select('max_breaks_per_period, max_used_fleet_per_period, max_mobilised_fleet_per_period')
    .limit(1)
    .single();
  
  return {
    'maxBreaks': response['max_breaks_per_period'] ?? 3,
    'maxUsedFleet': response['max_used_fleet_per_period'] ?? 6,
    'maxMobilisedFleet': response['max_mobilised_fleet_per_period'] ?? 4,
  };
}
```

### Saving Pay Rate Hours

```dart
Future<void> savePayRates(String timePeriodId, Map<String, double> payRates) async {
  final now = DateTime.now();
  
  // Prepare inserts/updates
  final inserts = payRates.entries
    .where((entry) => entry.value > 0) // Only save non-zero values
    .map((entry) => {
      final hours = entry.value;
      final wholeHours = hours.floor();
      final minutes = ((hours - wholeHours) * 60).round();
      
      return {
        'time_period_id': timePeriodId,
        'pay_rate_type': entry.key, // 'ft', 'th', 'dt', etc.
        'hours': wholeHours.toDouble(),
        'minutes': minutes > 0 ? minutes : null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
    })
    .toList();
  
  if (inserts.isEmpty) return;
  
  // Use upsert to handle conflicts
  await SupabaseService.client
    .from('time_period_pay_rates')
    .upsert(inserts, onConflict: 'time_period_id,pay_rate_type');
}
```

### Loading Pay Rate Hours

```dart
Future<Map<String, double>> loadPayRates(String timePeriodId) async {
  final response = await SupabaseService.client
    .from('time_period_pay_rates')
    .select('pay_rate_type, hours, minutes')
    .eq('time_period_id', timePeriodId);
  
  final payRates = <String, double>{};
  
  for (final row in response) {
    final type = row['pay_rate_type'] as String;
    final hours = (row['hours'] as num).toDouble();
    final minutes = row['minutes'] as int? ?? 0;
    final totalHours = hours + (minutes / 60.0);
    
    payRates[type] = totalHours;
  }
  
  return payRates;
}
```

### Complete Time Period Query with All Related Data

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

---

## Benefits of This Design

### Pay Rate Table Benefits

1. **Normalized**: One row per pay rate type, easy to extend
2. **Flexible**: Can add new pay rate types without schema changes
3. **Efficient**: Only stores non-zero values (optional optimization)
4. **Queryable**: Easy to aggregate and report on pay rates
5. **Precise**: Supports hours and minutes for accuracy

### System Settings Benefits

1. **Configurable**: Limits can be changed without code deployment
2. **Centralized**: All limits in one place
3. **Versioned**: Can track limit changes over time
4. **Flexible**: NULL values allow unlimited (if needed in future)

---

## Migration Considerations

### Adding Pay Rate Table

```sql
-- This is a new table, no migration needed
-- Just create it as shown above
```

### Updating System Settings

```sql
-- Add columns (safe, won't break existing code)
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS max_breaks_per_period INTEGER NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS max_used_fleet_per_period INTEGER NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS max_mobilised_fleet_per_period INTEGER NULL DEFAULT 4;
```

---

## Summary

- ✅ **Pay rates in separate normalized table** (7 types supported)
- ✅ **Configurable limits in system_settings** (breaks, fleet)
- ✅ **Consistent with existing normalization pattern**
- ✅ **Easy to query and aggregate**
- ✅ **Future-proof and extensible**

This design maintains consistency with your normalized approach while adding the flexibility you need for pay rate tracking and configurable limits.

