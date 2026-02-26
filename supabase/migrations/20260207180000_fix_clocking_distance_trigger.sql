-- clocking_distance is no longer a column on time_periods. Remove the trigger and
-- function that still reference it so inserts (e.g. payroll import) do not fail.

DROP TRIGGER IF EXISTS trg_time_periods_set_clocking_distance ON public.time_periods;
DROP FUNCTION IF EXISTS public.time_periods_set_clocking_distance();
