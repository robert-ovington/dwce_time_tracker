# Main Menu items and associated screens

Menu items from `lib/screens/main_menu_screen.dart`. Visibility is controlled by user permissions (e.g. `menu_clock_in`, `menu_administration`).

---

## Direct menu items (no submenu)

| Menu item | Screen | Permission |
|-----------|--------|------------|
| **Messages** | `MessagesScreen` | `menu_messages` |

---

## Messenger *(Web/Windows only; not on Android/iOS)*

| Menu item | Screen | Permission |
|-----------|--------|------------|
| New Message | `NewMessageScreen` | `menu_messenger` |
| Message Log | `MessageLogScreen` | `menu_messenger` |
| Message Template | `MessageTemplateScreen` | `menu_messenger` |

---

## Clock In

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Clock In/Out | `ClockInOutScreen` | `menu_clock_in` |
| My Clockings | `MyClockingsScreen` | `menu_clock_in` |

---

## Office

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Clock In/Out | `ClockOfficeScreen` | `menu_office` |
| My Clockings | `MyClockingsScreen` | `menu_office` |

---

## Office Admin

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Attendance | `AdminStaffAttendanceScreen` | `menu_office_admin` |
| Summary | `AdminStaffSummaryScreen` | `menu_office_admin` |

---

## Timesheets

| Menu item | Screen | Permission |
|-----------|--------|------------|
| New Time Period | `TimeTrackingScreen` | `menu_time_periods` |
| My Time Periods | `MyTimePeriodsScreen` | `menu_time_periods` |
| Clock In/Out | `TimeClockingScreen` | `menu_time_periods` |

---

## Plant Checks

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Large Plant | `ComingSoonScreen` (featureName: Large Plant) | `menu_plant_checks` |
| Small Plant | `AssetCheckScreen` | `menu_plant_checks` |
| My Checks | `MyChecksScreen` | `menu_plant_checks` |

---

## Deliveries

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Aggregates | `ComingSoonScreen` (featureName: Aggregates) | `menu_deliveries` |
| Waste Dockets | `DeliveryScreen` | `menu_deliveries` |
| My Deliveries | `ComingSoonScreen` (featureName: My Deliveries) | `menu_deliveries` |

---

## Paperwork

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Material Diaries | `ComingSoonScreen` (featureName: Material Diaries) | `menu_paperwork` |
| Cable Pulling | `ComingSoonScreen` (featureName: Cable Pulling) | `menu_paperwork` |
| My Paperwork | `ComingSoonScreen` (featureName: My Paperwork) | `menu_paperwork` |

---

## Time Off

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Request Time Off | `ComingSoonScreen` (featureName: Request Time Off) | `menu_time_off` |
| Holiday Calendar | `ComingSoonScreen` (featureName: Holiday Calendar) | `menu_time_off` |
| My Requests | `ComingSoonScreen` (featureName: My Requests) | `menu_time_off` |

---

## Training

| Menu item | Screen | Permission |
|-----------|--------|------------|
| My Training | `ComingSoonScreen` (featureName: My Training) | `menu_training` |
| Search | `ComingSoonScreen` (featureName: Search) | `menu_training` |

---

## Testing

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Cube Details | `CubeDetailsScreen` | `menu_cube_test` |
| Test Results | `ComingSoonScreen` (featureName: Test Results) | `menu_cube_test` |
| Summary | `ComingSoonScreen` (featureName: Summary) | `menu_cube_test` |

---

## Sites

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Site Attendance | `ComingSoonScreen` (featureName: Site Attendance) | `menu_sites` |
| Plant on Site | `ComingSoonScreen` (featureName: Plant on Site) | `menu_sites` |

---

## Reports

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Small Plant Location Report | `SmallPlantLocationReportScreen` | `menu_reports` |
| Small Plant Fault Management | `SmallPlantFaultManagementReportScreen` | `menu_reports` |
| Large Plant Prestart Checks | `ComingSoonScreen` (featureName: Large Plant Prestart Checks) | `menu_reports` |
| Large Plant Fault Management | `ComingSoonScreen` (featureName: Large Plant Fault Management) | `menu_reports` |
| Stock Locations | `StockLocationsManagementScreen` | `menu_reports` |

---

## Managers

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Tar Crew | `ComingSoonScreen` (featureName: Tar Crew) | `menu_managers` |
| Timesheets | `SupervisorApprovalScreen` | `menu_managers` |
| Time Off Requests | `ComingSoonScreen` (featureName: Time Off Requests) | `menu_managers` |

---

## Exports

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Export Payroll | `ComingSoonScreen` (featureName: Export Payroll) | `menu_exports` |
| Export Deliveries | `ComingSoonScreen` (featureName: Export Deliveries) | `menu_exports` |
| Export Diaries | `ComingSoonScreen` (featureName: Export Diaries) | `menu_exports` |

---

## Administration

| Menu item | Screen | Permission |
|-----------|--------|------------|
| Create User | `UserCreationScreen` | `menu_administration` |
| Edit User | `UserEditScreen` | `menu_administration` |
| Employer | `EmployerManagementScreen` | `menu_administration` |
| Platform Config | `PlatformConfigScreen` | `menu_administration` |

---

## Screen file reference

| Screen class | File |
|--------------|------|
| `MessagesScreen` | `lib/screens/messages_screen.dart` |
| `NewMessageScreen` | `lib/screens/new_message_screen.dart` |
| `MessageLogScreen` | `lib/screens/message_log_screen.dart` |
| `MessageTemplateScreen` | `lib/screens/message_template_screen.dart` |
| `ClockInOutScreen` | `lib/screens/clock_in_out_screen.dart` |
| `MyClockingsScreen` | `lib/screens/my_clockings_screen.dart` |
| `ClockOfficeScreen` | `lib/screens/clock_office_screen.dart` |
| `AdminStaffAttendanceScreen` | `lib/screens/admin_staff_attendance_screen.dart` |
| `AdminStaffSummaryScreen` | `lib/screens/admin_staff_summary_screen.dart` |
| `TimeTrackingScreen` | `lib/screens/timesheet_screen.dart` |
| `MyTimePeriodsScreen` | `lib/screens/my_time_periods_screen.dart` |
| `TimeClockingScreen` | `lib/screens/time_clocking_screen.dart` |
| `AssetCheckScreen` | `lib/screens/asset_check_screen.dart` |
| `MyChecksScreen` | `lib/screens/my_checks_screen.dart` |
| `DeliveryScreen` | `lib/screens/delivery_screen.dart` |
| `CubeDetailsScreen` | `lib/screens/cube_details_screen.dart` |
| `SmallPlantLocationReportScreen` | `lib/screens/plant_location_report_screen.dart` |
| `SmallPlantFaultManagementReportScreen` | `lib/screens/fault_management_report_screen.dart` |
| `StockLocationsManagementScreen` | `lib/screens/stock_locations_management_screen.dart` |
| `SupervisorApprovalScreen` | `lib/screens/supervisor_approval_screen.dart` |
| `UserCreationScreen` | `lib/screens/user_creation_screen.dart` |
| `UserEditScreen` | `lib/screens/user_edit_screen.dart` |
| `EmployerManagementScreen` | `lib/screens/employer_management_screen.dart` |
| `PlatformConfigScreen` | `lib/screens/platform_config_screen.dart` |
| `ComingSoonScreen` | `lib/screens/coming_soon_screen.dart` |
