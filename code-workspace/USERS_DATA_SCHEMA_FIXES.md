# users_data Schema Alignment - Fixes Applied

## Issues Found and Fixed

### 1. Time Field Names in `user_edit_screen.dart`

**Problem:** Field names didn't match the schema when reading/writing daily times and breaks.

**Schema Fields:**
- `monday_start_time` (not `monday_start`)
- `monday_finish_time` (not `monday_end`)
- `monday_break_1_start` (not `monday_break1_start`)
- `monday_break_1_finish` (not `monday_break1_end`)
- `monday_break_2_start` (not `monday_break2_start`)
- `monday_break_2_finish` (not `monday_break2_end`)

**Fixed:**
- ✅ Reading: Updated to use `${dayLower}_start_time`, `${dayLower}_finish_time`, `${dayLower}_break_1_start`, etc.
- ✅ Writing: Updated to use correct field names when saving

## Verified Correct References

### ✅ Boolean Flags
- `show_project` ✅
- `show_fleet` ✅
- `show_allowances` ✅
- `show_comments` ✅
- `concrete_mix_lorry` ✅
- `reinstatement_crew` ✅
- `cable_pulling` ✅
- `is_mechanic` ✅
- `is_public` ✅
- `is_active` ✅

### ✅ Fleet Fields
- `fleet_1` through `fleet_6` (character varying(6)) ✅

### ✅ Location Fields
- `home_latitude` (numeric(9,6)) ✅
- `home_longitude` (numeric(10,6)) ✅
- `home_address` (text) ✅
- `eircode` (text, max 8 chars) ✅

### ✅ User Info Fields
- `user_id` (uuid) ✅
- `display_name` (varchar 50) ✅
- `forename` (text) ✅
- `surname` (text) ✅
- `initials` (text, unique) ✅
- `employer_name` (text) ✅
- `stock_location` (varchar 50) ✅

### ✅ Time Fields (in time_tracking_screen.dart)
- `${dayName}_start_time` ✅
- `${dayName}_finish_time` ✅
- `${dayName}_break_1_start` ✅
- `${dayName}_break_1_finish` ✅
- `${dayName}_break_2_start` ✅
- `${dayName}_break_2_finish` ✅

## Time Format Handling

The schema uses `time without time zone` which returns as strings like `"09:00:00"` or `"09:00"`. The code handles this by:
- Converting to string with `.toString()`
- Parsing time strings when needed (e.g., splitting `"09:00"` into hours and minutes)

## Fields Not Currently Used

These fields exist in the schema but aren't used in the current code:
- `project_1` through `project_10` (varchar 10) - Reserved for future use
- `terms_accepted_date` (timestamp)
- `terms_version_date` (date)

## Summary

All field references in the code now match the `users_data` table schema. The main fix was correcting the time field names in `user_edit_screen.dart` to use `_start_time`, `_finish_time`, `_break_1_start`, `_break_1_finish`, `_break_2_start`, and `_break_2_finish` instead of the incorrect `_start`, `_end`, `_break1_start`, etc.

