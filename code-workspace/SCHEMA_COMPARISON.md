# Schema Comparison: Current vs Recommended

## Quick Summary

| Aspect | Current Design | Recommended Design | Benefit |
|--------|---------------|-------------------|---------|
| **Fleet Storage** | Numbered columns (`large_plant_id_1` to `_6`) | Normalized table (one row per item) | Unlimited items, easier queries |
| **Breaks Storage** | ❌ Missing | Normalized table (one row per break) | Unlimited breaks, proper tracking |
| **Revision Tracking** | No link to `time_period_id` | Linked via foreign key | Easy to query revisions per period |
| **Missing Fields** | Many fields from original design missing | All fields included | Complete feature set |
| **Scalability** | Limited to 6 fleet items, 0 breaks | Unlimited | Future-proof |

---

## Detailed Comparison

### 1. Fleet Data Storage

#### Current Design ❌
```sql
-- time_used_large_plant table
large_plant_id_1 UUID
large_plant_id_2 UUID
large_plant_id_3 UUID
large_plant_id_4 UUID
large_plant_id_5 UUID
large_plant_id_6 UUID
```

**Problems:**
- Limited to 6 items
- Hard to query (need to check 6 columns)
- Can't easily count usage
- Wastes space if fewer than 6 items

#### Recommended Design ✅
```sql
-- time_period_used_fleet table
time_period_id UUID
large_plant_id UUID
display_order INTEGER
```

**Benefits:**
- Unlimited items per time period
- Easy queries: `SELECT * FROM time_period_used_fleet WHERE large_plant_id = '...'`
- Simple counting: `COUNT(*) GROUP BY large_plant_id`
- Efficient storage (only stores what's used)

---

### 2. Breaks Storage

#### Current Design ❌
```sql
-- No breaks table exists!
-- Breaks are not being tracked in the database
```

**Problems:**
- Breaks data is lost
- Can't query break patterns
- No audit trail for breaks

#### Recommended Design ✅
```sql
-- time_period_breaks table
time_period_id UUID
break_start TIMESTAMP
break_finish TIMESTAMP
break_reason TEXT
display_order INTEGER
```

**Benefits:**
- Unlimited breaks per time period
- Proper time tracking
- Can analyze break patterns
- Full audit trail

---

### 3. Revision Tracking

#### Current Design ❌
```sql
-- time_period_revision table
revision_number INTEGER
changed_at TIMESTAMP
user_name TEXT
field_name TEXT
old_value TEXT
new_value TEXT
-- ❌ NO time_period_id link!
```

**Problems:**
- Can't easily find revisions for a specific time period
- Must join on `revision_number` (not reliable)
- No link to user who made change

#### Recommended Design ✅
```sql
-- time_period_revisions table
time_period_id UUID  -- ✅ Direct link
revision_number INTEGER
changed_at TIMESTAMP
changed_by UUID  -- ✅ Foreign key to user
user_name TEXT
field_name TEXT
old_value TEXT
new_value TEXT
```

**Benefits:**
- Direct link to time period
- Easy query: `SELECT * FROM revisions WHERE time_period_id = '...'`
- Proper user tracking via foreign key
- Better data integrity

---

### 4. Missing Fields

#### Current Design ❌
Missing from `time_periods`:
- `supervisor_id`
- `supervisor_time_stamp`
- `admin_id`
- `admin_time_stamp`
- `user_absenteeism_reason`
- `absenteeism_notice_date`
- `supervisor_absenteeism_reason`
- `allowance_holiday_hours_min`
- `allowance_non_worked_ft_min`
- `allowance_non_worked_th_min`
- `allowance_non_worked_dt_min`
- `submission_datetime`

#### Recommended Design ✅
All fields from original design included with proper data types and constraints.

---

## Query Examples

### Find All Time Periods Using a Specific Fleet Item

#### Current Design ❌
```sql
-- Must check 6 columns!
SELECT DISTINCT time_period_id
FROM time_used_large_plant
WHERE large_plant_id_1 = 'uuid'
   OR large_plant_id_2 = 'uuid'
   OR large_plant_id_3 = 'uuid'
   OR large_plant_id_4 = 'uuid'
   OR large_plant_id_5 = 'uuid'
   OR large_plant_id_6 = 'uuid';
```

#### Recommended Design ✅
```sql
-- Simple, clean query
SELECT time_period_id
FROM time_period_used_fleet
WHERE large_plant_id = 'uuid';
```

---

### Count Fleet Usage

#### Current Design ❌
```sql
-- Complex, error-prone
SELECT 
  lp.plant_no,
  (SELECT COUNT(*) FROM time_used_large_plant WHERE large_plant_id_1 = lp.id) +
  (SELECT COUNT(*) FROM time_used_large_plant WHERE large_plant_id_2 = lp.id) +
  (SELECT COUNT(*) FROM time_used_large_plant WHERE large_plant_id_3 = lp.id) +
  (SELECT COUNT(*) FROM time_used_large_plant WHERE large_plant_id_4 = lp.id) +
  (SELECT COUNT(*) FROM time_used_large_plant WHERE large_plant_id_5 = lp.id) +
  (SELECT COUNT(*) FROM time_used_large_plant WHERE large_plant_id_6 = lp.id) as usage_count
FROM large_plant lp;
```

#### Recommended Design ✅
```sql
-- Simple, efficient
SELECT 
  lp.plant_no,
  COUNT(tuf.id) as usage_count
FROM large_plant lp
LEFT JOIN time_period_used_fleet tuf ON lp.id = tuf.large_plant_id
GROUP BY lp.plant_no
ORDER BY usage_count DESC;
```

---

### Get Time Period with All Related Data

#### Current Design ❌
```sql
-- Multiple queries needed
-- Query 1: Get time period
SELECT * FROM time_periods WHERE id = 'uuid';

-- Query 2: Get used fleet (check 6 columns)
SELECT * FROM time_used_large_plant WHERE time_period_id = 'uuid';

-- Query 3: Get mobilised fleet (check 4 columns)
SELECT * FROM time_mobilised_large_plant WHERE time_period_id = 'uuid';

-- Query 4: Get breaks (doesn't exist!)
-- ❌ Can't do this
```

#### Recommended Design ✅
```sql
-- Single query with JOINs
SELECT 
  tp.*,
  json_agg(DISTINCT jsonb_build_object(
    'id', tpb.id,
    'break_start', tpb.break_start,
    'break_finish', tpb.break_finish,
    'break_reason', tpb.break_reason
  )) FILTER (WHERE tpb.id IS NOT NULL) as breaks,
  json_agg(DISTINCT jsonb_build_object(
    'id', tuf.id,
    'large_plant_id', tuf.large_plant_id,
    'display_order', tuf.display_order
  )) FILTER (WHERE tuf.id IS NOT NULL) as used_fleet,
  json_agg(DISTINCT jsonb_build_object(
    'id', tmf.id,
    'large_plant_id', tmf.large_plant_id,
    'display_order', tmf.display_order
  )) FILTER (WHERE tmf.id IS NOT NULL) as mobilised_fleet
FROM time_periods tp
LEFT JOIN time_period_breaks tpb ON tp.id = tpb.time_period_id
LEFT JOIN time_period_used_fleet tuf ON tp.id = tuf.time_period_id
LEFT JOIN time_period_mobilised_fleet tmf ON tp.id = tmf.time_period_id
WHERE tp.id = 'uuid'
GROUP BY tp.id;
```

---

## Application Code Impact

### Saving a Time Period

#### Current Design ❌
```dart
// Save time period
await saveTimePeriod(data);

// Save used fleet (must map to numbered columns)
final fleetData = {
  'time_period_id': periodId,
  'large_plant_id_1': usedFleet.length > 0 ? usedFleet[0] : null,
  'large_plant_id_2': usedFleet.length > 1 ? usedFleet[1] : null,
  'large_plant_id_3': usedFleet.length > 2 ? usedFleet[2] : null,
  'large_plant_id_4': usedFleet.length > 3 ? usedFleet[3] : null,
  'large_plant_id_5': usedFleet.length > 4 ? usedFleet[4] : null,
  'large_plant_id_6': usedFleet.length > 5 ? usedFleet[5] : null,
};
await saveUsedFleet(fleetData);
```

#### Recommended Design ✅
```dart
// Save time period
await saveTimePeriod(data);

// Save used fleet (simple loop)
for (int i = 0; i < usedFleet.length; i++) {
  await saveUsedFleetItem({
    'time_period_id': periodId,
    'large_plant_id': usedFleet[i],
    'display_order': i + 1,
  });
}

// Or batch insert (even better)
await batchSaveUsedFleet(
  usedFleet.map((fleetId, index) => {
    'time_period_id': periodId,
    'large_plant_id': fleetId,
    'display_order': index + 1,
  }).toList()
);
```

---

## Performance Considerations

### Storage Efficiency

| Scenario | Current Design | Recommended Design |
|----------|---------------|-------------------|
| Time period with 2 fleet items | Stores 6 columns (4 null) | Stores 2 rows |
| Time period with 6 fleet items | Stores 6 columns | Stores 6 rows |
| Time period with 10 fleet items | ❌ Can't store | ✅ Stores 10 rows |

### Query Performance

- **Current**: Must scan 6 columns per row
- **Recommended**: Indexed foreign key, single column lookup

---

## Migration Path

1. ✅ Create new normalized tables
2. ✅ Migrate existing data
3. ✅ Update application code
4. ✅ Test thoroughly
5. ✅ Drop old tables (after verification)

See `MIGRATION_TO_NORMALIZED_SCHEMA.sql` for complete migration script.

---

## Conclusion

The recommended normalized design:
- ✅ Eliminates numbered columns
- ✅ Supports unlimited related items
- ✅ Includes all original fields
- ✅ Provides better query capabilities
- ✅ Scales for future growth
- ✅ Follows database best practices

**Recommendation**: Migrate to the normalized schema for long-term maintainability and scalability.

