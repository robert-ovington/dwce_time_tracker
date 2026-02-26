-- Fix: time_periods used clocking_distance; schema now has clock_in_distance and clock_out_distance.
-- Drop the old trigger and function so inserts/updates do not reference the removed column.
-- If you need distance logic, recreate the function to set clock_in_distance and clock_out_distance
-- (e.g. from time_clocking or from submission_lat/lng vs project_lat/lng).

DROP TRIGGER IF EXISTS trg_time_periods_set_clocking_distance ON public.time_periods;
DROP FUNCTION IF EXISTS public.time_periods_set_clocking_distance();

-- Optional: recreate a no-op or minimal function if the trigger is required to exist.
-- Uncomment and adjust if your app or other triggers depend on this trigger existing.
/*
CREATE OR REPLACE FUNCTION public.time_periods_set_clocking_distance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Set clock_in_distance / clock_out_distance from your logic (e.g. from time_clocking or coords).
  -- For now leave them as-is (already set by trg_time_periods_set_distances when clock_in_id/clock_out_id change).
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_time_periods_set_clocking_distance
  BEFORE INSERT OR UPDATE OF project_lat, project_lng, submission_lat, submission_lng
  ON public.time_periods
  FOR EACH ROW
  EXECUTE FUNCTION public.time_periods_set_clocking_distance();
*/
