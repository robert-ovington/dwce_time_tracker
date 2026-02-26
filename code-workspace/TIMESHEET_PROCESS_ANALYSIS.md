# Timesheet Screen Process Analysis

## PHASE 1: SCREEN LOADING/INITIALIZATION

1. **Initialize State** - Set up all variables and flags (online status, form fields, lists, etc.)

2. **Setup Connectivity Listener** - Start monitoring internet connection status (runs continuously in background)

3. **Initialize Offline Storage** - Prepare local database for offline queue (only on mobile platforms)

4. **Load Current User** - Get authenticated user information from Supabase Auth
   - Get user ID and email
   - Check user's security level from `users_setup` table
   - Determine if user can enter time for others (security level 1-4)

5. **Load All Users** - Fetch all users from `users_data` table
   - Get forename/surname for display
   - Merge with security levels from `users_setup`
   - Set default selected employee to current user

6. **Load User Data** - Fetch current user's preferences from `users_data` table
   - Get feature flags (show_project, show_fleet, show_allowances, show_comments)
   - Get user type (is_mechanic)
   - Get default times for each day of week
   - **Autofill start/finish times** based on selected date and day of week

7. **Load Employers** - Fetch all employers from `employers` table (for filtering employees)

8. **Load Projects** - Fetch all active projects from `projects` table
   - If no active projects, fallback to all projects
   - Store in `_allProjects` list

9. **Load Plant/Fleet** - Fetch all active fleet items from `large_plant` table
   - If no active fleet, fallback to all fleet
   - Store in `_allPlant` list
   - **Build lookup map** (`_plantMapByNo`) for fast O(1) access by plant number

10. **Load Concrete Mixes** - Fetch active concrete mixes (only if user has `concrete_mix_lorry` enabled)

11. **Update Pending Count** - Check offline queue for unsynced entries

**NOTE:** All loading steps run sequentially (one after another), not in parallel.

---

## PHASE 2: DATA INPUT (User Interactions)

12. **User Selects Date** - When date changes:
    - Autofill start/finish times based on day of week from user preferences
    - If date is not today, show "Reset to Today" button

13. **User Enters Start/Finish Times** - Dropdown selections with 15-minute intervals

14. **User Adds Breaks** - Optional break entries:
    - Break start/finish dropdowns filtered based on time period length
    - Validation: break must start at least 0 minutes after start time
    - Validation: break must finish at least 0 minutes before finish time

15. **User Selects Project or Fleet** - Dropdown with filter text box:
    - For projects: filter by project name (supports multiple search terms)
    - For fleet: filter by plant number or description (supports multiple search terms)
    - **Store description** from dropdown selection in `_selectedProjectDescription` (no lookup needed later)

16. **User Enters Used Fleet Numbers** - Text input fields:
    - **Debounced lookup** (1 second delay after typing stops)
    - Lookup fleet description from `_allPlant` list
    - Show description below input field
    - Mark invalid fleet numbers in red

17. **User Enters Mobilised Fleet Numbers** - Same as Used Fleet (separate debounced lookups)

18. **User Enters Travel Allowances** - Optional time entries for travel to/from site and miscellaneous

19. **User Enters Comments** - Optional text field

20. **User Toggles On-Call** - Optional checkbox

21. **User Enters Concrete Mix Details** - Optional (only if materials enabled):
    - Ticket number
    - Mix type dropdown
    - Quantity

---

## PHASE 3: SAVING PROCESS (When "Upload Time Period" is clicked)

22. **Set Saving Flag** - Prevent multiple clicks (`_isSaving = true`)

23. **Validate Form** - Check:
    - Employee is selected
    - Project/Fleet is selected
    - No invalid fleet numbers
    - Start and finish times are entered

24. **Get GPS Location** - Request current position from device
    - **DELAY: 200-3000ms** (varies by device/GPS signal)
    - Uses high accuracy with 5-second timeout
    - Stores latitude, longitude, and accuracy

25. **Get User ID** - Extract from authenticated session
    - Uses current user ID (not selected employee ID for RLS compliance)

26. **Lookup Project/Fleet ID** - Find database ID from selected name/number
    - **For Fleet Mode:** Search `_allPlant` list by `plant_no` (O(n) search)
    - **For Project Mode:** Search `_allProjects` list by `project_name` (O(n) search)
    - **DELAY: 0-1ms** (very fast, in-memory search)
    - **OPTIMIZATION OPPORTUNITY:** Could use map lookup instead of `firstWhere` for O(1) access

27. **Parse Date/Time Strings** - Convert form inputs to DateTime objects
    - Combine date string with start/finish time strings
    - Handle timezone conversion

28. **Parse Travel Allowances** - Convert allowance strings to integer minutes

29. **Parse Distance** - Extract numeric value from calculated distance string

30. **Validate Timestamps** - Ensure start and finish times are valid

31. **Check for Overlaps and Gaps** - Query database for existing time periods
    - **DELAY: 80-600ms** (database query)
    - Fetches all time periods for user on the same date
    - Checks if new period overlaps with existing periods
    - Checks for gaps between periods
    - **If overlap detected:** Show error, prevent save
    - **If gap detected:** Show warning dialog (user can continue or cancel)

32. **Build Confirmation Dialog** - Create summary dialog widget
    - Filter empty breaks, fleet items
    - **Get fleet descriptions** using `_plantMapByNo` map (O(1) lookups) - **OPTIMIZED**
    - Calculate total break time
    - Calculate total hours worked (minus breaks)
    - Format all times to 12-hour format
    - **DELAY: 3900-5500ms** (widget building/rendering)
    - **POTENTIAL BOTTLENECK:** Dialog widget is complex with many calculations and formatting

33. **Show Confirmation Dialog** - Display dialog and wait for user response
    - User can click "OK" to confirm or "Cancel" to abort
    - **DELAY: User interaction time** (varies)

34. **Build Time Period Data Object** - Create map with all fields for database
    - Includes user_id, project_id or mechanic_large_plant_id
    - Includes timestamps, allowances, GPS data, etc.

35. **Create Time Period Record** - Insert into `time_periods` table
    - **DELAY: 97-244ms** (database insert)
    - Returns new record ID

36. **Save Breaks** - If breaks exist, insert into `time_period_breaks` table
    - One insert per break
    - **DELAY: 0-138ms** (depends on number of breaks)

37. **Save Used Fleet** - If used fleet exists, insert into `time_period_used_fleet` table
    - One insert per fleet item
    - **DELAY: 0-2ms** (usually none)

38. **Save Mobilised Fleet** - If mobilised fleet exists, insert into `time_period_mobilised_fleet` table
    - One insert per fleet item
    - **DELAY: 0-2ms** (usually none)

39. **Update User Project History** - If project mode, update `users_data` table
    - Updates `project_1` through `project_10` fields
    - Updates `project_X_changed_at` timestamp
    - **DELAY: Included in total save time**

40. **Show Success Message** - Display green snackbar notification

41. **Reset Form** - Clear all form fields
    - Preserve selected date (don't reset to today)
    - Clear comment field (using ValueKey to force rebuild)
    - Set start time to previous finish time (for quick entry of next period)

42. **Clear Saving Flag** - Allow new save attempts (`_isSaving = false`)

---

## IDENTIFIED DELAYS AND OPTIMIZATION OPPORTUNITIES

### Major Delays:
1. **GPS Acquisition: 200-3000ms**
   - **Cause:** Device GPS hardware response time
   - **Optimization:** Could be done in background while user fills form, or made optional
   - **Impact:** Medium (user waits before save can proceed)

2. **Confirmation Dialog Building: 3900-5500ms**
   - **Cause:** Complex widget tree with many calculations and formatting operations
   - **Optimization Opportunities:**
     - Pre-calculate values before building dialog
     - Simplify dialog structure
     - Use cached values instead of recalculating
     - Consider lazy loading dialog content
   - **Impact:** High (this is the main delay in save process)

3. **Overlap Check: 80-600ms**
   - **Cause:** Database query to fetch existing time periods
   - **Optimization:** Could cache recent time periods in memory
   - **Impact:** Low (acceptable delay)

### Minor Delays:
4. **Database Create: 97-244ms** - Acceptable
5. **Breaks/Fleet Save: 0-138ms** - Acceptable

### Potential Optimizations:

1. **Project/Fleet ID Lookup (Step 26)**
   - Currently uses `firstWhere` (O(n) search)
   - Could use map lookup: `_projectMapByName` for O(1) access
   - **Impact:** Minimal (already very fast at 0-1ms)

2. **Confirmation Dialog (Step 32)**
   - Pre-calculate all values before `showDialog` is called
   - Build dialog content in a separate method that's called once
   - Cache formatted strings instead of recalculating
   - **Impact:** High (could reduce 4-5 second delay significantly)

3. **GPS Acquisition (Step 24)**
   - Start GPS request when form is opened or when user starts filling
   - Cache last known location
   - Make GPS optional (allow save without location)
   - **Impact:** Medium (could improve perceived responsiveness)

4. **Loading Phase (Steps 1-11)**
   - Currently sequential (one after another)
   - Could load independent data in parallel (projects, plant, employers, concrete mixes)
   - **Impact:** Medium (could reduce initial load time)

5. **Overlap Check (Step 31)**
   - Cache time periods for current date in memory
   - Only refresh when new period is saved
   - **Impact:** Low (already fast enough)

---

## TOTAL SAVE TIME BREAKDOWN (from console logs)

- GPS Acquisition: ~200-3000ms
- Project/Plant ID Lookup: ~0-1ms
- Overlap Check: ~80-600ms
- Confirmation Dialog: ~3900-5500ms ⚠️ **MAIN BOTTLENECK**
- Database Create: ~97-244ms
- Breaks/Fleet Save: ~0-138ms
- **Total: ~4000-6000ms (4-6 seconds)**

---

## RECOMMENDATIONS

### High Priority:
1. **Optimize Confirmation Dialog Building** - This is causing 4-5 second delay
   - Pre-calculate all values before building dialog
   - Simplify widget tree
   - Consider showing a loading indicator while dialog builds

2. **Make GPS Optional or Background** - Don't block save process for GPS
   - Start GPS request early
   - Allow save to proceed if GPS times out

### Medium Priority:
3. **Parallel Data Loading** - Load independent data sources simultaneously
4. **Cache Time Periods** - Keep recent periods in memory to speed up overlap checks

### Low Priority:
5. **Map Lookups for Projects** - Already fast enough, but could be slightly faster

