-- Migration Script: Change Fleet Foreign Keys from plant_no to id (UUID)
-- This migrates time_used_large_plant and time_mobilised_large_plant foreign keys
-- to reference large_plant.id (UUID) instead of large_plant.plant_no (text)
--
-- IMPORTANT: Backup your database before running this script!
-- This script will:
-- 1. Drop existing foreign key constraints
-- 2. Convert text columns to UUID (migrating existing data)
-- 3. Create new foreign key constraints pointing to id
--
-- Run this in Supabase SQL Editor

BEGIN;

-- ============================================================================
-- STEP 1: Check current state and existing data
-- ============================================================================

-- Check if there's existing data that needs migration
DO $$
DECLARE
    used_count INTEGER;
    mobilised_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO used_count FROM time_used_large_plant;
    SELECT COUNT(*) INTO mobilised_count FROM time_mobilised_large_plant;
    
    RAISE NOTICE 'Found % records in time_used_large_plant', used_count;
    RAISE NOTICE 'Found % records in time_mobilised_large_plant', mobilised_count;
    
    IF used_count > 0 OR mobilised_count > 0 THEN
        RAISE NOTICE '⚠️  Existing data found. Will migrate plant_no values to UUIDs.';
    END IF;
END $$;

-- ============================================================================
-- STEP 2: Drop existing foreign key constraints for time_used_large_plant
-- ============================================================================

ALTER TABLE time_used_large_plant 
    DROP CONSTRAINT IF EXISTS time_used_large_plant_large_plant_id_1_fkey;

ALTER TABLE time_used_large_plant 
    DROP CONSTRAINT IF EXISTS time_used_large_plant_large_plant_id_2_fkey;

ALTER TABLE time_used_large_plant 
    DROP CONSTRAINT IF EXISTS time_used_large_plant_large_plant_id_3_fkey;

ALTER TABLE time_used_large_plant 
    DROP CONSTRAINT IF EXISTS time_used_large_plant_large_plant_id_4_fkey;

ALTER TABLE time_used_large_plant 
    DROP CONSTRAINT IF EXISTS time_used_large_plant_large_plant_id_5_fkey;

ALTER TABLE time_used_large_plant 
    DROP CONSTRAINT IF EXISTS time_used_large_plant_large_plant_id_6_fkey;

-- ============================================================================
-- STEP 3: Migrate existing data in time_used_large_plant (plant_no → id)
-- ============================================================================

-- Create a function to convert plant_no to id
CREATE OR REPLACE FUNCTION migrate_plant_no_to_id(plant_no_text TEXT)
RETURNS UUID AS $$
DECLARE
    plant_uuid UUID;
BEGIN
    IF plant_no_text IS NULL OR plant_no_text = '' THEN
        RETURN NULL;
    END IF;
    
    SELECT id INTO plant_uuid
    FROM large_plant
    WHERE plant_no = plant_no_text;
    
    IF plant_uuid IS NULL THEN
        RAISE WARNING 'Plant number % not found in large_plant table', plant_no_text;
    END IF;
    
    RETURN plant_uuid;
END;
$$ LANGUAGE plpgsql;

-- Migrate each column
UPDATE time_used_large_plant
SET large_plant_id_1 = migrate_plant_no_to_id(large_plant_id_1)
WHERE large_plant_id_1 IS NOT NULL;

UPDATE time_used_large_plant
SET large_plant_id_2 = migrate_plant_no_to_id(large_plant_id_2)
WHERE large_plant_id_2 IS NOT NULL;

UPDATE time_used_large_plant
SET large_plant_id_3 = migrate_plant_no_to_id(large_plant_id_3)
WHERE large_plant_id_3 IS NOT NULL;

UPDATE time_used_large_plant
SET large_plant_id_4 = migrate_plant_no_to_id(large_plant_id_4)
WHERE large_plant_id_4 IS NOT NULL;

UPDATE time_used_large_plant
SET large_plant_id_5 = migrate_plant_no_to_id(large_plant_id_5)
WHERE large_plant_id_5 IS NOT NULL;

UPDATE time_used_large_plant
SET large_plant_id_6 = migrate_plant_no_to_id(large_plant_id_6)
WHERE large_plant_id_6 IS NOT NULL;

-- ============================================================================
-- STEP 4: Change column types from TEXT to UUID for time_used_large_plant
-- ============================================================================

-- Note: This will fail if any values couldn't be converted (NULLs are OK)
ALTER TABLE time_used_large_plant 
    ALTER COLUMN large_plant_id_1 TYPE UUID USING large_plant_id_1::UUID;

ALTER TABLE time_used_large_plant 
    ALTER COLUMN large_plant_id_2 TYPE UUID USING large_plant_id_2::UUID;

ALTER TABLE time_used_large_plant 
    ALTER COLUMN large_plant_id_3 TYPE UUID USING large_plant_id_3::UUID;

ALTER TABLE time_used_large_plant 
    ALTER COLUMN large_plant_id_4 TYPE UUID USING large_plant_id_4::UUID;

ALTER TABLE time_used_large_plant 
    ALTER COLUMN large_plant_id_5 TYPE UUID USING large_plant_id_5::UUID;

ALTER TABLE time_used_large_plant 
    ALTER COLUMN large_plant_id_6 TYPE UUID USING large_plant_id_6::UUID;

-- ============================================================================
-- STEP 5: Create new foreign key constraints for time_used_large_plant
-- ============================================================================

ALTER TABLE time_used_large_plant
    ADD CONSTRAINT time_used_large_plant_large_plant_id_1_fkey
    FOREIGN KEY (large_plant_id_1) REFERENCES large_plant(id);

ALTER TABLE time_used_large_plant
    ADD CONSTRAINT time_used_large_plant_large_plant_id_2_fkey
    FOREIGN KEY (large_plant_id_2) REFERENCES large_plant(id);

ALTER TABLE time_used_large_plant
    ADD CONSTRAINT time_used_large_plant_large_plant_id_3_fkey
    FOREIGN KEY (large_plant_id_3) REFERENCES large_plant(id);

ALTER TABLE time_used_large_plant
    ADD CONSTRAINT time_used_large_plant_large_plant_id_4_fkey
    FOREIGN KEY (large_plant_id_4) REFERENCES large_plant(id);

ALTER TABLE time_used_large_plant
    ADD CONSTRAINT time_used_large_plant_large_plant_id_5_fkey
    FOREIGN KEY (large_plant_id_5) REFERENCES large_plant(id);

ALTER TABLE time_used_large_plant
    ADD CONSTRAINT time_used_large_plant_large_plant_id_6_fkey
    FOREIGN KEY (large_plant_id_6) REFERENCES large_plant(id);

-- ============================================================================
-- STEP 6: Handle time_mobilised_large_plant table
-- ============================================================================

-- Check if time_mobilised_large_plant exists and has similar structure
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'time_mobilised_large_plant'
    ) THEN
        RAISE NOTICE 'Processing time_mobilised_large_plant table...';
        
        -- Drop existing foreign keys (if they exist)
        ALTER TABLE time_mobilised_large_plant 
            DROP CONSTRAINT IF EXISTS time_mobilised_large_plant_large_plant_no_1_fkey;
        ALTER TABLE time_mobilised_large_plant 
            DROP CONSTRAINT IF EXISTS time_mobilised_large_plant_large_plant_no_2_fkey;
        ALTER TABLE time_mobilised_large_plant 
            DROP CONSTRAINT IF EXISTS time_mobilised_large_plant_large_plant_no_3_fkey;
        ALTER TABLE time_mobilised_large_plant 
            DROP CONSTRAINT IF EXISTS time_mobilised_large_plant_large_plant_no_4_fkey;
        
        -- Migrate existing data
        UPDATE time_mobilised_large_plant
        SET large_plant_no_1 = migrate_plant_no_to_id(large_plant_no_1)
        WHERE large_plant_no_1 IS NOT NULL;
        
        UPDATE time_mobilised_large_plant
        SET large_plant_no_2 = migrate_plant_no_to_id(large_plant_no_2)
        WHERE large_plant_no_2 IS NOT NULL;
        
        UPDATE time_mobilised_large_plant
        SET large_plant_no_3 = migrate_plant_no_to_id(large_plant_no_3)
        WHERE large_plant_no_3 IS NOT NULL;
        
        UPDATE time_mobilised_large_plant
        SET large_plant_no_4 = migrate_plant_no_to_id(large_plant_no_4)
        WHERE large_plant_no_4 IS NOT NULL;
        
        -- Change column types
        ALTER TABLE time_mobilised_large_plant 
            ALTER COLUMN large_plant_no_1 TYPE UUID USING large_plant_no_1::UUID;
        ALTER TABLE time_mobilised_large_plant 
            ALTER COLUMN large_plant_no_2 TYPE UUID USING large_plant_no_2::UUID;
        ALTER TABLE time_mobilised_large_plant 
            ALTER COLUMN large_plant_no_3 TYPE UUID USING large_plant_no_3::UUID;
        ALTER TABLE time_mobilised_large_plant 
            ALTER COLUMN large_plant_no_4 TYPE UUID USING large_plant_no_4::UUID;
        
        -- Create new foreign keys
        ALTER TABLE time_mobilised_large_plant
            ADD CONSTRAINT time_mobilised_large_plant_large_plant_no_1_fkey
            FOREIGN KEY (large_plant_no_1) REFERENCES large_plant(id);
        
        ALTER TABLE time_mobilised_large_plant
            ADD CONSTRAINT time_mobilised_large_plant_large_plant_no_2_fkey
            FOREIGN KEY (large_plant_no_2) REFERENCES large_plant(id);
        
        ALTER TABLE time_mobilised_large_plant
            ADD CONSTRAINT time_mobilised_large_plant_large_plant_no_3_fkey
            FOREIGN KEY (large_plant_no_3) REFERENCES large_plant(id);
        
        ALTER TABLE time_mobilised_large_plant
            ADD CONSTRAINT time_mobilised_large_plant_large_plant_no_4_fkey
            FOREIGN KEY (large_plant_no_4) REFERENCES large_plant(id);
        
        RAISE NOTICE '✅ time_mobilised_large_plant migration completed';
    ELSE
        RAISE NOTICE 'ℹ️  time_mobilised_large_plant table does not exist, skipping...';
    END IF;
END $$;

-- ============================================================================
-- STEP 7: Clean up temporary function
-- ============================================================================

DROP FUNCTION IF EXISTS migrate_plant_no_to_id(TEXT);

-- ============================================================================
-- STEP 8: Verify the migration
-- ============================================================================

-- Check foreign key constraints
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
  AND tc.table_name IN ('time_used_large_plant', 'time_mobilised_large_plant')
ORDER BY tc.table_name, kcu.column_name;

-- Expected: All foreign keys should now reference large_plant.id (not plant_no)

COMMIT;

-- ============================================================================
-- Migration Complete!
-- ============================================================================
-- 
-- Next steps:
-- 1. Update your Flutter code to store UUIDs instead of plant_no values
-- 2. Test saving time periods with fleet items
-- 3. Verify data integrity
--
-- The code changes needed:
-- - In _saveUsedFleet: Store plant['id'] instead of plant['plant_no']
-- - In _saveMobilisedFleet: Store plant['id'] instead of plant['plant_no']

