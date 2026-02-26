-- ============================================================================
-- Diagnostic Script: Check Table Structure
-- ============================================================================
-- Run this FIRST to see what the primary keys are on your referenced tables
-- This will help identify why foreign keys might be failing
-- ============================================================================

-- Check users_data table structure
SELECT 
  'users_data' as table_name,
  a.attname as primary_key_column,
  t.typname as data_type
FROM pg_index i
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
JOIN pg_type t ON a.atttypid = t.oid
WHERE i.indrelid = 'public.users_data'::regclass
  AND i.indisprimary
LIMIT 1;

-- Check if user_id column exists and has unique constraint
SELECT 
  'users_data' as table_name,
  column_name,
  is_nullable,
  data_type,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM pg_constraint c
      JOIN pg_class t ON c.conrelid = t.oid
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(c.conkey)
      WHERE t.relname = 'users_data'
        AND a.attname = 'user_id'
        AND (c.contype = 'p' OR c.contype = 'u')
    ) THEN 'YES'
    ELSE 'NO'
  END as has_unique_constraint
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users_data'
  AND column_name = 'user_id';

-- Check projects table structure
SELECT 
  'projects' as table_name,
  a.attname as primary_key_column,
  t.typname as data_type
FROM pg_index i
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
JOIN pg_type t ON a.atttypid = t.oid
WHERE i.indrelid = 'public.projects'::regclass
  AND i.indisprimary
LIMIT 1;

-- Check large_plant table structure
SELECT 
  'large_plant' as table_name,
  a.attname as primary_key_column,
  t.typname as data_type
FROM pg_index i
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
JOIN pg_type t ON a.atttypid = t.oid
WHERE i.indrelid = 'public.large_plant'::regclass
  AND i.indisprimary
LIMIT 1;

-- Show all columns in users_data for reference
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users_data'
ORDER BY ordinal_position;

