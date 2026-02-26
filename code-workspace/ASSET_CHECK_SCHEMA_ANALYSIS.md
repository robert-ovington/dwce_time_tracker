# Asset Check Database Schema Analysis & Recommendations

## Current Schema Overview

### Tables Involved

1. **`public.small_plant`** - Small tools/equipment catalog
2. **`public.small_plant_check`** - Scan session records
3. **`public.small_plant_faults`** - Fault reports for scanned items
4. **`public.large_plant`** - Used for stock location dropdown
5. **`public.users_data`** - User preferences including default stock location

---

## Schema Analysis & Recommendations

### 1. `public.small_plant`

#### Current Structure
```sql
CREATE TABLE public.small_plant (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  small_plant_no TEXT,
  small_plant_description TEXT,
  is_active BOOLEAN DEFAULT true,
  type TEXT,
  make_model TEXT,
  serial_number TEXT
);

CREATE INDEX idx_small_plant_small_plant_no ON public.small_plant(small_plant_no);
```

#### Recommendations

**✅ Good Practices Already:**
- UUID primary key (better for distributed systems)
- Index on `small_plant_no` for lookups
- `is_active` flag for soft deletes
- Separated fields (type, make_model, serial_number) for better mobile display

**🔧 Suggested Improvements:**

1. **Add Audit Fields:**
```sql
ALTER TABLE public.small_plant
ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN created_by UUID REFERENCES auth.users(id),
ADD COLUMN updated_by UUID REFERENCES auth.users(id);
```

2. **Add Additional Indexes:**
```sql
CREATE INDEX IF NOT EXISTS idx_small_plant_is_active ON public.small_plant(is_active);
CREATE INDEX IF NOT EXISTS idx_small_plant_type ON public.small_plant(type) WHERE type IS NOT NULL;
```

3. **Add Constraints:**
```sql
-- Ensure small_plant_no is exactly 6 digits when provided
ALTER TABLE public.small_plant
ADD CONSTRAINT chk_small_plant_no_format 
CHECK (small_plant_no IS NULL OR small_plant_no ~ '^\d{6}$');

-- Ensure at least one identifier field is provided
ALTER TABLE public.small_plant
ADD CONSTRAINT chk_small_plant_has_identifier
CHECK (
  small_plant_no IS NOT NULL OR 
  (type IS NOT NULL AND make_model IS NOT NULL)
);
```

4. **Add Unique Constraint (Optional):**
```sql
-- If small_plant_no should be unique when provided
CREATE UNIQUE INDEX idx_small_plant_no_unique 
ON public.small_plant(small_plant_no) 
WHERE small_plant_no IS NOT NULL;
```

4. **Add Updated At Trigger:**
```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_small_plant_updated_at
BEFORE UPDATE ON public.small_plant
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
```

---

### 2. `public.small_plant_check`

#### Current Structure (Assumed)
```sql
CREATE TABLE public.small_plant_check (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  stock_location TEXT NOT NULL,
  small_plant_no TEXT REFERENCES public.small_plant(small_plant_no) NOT NULL,
  created_by UUID REFERENCES auth.users(id) NOT NULL,
  synced BOOLEAN DEFAULT true,
  offline_created BOOLEAN DEFAULT false
);
```

#### Recommendations

**✅ Good Practices Already:**
- UUID primary key
- Foreign key to `auth.users`
- Foreign key to `small_plant`
- Offline sync flags

**🔧 Suggested Improvements:**

1. **Add Audit Fields:**
```sql
ALTER TABLE public.small_plant_check
ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
```

2. **Add Indexes for Performance:**
```sql
-- Index for user queries (most common)
CREATE INDEX idx_small_plant_check_user_date 
ON public.small_plant_check(user_id, date DESC);

-- Index for stock location queries
CREATE INDEX idx_small_plant_check_stock_location 
ON public.small_plant_check(stock_location);

-- Index for small_plant_no lookups
CREATE INDEX idx_small_plant_check_plant_no 
ON public.small_plant_check(small_plant_no);

-- Index for sync operations
CREATE INDEX idx_small_plant_check_sync 
ON public.small_plant_check(synced, offline_created) 
WHERE synced = false OR offline_created = true;
```

3. **Add Constraints:**
```sql
-- Ensure date is not in the future
ALTER TABLE public.small_plant_check
ADD CONSTRAINT chk_small_plant_check_date_not_future 
CHECK (date <= CURRENT_DATE);

-- Ensure created_by matches user_id (or allow supervisors)
-- This is handled by RLS policies instead
```

4. **Add Composite Unique Constraint (Optional):**
```sql
-- Prevent duplicate scans on same day (if business rule requires)
-- Uncomment if needed:
-- CREATE UNIQUE INDEX idx_small_plant_check_unique_scan
-- ON public.small_plant_check(user_id, date, small_plant_no);
```

5. **Add Updated At Trigger:**
```sql
CREATE TRIGGER update_small_plant_check_updated_at
BEFORE UPDATE ON public.small_plant_check
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
```

---

### 3. `public.small_plant_faults`

#### Current Structure (Assumed)
```sql
CREATE TABLE public.small_plant_faults (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  small_plant_check_id UUID REFERENCES public.small_plant_check(id) NOT NULL,
  comment TEXT NOT NULL,
  photo_url TEXT,
  supervisor_id UUID REFERENCES auth.users(id),
  action_type TEXT,
  action_date TIMESTAMP WITH TIME ZONE,
  action_notes TEXT,
  synced BOOLEAN DEFAULT true,
  offline_created BOOLEAN DEFAULT false
);
```

#### Recommendations

**✅ Good Practices Already:**
- UUID primary key
- Foreign key to `small_plant_check`
- Optional fields properly nullable

**🔧 Suggested Improvements:**

1. **Add Audit Fields:**
```sql
ALTER TABLE public.small_plant_faults
ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN created_by UUID REFERENCES auth.users(id);
```

2. **Add Indexes:**
```sql
-- Index for check_id lookups (most common)
CREATE INDEX idx_small_plant_faults_check_id 
ON public.small_plant_faults(small_plant_check_id);

-- Index for supervisor queries
CREATE INDEX idx_small_plant_faults_supervisor 
ON public.small_plant_faults(supervisor_id) 
WHERE supervisor_id IS NOT NULL;

-- Index for sync operations
CREATE INDEX idx_small_plant_faults_sync 
ON public.small_plant_faults(synced, offline_created) 
WHERE synced = false OR offline_created = true;
```

3. **Add Constraints:**
```sql
-- Ensure comment is not empty
ALTER TABLE public.small_plant_faults
ADD CONSTRAINT chk_small_plant_faults_comment_not_empty 
CHECK (LENGTH(TRIM(comment)) > 0);

-- Ensure photo_url is a valid URL format (basic check)
ALTER TABLE public.small_plant_faults
ADD CONSTRAINT chk_small_plant_faults_photo_url_format 
CHECK (photo_url IS NULL OR photo_url ~ '^https?://');

-- Ensure action_date is not in the future
ALTER TABLE public.small_plant_faults
ADD CONSTRAINT chk_small_plant_faults_action_date_not_future 
CHECK (action_date IS NULL OR action_date <= NOW());
```

4. **Add Action Type Enum (Optional):**
```sql
-- Create enum for action types if standardized
CREATE TYPE fault_action_type AS ENUM (
  'repaired',
  'replaced',
  'disposed',
  'pending_review',
  'no_action_required'
);

-- Then update column:
-- ALTER TABLE public.small_plant_faults
-- ALTER COLUMN action_type TYPE fault_action_type USING action_type::fault_action_type;
```

5. **Add Updated At Trigger:**
```sql
CREATE TRIGGER update_small_plant_faults_updated_at
BEFORE UPDATE ON public.small_plant_faults
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
```

6. **Add Cascade Delete (Optional):**
```sql
-- If faults should be deleted when check is deleted:
-- ALTER TABLE public.small_plant_faults
-- DROP CONSTRAINT small_plant_faults_small_plant_check_id_fkey,
-- ADD CONSTRAINT small_plant_faults_small_plant_check_id_fkey
-- FOREIGN KEY (small_plant_check_id) 
-- REFERENCES public.small_plant_check(id) 
-- ON DELETE CASCADE;
```

---

## Row Level Security (RLS) Policies

### 1. `public.small_plant`

```sql
-- Enable RLS
ALTER TABLE public.small_plant ENABLE ROW LEVEL SECURITY;

-- Policy: All authenticated users can read active small plants
CREATE POLICY "Users can read active small plants"
ON public.small_plant FOR SELECT
TO authenticated
USING (is_active = true);

-- Policy: Users with security 1-3 can read all small plants
CREATE POLICY "High security users can read all small plants"
ON public.small_plant FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND security IN (1, 2, 3)
  )
);

-- Policy: Users with security 1-3 can insert/update/delete
CREATE POLICY "High security users can manage small plants"
ON public.small_plant FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND security IN (1, 2, 3)
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND security IN (1, 2, 3)
  )
);
```

### 2. `public.small_plant_check`

```sql
-- Enable RLS
ALTER TABLE public.small_plant_check ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own check records
CREATE POLICY "Users can read their own check records"
ON public.small_plant_check FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Policy: Users with security 1-3 can read all check records
CREATE POLICY "High security users can read all check records"
ON public.small_plant_check FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND security IN (1, 2, 3)
  )
);

-- Policy: Users can insert their own check records
CREATE POLICY "Users can insert their own check records"
ON public.small_plant_check FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid() AND created_by = auth.uid());

-- Policy: Users cannot update or delete their own records
-- (No UPDATE or DELETE policies - records are immutable)
```

### 3. `public.small_plant_faults`

```sql
-- Enable RLS
ALTER TABLE public.small_plant_faults ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read faults for their own check records
CREATE POLICY "Users can read faults for their own checks"
ON public.small_plant_faults FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.small_plant_check
    WHERE id = small_plant_faults.small_plant_check_id
    AND user_id = auth.uid()
  )
);

-- Policy: Users with security 1-3 can read all faults
CREATE POLICY "High security users can read all faults"
ON public.small_plant_faults FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND security IN (1, 2, 3)
  )
);

-- Policy: Users can insert faults for their own check records
CREATE POLICY "Users can insert faults for their own checks"
ON public.small_plant_faults FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.small_plant_check
    WHERE id = small_plant_faults.small_plant_check_id
    AND user_id = auth.uid()
  )
);

-- Policy: Users cannot update or delete fault records
-- (No UPDATE or DELETE policies - records are immutable)
```

---

## Storage Bucket Setup

### Create Storage Bucket for Fault Photos

```sql
-- Create bucket (run in Supabase SQL Editor)
INSERT INTO storage.buckets (id, name, public)
VALUES ('asset-check-photos', 'asset-check-photos', true);
```

### Storage Policies

```sql
-- Policy: Authenticated users can upload photos
CREATE POLICY "Authenticated users can upload fault photos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'asset-check-photos'
  AND (storage.foldername(name))[1] = 'faults'
);

-- Policy: Authenticated users can read photos
CREATE POLICY "Authenticated users can read fault photos"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'asset-check-photos');

-- Policy: Users with security 1-3 can delete photos
CREATE POLICY "High security users can delete fault photos"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'asset-check-photos'
  AND EXISTS (
    SELECT 1 FROM public.users_setup
    WHERE user_id = auth.uid()
    AND security IN (1, 2, 3)
  )
);
```

---

## Summary of Best Practices Implemented

### ✅ Data Integrity
- Foreign key constraints
- Check constraints for data validation
- Not null constraints where appropriate
- Unique constraints where needed

### ✅ Performance
- Indexes on frequently queried columns
- Composite indexes for common query patterns
- Partial indexes for filtered queries

### ✅ Audit Trail
- `created_at` and `updated_at` timestamps
- `created_by` and `updated_by` user tracking
- Automatic timestamp updates via triggers

### ✅ Security
- Row Level Security (RLS) enabled on all tables
- Users can only read their own records
- High security users (1-3) can read all records
- Records are immutable (no UPDATE/DELETE for regular users)

### ✅ Offline Support
- `synced` and `offline_created` flags
- Indexes optimized for sync operations

### ✅ Scalability
- UUID primary keys for distributed systems
- Proper indexing strategy
- Efficient foreign key relationships

---

## Migration Script

A complete migration script combining all recommendations is available in:
`supabase/migrations/YYYYMMDDHHMMSS_asset_check_schema.sql`

Run this migration in your Supabase SQL Editor to apply all improvements at once.

---

## Testing Checklist

After applying the schema changes:

- [ ] Test RLS policies with different user security levels
- [ ] Verify indexes improve query performance
- [ ] Test constraint validations (invalid data should be rejected)
- [ ] Verify audit fields are populated correctly
- [ ] Test storage bucket policies for photo uploads
- [ ] Verify cascade deletes (if implemented)
- [ ] Test offline sync with `synced` and `offline_created` flags

