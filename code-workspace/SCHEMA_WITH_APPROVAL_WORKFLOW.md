# Database Schema with Approval Workflow Support

## Approval Workflow Stages

1. **Draft/Edit (User)**: User submits and can edit without triggering revisions
2. **Supervisor Approval**: Supervisor/Manager approves without triggering revision
3. **Supervisor Edit**: Supervisor/Manager edits before approving → **triggers revision**
4. **Admin Approval**: Administrator approves supervisor-approved period → **no revision**
5. **Admin Edit**: Administrator edits before approving → **triggers revision**

---

## Updated Schema Design

### 1. Enhanced Time Periods Table

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
  -- Status values: 'draft', 'submitted', 'supervisor_approved', 'admin_approved', 'rejected'
  
  -- Approval tracking (separate from revisions)
  submitted_at TIMESTAMP WITH TIME ZONE NULL, -- When user first submitted
  submitted_by UUID NULL, -- Usually same as user_id, but tracks who submitted
  
  supervisor_id UUID NULL, -- Supervisor who approved
  supervisor_approved_at TIMESTAMP WITH TIME ZONE NULL,
  supervisor_edited_before_approval BOOLEAN NULL DEFAULT false, -- True if supervisor made edits
  
  admin_id UUID NULL, -- Admin who approved
  admin_approved_at TIMESTAMP WITH TIME ZONE NULL,
  admin_edited_before_approval BOOLEAN NULL DEFAULT false, -- True if admin made edits
  
  -- Legacy fields (for backward compatibility)
  approved_by UUID NULL, -- Points to final approver (admin if exists, else supervisor)
  approved_at TIMESTAMP WITH TIME ZONE NULL, -- Final approval timestamp
  
  -- Travel allowances
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
  
  -- Revision tracking (only incremented when supervisor/admin edits)
  revision_number INTEGER NOT NULL DEFAULT 0,
  last_revised_at TIMESTAMP WITH TIME ZONE NULL,
  last_revised_by UUID NULL, -- Who made the last revision-triggering edit
  
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
  -- Note: 15-minute increment validation should be enforced at application level
  -- Minimum time period is 15 minutes (0.25 hours)
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
CREATE INDEX IF NOT EXISTS idx_time_periods_submitted_at 
  ON public.time_periods USING btree (submitted_at DESC) 
  WHERE submitted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_time_periods_supervisor_pending 
  ON public.time_periods USING btree (status, submitted_at) 
  WHERE status = 'submitted';
```

---

### 2. Enhanced Revision History Table

**Key Enhancement**: Distinguishes between different types of changes and tracks workflow stage.

```sql
CREATE TABLE public.time_period_revisions (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  time_period_id UUID NOT NULL,
  revision_number INTEGER NOT NULL, -- Links to time_periods.revision_number
  
  -- Change metadata
  changed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  changed_by UUID NOT NULL, -- User who made the change
  changed_by_name TEXT NULL, -- Denormalized for quick display
  changed_by_role TEXT NULL, -- 'user', 'supervisor', 'manager', 'admin'
  
  -- Change type tracking
  change_type TEXT NOT NULL, 
  -- Values: 'user_edit' (no revision), 'supervisor_edit' (revision), 
  --         'admin_edit' (revision), 'supervisor_approval' (no revision),
  --         'admin_approval' (no revision), 'user_submission' (no revision)
  
  -- Workflow stage when change occurred
  workflow_stage TEXT NOT NULL,
  -- Values: 'draft', 'submitted', 'supervisor_review', 'admin_review', 'approved'
  
  -- Field-level change tracking
  field_name TEXT NOT NULL, -- Which field changed
  old_value TEXT NULL,
  new_value TEXT NULL,
  change_reason TEXT NULL, -- Optional reason for the change
  
  -- Flags
  is_revision BOOLEAN NOT NULL DEFAULT false, -- True if this change triggered a revision
  is_approval BOOLEAN NOT NULL DEFAULT false, -- True if this is an approval action
  is_edit BOOLEAN NOT NULL DEFAULT false, -- True if this is an edit action
  
  -- Original submission tracking
  original_submission BOOLEAN NOT NULL DEFAULT false, -- True for initial creation
  
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

-- Indexes for reporting
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_time_period_id 
  ON public.time_period_revisions USING btree (time_period_id);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_revision_number 
  ON public.time_period_revisions USING btree (time_period_id, revision_number DESC);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_changed_at 
  ON public.time_period_revisions USING btree (changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_changed_by 
  ON public.time_period_revisions USING btree (changed_by);
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_is_revision 
  ON public.time_period_revisions USING btree (time_period_id, is_revision) 
  WHERE is_revision = true;
CREATE INDEX IF NOT EXISTS idx_time_period_revisions_change_type 
  ON public.time_period_revisions USING btree (time_period_id, change_type);
```

---

### 3. Breaks Table (Unchanged)

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

---

### 4. Used Fleet Table (Unchanged)

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

---

### 5. Mobilised Fleet Table (Unchanged)

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

---

## Workflow Implementation Logic

### Stage 1: User Submits/Edits (No Revision)

```sql
-- User edits while status = 'draft'
-- Log to revisions with:
--   change_type = 'user_edit'
--   is_revision = false
--   workflow_stage = 'draft'

-- User submits for approval
UPDATE time_periods 
SET status = 'submitted',
    submitted_at = now(),
    submitted_by = user_id
WHERE id = '...';

-- Log to revisions with:
--   change_type = 'user_submission'
--   is_revision = false
--   workflow_stage = 'submitted'
```

### Stage 2: Supervisor Approves (No Revision)

```sql
UPDATE time_periods 
SET status = 'supervisor_approved',
    supervisor_id = supervisor_user_id,
    supervisor_approved_at = now(),
    approved_by = supervisor_user_id,
    approved_at = now()
WHERE id = '...';

-- Log to revisions with:
--   change_type = 'supervisor_approval'
--   is_revision = false
--   workflow_stage = 'supervisor_review'
```

### Stage 3: Supervisor Edits Before Approval (Triggers Revision)

```sql
-- Increment revision number
UPDATE time_periods 
SET revision_number = revision_number + 1,
    last_revised_at = now(),
    last_revised_by = supervisor_user_id,
    supervisor_edited_before_approval = true
WHERE id = '...';

-- Log each field change to revisions with:
--   change_type = 'supervisor_edit'
--   is_revision = true
--   workflow_stage = 'supervisor_review'
--   revision_number = (new value)
```

### Stage 4: Admin Approves (No Revision)

```sql
UPDATE time_periods 
SET status = 'admin_approved',
    admin_id = admin_user_id,
    admin_approved_at = now(),
    approved_by = admin_user_id,
    approved_at = now()
WHERE id = '...';

-- Log to revisions with:
--   change_type = 'admin_approval'
--   is_revision = false
--   workflow_stage = 'admin_review'
```

### Stage 5: Admin Edits Before Approval (Triggers Revision)

```sql
-- Increment revision number
UPDATE time_periods 
SET revision_number = revision_number + 1,
    last_revised_at = now(),
    last_revised_by = admin_user_id,
    admin_edited_before_approval = true
WHERE id = '...';

-- Log each field change to revisions with:
--   change_type = 'admin_edit'
--   is_revision = true
--   workflow_stage = 'admin_review'
--   revision_number = (new value)
```

---

## Report Queries

### 1. User Report: Changes Made to My Submission

Shows all changes made to a user's time period, highlighting supervisor/admin edits.

```sql
SELECT 
  tp.id,
  tp.work_date,
  tp.status,
  tr.revision_number,
  tr.changed_at,
  tr.changed_by_name,
  tr.changed_by_role,
  tr.change_type,
  tr.field_name,
  tr.old_value,
  tr.new_value,
  tr.change_reason,
  CASE 
    WHEN tr.is_revision = true THEN '⚠️ This change required a revision'
    WHEN tr.is_approval = true THEN '✅ Approved'
    ELSE 'ℹ️ Informational change'
  END as change_impact
FROM time_periods tp
JOIN time_period_revisions tr ON tp.id = tr.time_period_id
WHERE tp.user_id = 'user-uuid'
  AND tp.work_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY tp.work_date DESC, tr.changed_at DESC;
```

### 2. Supervisor/Manager Report: Pending Approvals

Shows all time periods awaiting supervisor approval, with edit history.

```sql
SELECT 
  tp.id,
  tp.work_date,
  ud.display_name as employee_name,
  tp.submitted_at,
  tp.revision_number,
  tp.supervisor_edited_before_approval,
  COUNT(tr.id) FILTER (WHERE tr.is_revision = true) as revision_count,
  MAX(tr.changed_at) FILTER (WHERE tr.is_revision = true) as last_revision_at
FROM time_periods tp
JOIN users_data ud ON tp.user_id = ud.user_id
LEFT JOIN time_period_revisions tr ON tp.id = tr.time_period_id
WHERE tp.status = 'submitted'
  AND tp.work_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY tp.id, tp.work_date, ud.display_name, tp.submitted_at, 
         tp.revision_number, tp.supervisor_edited_before_approval
ORDER BY tp.submitted_at ASC;
```

### 3. Supervisor/Manager Report: Changes Made During Review

Shows all changes made by supervisors/managers during review process.

```sql
SELECT 
  tp.id,
  tp.work_date,
  ud.display_name as employee_name,
  tr.revision_number,
  tr.changed_at,
  tr.field_name,
  tr.old_value,
  tr.new_value,
  tr.change_reason,
  tp.supervisor_approved_at
FROM time_periods tp
JOIN users_data ud ON tp.user_id = ud.user_id
JOIN time_period_revisions tr ON tp.id = tr.time_period_id
WHERE tr.change_type IN ('supervisor_edit', 'admin_edit')
  AND tr.is_revision = true
  AND tp.work_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY tp.work_date DESC, tr.revision_number ASC, tr.changed_at ASC;
```

### 4. User Education Report: Common Issues

Identifies patterns in supervisor/admin edits to help users improve submissions.

```sql
SELECT 
  tr.field_name,
  COUNT(*) as edit_count,
  COUNT(DISTINCT tr.time_period_id) as affected_periods,
  STRING_AGG(DISTINCT tr.change_reason, '; ') as common_reasons
FROM time_period_revisions tr
WHERE tr.is_revision = true
  AND tr.change_type IN ('supervisor_edit', 'admin_edit')
  AND tr.changed_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY tr.field_name
HAVING COUNT(*) >= 5  -- Only show fields edited 5+ times
ORDER BY edit_count DESC;
```

### 5. Approval Workflow Status Report

Shows status of all time periods in the approval pipeline.

```sql
SELECT 
  tp.status,
  COUNT(*) as count,
  COUNT(*) FILTER (WHERE tp.supervisor_edited_before_approval = true) as supervisor_edited_count,
  COUNT(*) FILTER (WHERE tp.admin_edited_before_approval = true) as admin_edited_count,
  AVG(EXTRACT(EPOCH FROM (COALESCE(tp.approved_at, now()) - tp.submitted_at)) / 3600) as avg_hours_to_approval
FROM time_periods tp
WHERE tp.submitted_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY tp.status
ORDER BY 
  CASE tp.status
    WHEN 'submitted' THEN 1
    WHEN 'supervisor_approved' THEN 2
    WHEN 'admin_approved' THEN 3
    ELSE 4
  END;
```

---

## Key Enhancements Summary

1. ✅ **Workflow Stage Tracking**: `submitted_at`, `supervisor_approved_at`, `admin_approved_at`
2. ✅ **Edit Flags**: `supervisor_edited_before_approval`, `admin_edited_before_approval`
3. ✅ **Enhanced Revision Tracking**: 
   - `change_type` distinguishes user edits vs supervisor/admin edits
   - `is_revision` flag indicates if change triggered revision
   - `workflow_stage` tracks where in workflow the change occurred
4. ✅ **Reporting Support**: Indexes and structure optimized for report queries
5. ✅ **User Education**: Field-level tracking enables pattern analysis

This design supports all five workflow stages and enables comprehensive reporting for both users and supervisors/managers.

