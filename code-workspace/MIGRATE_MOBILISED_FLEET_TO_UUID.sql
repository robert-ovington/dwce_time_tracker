-- Migration Script: Complete time_mobilised_large_plant Foreign Key Migration
-- This finishes migrating time_mobilised_large_plant foreign keys
-- from plant_no (text) to id (UUID)
--
-- Run this in Supabase SQL Editor

BEGIN;

-- ============================================================================
-- STEP 1: Drop existing foreign key constraints
-- ============================================================================

ALTER TABLE time_mobilised_large_plant 
    DROP CONSTRAINT IF EXISTS time_mobilised_large_plant_large_plant_no_1_fkey;

ALTER TABLE time_mobilised_large_plant 
    DROP CONSTRAINT IF EXISTS time_mobilised_large_plant_large_plant_no_2_fkey;

ALTER TABLE time_mobilised_large_plant 
    DROP CONSTRAINT IF EXISTS time_mobilised_large_plant_large_plant_no_3_fkey;

ALTER TABLE time_mobilised_large_plant 
    DROP CONSTRAINT IF EXISTS time_mobilised_large_plant_large_plant_no_4_fkey;

-- ============================================================================
-- STEP 2: Create function to convert plant_no to id (if not exists)
-- ============================================================================

CREATE OR REPLACE FUNCTION migrate_plant_no_to_id(plant_no_text TEXT)
RETURNS UUID AS $$
DECLARE
    plant_uuid UUID;
BEGIN
    IF plant_no_text IS NULL OR plant_no_text = '' THEN
        RETURN NULL;
    END IF;
    
    -- Try to convert directly if it's already a UUID
    BEGIN
        RETURN plant_no_text::UUID;
    EXCEPTION WHEN OTHERS THEN
        -- If not a UUID, look it up by plant_no
        SELECT id INTO plant_uuid
        FROM large_plant
        WHERE plant_no = plant_no_text;
        
        IF plant_uuid IS NULL THEN
            RAISE WARNING 'Plant number % not found in large_plant table', plant_no_text;
        END IF;
        
        RETURN plant_uuid;
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- STEP 3: Migrate existing data (plant_no → id)
-- ============================================================================

-- Check current data type and migrate accordingly
DO $$
DECLARE
    col_type TEXT;
BEGIN
    -- Check the data type of large_plant_no_1
    SELECT data_type INTO col_type
    FROM information_schema.columns
    WHERE table_name = 'time_mobilised_large_plant'
      AND column_name = 'large_plant_no_1';
    
    IF col_type = 'text' THEN
        -- Migrate from plant_no (text) to id (UUID)
        RAISE NOTICE 'Migrating text values to UUIDs...';
        
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
    ELSE
        RAISE NOTICE 'Columns are already UUID type, skipping data migration';
    END IF;
END $$;

-- ============================================================================
-- STEP 4: Change column types from TEXT to UUID
-- ============================================================================

-- This will work even if columns are already UUID (no-op)
ALTER TABLE time_mobilised_large_plant 
    ALTER COLUMN large_plant_no_1 TYPE UUID USING 
        CASE 
            WHEN large_plant_no_1 IS NULL THEN NULL
            ELSE large_plant_no_1::UUID
        END;

ALTER TABLE time_mobilised_large_plant 
    ALTER COLUMN large_plant_no_2 TYPE UUID USING 
        CASE 
            WHEN large_plant_no_2 IS NULL THEN NULL
            ELSE large_plant_no_2::UUID
        END;

ALTER TABLE time_mobilised_large_plant 
    ALTER COLUMN large_plant_no_3 TYPE UUID USING 
        CASE 
            WHEN large_plant_no_3 IS NULL THEN NULL
            ELSE large_plant_no_3::UUID
        END;

ALTER TABLE time_mobilised_large_plant 
    ALTER COLUMN large_plant_no_4 TYPE UUID USING 
        CASE 
            WHEN large_plant_no_4 IS NULL THEN NULL
            ELSE large_plant_no_4::UUID
        END;

-- ============================================================================
-- STEP 5: Create new foreign key constraints pointing to id
-- ============================================================================

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

-- ============================================================================
-- STEP 6: Clean up
-- ============================================================================

DROP FUNCTION IF EXISTS migrate_plant_no_to_id(TEXT);

-- ============================================================================
-- STEP 7: Verify the migration
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
  AND tc.table_name = 'time_mobilised_large_plant'
ORDER BY kcu.column_name;

-- Expected: All foreign keys should now reference large_plant.id (not plant_no)

COMMIT;

-- ============================================================================
-- Migration Complete!
-- ============================================================================
-- 
-- Both tables should now have foreign keys referencing large_plant.id (UUID)
-- The Flutter code is already updated to use UUIDs

