-- Task type for schedule entries: Loading, Travelling, On Site, Wash, Waiting (Idle).
-- Only 'On Site' events are synced to Google Calendar.
ALTER TABLE public.concrete_mix_calendar
  ADD COLUMN IF NOT EXISTS task_type character varying(50) NULL;

COMMENT ON COLUMN public.concrete_mix_calendar.task_type IS 'Schedule task type: Loading, Travelling, On Site, Wash, Waiting. Only On Site is synced to Google Calendar.';
