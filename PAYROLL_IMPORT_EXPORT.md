# Payroll Import & Export (Excel ↔ Supabase)

This document describes the approach for importing existing time period data from your Excel payroll into Supabase, and exporting data back from Supabase for your spreadsheet when users have migrated to the new app.

---

## Overview

- **Import Payroll**: Bring legacy data from Excel (two tabs) into Supabase `time_periods` (and related tables) using the web app as the translator.
- **Export Payroll**: Query Supabase for a date range and download CSV (or Excel) in a layout that matches your spreadsheet for feeding back into Excel.

---

## Your Excel Layout

- **Hours tabs**: `Week (n)` — week number **n** from System List tab (A1:C53). Two header rows (category + subcategory); columns B–V are 3 per day (Start, Break, Finish) for Mon–Sun; then Worked Hours, FT/TH/DT and other allowance columns. One data row per employee per week. Example: **Hours.csv**.
- **Allocation tabs**: `Allocated Week (n)` — same week number. One header row. Each data row = one time period (Date, Contract, Location, Section, Employee, Start, Break, Finish, Hours, Plant 1–6, Mob 1–4, Material, Quantity, FT, TH, DT, NW FT/TH/DT, Travel, On Call, Misc, Paperwork, Eating All., Country). Example: **projects.csv**.
- **Primary source for import**: **projects.csv** (Allocated Week) is the source of truth for creating `time_periods` rows. **Hours.csv** can be used for validation or for allowances only present there.

---

## Supabase Target Schema (summary)

- **`time_periods`**: One row per block of time (user, project, work_date, start_time, finish_time, status, travel/allowance fields, etc.). See `code-workspace/CREATE_COMPLETE_SCHEMA.sql` for full columns.
- **Related**: `time_period_breaks`, `time_period_used_fleet`, `time_period_mobilised_fleet`, `time_period_pay_rates` (optional for import v1).

---

## Recommended Approach

### 1. File format

- **CSV** is the simplest and works everywhere: in Excel use *Save As → CSV (Comma delimited)* for each tab. The web app can parse CSV without extra packages.
- **Excel (.xlsx)** can be supported later with a package (e.g. `excel`) if you prefer uploading the workbook directly; the app would read each sheet.

### 2. Import flow (Web app as translator)

1. **Prepare files**: Export Tab 1 to `hours_allowances.csv` and Tab 2 to `project_allocation.csv` (or use the same names you prefer).
2. **Import Payroll screen** (Main Menu → Exports → Import Payroll):
   - **Step 1**: Select two files (or one ZIP containing both). Alternatively: one file at a time (first “Hours & allowances”, then “Project allocation”).
   - **Step 2**: **Column mapping** (optional but recommended): Map Excel/CSV column names or positions to Supabase fields, e.g.  
     - Tab 1: `Employee Name` / `Employee ID` → `user_id` (via `users_setup` or `users_data` lookup), `Date` → `work_date`, `Total Hours` → used to derive start/finish or store in pay_rates, `Travel (min)` → `travel_to_site_min` / `travel_from_site_min`, etc.  
     - Tab 2: `User`, `Date`, `Project` (name or number) → `project_id` (lookup from `projects`), `Hours` → split into one `time_period` per row (with start_time/finish_time derived from hours if needed).
   - **Step 3**: **Preview**: Show first N rows as they would appear in Supabase (user_id, project_id, work_date, hours, allowances). Allow “Import” or “Cancel”.
   - **Step 4**: **Import**: Translate each row to `time_periods` (and optionally pay_rates / allowances). Insert via Supabase client. Handle duplicates (e.g. by work_date + user_id + project_id) as you prefer (skip, replace, or error).

### 3. Translation rules (to implement once column names are known)

- **User identifier**: Excel may have name, employee number, or email. Map to Supabase `user_id` (UUID) via a lookup table or `users_setup` / `users_data` (e.g. match on `display_name` or a stored employee number).
- **Project**: Excel project name or number → `projects.id` (UUID) via `projects.project_name` or `projects.project_number`.
- **Dates**: Parse Excel date format (e.g. `dd/MM/yyyy` or ISO) → `work_date` (DATE).
- **Hours**: If Tab 2 has “hours per project”, create one `time_period` row per (user, date, project) with:
  - `start_time` / `finish_time`: e.g. assume same day, 08:00 + hours offset, or store only date and leave times null and use `time_period_pay_rates` for hours.
- **Allowances** (from Tab 1): Map to `travel_to_site_min`, `travel_from_site_min`, `misc_allowance_min`, `on_call`, etc., and attach to the corresponding time_period(s) for that user/date (e.g. first period of the day or spread across periods).

### 4. Export flow (Supabase → Excel)

1. **Export Payroll screen** (Main Menu → Exports → Export Payroll):
   - User selects **date range** (and optionally filters by user/project).
   - App queries `time_periods` (and related tables) for that range.
   - Build two outputs that mirror your two tabs:
     - **Tab 1 (hours & allowances)**: One row per user per day (or per user) with totals and allowance fields.
     - **Tab 2 (project allocation)**: One row per user, date, project with hours (and plant if applicable).
   - **Download** as CSV (and optionally .xlsx) so you can open in Excel or paste into your existing spreadsheet.

This gives you a **reverse process** that matches the import layout, so once everyone is on the app you can still feed data back into the same Excel structure if needed.

---

## Implementation status

- **Import Payroll**: Screen added under Exports with file picker for two CSVs and instructions. **Mapping defined**: see **PAYROLL_IMPORT_MAPPING.md** for the full table (projects.csv to time_periods, pay_rates, fleet; Hours.csv optional for validation). Implement import logic using that mapping; break start/finish are not in Excel — store duration in comments and leave time_period_breaks empty for now.
- **Export Payroll**: Screen added with date range and “Export” button. Query and CSV/Excel generation to be implemented to match the two-tab layout above.

---

## Permissions & RLS

- **Import**: Inserts into `time_periods` (and related) must be allowed for the importing user. Options:
  - Use an admin/service account with RLS that allows insert for any user_id, or
  - Use a Supabase Edge Function with service role to perform the inserts (app sends parsed rows, function inserts).
- **Export**: Read access to `time_periods` (and related) for the date range; existing RLS for supervisors/admins should be sufficient if they can already see time period data.

---

## Next steps

1. Provide sample CSVs (or exact column headers) for both tabs so the app can:
   - Parse and show a preview.
   - Implement the exact mapping to `time_periods` (and allowances).
2. Decide duplicate policy: skip existing (user, date, project), replace, or fail.
3. Implement Export Payroll query and CSV layout to mirror your Excel tabs so the round-trip (Import → use in app → Export → back into Excel) is consistent.
