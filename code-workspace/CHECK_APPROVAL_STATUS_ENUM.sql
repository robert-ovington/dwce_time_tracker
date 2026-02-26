-- Check what values exist in the approval_status enum
SELECT enumlabel 
FROM pg_enum 
WHERE enumtypid = 'public.approval_status'::regtype
ORDER BY enumsortorder;

