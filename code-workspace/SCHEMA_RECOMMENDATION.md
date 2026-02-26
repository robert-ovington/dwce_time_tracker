# Database Schema Recommendation for Time Periods

## Executive Summary

Your current schema has fragmented into multiple tables, but still uses **numbered columns** (e.g., `large_plant_id_1`, `large_plant_id_2`) which is not normalized. This document proposes a **properly normalized** design that:

1. ✅ Eliminates numbered columns
2. ✅ Supports unlimited fleet items per time period
3. ✅ Properly tracks breaks, allowances, and revisions
4. ✅ Maintains referential integrity
5. ✅ Supports future growth

---

## Recommended Schema Design

### 1. Main Time Periods Table

```sql
CREATE TABLE public.time_periods (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  project_id UUID NULL,
  mechanic_large_plant_id UUID NULL, -- For mechanic mode
  
  -- Core time tracking
  work_date DATE NOT NULL,
  start_time TIMESTAMP WITH TIME ZONE NULL,
  finish_time TIMESTAMP WITH TIME ZONE NULL,
  
  -- Status and approval workflow
  status public.approval_status NOT NULL DEFAULT 'draft'::approval_status,
  approved_by UUID NULL,
  approved_at TIMESTAMP WITH TIME ZONE NULL,
  supervisor_id UUID NULL, -- Supervisor who approved
  supervisor_time_stamp TIMESTAMP WITH TIME ZONE NULL,
  admin_id UUID NULL, -- Admin who approved
  admin_time_stamp TIMESTAMP WITH TIME ZONE NULL,
  
  -- Travel allowances (stored as minutes for consistency)
  travel_to_site_min INTEGER NULL DEFAULT 0,
  travel_from_site_min INTEGER NULL DEFAULT 0,
  distance_from_home NUMERIC(10, 2) NULL,
  travel_time_text TEXT NULL, -- Formatted display text (e.g., "1h 23m")
  
  -- Other allowances
  on_call BOOLEAN NULL DEFAULT false,
  misc_allowance_min INTEGER NULL DEFAULT 0,
  allowance_holiday_hours_min INTEGER NULL DEFAULT 0,
  allowance_non_worked_ft_min INTEGER NULL DEFAULT 0, -- Full Time
  allowance_non_worked_th_min INTEGER NULL DEFAULT 0, -- Part Time
  allowance_non_worked_dt_min INTEGER NULL DEFAULT 0, -- Day Time
  
  -- Absenteeism
  user_absenteeism_reason TEXT NULL,
  absenteeism_notice_date DATE NULL,
  supervisor_absenteeism_reason TEXT NULL,
  
  -- Concrete/Materials
  concrete_ticket_no INTEGER NULL,
  concrete_mix_type TEXT NULL,
  concrete_qty NUMERIC(10, 2) NULL,
  
  -- Submission metadata
  comments TEXT NULL,
  submission_lat DOUBLE PRECISION NULL,
  submission_lng DOUBLE PRECISION NULL,
  submission_gps_accuracy INTEGER NULL,
  submission_datetime TIMESTAMP WITH TIME ZONE NULL DEFAULT now(),
  
  -- Revision tracking
  revision_number INTEGER NOT NULL DEFAULT 0,
  last_revised_at TIMESTAMP WITH TIME ZONE NULL,
  last_revised_by UUID NULL,
  
  -- Offline support
  offline_created BOOLEAN NULL DEFAULT false,
  synced BOOLEAN NULL DEFAULT false,
  offline_id TEXT NULL,
  
  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_periods_pkey PRIMARY KEY (id),
  CONSTRAINT time_periods_user_id_fkey FOREIGN KEY (user_id) 
    REFERENCES public.users_data(user_id) ON DELETE RESTRICT,
  CONSTRAINT time_periods_project_id_fkey FOREIGN KEY (project_id) 
    REFERENCES public.projects(id) ON DELETE SET NULL,
  CONSTRAINT time_periods_approved_by_fkey FOREIGN KEY (approved_by) 
    REFERENCES public.users_data(user_id) ON DELETE SET NULL,
  CONSTRAINT time_periods_supervisor_id_fkey FOREIGN KEY (supervisor_id) 
    REFERENCES public.users_data(user_id) ON DELETE SET NULL,
  CONSTRAINT time_periods_admin_id_fkey FOREIGN KEY (admin_id) 
    REFERENCES public.users_data(user_id) ON DELETE SET NULL,
  CONSTRAINT time_periods_last_revised_by_fkey FOREIGN KEY (last_revised_by) 
    REFERENCES public.users_data(user_id) ON DELETE SET NULL,
  CONSTRAINT time_periods_mechanic_large_plant_id_fkey FOREIGN KEY (mechanic_large_plant_id) 
    REFERENCES public.large_plant(id) ON DELETE SET NULL,
  CONSTRAINT time_periods_finish_after_start CHECK (
    finish_time IS NULL OR start_time IS NULL OR finish_time >= start_time
  ),
  CONSTRAINT time_periods_same_day CHECK (
    finish_time IS NULL OR start_time IS NULL OR 
    DATE(finish_time) = DATE(start_time)
  )
) TABLESPACE pg_default;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_time_periods_user_id 
  ON public.time_periods USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_time_periods_project_id 
  ON public.time_periods USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_time_periods_work_date 
  ON public.time_periods USING btree (work_date DESC);
CREATE INDEX IF NOT EXISTS idx_time_periods_status 
  ON public.time_periods USING btree (status);
CREATE INDEX IF NOT EXISTS idx_time_periods_mechanic_large_plant_id 
  ON public.time_periods USING btree (mechanic_large_plant_id);
CREATE INDEX IF NOT EXISTS idx_time_periods_offline_sync 
  ON public.time_periods USING btree (offline_created, synced) 
  WHERE offline_created = true AND synced = false;
```

---

### 2. Breaks Table (Normalized)

**Problem with original design**: Using `break_1_start`, `break_2_start`, etc. limits you to 3 breaks and makes queries difficult.

**Solution**: One row per break, unlimited breaks per time period.

```sql
CREATE TABLE public.time_period_breaks (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  break_start TIMESTAMP WITH TIME ZONE NOT NULL,
  break_finish TIMESTAMP WITH TIME ZONE NULL,
  break_reason TEXT NULL,
  display_order INTEGER NOT NULL DEFAULT 0, -- For UI ordering (1, 2, 3, etc.)
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_breaks_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_breaks_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_breaks_finish_after_start CHECK (
    break_finish IS NULL OR break_start IS NULL OR break_finish >= break_start
  )
) TABLESPACE pg_default;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_time_period_breaks_time_period_id 
  ON public.time_period_breaks USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_breaks_display_order 
  ON public.time_period_breaks USING btree (time_period_id, display_order);
```

---

### 3. Used Fleet Table (Normalized)

**Problem with current design**: `large_plant_id_1` through `large_plant_id_6` limits you to 6 items and makes queries difficult.

**Solution**: One row per fleet item, unlimited items per time period.

```sql
CREATE TABLE public.time_period_used_fleet (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  large_plant_id UUID NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0, -- For UI ordering (1, 2, 3, etc.)
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_used_fleet_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_used_fleet_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_used_fleet_large_plant_id_fkey FOREIGN KEY (large_plant_id) 
    REFERENCES public.large_plant(id) ON DELETE RESTRICT,
  CONSTRAINT time_period_used_fleet_unique_per_period UNIQUE (time_period_id, large_plant_id) -- Prevent duplicates
) TABLESPACE pg_default;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_time_period_used_fleet_time_period_id 
  ON public.time_period_used_fleet USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_used_fleet_large_plant_id 
  ON public.time_period_used_fleet USING btree (large_plant_id);
CREATE INDEX IF NOT EXISTS idx_time_period_used_fleet_display_order 
  ON public.time_period_used_fleet USING btree (time_period_id, display_order);
```

---

### 4. Mobilised Fleet Table (Normalized)

Same normalization approach as used fleet.

```sql
CREATE TABLE public.time_period_mobilised_fleet (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  large_plant_id UUID NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0, -- For UI ordering (1, 2, 3, etc.)
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_mobilised_fleet_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_mobilised_fleet_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_mobilised_fleet_large_plant_id_fkey FOREIGN KEY (large_plant_id) 
    REFERENCES public.large_plant(id) ON DELETE RESTRICT,
  CONSTRAINT time_period_mobilised_fleet_unique_per_period UNIQUE (time_period_id, large_plant_id) -- Prevent duplicates
) TABLESPACE pg_default;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_time_period_mobilised_fleet_time_period_id 
  ON public.time_period_mobilised_fleet USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_mobilised_fleet_large_plant_id 
  ON public.time_period_mobilised_fleet USING btree (large_plant_id);
CREATE INDEX IF NOT EXISTS idx_time_period_mobilised_fleet_display_order 
  ON public.time_period_mobilised_fleet USING btree (time_period_id, display_order);
```

---

### 5. Revision History Table (Improved)

**Problem with current design**: No link to `time_period_id`, making it hard to query revisions for a specific time period.

**Solution**: Link to `time_period_id` and add more context.

```sql
CREATE TABLE public.time_period_revisions (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  revision_number INTEGER NOT NULL,
  changed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  changed_by UUID NOT NULL, -- User who made the change
  user_name TEXT NULL, -- Denormalized for quick display
  field_name TEXT NOT NULL, -- Which field changed
  old_value TEXT NULL,
  new_value TEXT NULL,
  change_reason TEXT NULL,
  original_submission BOOLEAN NOT NULL DEFAULT false, -- True for initial creation
  
  CONSTRAINT time_period_revisions_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_revisions_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_revisions_changed_by_fkey FOREIGN KEY (changed_by) 
    REFERENCES public.users_data(user_id) ON DELETE RESTRICT
) TABLESPACE pg_default;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_time_period_id 
  ON public.time_period_revisions USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_revision_number 
  ON public.time_period_revisions USING btree (time_period_id, revision_number DESC);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_changed_at 
  ON public.time_period_revisions USING btree (changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_changed_by 
  ON public.time_period_revisions USING btree (changed_by);
```

---

## Key Improvements

### ✅ Normalization Benefits

1. **Unlimited Fleet Items**: No more 6-item limit. Add as many as needed.
2. **Unlimited Breaks**: No more 3-break limit.
3. **Easier Queries**: 
   ```sql
   -- Find all time periods using a specific fleet item
   SELECT tp.* FROM time_periods tp
   JOIN time_period_used_fleet tuf ON tp.id = tuf.time_period_id
   WHERE tuf.large_plant_id = 'some-uuid';
   
   -- Count fleet usage
   SELECT lp.plant_no, COUNT(*) as usage_count
   FROM large_plant lp
   JOIN time_period_used_fleet tuf ON lp.id = tuf.large_plant_id
   GROUP BY lp.plant_no
   ORDER BY usage_count DESC;
   ```

4. **Better Data Integrity**: Unique constraints prevent duplicate fleet entries per time period.

### ✅ Missing Fields Added

- `supervisor_id` and `supervisor_time_stamp`
- `admin_id` and `admin_time_stamp`
- `user_absenteeism_reason` and `absenteeism_notice_date`
- `supervisor_absenteeism_reason`
- `allowance_holiday_hours_min`
- `allowance_non_worked_ft_min`, `allowance_non_worked_th_min`, `allowance_non_worked_dt_min`
- `submission_datetime`

### ✅ Better Revision Tracking

- Links to `time_period_id` for easy querying
- Tracks `changed_by` user
- Supports multiple revisions per time period

---

## Migration Strategy

### Option 1: Clean Migration (Recommended for Development)

1. Create new tables with new names
2. Update application code to use new schema
3. Migrate existing data (if any)
4. Drop old tables

### Option 2: Gradual Migration (For Production)

1. Create new tables alongside old ones
2. Update application to write to both schemas
3. Migrate existing data
4. Switch reads to new schema
5. Drop old tables

---

## Example Queries

### Get Time Period with All Related Data

```sql
SELECT 
  tp.*,
  json_agg(DISTINCT jsonb_build_object(
    'id', tpb.id,
    'break_start', tpb.break_start,
    'break_finish', tpb.break_finish,
    'break_reason', tpb.break_reason,
    'display_order', tpb.display_order
  )) FILTER (WHERE tpb.id IS NOT NULL) as breaks,
  json_agg(DISTINCT jsonb_build_object(
    'id', tuf.id,
    'large_plant_id', tuf.large_plant_id,
    'plant_no', lp_used.plant_no,
    'short_description', lp_used.short_description,
    'display_order', tuf.display_order
  )) FILTER (WHERE tuf.id IS NOT NULL) as used_fleet,
  json_agg(DISTINCT jsonb_build_object(
    'id', tmf.id,
    'large_plant_id', tmf.large_plant_id,
    'plant_no', lp_mob.plant_no,
    'short_description', lp_mob.short_description,
    'display_order', tmf.display_order
  )) FILTER (WHERE tmf.id IS NOT NULL) as mobilised_fleet
FROM time_periods tp
LEFT JOIN time_period_breaks tpb ON tp.id = tpb.time_period_id
LEFT JOIN time_period_used_fleet tuf ON tp.id = tuf.time_period_id
LEFT JOIN large_plant lp_used ON tuf.large_plant_id = lp_used.id
LEFT JOIN time_period_mobilised_fleet tmf ON tp.id = tmf.time_period_id
LEFT JOIN large_plant lp_mob ON tmf.large_plant_id = lp_mob.id
WHERE tp.id = 'some-uuid'
GROUP BY tp.id;
```

### Get Revision History for a Time Period

```sql
SELECT 
  tr.*,
  ud.display_name as changed_by_name
FROM time_period_revisions tr
JOIN users_data ud ON tr.changed_by = ud.user_id
WHERE tr.time_period_id = 'some-uuid'
ORDER BY tr.revision_number ASC, tr.changed_at ASC;
```

---

## Recommendations for Application Code

1. **Use Transactions**: When saving a time period, wrap all inserts (time_period, breaks, fleet) in a transaction.

2. **Batch Inserts**: Use `INSERT ... VALUES` with multiple rows for fleet/breaks instead of individual inserts.

3. **Display Order**: Maintain `display_order` based on UI position (1, 2, 3, etc.) for consistent ordering.

4. **Validation**: 
   - Check for duplicate fleet items before inserting
   - Validate break times are within start/finish time
   - Ensure finish_time > start_time

5. **Revision Tracking**: 
   - Increment `revision_number` on each update
   - Log each field change to `time_period_revisions`
   - Set `last_revised_at` and `last_revised_by` on updates

---

## Summary

This normalized design:
- ✅ Eliminates numbered columns
- ✅ Supports unlimited related items (fleet, breaks)
- ✅ Maintains referential integrity
- ✅ Includes all fields from your original design
- ✅ Provides better querying capabilities
- ✅ Scales for future growth
- ✅ Follows database best practices

The trade-off is slightly more complex queries (using JOINs), but this is standard practice and provides much better flexibility and maintainability.

