# Timesheet Screen — Processes and Data

This document describes the **timesheet screen** (`lib/screens/timesheet_screen.dart`): (1) all processes for loading, running, and saving in plain English, and (2) all Supabase tables and fields used, with read / write / read+write.

---

## 1. Processes (Plain English)

### 1.1 Loading

- **Screen start**
  - Load the current logged-in user (from auth) and store their id and email.
  - Load the current user’s setup (from **users_setup**) to see if they can enter time for others; if so, load the list of users (from **users_data** and **users_setup** via UserEditService) and set the selected employee (self or first in list).
  - Load the current user’s profile data (from **users_data** via UserService) and use it to set: materials visibility, plant-list vs project mode, which sections to show (project, fleet, allowances, comments), last ticket number for autofill, and saved fleet slots for “Recall fleet”.
  - Load the week-start setting (from **system_settings**) and use it for date validation and “earliest allowed date”.
  - Load all active projects (from **projects**), and build a lookup by project name.
  - Load fleet/plant (from **large_plant**); if the user is in “plant list” (mechanic) mode, also load **workshop_tasks** and prepend them to the plant list, then build a lookup by plant number.
  - Load concrete mixes (from **concrete_mix**) for the materials dropdown.
  - Get the count of pending offline entries (from local offline storage) and show it in the UI.
  - If the screen was opened with an existing time period id (edit mode), load that time period and its related data (see below).

- **Loading an existing time period (edit)**
  - Load the time period row from **time_periods** by id.
  - Check status and permissions: only “submitted” or “supervisor_approved” are editable; “admin_approved” is not; supervisors/admins can edit “supervisor_approved”; only the owner or a supervisor/admin may edit.
  - Fill the form from the time period (date, start/finish time, project or fleet, allowances, distance, on call, materials, comments, etc.).
  - Load breaks for that time period from **time_period_breaks** (break_start, break_finish, break_reason) and show them in the breaks list.
  - Load used fleet from **time_period_used_fleet** (with **large_plant** plant_no) and show plant numbers in the “used fleet” list.
  - Load mobilised fleet from **time_period_mobilised_fleet** (with **large_plant** plant_no) and show plant numbers in the “mobilised fleet” list.

- **When “record for another person” is used**
  - When the selected employee changes, load that employee’s **users_data** (is_mechanic) to set plant-list vs project mode; if mode changes, reload plant (and optionally workshop_tasks) so the project/fleet dropdown matches.

- **Autofill and helpers**
  - Default date to today; validate it against week_start and “no future dates” using **system_settings** week_start.
  - Autofill start/finish times using last-used logic (from in-memory or user data where applicable).
  - “Recall fleet” fills the used-fleet list from **users_data** (fleet_1–fleet_6) and looks up descriptions from the already-loaded **large_plant** list.
  - “Find last job” loads the current user’s **users_data** (project_1–project_10 and project_*_changed_at), sorts by date, and shows a dialog to pick a previous project.
  - “Find nearest job” uses project list (with coordinates) and optionally **google_api_calls** (read for cache); if directions are fetched from the API, it may update **google_api_calls** (insert) and **system_settings** (read then update google_api_calls / google_api_saves, or insert if no row exists).

### 1.2 Running

- **Form behaviour**
  - User changes date, times, project/fleet, breaks, used fleet, mobilised fleet, travel/misc allowances, materials (ticket, mix, quantity), on call, comments.
  - Project/fleet dropdowns and “Find nearest” / “Find last job” use the data already loaded from **projects**, **large_plant**, and **users_data** (no extra table reads per keystroke).
  - Fleet number fields are validated on blur against the in-memory **large_plant** list (and workshop_tasks when in plant mode); invalid numbers are highlighted and a description is shown from that list.

- **Connectivity and sync**
  - A connectivity listener updates “online” vs “offline”; when online, a manual “Sync” runs the sync service to send pending offline entries to Supabase (which then writes to **time_periods** and related tables). Pending count is refreshed from local offline storage after sync.

- **GPS**
  - A background timer periodically refreshes GPS; the last position is used on save for submission_lat, submission_lng, submission_gps_accuracy (no tables read/written for GPS alone).

### 1.3 Saving

- **Build payload and resolve ids**
  - Determine the user_id (current auth user or selected employee, depending on permissions).
  - Resolve project_id or large_plant_id from the selected project/fleet name using the in-memory **projects** / **large_plant** lookups.
  - Build the main time-period payload (user_id, work_date, start_time, finish_time, status, project_id or large_plant_id, travel/misc allowances, on_call, materials fields, comments, GPS, distance, revision_number, offline_created, synced, etc.).
  - If “Calculate travel” was used, directions may have been read from **google_api_calls** or inserted there, and **system_settings** may have been read/updated for API call/save counters.

- **Update existing time period (edit)**
  - Read the existing **time_periods** row to get current status and revision_number.
  - Compare old vs new payload; if there are changes, compute a new revision_number and create one or more rows in **time_period_revisions** (change_type, field_name, old_value, new_value, changed_by, etc.).
  - Update the **time_periods** row (including status left as submitted/supervisor_approved, revision_number, last_revised_at, updated_at, last_revised_by).
  - Delete all existing rows for this time period in **time_period_breaks**, **time_period_used_fleet**, and **time_period_mobilised_fleet**.
  - Re-create breaks, used fleet, and mobilised fleet (see below).

- **Create new time period**
  - Insert one row into **time_periods** with the payload.
  - For “original submission” tracking, insert one row per tracked field into **time_period_revisions** (change_type = user_submission, original_submission = true, etc.).

- **Breaks**
  - For each break in the form that has start or finish time, insert a row into **time_period_breaks** (time_period_id, break_start, break_finish, break_reason, display_order).

- **Used fleet**
  - For each used-fleet plant number, resolve large_plant id from the in-memory plant list and insert a row into **time_period_used_fleet** (time_period_id, large_plant_id). Display order is implicit by insert order.

- **Mobilised fleet**
  - Same as used fleet: resolve large_plant id and insert rows into **time_period_mobilised_fleet** (time_period_id, large_plant_id).

- **User profile updates after save**
  - If not in plant mode and a project was used: update **users_data** project history (project_1–project_10 and project_1_changed_at–project_10_changed_at) so “Find last job” and recent-project ordering stay correct.
  - If materials are enabled: update **users_data** last_ticket_number (and optionally auto-increment ticket number in the UI for next entry).
  - “Save fleet” (separate button): update **users_data** fleet_1–fleet_6 from the current used-fleet list.

- **Offline save**
  - If the app is offline, the time period payload (plus breaks and fleet for later) is added to the local offline queue; no Supabase tables are written until sync runs. Pending count is updated from local storage.

---

## 2. Tables and Fields (Read / Write / Read+Write)

Tables are listed in alphabetical order. **Read** = screen only reads the field; **Write** = screen only writes the field; **Read/write** = screen both reads and writes it.

---

### auth.users (via AuthService / SupabaseService.client.auth)

Used for “current user” only; no direct table name in the screen. The screen reads:

- **Read:** `id`, `email` (for current user id and email; “list all users” comes from **users_data** / **users_setup**).

---

### concrete_mix

- **Read:** All columns needed for the mix dropdown (e.g. id, name / mix identifier). Screen uses `DatabaseService.read('concrete_mix')` and displays selections; concrete_mix_type and concrete_qty are stored on **time_periods**, not here.
- **Write:** None.

---

### google_api_calls

- **Read:** travel_time_minutes, distance_kilometers, distance_text, travel_time_formatted, was_cached, display_name (for cache lookup by home and project coordinates).
- **Write:** insert new row when directions are fetched and cached (home_latitude, home_longitude, project_latitude, project_longitude, distance_kilometers, travel_time_minutes, distance_text, travel_time_formatted, time_stamp, was_cached, etc.).
- **Read/write:** None.

---

### large_plant

- **Read:** id, plant_no, plant_description, short_description, is_active, and any other columns returned by `DatabaseService.read('large_plant')` used for dropdown and fleet validation. Referenced via foreign key from **time_period_used_fleet** and **time_period_mobilised_fleet** (select with `large_plant(plant_no)`).
- **Write:** None.

---

### projects

- **Read:** id, project_name, description, is_active, and any other columns used for the project dropdown and “Find nearest” (e.g. latitude, longitude if present). Screen uses `DatabaseService.read('projects', filterColumn: 'is_active', filterValue: true)`.
- **Write:** None.

---

### system_settings

- **Read:** id, week_start (for date validation); id, google_api_calls (before incrementing); id, google_api_saves (before incrementing).
- **Write:** update google_api_calls, google_api_saves (increment by 1); insert one row (google_api_calls, google_api_saves, week_start) if no row exists when incrementing.
- **Read/write:** id is read to perform updates; google_api_calls and google_api_saves are read then updated (or row inserted).

---

### time_period_breaks

- **Read:** break_start, break_finish, break_reason (and time_period_id for filter) when loading an existing time period for edit.
- **Write:** delete by time_period_id when updating an existing time period; insert rows (time_period_id, break_start, break_finish, break_reason, display_order) when saving.
- **Read/write:** All of the above fields are involved in either load (read) or save (delete + insert).

---

### time_period_mobilised_fleet

- **Read:** large_plant_id and related large_plant(plant_no) when loading an existing time period for edit.
- **Write:** delete by time_period_id when updating; insert rows (time_period_id, large_plant_id) when saving mobilised fleet.
- **Read/write:** time_period_id, large_plant_id (and display_order if present) are read or written as above.

---

### time_period_revisions

- **Read:** None in this screen (revisions are created for audit only).
- **Write:** insert rows: time_period_id, revision_number, changed_by, changed_by_name, changed_by_role, change_type, workflow_stage, field_name, old_value, new_value, change_reason, is_revision, is_approval, is_edit, original_submission (and any other columns defined on the table).
- **Read/write:** None.

---

### time_period_used_fleet

- **Read:** large_plant_id and large_plant(plant_no) when loading an existing time period for edit (ordered by display_order).
- **Write:** delete by time_period_id when updating; insert rows (time_period_id, large_plant_id) when saving used fleet.
- **Read/write:** time_period_id, large_plant_id (and display_order if used) are read or written as above.

---

### time_periods

- **Read:** Full row when loading for edit (e.g. user_id, work_date, start_time, finish_time, finish_time, status, project_id, large_plant_id, travel_to_site_min, travel_from_site_min, distance_from_home, on_call, misc_allowance_min, concrete_ticket_no, concrete_mix_type, concrete_qty, comments, revision_number, status, etc.); and again when tracking original submission or edits (for revision_number and field values).
- **Write:** insert (new entry) or update (edit) with: user_id, project_id, large_plant_id, work_date, start_time, finish_time, status, travel_to_site_min, travel_from_site_min, on_call, misc_allowance_min, concrete_ticket_no, concrete_mix_type, concrete_qty, comments, submission_lat, submission_lng, submission_gps_accuracy, distance_from_home, travel_time_text, revision_number, last_revised_at, updated_at, last_revised_by, offline_created, synced.
- **Read/write:** All fields listed above are either loaded for edit (read) or saved on create/update (write).

---

### users_data

- **Read:** id, user_id, is_mechanic, concrete_mix_lorry, show_project, show_fleet, show_allowances, show_comments, last_ticket_number, fleet_1–fleet_6, project_1–project_10, project_1_changed_at–project_10_changed_at (via UserService.getCurrentUserData(), or direct select for “record for another person” is_mechanic, or DatabaseService.read for project history / “Find last job”).
- **Write:** update last_ticket_number; update fleet_1–fleet_6 (“Save fleet”); update project_1–project_10 and project_1_changed_at–project_10_changed_at (project history after save).
- **Read/write:** id (read for updates), user_id (read for filtering), last_ticket_number, fleet_1–fleet_6, project_1–project_10, project_1_changed_at–project_10_changed_at.

---

### users_setup

- **Read:** user_id, security, security_limit, display_name, role, and any menu/permission columns used by UserService (e.g. dashboard, menu_*). Screen uses UserService.getCurrentUserSetup() and getCurrentUserData(); “all users” list is built via UserEditService (users_data + users_setup).
- **Write:** None in the timesheet screen.
- **Read/write:** None.

---

### workshop_tasks

- **Read:** id, task, task_description (mapped to plant_no, plant_description, short_description, description_of_work for the plant list when in mechanic mode).
- **Write:** None.

---

## Summary by access type

| Access    | Tables |
|----------|--------|
| **Read only** | concrete_mix, large_plant, projects, workshop_tasks; users_setup (via UserService); auth (id, email for current user). |
| **Write only** | time_period_revisions (insert only). |
| **Read and write** | time_periods, time_period_breaks, time_period_used_fleet, time_period_mobilised_fleet, users_data, system_settings, google_api_calls. |

*Offline storage and SyncService operate on local queues and then push to Supabase; the tables written by sync are the same as above (time_periods, time_period_breaks, time_period_used_fleet, time_period_mobilised_fleet).*
