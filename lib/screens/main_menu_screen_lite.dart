/// Main Menu Screen (lite build)
///
/// Bare-minimum menu for lite mobile app (basic users).
/// Only includes screens with lite=true in platform_screens.dart.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../modules/users/user_service.dart';
import '../modules/auth/auth_service.dart';
import '../modules/messaging/messaging_service.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import 'messages_screen.dart';
import 'clock_in_out_screen.dart';
import 'my_clockings_screen.dart';
import 'timesheet_screen.dart';
import 'my_time_periods_screen.dart';
import 'time_clocking_screen.dart';
import 'coming_soon_screen.dart';
import 'concrete_mix_bookings_screen.dart';
import 'concrete_mix_calendar_screen.dart';
import 'concrete_mix_scheduler_screen.dart';
import 'login_screen.dart';

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
  Set<String> _expandedItems = {};
  bool _isMenuMinimized = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _importantMessagesTimer;

  bool get _isLargeScreen {
    if (kIsWeb) return true;
    final width = MediaQuery.of(context).size.width;
    return width >= 768;
  }

  @override
  void initState() {
    super.initState();
    _loadMenuData();
    _initConnectivity();
    _checkImportantMessages();
  }

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
    Connectivity().checkConnectivity().then((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = isOnline);
    });
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = isOnline);
    });
  }

  Future<void> _loadMenuData() async {
    setState(() => _isLoading = true);
    try {
      _userSetup = await UserService.getCurrentUserSetup();
      _userData = await UserService.getCurrentUserData();
      _menuPermissions = await UserService.getAllMenuPermissions(setup: _userSetup);
      _currentUserEmail = SupabaseService.client.auth.currentUser?.email ?? '';
    } catch (e) {
      print('❌ Error loading menu data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleMenuExpansion(String key) {
    setState(() {
      if (_expandedItems.contains(key)) {
        _expandedItems.remove(key);
      } else {
        _expandedItems.add(key);
      }
    });
  }

  void _toggleMenuMinimized() {
    setState(() => _isMenuMinimized = !_isMenuMinimized);
  }

  void _navigateToScreen(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
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
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
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
    final displayName = _userSetup?['display_name'] ?? _userData?['display_name'] ?? _currentUserEmail;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('User Information'),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(child: Text(value)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_isLargeScreen) {
      return Scaffold(
        body: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _isMenuMinimized ? 0 : 300,
              child: _isMenuMinimized ? Container() : Container(
                color: Colors.grey.shade100,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0081FB),
                        border: Border(bottom: BorderSide(color: const Color(0xFFFEFE00), width: 4.0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(child: Text('Lite Menu', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20), onPressed: _toggleMenuMinimized, tooltip: 'Minimize'),
                        ],
                      ),
                    ),
                    Expanded(child: _buildMenuList()),
                    _buildUserInfoSection(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  const Center(child: Text('Select an item from the menu', style: TextStyle(fontSize: 16, color: Colors.grey))),
                  if (_isMenuMinimized) Positioned(top: 8, left: 8, child: IconButton(icon: const Icon(Icons.menu), onPressed: _toggleMenuMinimized, tooltip: 'Show menu')),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0081FB),
        title: const Text('Lite Menu', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        foregroundColor: Colors.black,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(4.0), child: Container(height: 4.0, color: const Color(0xFFFEFE00))),
        actions: [
          const ScreenInfoIcon(screenName: 'main_menu_screen_lite.dart'),
          IconButton(icon: const Icon(Icons.person, color: Colors.white), onPressed: _showUserInfoPopup, tooltip: 'User Information'),
          TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Sign Out', style: TextStyle(color: Colors.white)),
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
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMenuList()),
          _buildUserInfoSection(),
        ],
      ),
    );
  }

  Widget _buildMenuList() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        if (_menuPermissions[UserService.menuMessages] == true)
          _buildDirectMenuItem(title: 'Messages', icon: Icons.message, onTap: () => _navigateToScreen(const MessagesScreen())),
        if (_menuPermissions[UserService.menuClockIn] == true)
          _buildMenuSection(
            key: 'clock_in',
            title: 'Clock In',
            icon: Icons.access_time,
            subItems: [
              _SubMenuItem(title: 'Clock In/Out', onTap: () => _navigateToScreen(const ClockInOutScreen())),
              _SubMenuItem(title: 'My Clockings', onTap: () => _navigateToScreen(const MyClockingsScreen())),
            ],
          ),
        if (_menuPermissions[UserService.menuTimePeriods] == true)
          _buildMenuSection(
            key: 'time_periods',
            title: 'Timesheets',
            icon: Icons.calendar_today,
            subItems: [
              _SubMenuItem(title: 'Clock In/Out', onTap: () => _navigateToScreen(const TimeClockingScreen())),
              _SubMenuItem(title: 'New Time Period', onTap: () => _navigateToScreen(const TimeTrackingScreen())),
              _SubMenuItem(title: 'My Time Periods', onTap: () => _navigateToScreen(const MyTimePeriodsScreen())),
            ],
          ),
        if (_menuPermissions[UserService.menuConcreteMix] == true)
          _buildMenuSection(
            key: 'concrete_mix',
            title: 'Concrete Mix',
            icon: Icons.precision_manufacturing,
            subItems: [
              _SubMenuItem(title: 'Bookings', onTap: () => _navigateToScreen(const ConcreteMixBookingsScreen())),
              _SubMenuItem(title: 'Calendar', onTap: () => _navigateToScreen(const ConcreteMixCalendarScreen())),
              _SubMenuItem(title: 'Scheduler', onTap: () => _navigateToScreen(const ConcreteMixSchedulerScreen())),
              _SubMenuItem(title: 'Google Calendar', onTap: () => _openGoogleCalendar()),
            ],
          ),
        if (_menuPermissions[UserService.menuWorkshop] == true)
          _buildDirectMenuItem(title: 'Workshop', icon: Icons.build, onTap: () => _navigateToScreen(const ComingSoonScreen(featureName: 'Workshop'))),
      ],
    );
  }

  Widget _buildDirectMenuItem({required String title, required IconData icon, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFBADDFF),
          border: Border.all(color: const Color(0xFF005AB0), width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: Icon(icon, color: Colors.black),
          title: Text(title, style: const TextStyle(color: Colors.black)),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildMenuSection({required String key, required String title, required IconData icon, required List<_SubMenuItem> subItems}) {
    final isExpanded = _expandedItems.contains(key);
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleMenuExpansion(key),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              decoration: BoxDecoration(
                color: const Color(0xFFBADDFF),
                border: Border.all(color: const Color(0xFF005AB0), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, color: Colors.black),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.black),
                ],
              ),
            ),
          ),
          if (isExpanded)
            ...subItems.map((item) => ListTile(
                  title: Text(item.title),
                  onTap: item.onTap,
                )),
        ],
      ),
    );
  }

  Widget _buildUserInfoSection() {
    final statusColor = _isOnline ? Colors.green : Colors.orange;
    final statusIcon = _isOnline ? Icons.cloud_done : Icons.cloud_off;
    final statusText = _isOnline ? 'Online' : 'Offline';
    final displayName = _userSetup?['display_name'] ?? _userData?['display_name'] ?? _currentUserEmail;
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        border: Border(top: BorderSide(color: const Color(0xFF0081FB), width: 4.0)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Current User:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(child: Text(displayName.toString(), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubMenuItem {
  final String title;
  final VoidCallback onTap;
  _SubMenuItem({required this.title, required this.onTap});
}
