# Payroll Import: Source (Excel/CSV) → Destination (Supabase)

This table defines how data from your Excel payroll maps into Supabase. It is based on the example CSVs **Hours.csv** and **projects.csv** (single user, Week 2), and the Supabase schema for `time_periods` and related tables.

---

## Excel/Spreadsheet context

- **File**: `W:\Master Files\2026\Staff Hours (2026).xlsm`
- **Hours tabs**: `Week (n)` — week number **n** (single or double digit from System List tab, cells A1:C53). Contains **total hours and allowances** per employee per week; this data is forwarded to payroll software for weekly pay. Employee-specific calculation rules in the spreadsheet can be addressed later.
- **Allocation tabs**: `Allocated Week (n)` — same week number. One row per time period (project allocation).
- **Week number source**: Table in "System List" tab, cells A1:C53.

---

## 1. Primary source: projects.csv (Allocated Week tab)

**One header row.** Each data row = **one time period** (one employee, one date, one project, one block of time). This is the main source for creating `time_periods` rows.

### Project lookup (columns 1–3)

- **Column 1 – Contract**: maps to `public.projects.client_name`
- **Column 2 – Location**: maps to `public.projects.town`
- **Column 3 – Section**: maps to `public.projects.short_description`. If data in Column 3 is **unique** in `public.projects.short_description`, it is sufficient to identify the project (no need to search further by client_name/town). The `short_description` column has been added to `public.projects` and is populated by the sync script (see **Sync script** below).

### Column layout (from your example)

| CSV col | CSV header   | Sample value        | Destination (Supabase) | Notes |
|---------|--------------|---------------------|------------------------|--------|
| 0       | Date         | 05/01/2026          | `time_periods.work_date` | Parse DD/MM/YYYY → DATE |
| 1       | Contract     | Walsh Homes, …      | Project lookup → `time_periods.project_id` | `projects.client_name` |
| 2       | Location     | Shanrath…, Knocknacree | Project lookup | `projects.town` |
| 3       | Section      | 1 - Phase I (E4-0001) | Project lookup | `projects.short_description`; if unique, use alone for match |
| 4       | Employee     | "Tracey, Paul"      | `time_periods.user_id` | Lookup `users_setup.display_name` → UUID |
| 5       | Start        | 9:30, 6:30          | `time_periods.start_time` | Time + Date → TIMESTAMP WITH TIME ZONE |
| 6       | Break        | (empty), 0:30       | `time_period_breaks` (derived) | See **Breaks** section below |
| 7       | Finish       | 14:30, 17:00        | `time_periods.finish_time` | Time + Date |
| 8       | Hours        | 3:00, 2:00          | Ignore for insert | Sum of worked hours only; can validate if needed |
| 9–14    | Plant 1–6    | 382, 242, …         | `time_period_used_fleet` only | Resolve to `large_plant.id` |
| 15–18   | Mob 1–4      | (empty in sample)   | `time_period_mobilised_fleet` only | Resolve to `large_plant.id`. **Exception:** Col 18 — if value is **numeric**, **minimum 4 digits**, and **does not match** any `public.large_plant.plant_no`, use it as `time_periods.concrete_ticket_no` instead of fleet. |
| 19      | Material     | 1780, W 20n 20      | `time_periods.concrete_mix_type` only | Mix type (e.g. W 20n 20) |
| 20      | Quantity     | 1.57, 6.58          | `time_periods.concrete_qty` only | Numeric quantity |
| 21–32   | FT, TH, DT, NW FT, NW TH, NW DT, **Travel (27), On Call (28), Misc (29)**, Paperwork, Eating All., Country | Various | **Travel / On Call / Misc (cols 27–29): import in v1** into `time_periods` (travel_to_site_min / travel_from_site_min, on_call, misc_allowance_min). Other pay columns: do not import into `time_period_pay_rates` at this stage. |
| 33      | (trailing)   | 1262                | Ignore | Row count used for managing the tab (last row number, extract/repopulate). |

### Breaks (column 6)

- **Source:** Break is a **duration** (e.g. `0:30` = 30 minutes) or empty. Breaks are usually **15–60 minutes**. **All time periods and break times are rounded to the nearest 15 minutes.**
- **Import logic:**
  - **15–30 min:** Treat as **one break**. Place within the period with **13:00 (1 pm) taking priority** over 10:00. If the period does not include 10:00 or 13:00, place the break at the **start or end** of the period that is **closest** to 10:00 or 13:00.
  - **45–60 min:** Treat as **two breaks**, with the **larger** break at **13:00** and the smaller at 10:00 (or at start/end if period doesn’t include those times).
  - If period doesn’t include 10:00 or 13:00, place break(s) at the **beginning or end** of the period that is closest to 10:00 or 13:00.
- **Supabase:** Insert into `time_period_breaks` with derived `break_start` and `break_finish` (rounded to nearest 15 min).

---

## 2. Secondary source: Hours.csv (Week tab)

- **Purpose:** Compilation of **worked hours and allowances** per employee per week, used for payroll (forwarded to payroll software). Employee-specific rules and calculations in the spreadsheet will be addressed later.
- **Import:** **Do not use Hours.csv for import at this stage.** We will work on populating `time_period_pay_rates` (and any other export fields) so that **export** from the app matches this layout for feeding back into the spreadsheet once all users have migrated.

---

## 3. Lookups required before insert

| What | Source | Supabase lookup |
|------|--------|------------------|
| **user_id** | Employee (e.g. "Tracey, Paul") | `users_setup.display_name` (normalize "Surname, Forename"). If no match, skip or flag. |
| **project_id** | Contract (col 1), Location (col 2), Section (col 3) | Prefer **Section (col 3)** vs `projects.short_description`; if unique, use it alone. Otherwise match on `projects.client_name` + `projects.town` + `projects.short_description`. |
| **large_plant_id** (used) | Plant 1–6 (cols 9–14) | Resolve using **`public.large_plant.plant_no`** only to get **`public.large_plant.id`** (for easy identification by user). |
| **large_plant_id** (mobilised) | Mob 1–4 (cols 15–18), unless col 18 is concrete_ticket_no | Same (plant_no → large_plant.id). For col 18: if numeric, ≥4 digits, and not in large_plant.plant_no → set `time_periods.concrete_ticket_no` instead. |

---

## 4. Sync script: populate `projects.town` and `projects.short_description`

- **`code-workspace/sync_projects_production.py`** syncs from the Access "Master Job List" to Supabase.
- **Mapping:**  
  - **projects.csv "Location"** (Column 2) → Access **Town** → **`public.projects.town`**  
  - **projects.csv "Section"** (Column 3) → Access **Short_Description** → **`public.projects.short_description`**
- **`public.projects.short_description`** is populated from the Access database via the sync script. Import can match CSV Section (col 3) to `projects.short_description` and CSV Location (col 2) to `projects.town`.

---

## 5. Defaults and status for imported rows

- **status**: Use **`imported`** (approval_status enum: `submitted`, `supervisor_approved`, `admin_approved`, `imported`). Supervisors can approve `imported` and `submitted`; once `admin_approved`, only security level 1 (admin) can edit.
- **submitted_by**: Set to the **same value as `user_id`** (the employee UUID from the Employee lookup). This allows the user to access their own imported data when they start using the app (e.g. RLS or app logic that filters by submitted_by).
- **revision_number**: 0.
- **created_at / updated_at**: Default (now).

---

## 6. Summary: which source for which destination

| Supabase table.column | Source | Notes |
|------------------------|--------|------|
| time_periods.user_id | projects.csv → Employee | Lookup users_setup |
| time_periods.submitted_by | Same as user_id | Set = user_id so the user can access their own data in the app |
| time_periods.project_id | projects.csv → Contract/Location/Section | Prefer Section → short_description (unique); else client_name + town + short_description |
| time_periods.work_date | projects.csv → Date | DD/MM/YYYY |
| time_periods.start_time / finish_time | projects.csv → Start, Finish | Combined with Date |
| time_period_breaks | projects.csv → Break (duration) | 15–30 min = one break; 45–60 min = two breaks (larger at 13:00); round to 15 min; place at 10/13 or period start/end closest to 10/13 |
| time_periods.travel_to_site_min / travel_from_site_min | projects.csv → Travel (col 27) | **Import in v1**; convert to minutes. |
| time_periods.on_call, misc_allowance_min | projects.csv → On Call, Misc (cols 28–29) | **Import in v1**. |
| time_periods.concrete_ticket_no | projects.csv → Col 18 (Mob 4) | Only when value is numeric, ≥4 digits, and not in large_plant.plant_no |
| time_periods.concrete_mix_type | projects.csv → Col 19 (Material) | |
| time_periods.concrete_qty | projects.csv → Col 20 (Quantity) | |
| time_period_used_fleet | projects.csv → Plant 1–6 (cols 9–14) | Resolve to large_plant.id |
| time_period_mobilised_fleet | projects.csv → Mob 1–4 (cols 15–18) | Col 18: skip if used as concrete_ticket_no |
| time_period_pay_rates | projects.csv → cols 21–32 | **Not imported in v1**; populate later for export to match spreadsheet |

---

## 7. Export: IDs → human-readable values

For **export** (e.g. back to spreadsheet or payroll), convert stored IDs to the same format mechanics use:

- **`time_periods.project_id`** → resolve to **`projects.client_name`**, **`town`**, **`short_description`** (and any other needed project fields) for display/export.
- **`time_periods.large_plant_id`** → resolve to the **plant display format** used by mechanics, e.g. **D.W.C.E. Ltd. > Knocknacree > Fleet No 234**, which corresponds to `public.large_plant.id` (and related `public.projects.project_name` e.g. "W6-0234 - Fleet No 234, Knocknacree, Co. Kildare").
- **`time_periods.workshop_tasks_id`** → resolve to the relevant **client_name**, **town**, **short_description** (or task description) for export.

Import uses **`public.large_plant.plant_no`** only to find **`public.large_plant.id`**; the mechanics' hierarchical label (client > town > fleet) is the export format to produce from that id (and linked project if any).
