# Step-by-Step Implementation Guide

## Overview

This guide walks you through implementing the new normalized time periods schema. Since existing tables contain no data, we can safely drop and recreate them.

**Estimated Time**: 30-60 minutes  
**Prerequisites**: 
- Access to Supabase dashboard or SQL editor
- Database admin permissions
- Backup of current schema (for reference)

---

## Step 1: Review Current Schema

### 1.1 Identify Existing Tables

Run this query to see what time period related tables exist:

```sql
SELECT 
  table_name,
  table_schema
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name LIKE '%time%'
  OR table_name LIKE '%period%'
  OR table_name LIKE '%fleet%'
ORDER BY table_name;
```

**Expected tables to find:**
- `time_periods`
- `time_used_large_plant`
- `time_mobilised_large_plant`
- `time_period_revision` (or similar)

### 1.2 Verify No Data Exists

```sql
-- Check row counts
SELECT 
  'time_periods' as table_name, COUNT(*) as row_count FROM time_periods
UNION ALL
SELECT 'time_used_large_plant', COUNT(*) FROM time_used_large_plant
UNION ALL
SELECT 'time_mobilised_large_plant', COUNT(*) FROM time_mobilised_large_plant
UNION ALL
SELECT 'time_period_revision', COUNT(*) FROM time_period_revision;
```

**Expected result**: All counts should be 0.

---

## Step 2: Backup Current Schema (Optional but Recommended)

Even with no data, it's good practice to backup the schema structure.

### 2.1 Export Schema

In Supabase Dashboard:
1. Go to **SQL Editor**
2. Run this to get table definitions:

```sql
-- Get CREATE TABLE statements
SELECT 
  'CREATE TABLE ' || table_name || ' (' || E'\n' ||
  string_agg(
    '  ' || column_name || ' ' || data_type || 
    CASE 
      WHEN character_maximum_length IS NOT NULL 
      THEN '(' || character_maximum_length || ')'
      ELSE ''
    END ||
    CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END,
    ',' || E'\n'
  ) || E'\n' || ');'
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('time_periods', 'time_used_large_plant', 'time_mobilised_large_plant', 'time_period_revision')
GROUP BY table_name;
```

Or simply take screenshots of the table structures in the Supabase Table Editor.

---

## Step 3: Drop Existing Tables

### 3.1 Drop in Correct Order (Respect Foreign Keys)

```sql
BEGIN;

-- Drop dependent tables first
DROP TABLE IF EXISTS public.time_used_large_plant CASCADE;
DROP TABLE IF EXISTS public.time_mobilised_large_plant CASCADE;
DROP TABLE IF EXISTS public.time_period_revision CASCADE;

-- Drop main table last
DROP TABLE IF EXISTS public.time_periods CASCADE;

COMMIT;
```

**Note**: `CASCADE` will also drop any dependent objects (indexes, constraints, etc.)

### 3.2 Verify Tables Dropped

```sql
SELECT table_name 
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('time_periods', 'time_used_large_plant', 'time_mobilised_large_plant', 'time_period_revision');
```

**Expected result**: No rows returned.

---

## Step 4: Create New Normalized Tables

### 4.1 Create Main Time Periods Table

```sql
CREATE TABLE public.time_periods (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  project_id UUID NULL,
  mechanic_large_plant_id UUID NULL,
  
  -- Core time tracking
  work_date DATE NOT NULL,
  start_time TIMESTAMP WITH TIME ZONE NULL,
  finish_time TIMESTAMP WITH TIME ZONE NULL,
  
  -- Approval workflow status
  status public.approval_status NOT NULL DEFAULT 'draft'::approval_status,
  
  -- Approval tracking
  submitted_at TIMESTAMP WITH TIME ZONE NULL,
  submitted_by UUID NULL,
  supervisor_id UUID NULL,
  supervisor_approved_at TIMESTAMP WITH TIME ZONE NULL,
  supervisor_edited_before_approval BOOLEAN NULL DEFAULT false,
  admin_id UUID NULL,
  admin_approved_at TIMESTAMP WITH TIME ZONE NULL,
  admin_edited_before_approval BOOLEAN NULL DEFAULT false,
  approved_by UUID NULL,
  approved_at TIMESTAMP WITH TIME ZONE NULL,
  
  -- Travel allowances (stored as minutes)
  travel_to_site_min INTEGER NULL DEFAULT 0,
  travel_from_site_min INTEGER NULL DEFAULT 0,
  distance_from_home NUMERIC(10, 2) NULL,
  travel_time_text TEXT NULL,
  
  -- Other allowances
  on_call BOOLEAN NULL DEFAULT false,
  misc_allowance_min INTEGER NULL DEFAULT 0,
  allowance_holiday_hours_min INTEGER NULL DEFAULT 0,
  allowance_non_worked_ft_min INTEGER NULL DEFAULT 0,
  allowance_non_worked_th_min INTEGER NULL DEFAULT 0,
  allowance_non_worked_dt_min INTEGER NULL DEFAULT 0,
  
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
  CONSTRAINT time_periods_submitted_by_fkey FOREIGN KEY (submitted_by) 
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
```

### 4.2 Create Breaks Table

```sql
CREATE TABLE public.time_period_breaks (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  break_start TIMESTAMP WITH TIME ZONE NOT NULL,
  break_finish TIMESTAMP WITH TIME ZONE NULL,
  break_reason TEXT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_breaks_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_breaks_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_breaks_finish_after_start CHECK (
    break_finish IS NULL OR break_start IS NULL OR break_finish >= break_start
  )
) TABLESPACE pg_default;
```

### 4.3 Create Used Fleet Table

```sql
CREATE TABLE public.time_period_used_fleet (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  large_plant_id UUID NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_used_fleet_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_used_fleet_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_used_fleet_large_plant_id_fkey FOREIGN KEY (large_plant_id) 
    REFERENCES public.large_plant(id) ON DELETE RESTRICT,
  CONSTRAINT time_period_used_fleet_unique_per_period UNIQUE (time_period_id, large_plant_id)
) TABLESPACE pg_default;
```

### 4.4 Create Mobilised Fleet Table

```sql
CREATE TABLE public.time_period_mobilised_fleet (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  large_plant_id UUID NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  CONSTRAINT time_period_mobilised_fleet_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_mobilised_fleet_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_mobilised_fleet_large_plant_id_fkey FOREIGN KEY (large_plant_id) 
    REFERENCES public.large_plant(id) ON DELETE RESTRICT,
  CONSTRAINT time_period_mobilised_fleet_unique_per_period UNIQUE (time_period_id, large_plant_id)
) TABLESPACE pg_default;
```

### 4.5 Create Pay Rates Table

```sql
CREATE TABLE public.time_period_pay_rates (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  pay_rate_type TEXT NOT NULL,
  hours NUMERIC(10, 2) NOT NULL DEFAULT 0,
  minutes INTEGER NULL,
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
  CONSTRAINT time_period_pay_rates_15min_increment CHECK (
    (hours * 4)::INTEGER = (hours * 4) AND
    (minutes IS NULL OR minutes IN (0, 15, 30, 45))
  )
) TABLESPACE pg_default;
```

### 4.6 Create Revisions Table

```sql
CREATE TABLE public.time_period_revisions (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  revision_number INTEGER NOT NULL,
  changed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  changed_by UUID NOT NULL,
  changed_by_name TEXT NULL,
  changed_by_role TEXT NULL,
  change_type TEXT NOT NULL,
  workflow_stage TEXT NOT NULL,
  field_name TEXT NOT NULL,
  old_value TEXT NULL,
  new_value TEXT NULL,
  change_reason TEXT NULL,
  is_revision BOOLEAN NOT NULL DEFAULT false,
  is_approval BOOLEAN NOT NULL DEFAULT false,
  is_edit BOOLEAN NOT NULL DEFAULT false,
  original_submission BOOLEAN NOT NULL DEFAULT false,
  
  CONSTRAINT time_period_revisions_pkey PRIMARY KEY (id),
  CONSTRAINT time_period_revisions_time_period_id_fkey FOREIGN KEY (time_period_id) 
    REFERENCES public.time_periods(id) ON DELETE CASCADE,
  CONSTRAINT time_period_revisions_changed_by_fkey FOREIGN KEY (changed_by) 
    REFERENCES public.users_data(user_id) ON DELETE RESTRICT,
  CONSTRAINT time_period_revisions_change_type_check CHECK (
    change_type IN ('user_edit', 'supervisor_edit', 'admin_edit', 
                    'supervisor_approval', 'admin_approval', 'user_submission')
  ),
  CONSTRAINT time_period_revisions_workflow_stage_check CHECK (
    workflow_stage IN ('draft', 'submitted', 'supervisor_review', 'admin_review', 'approved')
  )
) TABLESPACE pg_default;
```

---

## Step 5: Create Indexes

### 5.1 Time Periods Indexes

```sql
CREATE INDEX idx_time_periods_user_id 
  ON public.time_periods USING btree (user_id);

CREATE INDEX idx_time_periods_project_id 
  ON public.time_periods USING btree (project_id);

CREATE INDEX idx_time_periods_work_date 
  ON public.time_periods USING btree (work_date DESC);

CREATE INDEX idx_time_periods_status 
  ON public.time_periods USING btree (status);

CREATE INDEX idx_time_periods_submitted_at 
  ON public.time_periods USING btree (submitted_at DESC) 
  WHERE submitted_at IS NOT NULL;

CREATE INDEX idx_time_periods_supervisor_pending 
  ON public.time_periods USING btree (status, submitted_at) 
  WHERE status = 'submitted';

CREATE INDEX idx_time_periods_mechanic_large_plant_id 
  ON public.time_periods USING btree (mechanic_large_plant_id);

CREATE INDEX idx_time_periods_offline_sync 
  ON public.time_periods USING btree (offline_created, synced) 
  WHERE offline_created = true AND synced = false;
```

### 5.2 Breaks Indexes

```sql
CREATE INDEX idx_time_period_breaks_time_period_id 
  ON public.time_period_breaks USING btree (time_period_id);

CREATE INDEX idx_time_period_breaks_display_order 
  ON public.time_period_breaks USING btree (time_period_id, display_order);
```

### 5.3 Used Fleet Indexes

```sql
CREATE INDEX idx_time_period_used_fleet_time_period_id 
  ON public.time_period_used_fleet USING btree (time_period_id);

CREATE INDEX idx_time_period_used_fleet_large_plant_id 
  ON public.time_period_used_fleet USING btree (large_plant_id);

CREATE INDEX idx_time_period_used_fleet_display_order 
  ON public.time_period_used_fleet USING btree (time_period_id, display_order);
```

### 5.4 Mobilised Fleet Indexes

```sql
CREATE INDEX idx_time_period_mobilised_fleet_time_period_id 
  ON public.time_period_mobilised_fleet USING btree (time_period_id);

CREATE INDEX idx_time_period_mobilised_fleet_large_plant_id 
  ON public.time_period_mobilised_fleet USING btree (large_plant_id);

CREATE INDEX idx_time_period_mobilised_fleet_display_order 
  ON public.time_period_mobilised_fleet USING btree (time_period_id, display_order);
```

### 5.5 Pay Rates Indexes

```sql
CREATE INDEX idx_time_period_pay_rates_time_period_id 
  ON public.time_period_pay_rates USING btree (time_period_id);

CREATE INDEX idx_time_period_pay_rates_type 
  ON public.time_period_pay_rates USING btree (pay_rate_type);

CREATE INDEX idx_time_period_pay_rates_time_period_type 
  ON public.time_period_pay_rates USING btree (time_period_id, pay_rate_type);
```

### 5.6 Revisions Indexes

```sql
CREATE INDEX idx_time_period_revisions_time_period_id 
  ON public.time_period_revisions USING btree (time_period_id);

CREATE INDEX idx_time_period_revisions_revision_number 
  ON public.time_period_revisions USING btree (time_period_id, revision_number DESC);

CREATE INDEX idx_time_period_revisions_changed_at 
  ON public.time_period_revisions USING btree (changed_at DESC);

CREATE INDEX idx_time_period_revisions_changed_by 
  ON public.time_period_revisions USING btree (changed_by);

CREATE INDEX idx_time_period_revisions_is_revision 
  ON public.time_period_revisions USING btree (time_period_id, is_revision) 
  WHERE is_revision = true;

CREATE INDEX idx_time_period_revisions_change_type 
  ON public.time_period_revisions USING btree (time_period_id, change_type);
```

---

## Step 6: Update System Settings

### 6.1 Add Limit Columns

```sql
ALTER TABLE public.system_settings
  ADD COLUMN IF NOT EXISTS max_breaks_per_period INTEGER NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS max_used_fleet_per_period INTEGER NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS max_mobilised_fleet_per_period INTEGER NULL DEFAULT 4;
```

### 6.2 Add Constraints

```sql
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
```

### 6.3 Set Default Values

```sql
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

## Step 7: Verify Schema Creation

### 7.1 Check All Tables Exist

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'time_periods',
    'time_period_breaks',
    'time_period_used_fleet',
    'time_period_mobilised_fleet',
    'time_period_pay_rates',
    'time_period_revisions'
  )
ORDER BY table_name;
```

**Expected result**: 6 tables listed.

### 7.2 Check Foreign Keys

```sql
SELECT
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND tc.table_name LIKE 'time_period%'
ORDER BY tc.table_name, kcu.column_name;
```

**Expected result**: Multiple foreign key relationships listed.

### 7.3 Check Indexes

```sql
SELECT
  schemaname,
  tablename,
  indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename LIKE 'time_period%'
ORDER BY tablename, indexname;
```

**Expected result**: Multiple indexes listed for each table.

---

## Step 8: Test Basic Operations

### 8.1 Test Insert (Time Period)

```sql
-- Get a test user_id and project_id first
DO $$
DECLARE
  test_user_id UUID;
  test_project_id UUID;
  test_period_id UUID;
BEGIN
  -- Get first user and project
  SELECT user_id INTO test_user_id FROM users_data LIMIT 1;
  SELECT id INTO test_project_id FROM projects WHERE is_active = true LIMIT 1;
  
  -- Insert test time period
  INSERT INTO time_periods (
    user_id,
    project_id,
    work_date,
    start_time,
    finish_time,
    status
  ) VALUES (
    test_user_id,
    test_project_id,
    CURRENT_DATE,
    CURRENT_DATE + INTERVAL '8 hours',
    CURRENT_DATE + INTERVAL '17 hours',
    'draft'
  ) RETURNING id INTO test_period_id;
  
  RAISE NOTICE 'Test time period created with ID: %', test_period_id;
  
  -- Clean up
  DELETE FROM time_periods WHERE id = test_period_id;
  
  RAISE NOTICE 'Test completed successfully';
END $$;
```

### 8.2 Test Insert (Related Data)

```sql
DO $$
DECLARE
  test_user_id UUID;
  test_project_id UUID;
  test_plant_id UUID;
  test_period_id UUID;
BEGIN
  -- Get test data
  SELECT user_id INTO test_user_id FROM users_data LIMIT 1;
  SELECT id INTO test_project_id FROM projects WHERE is_active = true LIMIT 1;
  SELECT id INTO test_plant_id FROM large_plant LIMIT 1;
  
  -- Insert time period
  INSERT INTO time_periods (
    user_id, project_id, work_date, start_time, finish_time, status
  ) VALUES (
    test_user_id, test_project_id, CURRENT_DATE,
    CURRENT_DATE + INTERVAL '8 hours', CURRENT_DATE + INTERVAL '17 hours', 'draft'
  ) RETURNING id INTO test_period_id;
  
  -- Insert break
  INSERT INTO time_period_breaks (
    time_period_id, break_start, break_finish, display_order
  ) VALUES (
    test_period_id,
    CURRENT_DATE + INTERVAL '12 hours',
    CURRENT_DATE + INTERVAL '12 hours 30 minutes',
    1
  );
  
  -- Insert used fleet
  INSERT INTO time_period_used_fleet (
    time_period_id, large_plant_id, display_order
  ) VALUES (
    test_period_id, test_plant_id, 1
  );
  
  -- Insert pay rate
  INSERT INTO time_period_pay_rates (
    time_period_id, pay_rate_type, hours
  ) VALUES (
    test_period_id, 'ft', 8.0
  );
  
  RAISE NOTICE 'Test data inserted successfully for period: %', test_period_id;
  
  -- Clean up (CASCADE will delete related records)
  DELETE FROM time_periods WHERE id = test_period_id;
  
  RAISE NOTICE 'Test completed successfully';
END $$;
```

---

## Step 9: Set Up Row-Level Security (RLS)

### 9.1 Enable RLS on All Tables

```sql
ALTER TABLE public.time_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_breaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_used_fleet ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_mobilised_fleet ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_pay_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_period_revisions ENABLE ROW LEVEL SECURITY;
```

### 9.2 Create RLS Policies

**Note**: Adjust these policies based on your security requirements.

```sql
-- Users can view their own time periods
CREATE POLICY "Users can view own time periods"
  ON public.time_periods FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own time periods
CREATE POLICY "Users can insert own time periods"
  ON public.time_periods FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own draft time periods
CREATE POLICY "Users can update own draft time periods"
  ON public.time_periods FOR UPDATE
  USING (auth.uid() = user_id AND status = 'draft');

-- Supervisors can view submitted time periods
CREATE POLICY "Supervisors can view submitted time periods"
  ON public.time_periods FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM users_setup
      WHERE user_id = auth.uid()
      AND (role = 'Supervisor' OR role = 'Manager' OR security <= 4)
    )
  );

-- Similar policies for related tables...
-- (Add policies for breaks, fleet, pay_rates, revisions as needed)
```

**Important**: Review and customize RLS policies based on your specific security requirements.

---

## Step 10: Update Application Code

### 10.1 Update Flutter Code

Refer to these documents for code examples:
- `SCHEMA_WITH_PAY_RATES.md` - Pay rate saving/loading
- `WORKFLOW_IMPLEMENTATION_GUIDE.md` - Workflow implementation
- `TIME_VALIDATION_RULES.md` - Time validation helpers

### 10.2 Key Code Changes Needed

1. **Update time period save logic**:
   - Save breaks to `time_period_breaks` (one row per break)
   - Save fleet to `time_period_used_fleet` and `time_period_mobilised_fleet` (one row per item)
   - Save pay rates to `time_period_pay_rates` (one row per type)

2. **Update time period load logic**:
   - Join related tables to get breaks, fleet, pay rates
   - Use JSON aggregation for related data

3. **Add system limits reading**:
   - Read `max_breaks_per_period`, `max_used_fleet_per_period`, `max_mobilised_fleet_per_period` from `system_settings`

4. **Add time validation**:
   - Implement 15-minute increment validation
   - Use helper functions from `TIME_VALIDATION_RULES.md`

---

## Step 11: Final Verification

### 11.1 Complete Schema Check

Run this comprehensive check:

```sql
SELECT 
  'Tables' as check_type,
  COUNT(*) as count
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name LIKE 'time_period%'

UNION ALL

SELECT 
  'Indexes',
  COUNT(*)
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename LIKE 'time_period%'

UNION ALL

SELECT 
  'Foreign Keys',
  COUNT(*)
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND constraint_type = 'FOREIGN KEY'
  AND table_name LIKE 'time_period%';
```

### 11.2 Test Complete Workflow

1. Create a time period
2. Add breaks
3. Add fleet items
4. Add pay rates
5. Submit for approval
6. Verify revision tracking

---

## Troubleshooting

### Issue: Foreign Key Constraint Errors

**Solution**: Ensure referenced tables exist:
- `users_data` (for `user_id`)
- `projects` (for `project_id`)
- `large_plant` (for `large_plant_id`)

### Issue: Check Constraint Violations

**Solution**: Verify data meets constraints:
- Pay rate hours must be multiples of 0.25
- Pay rate minutes must be 0, 15, 30, or 45
- Finish time must be after start time

### Issue: RLS Blocking Access

**Solution**: Review and adjust RLS policies based on your security model.

---

## Next Steps

1. ✅ Schema created and verified
2. ⏭️ Update Flutter application code
3. ⏭️ Test end-to-end workflow
4. ⏭️ Deploy to production
5. ⏭️ Monitor and optimize

---

## Quick Reference

**All SQL in one file**: See `MIGRATION_COMPLETE_SCHEMA.sql` for a complete script that does everything in one go.

**Documentation**:
- `SCHEMA_WITH_PAY_RATES.md` - Complete schema design
- `SCHEMA_WITH_APPROVAL_WORKFLOW.md` - Workflow details
- `TIME_VALIDATION_RULES.md` - Validation rules and code
- `WORKFLOW_IMPLEMENTATION_GUIDE.md` - Implementation examples

