import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../modules/users/user_service.dart';
import '../modules/auth/auth_service.dart';
import '../modules/messaging/messaging_service.dart';
import '../config/supabase_config.dart';
import '../widgets/app_dialog.dart';
import '../widgets/screen_info_icon.dart';
import 'timesheet_screen.dart';
import 'my_time_periods_screen.dart';
import 'asset_check_screen.dart';
import 'my_checks_screen.dart';
import 'delivery_screen.dart';
import 'supervisor_approval_screen.dart';
import 'admin_staff_attendance_screen.dart';
import 'admin_staff_summary_screen.dart';
import 'admin_screen.dart';
import 'user_creation_screen.dart';
import 'user_edit_screen.dart';
import 'employer_management_screen.dart';
import 'pay_rate_rules_screen.dart';
import 'platform_config_screen.dart';
import 'plant_location_report_screen.dart';
import 'fault_management_report_screen.dart';
import 'stock_locations_management_screen.dart';
import 'coming_soon_screen.dart';
import 'import_payroll_screen.dart';
import 'export_payroll_screen.dart';
import 'clock_in_out_screen.dart';
import 'clock_office_screen.dart';
import 'my_clockings_screen.dart';
import 'time_clocking_screen.dart';
import 'cube_details_screen.dart';
import 'login_screen.dart';
import 'messages_screen.dart';
import 'submit_employee_review_screen.dart';
import 'ppe_catalog_screen.dart';
import 'ppe_stock_levels_screen.dart';
import 'ppe_stock_receive_screen.dart';
import 'ppe_allocate_screen.dart';
import 'ppe_request_screen.dart';
import 'ppe_my_requests_screen.dart';
import 'ppe_request_approvals_screen.dart';
import 'ppe_user_setup_screen.dart';
import 'ppe_approved_requests_screen.dart';
import 'concrete_mix_bookings_screen.dart';
import 'concrete_mix_calendar_screen.dart';
import 'concrete_mix_scheduler_screen.dart';
import 'request_time_off_screen.dart';
import 'my_time_off_requests_screen.dart';
import 'request_type_screen.dart';
import 'request_manager_list_screen.dart';
import 'holiday_calendar_screen.dart';
// Messenger screens (new_message, message_log, message_template) not imported for smaller mobile build

/// Main Menu Screen (mobile build)
/// 
/// Responsive menu system:
/// - Mobile: Full-width menu, submenu items appear when clicked
/// - Web/Tablet: Left sidebar menu, can be minimized/expanded
/// - Permission-based visibility for menu items
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  bool _isLoading = true;
  Map<String, bool> _menuPermissions = {};
  Map<String, dynamic>? _userSetup;
  Map<String, dynamic>? _userData;
  String _currentUserEmail = '';
  bool _isOnline = true;

  // Menu state
  Set<String> _expandedItems = {};
  bool _isMenuMinimized = false; // For web sidebar
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _importantMessagesTimer;
  
  // Check if we're on a large screen (web/tablet)
  bool get _isLargeScreen {
    if (kIsWeb) return true;
    final width = MediaQuery.of(context).size.width;
    return width >= 768; // Tablet or larger
  }

  @override
  void initState() {
    super.initState();
    _loadMenuData();
    _initConnectivity();
    _checkImportantMessages();
  }

  /// Check for important messages periodically (not immediately; login already showed the dialog once).
  void _checkImportantMessages() {
    _importantMessagesTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        MessagingService.showImportantMessagesDialog(context);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _importantMessagesTimer?.cancel();
    super.dispose();
  }

  void _initConnectivity() {
    // Check initial connectivity
    Connectivity().checkConnectivity().then((results) {
      final isOnline = results.any((result) => result != ConnectivityResult.none);
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((result) => result != ConnectivityResult.none);
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  Future<void> _loadMenuData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load user setup and permissions
      _userSetup = await UserService.getCurrentUserSetup();
      _userData = await UserService.getCurrentUserData();
      _menuPermissions = await UserService.getAllMenuPermissions(setup: _userSetup);

      // Get current user email
      final currentUser = SupabaseService.client.auth.currentUser;
      _currentUserEmail = currentUser?.email ?? '';
      
    } catch (e) {
      print('❌ Error loading menu data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _toggleMenuExpansion(String menuKey) {
    setState(() {
      if (_expandedItems.contains(menuKey)) {
        _expandedItems.remove(menuKey);
      } else {
        _expandedItems.add(menuKey);
      }
    });
  }

  void _toggleMenuMinimized() {
    setState(() {
      _isMenuMinimized = !_isMenuMinimized;
    });
  }

  void _navigateToScreen(Widget screen) {
    if (_isLargeScreen) {
      // Web/Tablet: Navigate but keep menu visible
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen),
      );
    } else {
      // Mobile: Full screen navigation
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen),
      );
    }
  }

  /// Open Google Calendar URL from public.system_settings.google_calendar.
  Future<void> _openGoogleCalendar() async {
    try {
      final row = await SupabaseService.client
          .from('system_settings')
          .select('google_calendar')
          .limit(1)
          .maybeSingle();
      final url = row != null ? row['google_calendar']?.toString().trim() : null;
      if (url == null || url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Google Calendar link not set in system settings.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final uri = Uri.parse(url);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open: $url'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening calendar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showUserInfoPopup() {
    final displayName = _userSetup?['display_name'] ?? 
                       _userData?['display_name'] ?? 
                       _currentUserEmail;
    
    showAppDialog<void>(
      context: context,
      title: 'User Information',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Display Name', displayName.toString()),
          const SizedBox(height: 8),
          _buildInfoRow('Email', _currentUserEmail),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Change password feature coming soon')),
            );
          },
          child: const Text('Change Password'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Text(value),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isLargeScreen) {
      // Web/Tablet: Sidebar layout
      return Scaffold(
        body: SafeArea(
          child: Row(
          children: [
            // Sidebar Menu
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _isMenuMinimized ? 0 : 300,
              child: _isMenuMinimized
                  ? Container()
                  : Container(
                      color: Colors.grey.shade100,
                      child: Column(
                        children: [
                          // Header with minimize button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0081FB),
                              border: Border(
                                bottom: BorderSide(
                                  color: const Color(0xFFFEFE00),
                                  width: 4.0,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Main Menu',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
                                  onPressed: _toggleMenuMinimized,
                                  tooltip: 'Minimize menu',
                                ),
                              ],
                            ),
                          ),
                          // Menu items
                          Expanded(
                            child: _buildMenuList(),
                          ),
                          // User info at bottom
                          _buildUserInfoSection(),
                        ],
                      ),
                    ),
            ),
            // Content area
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: Text(
                      'Select an item from the menu',
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                    ),
                  ),
                  // Hamburger icon overlay when menu is minimized
                  if (_isMenuMinimized)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: _toggleMenuMinimized,
                        tooltip: 'Show menu',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        ),
      );
    } else {
      // Mobile: Full-width menu
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0081FB),
          title: const Text(
            'Main Menu',
            style: TextStyle(color: Colors.black),
          ),
          centerTitle: true,
          foregroundColor: Colors.black,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4.0),
            child: Container(
              height: 4.0,
              color: const Color(0xFFFEFE00),
            ),
          ),
          actions: [
            const ScreenInfoIcon(screenName: 'main_menu_screen_mobile.dart'),
            IconButton(
              icon: const Icon(Icons.person, color: Colors.white),
              onPressed: _showUserInfoPopup,
              tooltip: 'User Information',
            ),
            TextButton.icon(
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                'Sign Out',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () async {
                await AuthService.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const MainMenuScreen(),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _buildMenuList(),
              ),
              // User info at bottom (mobile) — omit on Android; Sign Out is in the app bar
              if (defaultTargetPlatform != TargetPlatform.android) _buildUserInfoSection(),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildMenuList() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        // Messages - Direct menu item for receiving messages
        if (_menuPermissions[UserService.menuMessages] == true)
          _buildDirectMenuItem(
            title: 'Messages',
            icon: Icons.message,
            onTap: () => _navigateToScreen(const MessagesScreen()),
          ),
        
        // Messenger submenu omitted in mobile build (Web/Windows only)
        
        // Menu items based on permissions
        if (_menuPermissions[UserService.menuClockIn] == true)
          _buildMenuSection(
            key: 'clock_in',
            title: 'Clock In',
            icon: Icons.access_time,
            subItems: [
              _SubMenuItem(
                title: 'Clock In/Out',
                onTap: () => _navigateToScreen(const ClockInOutScreen()),
              ),
              _SubMenuItem(
                title: 'My Clockings',
                onTap: () => _navigateToScreen(const MyClockingsScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuOffice] == true)
          _buildMenuSection(
            key: 'office',
            title: 'Office',
            icon: Icons.business,
            subItems: [
              _SubMenuItem(
                title: 'Clock In/Out',
                onTap: () => _navigateToScreen(const ClockOfficeScreen()),
              ),
              _SubMenuItem(
                title: 'My Clockings',
                onTap: () => _navigateToScreen(const MyClockingsScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuOfficeAdmin] == true)
          _buildMenuSection(
            key: 'office_admin',
            title: 'Office Admin',
            icon: Icons.admin_panel_settings,
            subItems: [
              _SubMenuItem(
                title: 'Attendance',
                onTap: () => _navigateToScreen(const AdminStaffAttendanceScreen()),
              ),
              _SubMenuItem(
                title: 'Summary',
                onTap: () => _navigateToScreen(const AdminStaffSummaryScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuConcreteMix] == true)
          _buildMenuSection(
            key: 'concrete_mix',
            title: 'Concrete Mix',
            icon: Icons.precision_manufacturing,
            subItems: [
              _SubMenuItem(
                title: 'Bookings',
                onTap: () => _navigateToScreen(const ConcreteMixBookingsScreen()),
              ),
              _SubMenuItem(
                title: 'Calendar',
                onTap: () => _navigateToScreen(const ConcreteMixCalendarScreen()),
              ),
              _SubMenuItem(
                title: 'Scheduler',
                onTap: () => _navigateToScreen(const ConcreteMixSchedulerScreen()),
              ),
              _SubMenuItem(
                title: 'Google Calendar',
                onTap: () => _openGoogleCalendar(),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuWorkshop] == true)
          _buildDirectMenuItem(
            title: 'Workshop',
            icon: Icons.build,
            onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Workshop')),
          ),
        
        if (_menuPermissions[UserService.menuTimePeriods] == true)
          _buildMenuSection(
            key: 'time_periods',
            title: 'Timesheets',
            icon: Icons.calendar_today,
            subItems: [
              _SubMenuItem(
                title: 'Clock In/Out',
                onTap: () => _navigateToScreen(const TimeClockingScreen()),
              ),
              _SubMenuItem(
                title: 'New Time Period',
                onTap: () => _navigateToScreen(const TimeTrackingScreen()),
              ),
              _SubMenuItem(
                title: 'My Time Periods',
                onTap: () => _navigateToScreen(const MyTimePeriodsScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuPlantChecks] == true)
          _buildMenuSection(
            key: 'plant_checks',
            title: 'Plant Checks',
            icon: Icons.construction,
            subItems: [
              _SubMenuItem(
                title: 'Large Plant',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Large Plant')),
              ),
              _SubMenuItem(
                title: 'Small Plant',
                onTap: () => _navigateToScreen(const AssetCheckScreen()),
              ),
              _SubMenuItem(
                title: 'My Checks',
                onTap: () => _navigateToScreen(const MyChecksScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuDeliveries] == true)
          _buildMenuSection(
            key: 'deliveries',
            title: 'Deliveries',
            icon: Icons.local_shipping,
            subItems: [
              _SubMenuItem(
                title: 'Aggregates',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Aggregates')),
              ),
              _SubMenuItem(
                title: 'Waste Dockets',
                onTap: () => _navigateToScreen(const DeliveryScreen()),
              ),
              _SubMenuItem(
                title: 'My Deliveries',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'My Deliveries')),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuPaperwork] == true)
          _buildMenuSection(
            key: 'paperwork',
            title: 'Paperwork',
            icon: Icons.description,
            subItems: [
              _SubMenuItem(
                title: 'Material Diaries',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Material Diaries')),
              ),
              _SubMenuItem(
                title: 'Cable Pulling',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Cable Pulling')),
              ),
              _SubMenuItem(
                title: 'My Paperwork',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'My Paperwork')),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuTimeOff] == true)
          _buildMenuSection(
            key: 'time_off_ppe',
            title: 'PPE',
            icon: Icons.event_busy,
            subItems: [
              _SubMenuItem(
                title: 'Request PPE',
                onTap: () => _navigateToScreen(const PpeRequestScreen()),
              ),
              _SubMenuItem(
                title: 'My PPE Requests',
                onTap: () => _navigateToScreen(const PpeMyRequestsScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuTraining] == true)
          _buildMenuSection(
            key: 'training',
            title: 'Training',
            icon: Icons.school,
            subItems: [
              _SubMenuItem(
                title: 'My Training',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'My Training')),
              ),
              _SubMenuItem(
                title: 'Search',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Search')),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuCubeTest] == true)
          _buildMenuSection(
            key: 'testing',
            title: 'Testing',
            icon: Icons.science,
            subItems: [
              _SubMenuItem(
                title: 'Cube Details',
                onTap: () => _navigateToScreen(const CubeDetailsScreen()),
              ),
              _SubMenuItem(
                title: 'Test Results',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Test Results')),
              ),
              _SubMenuItem(
                title: 'Summary',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Summary')),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuSites] == true)
          _buildMenuSection(
            key: 'sites',
            title: 'Sites',
            icon: Icons.location_on,
            subItems: [
              _SubMenuItem(
                title: 'Site Attendance',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Site Attendance')),
              ),
              _SubMenuItem(
                title: 'Plant on Site',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Plant on Site')),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuReports] == true)
          _buildMenuSection(
            key: 'reports',
            title: 'Reports',
            icon: Icons.assessment,
            subItems: [
              _SubMenuItem(
                title: 'Small Plant Location Report',
                onTap: () => _navigateToScreen(const SmallPlantLocationReportScreen()),
              ),
              _SubMenuItem(
                title: 'Small Plant Fault Management',
                onTap: () => _navigateToScreen(const SmallPlantFaultManagementReportScreen()),
              ),
              _SubMenuItem(
                title: 'Large Plant Prestart Checks',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Large Plant Prestart Checks')),
              ),
              _SubMenuItem(
                title: 'Large Plant Fault Management',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Large Plant Fault Management')),
              ),
              _SubMenuItem(
                title: 'Stock Locations',
                onTap: () => _navigateToScreen(const StockLocationsManagementScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuManagers] == true)
          _buildMenuSection(
            key: 'payroll',
            title: 'Managers',
            icon: Icons.payment,
            subItems: [
              _SubMenuItem(
                title: 'Employee Review',
                onTap: () => _navigateToScreen(const SubmitEmployeeReviewScreen()),
              ),
              _SubMenuItem(
                title: 'Timesheet Approval',
                onTap: () => _navigateToScreen(const SupervisorApprovalScreen()),
              ),
              _SubMenuItem(
                title: 'Time Off Requests',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Time Off Requests')),
              ),
              _SubMenuItem(
                title: 'PPE Request Approvals',
                onTap: () => _navigateToScreen(const PpeRequestApprovalsScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.ppeManager] == true)
          _buildMenuSection(
            key: 'ppe_management',
            title: 'PPE Management',
            icon: Icons.health_and_safety,
            subItems: [
              _SubMenuItem(
                title: 'User Setup',
                onTap: () => _navigateToScreen(const PpeUserSetupScreen()),
              ),
              _SubMenuItem(
                title: 'PPE Requests',
                onTap: () => _navigateToScreen(const PpeApprovedRequestsScreen()),
              ),
              _SubMenuItem(
                title: 'PPE Catalog',
                onTap: () => _navigateToScreen(const PpeCatalogScreen()),
              ),
              _SubMenuItem(
                title: 'Stock / Receive PPE',
                onTap: () => _navigateToScreen(const PpeStockReceiveScreen()),
              ),
              _SubMenuItem(
                title: 'Stock Levels',
                onTap: () => _navigateToScreen(const PpeStockLevelsScreen()),
              ),
              _SubMenuItem(
                title: 'Allocate PPE',
                onTap: () => _navigateToScreen(const PpeAllocateScreen()),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuExports] == true)
          _buildMenuSection(
            key: 'exports',
            title: 'Exports',
            icon: Icons.file_download,
            subItems: [
              _SubMenuItem(
                title: 'Import Payroll',
                onTap: () => _navigateToScreen(const ImportPayrollScreen()),
              ),
              _SubMenuItem(
                title: 'Export Payroll',
                onTap: () => _navigateToScreen(const ExportPayrollScreen()),
              ),
              _SubMenuItem(
                title: 'Export Deliveries',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Export Deliveries')),
              ),
              _SubMenuItem(
                title: 'Export Diaries',
                onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Export Diaries')),
              ),
            ],
          ),
        
        if (_menuPermissions[UserService.menuAdministration] == true)
          _buildMenuSection(
            key: 'administration',
            title: 'Administration',
            icon: Icons.admin_panel_settings,
            subItems: [
              _SubMenuItem(
                title: 'Create User',
                onTap: () => _navigateToScreen(const UserCreationScreen()),
              ),
              _SubMenuItem(
                title: 'Edit User',
                onTap: () => _navigateToScreen(const UserEditScreen()),
              ),
              _SubMenuItem(
                title: 'Employer',
                onTap: () => _navigateToScreen(const EmployerManagementScreen()),
              ),
              _SubMenuItem(
                title: 'Pay Types',
                onTap: () => _navigateToScreen(const PayRateRulesScreen()),
              ),
              _SubMenuItem(
                title: 'Platform Config',
                onTap: () => _navigateToScreen(const PlatformConfigScreen()),
              ),
              _SubMenuItem(
                title: 'Request Type',
                onTap: () => _navigateToScreen(const RequestTypeScreen()),
              ),
              _SubMenuItem(
                title: 'Request List',
                onTap: () => _navigateToScreen(const RequestManagerListScreen()),
              ),
            ],
          ),
      ],
    );
  }

  /// Build a direct menu item (no submenu, navigates directly)
  Widget _buildDirectMenuItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFBADDFF), // Light Blue Background
          border: Border.all(
            color: const Color(0xFF005AB0), // Dark Blue Border
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12), // Round all corners
        ),
        child: ListTile(
          leading: Icon(icon, color: Colors.black),
          title: Text(
            title,
            style: const TextStyle(color: Colors.black),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildMenuSection({
    required String key,
    required String title,
    required IconData icon,
    required List<_SubMenuItem> subItems,
  }) {
    final isExpanded = _expandedItems.contains(key);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Expanded container - wraps main item and submenu items in one blue box
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFBADDFF), // Light Blue Background (same as main item)
                border: Border.all(
                  color: const Color(0xFF005AB0), // Dark Blue Border (same as main item)
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12), // Round all corners
              ),
              child: Column(
                children: [
                  // Top level menu item - no bottom border, square bottom corners
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide.none, // No bottom border
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(icon, color: Colors.black),
                      title: Text(
                        title,
                        style: const TextStyle(color: Colors.black),
                      ),
                      trailing: Icon(
                        Icons.expand_less,
                        color: Colors.black,
                      ),
                      onTap: () => _toggleMenuExpansion(key),
                    ),
                  ),
                  // Submenu items - Light Green Background, Dark Green Border (original style)
                  ...subItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final isLast = index == subItems.length - 1;
                    return Container(
                      margin: EdgeInsets.only(
                        left: 8.0,
                        right: 8.0,
                        bottom: isLast ? 8.0 : 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50, // Light Green Background
                        border: Border.all(
                          color: Colors.green.shade700, // Dark Green Border
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12), // Round all corners
                      ),
                      child: ListTile(
                        title: Text(
                          item.title,
                          style: const TextStyle(color: Colors.black),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black),
                        onTap: item.onTap,
                      ),
                    );
                  }),
                ],
              ),
            )
          else
            // Minimized - main menu item with all borders and rounded corners
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFBADDFF), // Light Blue Background
                border: Border.all(
                  color: const Color(0xFF005AB0), // Dark Blue Border
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12), // Round all corners
              ),
              child: ListTile(
                leading: Icon(icon, color: Colors.black),
                title: Text(
                  title,
                  style: const TextStyle(color: Colors.black),
                ),
                trailing: const Icon(
                  Icons.expand_more,
                  color: Colors.black,
                ),
                onTap: () => _toggleMenuExpansion(key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserInfoSection() {
    final displayName = _userSetup?['display_name'] ?? 
                       _userData?['display_name'] ?? 
                       _currentUserEmail;
    
    // Status indicator matching Timesheet screen format
    final statusColor = _isOnline ? Colors.green.shade50 : Colors.orange.shade50;
    final statusIconColor = _isOnline ? Colors.green : Colors.orange;
    final statusTextColor = _isOnline ? Colors.green.shade700 : Colors.orange.shade700;
    final statusIcon = _isOnline ? Icons.cloud_done : Icons.cloud_off;
    final statusText = _isOnline ? 'Online' : 'Offline';
    
    if (_isLargeScreen) {
      // Web: Show in sidebar
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: statusColor, // Background color based on Online/Offline status
          border: Border(
            top: BorderSide(
              color: const Color(0xFF0081FB), // Blue border
              width: 4.0,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status section with icon, text, and Sign Out button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusIconColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                // Sign Out button styled like Main Menu item
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFBADDFF), // Light Blue Background
                    border: Border.all(
                      color: const Color(0xFF005AB0), // Dark Blue Border
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12), // Round all corners
                  ),
                  child: TextButton.icon(
                    icon: const Icon(Icons.logout, size: 16, color: Colors.black),
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(color: Colors.black),
                    ),
                    onPressed: () async {
                      await AuthService.signOut();
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                          (route) => false, // Remove all previous routes
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current User:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayName.toString(),
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: _showUserInfoPopup,
                  tooltip: 'User Information',
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Mobile: Show at bottom (not used on Android — bottom block omitted there)
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: statusColor,
          border: Border(
            top: BorderSide(
              color: const Color(0xFF0081FB),
              width: 4.0,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusIconColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFBADDFF),
                    border: Border.all(color: const Color(0xFF005AB0), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextButton.icon(
                    icon: const Icon(Icons.logout, size: 16, color: Colors.black),
                    label: const Text('Sign Out', style: TextStyle(color: Colors.black)),
                    onPressed: () async {
                      await AuthService.signOut();
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current User:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayName.toString(),
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: _showUserInfoPopup,
                  tooltip: 'User Information',
                ),
              ],
            ),
          ],
        ),
      );
    }
  }
}

class _SubMenuItem {
  final String title;
  final VoidCallback onTap;

  _SubMenuItem({
    required this.title,
    required this.onTap,
  });
}
