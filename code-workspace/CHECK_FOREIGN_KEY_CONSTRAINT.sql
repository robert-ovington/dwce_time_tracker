-- Check Foreign Key Constraint for time_used_large_plant
-- Run this to see what table/column the foreign key is pointing to

-- Check the foreign key constraint details
SELECT
    tc.table_name, 
    kcu.column_name, 
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    tc.constraint_name
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND tc.table_name = 'time_used_large_plant'
  AND kcu.column_name LIKE 'large_plant_id%';

-- Check if the plant ID exists in large_plant table
-- Replace the UUID with the actual ID from the error
SELECT 
  id,
  plant_no,
  short_description,
  is_active
FROM large_plant
WHERE id = 'de8af748-a192-42a0-aaee-6f74ae02b0a2';

-- Check what columns exist in large_plant table
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'large_plant'
ORDER BY ordinal_position;

-- Check what columns exist in time_used_large_plant table
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'time_used_large_plant'
ORDER BY ordinal_position;

