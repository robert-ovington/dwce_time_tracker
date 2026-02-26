-- Add short_description to projects for payroll import (Section column in Allocated Week CSV).
-- Used to match projects when importing from Excel; sync script populates from Access.
ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS short_description TEXT;

COMMENT ON COLUMN public.projects.short_description IS 'Short/section description; matches Excel Allocated Week "Section" column for import. Populated by sync_projects script from Access.';
