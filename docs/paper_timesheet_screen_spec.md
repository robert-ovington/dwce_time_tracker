# Paper timesheet screen – detailed specification (Manager/Supervisor review)

This document captures the user's full feedback and is the source of truth for the paper-style timesheet screen. It should be used together with the plan in Cursor.

---

## Purpose and workflow

1. **Audience:** Managers and Supervisors reviewing and editing timesheets with minimal training, replicating the paper workflow.
2. **Editing rules:** Any change made by a Manager or Supervisor is shown **in red**. When satisfied, they click **"Update"** to persist changes to the submitted time periods.
3. **Layout:** Suitable for **A4 landscape** printing; aspect ratio must be maintained.

---

## Header

| Field | Source | Notes |
|-------|--------|-------|
| Sheet No. | — | **Omit** in digital format (redundant; origin tracked in background). |
| Week Starting | `public.system_settings.week_start` | Format depends on this (e.g. "Monday" or "Saturday"). |
| Employee Name | `public.users_data.forename` + " " + `public.users_data.surname` | |
| Company Name | `public.users_data.employer_name` | |

---

## Main grid

- **Week days:** Order and labels from `system_settings.week_start`. Flexible row count: after loading time periods, add empty rows so (1) days with no period have at least one row, (2) Mon–Fri share the rest so row counts are symmetric where possible.
- **Location/Town:** `public.projects.town`. Updates when Job No. (project) changes.
- **Section/Address:** `public.projects.address`. Updates when Job No. changes.
- **Job No.:** `public.projects.project_number`. **Editable**; changing it updates Location/Town and Section/Address.
- **Start, Break, Finish:** From `time_periods` and `time_period_breaks`. **Editable.**
- **Plant Number/Hired Plant:** From `time_period_used_fleet`. **Editable.**
- **Mobilised Plant** (header renamed from "Material/Plant Mobil"): From `time_period_mobilised_fleet`. **Editable.** If user recorded concrete data (`time_periods.concrete_ticket_no`, `.concrete_mix_type`, `.concrete_qty`), **replace** this section with **"Concrete Mixes"** and show those fields; all editable.
- **Travel:** Show travel claimed per time period in the main grid; **editable.**
- **Manager approval column:** First column in Manager section = approval marker (initials on paper). Show a symbol for approved/not; consider print visibility.

---

## Daily summary table

| Code | Meaning | Source | Notes |
|------|---------|--------|-------|
| PW | Paperwork | TBD table | Team-leader allowance; only if worked Mon–Fri. Table: who, quantity, pay rate. |
| ET | Extra Travel | Sum of travel from time periods | Total travel that day. Travel per period in main grid editable. |
| OC | On Call | `time_periods.on_call` (boolean) | New table TBD for allowance size by date (varies). |
| MS | Miscellaneous | `time_periods.misc_allowance_min` (integer min) | Display as **h:mm**. |
| NW-FT | Non-worked Flat Time | `time_periods.allowance_non_worked_ft_min` | Allocated by approver only. Integer minutes is suitable. |
| NW-TH | Non-worked Time & Half | `time_periods.allowance_non_worked_th_min` | Allocated by approver only. Integer minutes is suitable. |
| NW-DT | Non-worked Double Time | `time_periods.allowance_non_worked_dt_min` | Allocated by approver only. Integer minutes is suitable. |
| EA | Eating Allowance | TBD table | Only if worked Mon–Fri. Table: who, quantity, pay rate. |
| FT | Worked Flat Time | `time_period_pay_rates` + TBD table | Rules per user; table(s) for types, linked to pay_rates. |
| TH | Worked Time & Half | `time_period_pay_rates` + TBD table | Rules per user; table(s) for types. |
| DT | Worked Double Time | `time_period_pay_rates` + TBD table | Rules per user; table(s) for types. |
| CM | Country Money | TBD table | Only if worked Mon–Fri. Table: who, quantity, pay rate. |

---

## Weekly summary

Combined total of all Daily Summary columns (PW through CM), placed in the **bottom right** of the page.

---

## Data type note (NW-FT, NW-TH, NW-DT)

Storing as **integer minutes** in `allowance_non_worked_ft_min`, `allowance_non_worked_th_min`, `allowance_non_worked_dt_min` is appropriate and consistent with other allowance_min columns. No change suggested unless you prefer decimal hours elsewhere.

---

## Two formats

- **A. Interactive:** Managers/Supervisors can make corrections and mark approved. Edit actions: (a) change project, (b) start/finish times, (c) breaks, (d) used fleet, (e) mobilised fleet, (f) concrete mix data, (g) delete period, (h) split period (before/after/between; fleet from period before when between).
- **B. Printable:** Read-only; only saved data; approval column shows **initials** of person who approved each period (`time_periods.supervisor_id` → `users_data.initials`). A4 landscape.

## Approval and holiday

- **Approval initials:** From `time_periods.supervisor_id` and `users_data.initials`. No separate approval log table.
- **Holiday allowance:** `users_setup.holidays` boolean; true = user is allowed holiday hours (fixed 8h on public holidays from `holiday_list`).

## Split period (edit type h)

1. Adjust current period (reduce start or finish) to create space, or copy period and insert Before/After/Between.
2. Before: new period finish = original start; supervisor enters start.
3. After: new period start = original finish; supervisor enters finish.
4. Between: new period fills gap (start = earlier finish, finish = later start); **copy fleet from period before**.
5. New period: supervisor allocates to project; same used/mobilised fleet as original (or before when between).
6. On completion update: time_periods, time_period_used_fleet, time_period_mobilised_fleet, time_period_breaks, time_period_revisions; time_period_pay_rates recalculated by backend.

## Pay and absence

- **day_N_start/break/finish** in time_period_pay_rates: computed by backend, read-only; not displayed on screen.
- **ex_th_*, th_break_*:** Omit from first release.
- **absent_day_x_***: Admin allocates _paid; Managers/Supervisors do not. absenteeism_list.code → _type, description for display.
- **OC:** From `on_call_calendar` (duty_date, user_id) + `system_settings.on_call`; double when `holiday_list.on_call = 1` for that date.
- **holiday_list:** Single table (date, type, on_call); company holidays and allowance rules.

## Implementation checklist

- [x] Load `system_settings.week_start` (int 0–6) for weekday order and "Week Starting" label.
- [ ] Load `users_data` (forename, surname, employer_name, initials) for selected employee and for approvers (supervisor_id → initials).
- [ ] Load `projects` (id, town, address or project_name, project_number) for project_id resolution.
- [ ] Editable Job No. (project picker) updates Location/Town and Section/Address.
- [ ] Show travel per period in main grid; editable.
- [ ] Mobilised Plant vs Concrete Mixes: show Concrete Mixes when concrete_* present.
- [ ] Manager approval column: show initials from supervisor_id → users_data.initials; print-friendly.
- [ ] Track edits; render supervisor/manager changes in red; "Update" persists to time_periods and child tables.
- [ ] A4 landscape aspect ratio; print-friendly layout.
- [ ] Daily Summary from time_period_pay_rates (PW, ET, OC, MS, NW-*, EA, FT, TH, DT, CM); Weekly Summary totals bottom right.
- [ ] RLS: supervisor/manager can read and update relevant time_periods.
