-- Trigger to update users_data.employer_name when employers.employer_name changes
-- This ensures that when an employer name is edited, all related user records are updated

-- Step 1: Create a function that updates users_data when employer_name changes
CREATE OR REPLACE FUNCTION public.update_users_data_employer_name()
RETURNS TRIGGER AS $$
BEGIN
    -- Only update if employer_name actually changed
    IF OLD.employer_name IS DISTINCT FROM NEW.employer_name THEN
        -- Update all users_data records that reference the old employer name
        UPDATE public.users_data
        SET employer_name = NEW.employer_name
        WHERE employer_name = OLD.employer_name;
        
        RAISE NOTICE 'Updated % user(s) with employer name from "%" to "%"', 
            (SELECT COUNT(*) FROM public.users_data WHERE employer_name = NEW.employer_name),
            OLD.employer_name,
            NEW.employer_name;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 2: Create the trigger
DROP TRIGGER IF EXISTS trigger_update_users_data_employer_name ON public.employers;

CREATE TRIGGER trigger_update_users_data_employer_name
    AFTER UPDATE OF employer_name ON public.employers
    FOR EACH ROW
    WHEN (OLD.employer_name IS DISTINCT FROM NEW.employer_name)
    EXECUTE FUNCTION public.update_users_data_employer_name();

-- Step 3: Verify the trigger was created
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'trigger_update_users_data_employer_name';

-- Test the trigger (optional - remove after testing)
-- UPDATE public.employers 
-- SET employer_name = 'Test Employer Updated'
-- WHERE employer_name = 'Test Employer';
-- 
-- Check if users_data was updated:
-- SELECT user_id, employer_name FROM public.users_data WHERE employer_name = 'Test Employer Updated';

