# Timesheet Screen Logic - Detailed Description

## Overview
The Timesheet Screen is the main screen where users record their work time entries. It handles data entry, validation, GPS tracking, offline storage, and synchronization with the Supabase database.

---

## Initialization and Setup

### When the Screen Loads
1. **Connectivity Check**: The app checks if the device is online or offline and sets up a listener to monitor connection changes.
2. **User Authentication**: The app loads the currently logged-in user's information (email and user ID).
3. **Permission Check**: The app checks if the user has permission to enter time for other employees (Admins and users with security level 2 or lower can do this).
4. **Data Loading**: The app loads several pieces of data:
   - User's profile data (from `users_data` table)
   - All available projects (from `projects` table)
   - All available fleet/plant items (from `large_plant` table)
   - Concrete mix types (if the user is a concrete mix lorry driver)
   - All users list (if the current user can enter for others)
5. **Feature Flags**: Based on the user's profile, the app shows or hides certain sections:
   - Project section (can be hidden)
   - Fleet section (can be hidden)
   - Allowances section (can be hidden)
   - Comments section (can be hidden)
   - Materials section (shown only for concrete mix lorry drivers)
6. **Fleet Mode**: If the user is a mechanic (`is_mechanic = true`), the app switches to "fleet mode" where they select a fleet item instead of a project.
7. **Time Autofill**: The app automatically fills in start and finish times based on:
   - If there are NO existing time periods for the selected date: Uses the user's saved start time for that day of the week (e.g., `monday_start_time`) or defaults to 7:30 AM if no saved time exists. The finish time is automatically set to start time + 30 minutes.
   - If there ARE existing time periods: The times are left empty so the user must enter them manually.

---

## Form Fields and Data Entry

### Employee Selection
- **For Regular Users**: The employee field is automatically set to the logged-in user and cannot be changed.
- **For Admins/High-Level Users**: A dropdown appears allowing them to select any employee from the system. When an employee is selected, the app loads that employee's profile data to determine if they're a mechanic (which affects fleet mode).

### Date Selection
- The date defaults to today's date.
- Users can change the date using a date picker.
- When the date changes, the app re-checks for existing time periods and re-autofills times if needed.

### Time Entry (Start Time and Finish Time)
- **Time Format**: All times are displayed in 12-hour format (e.g., "9:30 AM") in dropdowns and when displayed, but stored internally as 24-hour format (e.g., "09:30").
- **Start Time Dropdown**: Shows all times in 15-minute intervals throughout the day.
- **Finish Time Dropdown**: 
  - Only shows times that are at least 15 minutes after the selected start time.
  - Automatically sets to start time + 30 minutes when start time is selected.
  - Cannot be earlier than start time + 15 minutes.

### Break Times
- Users can add multiple breaks (Break 1, Break 2, etc.).
- **Break Start Time Dropdown**:
  - For the first break: Shows times from 15 minutes after start time to 15 minutes before finish time.
  - For subsequent breaks: Shows times from 15 minutes after the previous break's finish time to 15 minutes before finish time.
  - If the user has saved break times in their profile for the current day of the week, and those times fall within the start/finish range, they are automatically applied.
- **Break Finish Time Dropdown**:
  - Only shows times that are at least 15 minutes after the break start time.
  - Cannot be later than 15 minutes before the finish time.
- **Break Reason**: Users can optionally enter a reason for each break.
- **Load Standard Breaks Button**: Loads the user's saved break times from their profile for the current day of the week.
- **Load Full Day Button**: Loads the user's saved start time, finish time, and break times for the current day of the week.

### Project Selection
- **Regular Mode**: Users select from a dropdown of active projects. The dropdown can be filtered by typing to search.
- **Fleet Mode (Mechanics)**: Users select a fleet item by plant number instead of a project.
- **Find Nearest Job Button**: Uses GPS to find the nearest project to the user's current location.
- **Find Last Job Button**: Loads the last project the user worked on (from their project history).

### Fleet Entry
- **Used Fleet**: Users can enter up to 6 fleet items that were used during the time period.
- **Mobilised Fleet**: Users can enter up to 4 fleet items that were mobilised (moved to/from site).
- **Fleet Lookup**: When a user types a fleet number:
  - The app waits 1 second after the user stops typing (debounce).
  - Then looks up the fleet number in the `large_plant` table.
  - Displays the short description of the fleet item below the input field.
  - If the fleet number is not found, no description is shown.
- **Recall Fleet Button**: Loads the user's saved fleet numbers from their profile (`fleet_1` through `fleet_6`) and populates the "Used Fleet" fields. Also immediately looks up and displays the descriptions for all recalled fleet numbers.

### Allowances
- **Travel To Site**: Time in minutes spent traveling to the work site.
- **Travel From Site**: Time in minutes spent traveling from the work site.
- **Miscellaneous**: Other allowance time in minutes.
- **On Call**: Checkbox indicating if the user was on call.
- **Check Travel Button**: 
  - Gets the user's home GPS coordinates from their profile.
  - Gets the selected project's GPS coordinates.
  - Calculates distance and estimated travel time (using cached Google Maps API data if available, or a simple distance calculation as fallback).
  - Shows a dialog asking the user how to apply the travel time (to site, from site, or both).
  - Updates the travel allowance fields accordingly.

### Materials (Concrete Mix Lorry Drivers Only)
- **Ticket Number**: Concrete delivery ticket number.
- **Concrete Mix**: Type of concrete mix (dropdown).
- **Quantity**: Amount of concrete delivered.

### Comments
- Free-text field for any additional notes about the time period.

---

## Validation and Error Checking

### Before Saving
1. **Required Fields Check**: 
   - Employee must be selected.
   - Project (or fleet in fleet mode) must be selected.
   - Start time and finish time must be entered.
2. **Time Validation**:
   - Finish time must be after start time.
   - Break times must be within the start/finish time range.
3. **Overlap Check**: 
   - The app checks if the new time period overlaps with any existing time periods for the same user on the same date.
   - If an overlap is found, the save is blocked and an error message is shown.
4. **Gap Check**:
   - The app checks if there are gaps (more than 15 minutes) between the new time period and existing periods.
   - If a gap is found and the user hasn't entered a comment, a warning dialog appears asking if they want to continue. They can add a comment to explain the gap.

---

## Save Process

### Step 1: GPS Location
- The app attempts to get the user's current GPS location.
- If successful, it stores the latitude, longitude, and GPS accuracy.
- If it fails (e.g., GPS disabled, timeout), it continues without GPS data.

### Step 2: User ID Resolution
- Gets the authenticated user's ID from the current session (required for database security policies).
- If recording for another employee, it still uses the authenticated user's ID (the logged-in user) for security compliance, but logs a warning.

### Step 3: Project/Fleet ID Lookup
- **Regular Mode**: Finds the selected project in the projects list and gets its UUID.
- **Fleet Mode**: Finds the selected fleet item in the fleet list and gets its UUID.

### Step 4: Data Conversion
- Converts date and time strings into full timestamp objects.
- Converts travel allowances from strings to integers (minutes).
- Parses distance from calculated distance string (if available).

### Step 5: Overlap and Gap Checking
- Calls the overlap/gap checking function (described above).
- Blocks save if overlaps are found.
- Warns about gaps but allows save if user confirms.

### Step 6: Confirmation Dialog
- Shows a detailed summary dialog with:
  - Employee name
  - Date
  - Start time and finish time (in 12-hour format)
  - Total hours worked (excluding breaks)
  - Total break time
  - Project name
  - Used fleet items (with descriptions)
  - Mobilised fleet items (with descriptions)
  - Travel allowances
  - On-call status
  - Comments
- User must click "OK" to proceed or "Cancel" to abort.
- Buttons are large, separated, and styled for easy selection.

### Step 7: Database Save (If Online)
1. **Create Time Period Record**: 
   - Creates a record in the `time_periods` table with all the time period data.
   - Gets back the new time period's ID.
2. **Save Breaks**:
   - For each break entered, creates a record in the `time_breaks` table.
   - Links each break to the time period using the time period ID.
   - Converts break times to full timestamps (combines date + time).
3. **Save Used Fleet**:
   - Looks up each fleet number in the `large_plant` table to get its UUID.
   - Verifies each UUID exists and is accessible (checks database security).
   - Creates a record in the `time_used_large_plant` table with up to 6 fleet IDs.
4. **Save Mobilised Fleet**:
   - Similar to used fleet, but creates a record in `time_mobilised_large_plant` table with up to 4 fleet IDs.
5. **Update User Project History**:
   - Updates the user's profile (`users_data` table) with the most recent projects they've worked on.
   - Stores the project name and the date it was last used.
   - This is used for the "Find Last Job" feature.

### Step 8: Offline Save (If Offline)
- If the device is offline, the time period data is saved to local offline storage.
- The data is queued for later synchronization when the device comes back online.
- A counter shows how many entries are pending sync.

### Step 9: Form Reset
- After successful save, the form is reset for the next entry.
- The start time is automatically set to the finish time of the just-saved period (so users can easily chain time periods).
- All other fields are cleared.

---

## Offline Support

### Offline Storage
- When offline, all time period data is saved to a local database (SQLite on mobile devices).
- The data includes all form fields plus breaks and fleet information.
- A counter at the top of the screen shows how many entries are pending sync.

### Auto-Sync
- When the device comes back online, the app automatically attempts to sync all pending entries.
- The sync process:
  1. Reads all pending entries from local storage.
  2. For each entry, attempts to save it to the Supabase database.
  3. If successful, removes it from the local queue.
  4. If it fails (e.g., validation error, network issue), keeps it in the queue for retry.

### Manual Sync
- Users can manually trigger a sync by clicking a sync button (if available in the UI).
- Shows progress and results (how many entries were synced successfully).

---

## Special Features

### Fleet Description Lookup
- When users type a fleet number, the app looks up the description after 1 second of no typing.
- The description is cached so it doesn't need to look it up again for the same fleet number.
- Descriptions are displayed below each fleet input field.

### Time Dropdown Filtering
- Time dropdowns are dynamically filtered based on:
  - Start time (for finish time dropdown)
  - Previous break times (for subsequent break dropdowns)
  - Finish time (for all break dropdowns)
- This prevents users from selecting invalid time combinations.

### Project History
- The app tracks the last 10 projects a user worked on.
- Each project is stored with the date it was last used.
- This enables the "Find Last Job" feature.

### GPS and Travel Calculation
- The app can calculate travel time and distance between the user's home and the selected project.
- Uses cached Google Maps API data when available to avoid unnecessary API calls.
- Falls back to simple distance calculation if cache is unavailable.
- Travel time can be applied to "Travel To Site", "Travel From Site", or both.

---

## Error Handling

### Network Errors
- If a save fails due to network issues, the data is automatically saved offline.
- User is notified that the entry will be synced when online.

### Validation Errors
- All validation errors are shown as red snackbar messages at the bottom of the screen.
- Specific error messages explain what needs to be fixed.

### Database Errors
- If a save fails due to database security policies (RLS), a clear error message is shown.
- If saving breaks or fleet fails, warnings are shown but the time period is still saved.

### GPS Errors
- If GPS is unavailable, the save continues without GPS data.
- No error is shown to the user (GPS is optional).

---

## User Interface Updates

### Real-Time Updates
- The form updates in real-time as users make changes.
- Fleet descriptions appear automatically after lookup.
- Time dropdowns update when start/finish times change.
- Break dropdowns update when previous breaks are added/removed.

### Visual Feedback
- Green snackbars for success messages.
- Red snackbars for errors.
- Orange snackbars for warnings.
- Loading indicators during sync operations.
- Offline indicator at the top when offline.

---

## Security and Permissions

### Row-Level Security (RLS)
- All database operations respect Supabase Row-Level Security policies.
- Users can only create time periods for themselves (using their authenticated user ID).
- Admins may have additional permissions, but the current implementation uses the authenticated user's ID for all saves.

### User Permissions
- Only users with Admin role or security level 2 or lower can enter time for other employees.
- Regular users can only enter time for themselves.

---

## Summary

The Timesheet Screen is a comprehensive time entry system that:
- Handles both online and offline scenarios
- Validates data to prevent errors and overlaps
- Provides intelligent autofill based on user history
- Supports multiple work types (regular projects, fleet/mechanic work)
- Tracks detailed information (breaks, fleet, allowances, materials)
- Uses GPS for location tracking and travel calculations
- Maintains user preferences and history
- Provides clear feedback and error messages
- Ensures data integrity through validation and security policies

