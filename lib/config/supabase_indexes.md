# Supabase table indexes (query hints)

Use these when writing or changing queries so the database can use indexes.

## Convention
- Prefer **filtering** on indexed columns (e.g. `.eq('user_id', id)`, `.gte('work_date', x).lte('work_date', y)`).
- Prefer **ordering** by indexed columns when you need sorted results.
- Avoid fetching whole tables and filtering in Dart when you can push filters into the query.

## Key tables and indexes

| Table | Indexes | Suggested filters / order |
|-------|---------|---------------------------|
| `users_data` | idx_users_data_user_id | `.eq('user_id', id)` |
| `users_setup` | uq_users_setup_user_id, uq_users_setup_display_name | `.eq('user_id', id)` or `.eq('display_name', name)`; use `.maybeSingle()` when expecting one row by user_id. |
| `time_periods` | user_id, project_id, work_date, status, deleted_by, clock_in_out | `.eq('user_id', id)`, `.gte('work_date', start).lte('work_date', end)`, `.eq('status', s)`, `.order('work_date')`. |
| `time_attendance` | idx_time_attendance_user_id, idx_time_attendance_project_id | `.eq('user_id', id)`, `.eq('project_id', id)`, date range on start_time, `.order('start_time')`. |
| `time_office` | idx_time_office_user_id, home_project_id, nearest_projects | `.eq('user_id', id)` or `.inFilter('user_id', list)`, `.gte('start_time', ...).lte('start_time', ...)`, `.order('start_time')`. |
| `concrete_mix_bookings` | idx_cmb_project_id, idx_cmb_driver_and_site, idx_cmb_due_date_time, idx_cmb_concrete_mix_type | `.gte('due_date_time', start).lte('due_date_time', end)`, `.eq('project_id', id)`, `.eq('booking_user_id', id)`, `.order('due_date_time')`. |
| `projects` | idx_projects_is_active, project_number, client_name | `.eq('is_active', true)`, `.eq('project_number', no)` or filter by client_name when needed. |
| `system_settings` | uq_system_settings_singleton, idx_system_settings_week_start_int | Use `.limit(1)` for singleton; week_start is integer 0–6 (DOW). |
| `google_api_calls` | idx_google_api_calls_time_stamp | For time-based lookups use `.lte('time_stamp', ...)` or `.order('time_stamp', ascending: false)`. |
| `small_plant_check` | idx_small_plant_check_user_id, idx_small_plant_check_small_plant_no | `.eq('user_id', id)`, `.order('date', ascending: false)`. |
| `leave_requests` | user_id, manager_id, status, dates | `.eq('user_id', id)` or `.eq('manager_id', id)`, `.eq('status', s)`, date range on start/end. |
| `deliveries` | user_id, large_plant_id, project_from_to, material_id, facility_id | Filter by user_id, dates, from_project_id/to_project_id where applicable. |
| `pay_rate_rules` | idx_pay_rate_rules_rule_name | `.order('rule_name')` for list. |

## Unique constraints
- `uq_users_setup_user_id`, `uq_users_setup_display_name`: use `.maybeSingle()` when querying by user_id or display_name.
- `uq_system_settings_singleton`: only one row; use `.limit(1).maybeSingle()`.
