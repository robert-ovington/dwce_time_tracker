# Fixing Employer Type Check Constraint

## Problem
The check constraint `employers_employer_type_check` is failing even though the employer types exist in the `employer_type` table. This suggests the constraint has a hardcoded list of values instead of checking against the table.

## Solution

### Step 1: Check Current Constraint

Run this SQL to see what the constraint currently allows:

```sql
-- Find the constraint definition
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'public.employers'::regclass
AND conname = 'employers_employer_type_check';
```

### Step 2: Drop the Old Constraint

```sql
-- Drop the existing check constraint
ALTER TABLE public.employers 
DROP CONSTRAINT IF EXISTS employers_employer_type_check;
```

### Step 3: Create a New Constraint That References the Table

```sql
-- Create a new constraint that checks against the employer_type table
ALTER TABLE public.employers
ADD CONSTRAINT employers_employer_type_check
CHECK (
    employer_type IN (
        SELECT employer_type FROM public.employer_type
    )
);
```

**Note:** PostgreSQL doesn't support subqueries in CHECK constraints directly. If the above doesn't work, use one of these alternatives:

### Alternative 1: Use a Function-Based Constraint

```sql
-- Create a function to check if employer_type exists
CREATE OR REPLACE FUNCTION public.check_employer_type(emp_type TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.employer_type 
        WHERE employer_type = emp_type
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Drop old constraint
ALTER TABLE public.employers 
DROP CONSTRAINT IF EXISTS employers_employer_type_check;

-- Add new constraint using the function
ALTER TABLE public.employers
ADD CONSTRAINT employers_employer_type_check
CHECK (public.check_employer_type(employer_type));
```

### Alternative 2: Update Constraint with All Current Values

If you prefer a simpler approach, update the constraint to include all current values:

```sql
-- First, get all current employer types
SELECT employer_type FROM public.employer_type;

-- Then drop the old constraint
ALTER TABLE public.employers 
DROP CONSTRAINT IF EXISTS employers_employer_type_check;

-- Add new constraint with all values (update this list as needed)
ALTER TABLE public.employers
ADD CONSTRAINT employers_employer_type_check
CHECK (employer_type IN ('Contractor', 'Agency', 'Subcontractor'));
```

**Note:** With this approach, you'll need to update the constraint whenever you add new employer types.

### Step 4: Verify the Fix

After updating the constraint, test by trying to insert an employer:

```sql
-- Test insert (should work now)
INSERT INTO public.employers (employer_name, employer_type, is_active)
VALUES ('Test Employer', 'Contractor', true);

-- Clean up test
DELETE FROM public.employers WHERE employer_name = 'Test Employer';
```

## Recommended Solution

I recommend **Alternative 1** (function-based constraint) because:
- It automatically allows any value that exists in `employer_type` table
- No need to update the constraint when adding new types
- More maintainable

After applying the fix, try importing your CSV again!

