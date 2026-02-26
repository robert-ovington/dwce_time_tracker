import 'dart:async';

import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/errors/error_log_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';
import 'package:dwce_time_tracker/screens/timesheet_screen.dart';
import 'package:dwce_time_tracker/utils/google_maps_loader.dart';
import 'package:flutter/material.dart';
import 'package:dwce_time_tracker/widgets/screen_info_icon.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

/// Supervisor/Manager Approval Screen
/// 
/// Allows supervisors and managers to review and approve time periods
/// Features:
/// - Filters by date range, project, and user
/// - Compact display with symbols
/// - Checkbox selection for bulk approval
/// - Individual edit/delete/approve actions
/// - Create time periods for users
class SupervisorApprovalScreen extends StatefulWidget {
  const SupervisorApprovalScreen({super.key});

  @override
  State<SupervisorApprovalScreen> createState() => _SupervisorApprovalScreenState();
}

class _SupervisorApprovalScreenState extends State<SupervisorApprovalScreen> {
  bool _isLoading = true;
  bool _isSupervisor = false;
  int? _currentUserSecurityLevel; // Store security level for approval logic
  List<Map<String, dynamic>> _timePeriods = [];
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _allProjects = [];
  
  // Week navigation
  DateTime _selectedWeekStart = DateTime.now();
  
  // Filters
  Set<String> _selectedUserIds = {}; // Multi-select for employees
  Set<String> _selectedProjectIds = {}; // Multi-select for projects
  Set<String> _selectedDays = {}; // Multi-select for days (Mon, Tue, etc.)
  Set<String> _selectedRoles = {}; // Multi-select for users_setup.role
  bool _dayFilterExplicitNone = false; // true = no days selected (untick all)
  bool _employeeFilterExplicitNone = false;
  bool _projectFilterExplicitNone = false;
  bool _roleFilterExplicitNone = false;
  String _projectFilter = ''; // Text filter for projects
  int _projectFilterResetCounter = 0; // Counter to force project filter field to rebuild
  final _prefixFilterController = TextEditingController(); // Filter Project column by prefix(es)
  String _statusFilter = 'submitted'; // submitted (includes imported), supervisor_approved, admin_approved, all
  String _sortBy = 'day'; // 'day' | 'employee' | 'role' | 'project' for _displayedPeriods sort
  
  // Column widths (for resizable columns)
  double _employeeColumnWidth = 120.0;
  double _projectColumnWidth = 360.0;
  
  // Filter dropdown visibility
  String? _openFilterDropdown; // 'day', 'employee', 'project', 'role', or null
  final GlobalKey _headerKey = GlobalKey();
  
  // Selection
  Set<String> _selectedPeriods = {};
  bool _selectAll = false;
  /// Cached list of employees for the current week (for Next/Back when one employee selected).
  List<Map<String, dynamic>>? _cachedEmployeeListForWeek;
  
  // System settings for fleet columns
  int _maxUsedFleet = 6;
  int _maxMobilisedFleet = 4;
  
  // Fleet data cache: time_period_id -> List<plant_no>
  final Map<String, List<String>> _usedFleetCache = {};
  final Map<String, List<String>> _mobilisedFleetCache = {};
  
  // Break durations cache: time_period_id -> minutes
  final Map<String, int> _breakDurationsCache = {};
  
  // Concrete mix names cache: id -> name
  final Map<String, String> _concreteMixNames = {};
  
  // Plant descriptions cache: plant_no -> plant_description
  final Map<String, String> _plantDescriptionsCache = {};

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = _getWeekStart(DateTime.now());
    _checkSupervisorStatus();
  }
  
  @override
  void dispose() {
    _prefixFilterController.dispose();
    _hideFilterDropdown();
    super.dispose();
  }

  /// Parse prefix filter: comma-separated prefixes for Project column (e.g. "A, B, C").
  List<String> _parsePrefixFilter() {
    final raw = _prefixFilterController.text.trim();
    if (raw.isEmpty) return [];
    return raw.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
  }

  /// Unique employees from the list that is actually displayed (after prefix filter). Used for dropdown and Next/Back.
  List<Map<String, dynamic>> get _employeesFromDisplayedPeriods {
    final list = _displayedPeriodsForEmployeeSource;
    final unique = <String, Map<String, dynamic>>{};
    for (final period in list) {
      final userId = period['user_id']?.toString() ?? '';
      if (userId.isNotEmpty && !unique.containsKey(userId)) {
        unique[userId] = {
          'user_id': userId,
          'display_name': period['user_name']?.toString() ?? 'Unknown',
        };
      }
    }
    final out = unique.values.toList();
    out.sort((a, b) => (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString()));
    return out;
  }

  /// Base list for building employee list: when prefix filter active use prefix-filtered list so dropdown/Next only show matching employees.
  List<Map<String, dynamic>> get _displayedPeriodsForEmployeeSource {
    List<Map<String, dynamic>> list = _timePeriods;
    final prefixes = _parsePrefixFilter();
    if (prefixes.isNotEmpty) {
      list = list.where((p) {
        final name = (p['project_name']?.toString() ?? '').toLowerCase();
        return prefixes.any((pre) => name.startsWith(pre));
      }).toList();
    }
    return list;
  }

  /// Displayed periods: filtered by prefix, then by selected employees (if any), then sorted by _sortBy and start time.
  List<Map<String, dynamic>> get _displayedPeriods {
    List<Map<String, dynamic>> list = List.from(_displayedPeriodsForEmployeeSource);
    if (!_employeeFilterExplicitNone && _selectedUserIds.isNotEmpty) {
      list = list.where((p) => _selectedUserIds.contains(p['user_id']?.toString())).toList();
    }
    list.sort((a, b) {
      int c;
      switch (_sortBy) {
        case 'employee':
          c = (a['user_name']?.toString() ?? '').toLowerCase().compareTo((b['user_name']?.toString() ?? '').toLowerCase());
          break;
        case 'role':
          c = (a['user_role']?.toString() ?? '').compareTo((b['user_role']?.toString() ?? ''));
          break;
        case 'project':
          c = (a['project_name']?.toString() ?? '').toLowerCase().compareTo((b['project_name']?.toString() ?? '').toLowerCase());
          break;
        case 'day':
        default:
          c = (a['work_date']?.toString() ?? '').compareTo(b['work_date']?.toString() ?? '');
          break;
      }
      if (c != 0) return c;
      final uA = (a['user_name']?.toString() ?? '').toLowerCase();
      final uB = (b['user_name']?.toString() ?? '').toLowerCase();
      c = uA.compareTo(uB);
      if (c != 0) return c;
      return (a['start_time']?.toString() ?? '').compareTo(b['start_time']?.toString() ?? '');
    });
    return list;
  }
  
  /// Get the start of the week (Monday) for a given date
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return date.subtract(Duration(days: weekday - 1));
  }

  /// Get the end of the week (Sunday) for a given date
  DateTime _getWeekEnd(DateTime weekStart) {
    return weekStart.add(const Duration(days: 6));
  }

  /// Check if we can navigate to next week (max is current week)
  bool _canNavigateNext() {
    final currentWeekStart = _getWeekStart(DateTime.now());
    return _selectedWeekStart.isBefore(currentWeekStart);
  }
  
  /// Navigate to previous week
  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
      _cachedEmployeeListForWeek = null;
    });
    _loadTimePeriods();
  }

  /// Navigate to next week (limited to current week)
  void _nextWeek() {
    if (!_canNavigateNext()) return;
    
    final nextWeek = _selectedWeekStart.add(const Duration(days: 7));
    final currentWeekStart = _getWeekStart(DateTime.now());
    
    if (nextWeek.isAfter(currentWeekStart)) {
      setState(() {
        _selectedWeekStart = currentWeekStart;
        _cachedEmployeeListForWeek = null;
      });
    } else {
      setState(() {
        _selectedWeekStart = nextWeek;
        _cachedEmployeeListForWeek = null;
      });
    }
    _loadTimePeriods();
  }

  /// Navigate to current week
  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
    });
    _loadTimePeriods();
  }

  /// Reset all filters to default (no filters, prefix clear, status Submitted).
  void _resetAllFilters() {
    setState(() {
      _selectedDays.clear();
      _selectedUserIds.clear();
      _selectedProjectIds.clear();
      _selectedRoles.clear();
      _dayFilterExplicitNone = false;
      _employeeFilterExplicitNone = false;
      _projectFilterExplicitNone = false;
      _roleFilterExplicitNone = false;
      _projectFilter = '';
      _projectFilterResetCounter++;
      _prefixFilterController.clear();
      _statusFilter = 'submitted';
    });
    _loadTimePeriods();
  }

  Future<void> _checkSupervisorStatus() async {
    setState(() => _isLoading = true);

    try {
      final isSupervisor = await UserService.isCurrentUserSupervisorOrManager();
      
      if (!isSupervisor) {
        setState(() {
          _isSupervisor = false;
          _isLoading = false;
        });
        return;
      }

      // Get current user's security level for approval logic
      final userSetup = await UserService.getCurrentUserSetup();
      if (userSetup != null && userSetup['security'] != null) {
        final security = userSetup['security'];
        _currentUserSecurityLevel = security is int ? security : int.tryParse(security.toString());
      }

      setState(() => _isSupervisor = true);

      // Load only what's needed for the list: settings + time periods (RPC + batch breaks/fleet).
      // User and project filters are built from loaded periods, so we do not load all users_data or projects.
      await Future.wait([
        _loadSystemSettings(),
        _loadTimePeriods(),
      ]);
      // Defer heavy lookups so the table appears first; load in background for popups/detail
      unawaited(_loadConcreteMixes());
      unawaited(_loadPlantDescriptions());
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Check Supervisor Status',
        type: 'Database',
        description: 'Error checking supervisor status: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _isLoading = false;
        _isSupervisor = false;
      });
    }
  }

  Future<void> _loadUsers() async {
    try {
      final users = await DatabaseService.read('users_data');
      setState(() => _allUsers = users);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Load Users',
        type: 'Database',
        description: 'Error loading users: $e',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await DatabaseService.read('projects');
      setState(() => _allProjects = projects);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Load Projects',
        type: 'Database',
        description: 'Error loading projects: $e',
        stackTrace: stackTrace,
      );
    }
  }
  
  Future<void> _loadSystemSettings() async {
    try {
      final settings = await DatabaseService.read('system_settings', limit: 1);
      if (settings.isNotEmpty) {
        final setting = settings.first;
        _maxUsedFleet = (setting['max_used_fleet_per_period'] as int?) ?? 6;
        _maxMobilisedFleet = (setting['max_mobilised_fleet_per_period'] as int?) ?? 4;
      }
    } catch (e) {
      print('Error loading system settings: $e');
      // Use defaults
      _maxUsedFleet = 6;
      _maxMobilisedFleet = 4;
    }
  }
  
  Future<void> _loadConcreteMixes() async {
    try {
      final mixes = await DatabaseService.read('concrete_mix');
      _concreteMixNames.clear();
      for (final mix in mixes) {
        final id = mix['id']?.toString()?.trim();
        if (id == null || id.isEmpty) continue;
        
        // Use only the 'name' field - no fallback
        final name = mix['name']?.toString()?.trim();
        
        if (name != null && name.isNotEmpty) {
          _concreteMixNames[id] = name;
        }
      }
      print('✅ Loaded ${_concreteMixNames.length} concrete mixes for lookup');
    } catch (e) {
      print('❌ Error loading concrete mixes: $e');
    }
  }
  
  Future<void> _loadPlantDescriptions() async {
    try {
      final plants = await DatabaseService.read('large_plant');
      _plantDescriptionsCache.clear();
      for (final plant in plants) {
        final plantNo = plant['plant_no']?.toString()?.trim();
        final description = plant['plant_description']?.toString()?.trim();
        if (plantNo != null && plantNo.isNotEmpty && description != null && description.isNotEmpty) {
          _plantDescriptionsCache[plantNo] = description;
        }
      }
      print('✅ Loaded ${_plantDescriptionsCache.length} plant descriptions for lookup');
    } catch (e) {
      print('❌ Error loading plant descriptions: $e');
    }
  }
  
  /// Show plant description popup
  void _showPlantDescriptionPopup(String plantNo) {
    final description = _plantDescriptionsCache[plantNo] ?? 'Description not available';
    
    // Show overlay popup
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: MediaQuery.of(context).size.width / 2 - 150,
        top: MediaQuery.of(context).size.height / 2 - 50,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(16),
            width: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fleet: $plantNo',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // Remove after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  Future<void> _loadTimePeriods() async {
    setState(() => _isLoading = true);

    try {
      final weekEnd = _getWeekEnd(_selectedWeekStart);
      final startDateStr = DateFormat('yyyy-MM-dd').format(_selectedWeekStart);
      final endDateStr = DateFormat('yyyy-MM-dd').format(weekEnd);

      // Backend RPC: one call returns date-filtered periods with user_name, project_name, job_address, user_role joined
      final rpcParams = <String, dynamic>{
        'p_start_date': startDateStr,
        'p_end_date': endDateStr,
      };
      if (_statusFilter != 'all') {
        rpcParams['p_status_filter'] = _statusFilter;
      }
      // Do not pass p_user_ids to RPC: we load all periods and filter by employee in memory,
      // so the employee list for "1/xxx" and Next/Back stays full and navigation works.
      // if (!_employeeFilterExplicitNone && _selectedUserIds.isNotEmpty) {
      //   rpcParams['p_user_ids'] = _selectedUserIds.toList();
      // }
      if (!_projectFilterExplicitNone && _selectedProjectIds.isNotEmpty) {
        rpcParams['p_project_ids'] = _selectedProjectIds.toList();
      }

      final response = await SupabaseService.client.rpc(
        'get_supervisor_approval_periods',
        params: rpcParams,
      );

      final rawList = response as List? ?? [];
      var periods = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Apply day filter in memory
      if (_dayFilterExplicitNone) {
        periods = [];
      } else if (_selectedDays.isNotEmpty) {
        periods = periods.where((period) {
          final workDate = period['work_date']?.toString();
          if (workDate == null) return false;
          try {
            final date = DateTime.parse(workDate);
            final dayName = DateFormat('EEE').format(date); // Mon, Tue, etc.
            return _selectedDays.contains(dayName);
          } catch (e) {
            return false;
          }
        }).toList();
      }
      
      // Apply employee filter in memory when "none selected"
      if (_employeeFilterExplicitNone) {
        periods = [];
      }
      
      // Apply project filter in memory when "none selected"
      if (_projectFilterExplicitNone) {
        periods = [];
      }
      
      // Apply role filter in memory
      if (_roleFilterExplicitNone) {
        periods = [];
      } else if (_selectedRoles.isNotEmpty) {
        periods = periods.where((period) {
          final role = period['user_role']?.toString() ?? '--';
          return _selectedRoles.contains(role);
        }).toList();
      }
      
      // Apply project text filter in memory (if set)
      if (_projectFilter.isNotEmpty) {
        final filterTerms = _projectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
        periods = periods.where((period) {
          final projectName = (period['project_name']?.toString() ?? '').toLowerCase();
          return filterTerms.every((term) => projectName.contains(term));
        }).toList();
      }
      
      // Apply approved filter in memory (if selected)
      if (_statusFilter == 'supervisor_approved') {
        periods = periods.where((period) {
          final supervisorId = period['supervisor_id'];
          final supervisorApprovedAt = period['supervisor_approved_at'];
          return supervisorId != null && supervisorApprovedAt != null;
        }).toList();
      }
      
      // Batch-load breaks and fleet (chunked to avoid huge URLs/timeouts)
      _breakDurationsCache.clear();
      _usedFleetCache.clear();
      _mobilisedFleetCache.clear();
      final periodIds = periods.map((p) => p['id']?.toString()).whereType<String>().toList();
      if (periodIds.isNotEmpty) {
        await Future.wait([
          _batchLoadBreaksChunked(periodIds),
          _batchLoadUsedFleetChunked(periodIds),
          _batchLoadMobilisedFleetChunked(periodIds),
        ]);
      }

      setState(() {
        _timePeriods = periods;
        _selectedPeriods.clear();
        _selectAll = false;
        _isLoading = false;
        if (_selectedUserIds.isEmpty) {
          final unique = <String, Map<String, dynamic>>{};
          for (final p in periods) {
            final userId = p['user_id']?.toString() ?? '';
            if (userId.isNotEmpty && !unique.containsKey(userId)) {
              unique[userId] = {
                'user_id': userId,
                'display_name': p['user_name']?.toString() ?? 'Unknown',
              };
            }
          }
          final list = unique.values.toList();
          list.sort((a, b) => (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString()));
          _cachedEmployeeListForWeek = list;
        }
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Load Time Periods',
        type: 'Database',
        description: 'Error loading time periods: $e',
        stackTrace: stackTrace,
      );
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading time periods: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Load breaks for a time period
  Future<void> _loadBreaks(String timePeriodId) async {
    try {
      final breaksResponse = await SupabaseService.client
          .from('time_period_breaks')
          .select('break_start, break_finish')
          .eq('time_period_id', timePeriodId)
          .order('break_start', ascending: true);
      
      int totalMinutes = 0;
      for (final breakData in (breaksResponse as List)) {
        final start = breakData['break_start']?.toString();
        final finish = breakData['break_finish']?.toString();
        if (start != null && finish != null) {
          try {
            final startTime = DateTime.parse(start);
            final finishTime = DateTime.parse(finish);
            totalMinutes += finishTime.difference(startTime).inMinutes;
          } catch (e) {
            print('Error parsing break times: $e');
          }
        }
      }
      _breakDurationsCache[timePeriodId] = totalMinutes;
    } catch (e) {
      print('Error loading breaks for $timePeriodId: $e');
      _breakDurationsCache[timePeriodId] = 0;
    }
  }
  
  /// Load used fleet for a time period
  Future<void> _loadUsedFleet(String timePeriodId) async {
    try {
      final fleetResponse = await SupabaseService.client
          .from('time_period_used_fleet')
          .select('large_plant_id, large_plant(plant_no)')
          .eq('time_period_id', timePeriodId)
          .order('display_order', ascending: true);
      
      final fleetList = <String>[];
      for (final item in (fleetResponse as List)) {
        final plant = (item as Map<String, dynamic>)['large_plant'] as Map<String, dynamic>?;
        if (plant != null && plant['plant_no'] != null) {
          fleetList.add(plant['plant_no']?.toString() ?? '');
        }
      }
      _usedFleetCache[timePeriodId] = fleetList;
    } catch (e) {
      print('Error loading used fleet for $timePeriodId: $e');
      _usedFleetCache[timePeriodId] = [];
    }
  }
  
  /// Load mobilised fleet for a time period
  Future<void> _loadMobilisedFleet(String timePeriodId) async {
    try {
      final fleetResponse = await SupabaseService.client
          .from('time_period_mobilised_fleet')
          .select('large_plant_id, large_plant(plant_no)')
          .eq('time_period_id', timePeriodId)
          .order('display_order', ascending: true);
      
      final fleetList = <String>[];
      for (final item in (fleetResponse as List)) {
        final plant = (item as Map<String, dynamic>)['large_plant'] as Map<String, dynamic>?;
        if (plant != null && plant['plant_no'] != null) {
          fleetList.add(plant['plant_no']?.toString() ?? '');
        }
      }
      _mobilisedFleetCache[timePeriodId] = fleetList;
    } catch (e) {
      print('Error loading mobilised fleet for $timePeriodId: $e');
      _mobilisedFleetCache[timePeriodId] = [];
    }
  }

  static const int _batchChunkSize = 150;

  Future<void> _batchLoadBreaksChunked(List<String> timePeriodIds) async {
    for (var i = 0; i < timePeriodIds.length; i += _batchChunkSize) {
      final end = (i + _batchChunkSize).clamp(0, timePeriodIds.length);
      if (end <= i) break;
      await _batchLoadBreaks(timePeriodIds.sublist(i, end));
    }
  }

  Future<void> _batchLoadUsedFleetChunked(List<String> timePeriodIds) async {
    for (var i = 0; i < timePeriodIds.length; i += _batchChunkSize) {
      final end = (i + _batchChunkSize).clamp(0, timePeriodIds.length);
      if (end <= i) break;
      await _batchLoadUsedFleet(timePeriodIds.sublist(i, end));
    }
  }

  Future<void> _batchLoadMobilisedFleetChunked(List<String> timePeriodIds) async {
    for (var i = 0; i < timePeriodIds.length; i += _batchChunkSize) {
      final end = (i + _batchChunkSize).clamp(0, timePeriodIds.length);
      if (end <= i) break;
      await _batchLoadMobilisedFleet(timePeriodIds.sublist(i, end));
    }
  }

  /// Batch-load break durations for many periods (one query)
  Future<void> _batchLoadBreaks(List<String> timePeriodIds) async {
    if (timePeriodIds.isEmpty) return;
    try {
      final response = await SupabaseService.client
          .from('time_period_breaks')
          .select('time_period_id, break_start, break_finish')
          .inFilter('time_period_id', timePeriodIds)
          .order('break_start', ascending: true);
      final map = <String, int>{};
      for (final row in (response as List)) {
        final id = row['time_period_id']?.toString();
        if (id == null) continue;
        int total = map[id] ?? 0;
        final start = row['break_start']?.toString();
        final finish = row['break_finish']?.toString();
        if (start != null && finish != null) {
          try {
            total += DateTime.parse(finish).difference(DateTime.parse(start)).inMinutes;
          } catch (_) {}
        }
        map[id] = total;
      }
      _breakDurationsCache.addAll(map);
      for (final id in timePeriodIds) {
        _breakDurationsCache.putIfAbsent(id, () => 0);
      }
    } catch (e) {
      print('Error batch-loading breaks: $e');
      for (final id in timePeriodIds) {
        _breakDurationsCache[id] = 0;
      }
    }
  }

  /// Batch-load used fleet for many periods (one query)
  Future<void> _batchLoadUsedFleet(List<String> timePeriodIds) async {
    if (timePeriodIds.isEmpty) return;
    try {
      final response = await SupabaseService.client
          .from('time_period_used_fleet')
          .select('time_period_id, large_plant_id, large_plant(plant_no)')
          .inFilter('time_period_id', timePeriodIds)
          .order('display_order', ascending: true);
      final map = <String, List<String>>{};
      for (final id in timePeriodIds) {
        map[id] = [];
      }
      for (final row in (response as List)) {
        final id = row['time_period_id']?.toString();
        if (id == null) continue;
        final plant = (row as Map<String, dynamic>)['large_plant'] as Map<String, dynamic>?;
        final no = plant?['plant_no']?.toString();
        if (no != null) map[id]!.add(no);
      }
      _usedFleetCache.addAll(map);
    } catch (e) {
      print('Error batch-loading used fleet: $e');
      for (final id in timePeriodIds) {
        _usedFleetCache[id] = [];
      }
    }
  }

  /// Batch-load mobilised fleet for many periods (one query)
  Future<void> _batchLoadMobilisedFleet(List<String> timePeriodIds) async {
    if (timePeriodIds.isEmpty) return;
    try {
      final response = await SupabaseService.client
          .from('time_period_mobilised_fleet')
          .select('time_period_id, large_plant_id, large_plant(plant_no)')
          .inFilter('time_period_id', timePeriodIds)
          .order('display_order', ascending: true);
      final map = <String, List<String>>{};
      for (final id in timePeriodIds) {
        map[id] = [];
      }
      for (final row in (response as List)) {
        final id = row['time_period_id']?.toString();
        if (id == null) continue;
        final plant = (row as Map<String, dynamic>)['large_plant'] as Map<String, dynamic>?;
        final no = plant?['plant_no']?.toString();
        if (no != null) map[id]!.add(no);
      }
      _mobilisedFleetCache.addAll(map);
    } catch (e) {
      print('Error batch-loading mobilised fleet: $e');
      for (final id in timePeriodIds) {
        _mobilisedFleetCache[id] = [];
      }
    }
  }

  /// Edit a time period - navigate to timesheet screen for editing
  Future<void> _editTimePeriod(Map<String, dynamic> period) async {
    final periodId = period['id']?.toString();
    if (periodId == null || periodId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Time period ID not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final status = period['status']?.toString() ?? '';
    final currentUser = AuthService.getCurrentUser();
    final currentUserId = currentUser?.id;
    final isAdmin = _currentUserSecurityLevel == 1;
    final supervisorId = period['supervisor_id']?.toString();

    // admin_approved: only security level 1 (admin) can edit
    if (status == 'admin_approved') {
      if (!isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This time period has been approved by admin. Only users with admin status (security level 1) can edit it.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
    } else if (status == 'supervisor_approved') {
      // Only the supervisor who approved (supervisor_id) can edit
      if (currentUserId == null || supervisorId == null || currentUserId != supervisorId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the supervisor who approved this period can edit it.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
    }
    // submitted and imported: any supervisor can edit

    // Backup current data to time_period_revisions before editing
    try {
      await _backupToRevisions(periodId, period);
    } catch (e) {
      print('Error backing up to revisions: $e');
      // Continue with edit even if backup fails
    }
    
    // Navigate to timesheet screen with the time period ID for editing
    if (!mounted) return;
    
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TimeTrackingScreen(timePeriodId: periodId),
      ),
    );
    
    // If edit was successful, update revision tracking
    if (result == true) {
      try {
        final currentUser = AuthService.getCurrentUser();
        if (currentUser != null) {
          // Get current user's users_data id
          final currentUserData = await UserService.getCurrentUserData();
          final changedById = currentUserData?['id']?.toString();
          
          // Get current revision number and increment
          final timePeriod = await DatabaseService.readById('time_periods', periodId);
          final currentRevision = (timePeriod?['revision_number'] as int?) ?? 0;
          final newRevision = currentRevision + 1;
          
          // Update time period with revision info
          await DatabaseService.update('time_periods', periodId, {
            'supervisor_edited_before_approval': true,
            'revision_number': newRevision,
            'last_revised_at': DateTime.now().toIso8601String(),
            'last_revised_by': changedById,
          });
        }
      } catch (e) {
        print('Error updating revision info: $e');
      }
    }
    
    // Reload time periods after returning from edit screen
    _loadTimePeriods();
  }
  
  /// Backup time period data to revisions table before editing
  Future<void> _backupToRevisions(String periodId, Map<String, dynamic> period) async {
    try {
      final currentUser = AuthService.getCurrentUser();
      if (currentUser == null) return;
      
      final currentUserData = await UserService.getCurrentUserData();
      final changedById = currentUserData?['id']?.toString();
      if (changedById == null) return;
      
      // Get current revision number
      final currentRevision = (period['revision_number'] as int?) ?? 0;
      
      // Get user's name and role
      String? changedByName;
      String? changedByRole;
      
      final userSetup = await UserService.getCurrentUserSetup();
      if (userSetup != null && userSetup['display_name'] != null) {
        changedByName = userSetup['display_name']?.toString();
      } else if (currentUserData?['forename'] != null || currentUserData?['surname'] != null) {
        final forename = currentUserData?['forename']?.toString() ?? '';
        final surname = currentUserData?['surname']?.toString() ?? '';
        changedByName = '$forename $surname'.trim();
      }
      
      if (currentUserData?['role'] != null) {
        changedByRole = currentUserData?['role']?.toString();
      } else if (userSetup != null && userSetup['role'] != null) {
        changedByRole = userSetup['role']?.toString();
      }
      
      // Create revision record with all current data
      await DatabaseService.create('time_period_revisions', {
        'time_period_id': periodId,
        'revision_number': currentRevision,
        'changed_by': changedById,
        'changed_by_name': changedByName,
        'changed_by_role': changedByRole,
        'change_type': 'supervisor_edit',
        'workflow_stage': period['status']?.toString() ?? 'submitted',
        'field_name': 'all_fields', // Backup of all fields
        'old_value': null, // Full backup stored in JSON
        'new_value': null,
        'change_reason': 'Backup before supervisor edit',
        'is_revision': true,
        'is_approval': false,
        'is_edit': true,
        'original_submission': false,
        // Store full period data as JSON in a note field if available
      });
    } catch (e) {
      print('Error backing up to revisions: $e');
      rethrow;
    }
  }

  Future<void> _toggleApproval(String periodId, bool isApproved) async {
    try {
      final currentUser = AuthService.getCurrentUser();
      if (currentUser == null) throw Exception('User not authenticated');
      
      // Get the time period to check current status (use direct query to avoid .single() issues)
      final timePeriodResponse = await SupabaseService.client
          .from('time_periods')
          .select()
          .eq('id', periodId)
          .maybeSingle();
      
      if (timePeriodResponse == null) throw Exception('Time period not found');
      final timePeriod = Map<String, dynamic>.from(timePeriodResponse);
      
      final currentStatus = timePeriod['status']?.toString() ?? '';
      final now = DateTime.now();
      
      // Determine approval step based on security level
      final isAdmin = _currentUserSecurityLevel == 1;
      final isSupervisor = _currentUserSecurityLevel == 2 || _currentUserSecurityLevel == 3;
      
      if (!isAdmin && !isSupervisor) {
        throw Exception('Insufficient permissions to approve time periods');
      }
      
      if (isApproved) {
        // Approve based on security level
        // Check if edits were made before approval (revision_number > 0 indicates edits)
        final revisionNumber = timePeriod['revision_number'] as int? ?? 0;
        final hasBeenEdited = revisionNumber > 0;
        
        final updateData = <String, dynamic>{};
        
        // This screen only performs supervisor approval. Admin approval is a separate screen.
        if (isAdmin || isSupervisor) {
          updateData['status'] = 'supervisor_approved';
          updateData['supervisor_id'] = currentUser.id;
          updateData['supervisor_approved_at'] = now.toIso8601String();
          updateData['supervisor_edited_before_approval'] = hasBeenEdited;
          await _trackApprovalRevision(
            periodId,
            timePeriod,
            isAdmin ? 'admin_approval' : 'supervisor_approval',
            'supervisor_review',
          );
        }
        
        await DatabaseService.update('time_periods', periodId, updateData);
      } else {
        // Unapprove - show confirmation popup first
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Unapprove Time Period'),
            content: const Text('Are you sure you want to unapprove this time period? This will clear the supervisor approval.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Unapprove'),
              ),
            ],
          ),
        );
        
        if (confirmed != true) return;
        
        // Clear approval fields based on who approved it
        // Note: For Supabase, we need to explicitly set null values
        final updateData = <String, dynamic>{
          'status': 'submitted',
        };
        
        // Determine which fields to clear based on current status
        if (currentStatus == 'admin_approved') {
          // If admin approved, clear both admin and supervisor fields
          updateData['admin_id'] = null;
          updateData['admin_approved_at'] = null;
          updateData['admin_edited_before_approval'] = null;
          updateData['supervisor_id'] = null;
          updateData['supervisor_approved_at'] = null;
          updateData['supervisor_edited_before_approval'] = null;
        } else if (currentStatus == 'supervisor_approved') {
          // If supervisor approved, clear supervisor fields only
          updateData['supervisor_id'] = null;
          updateData['supervisor_approved_at'] = null;
          updateData['supervisor_edited_before_approval'] = null;
        } else {
          // If status is not approved, still clear supervisor fields as a safety measure
          updateData['supervisor_id'] = null;
          updateData['supervisor_approved_at'] = null;
          updateData['supervisor_edited_before_approval'] = null;
          print('⚠️ Warning: Unapproving time period with status: $currentStatus (expected admin_approved or supervisor_approved)');
        }
        
        // Use direct Supabase update without select to avoid .select().single() issues
        try {
          print('🔄 Attempting to unapprove period $periodId with status: $currentStatus');
          print('🔄 Update data: $updateData');
          
          // Update without select to avoid extra API calls and potential RLS issues
          await SupabaseService.client
              .from('time_periods')
              .update(updateData)
              .eq('id', periodId);
          
          print('✅ Unapproval update completed successfully for period $periodId');
        } catch (updateError) {
          print('❌ Error updating time period $periodId: $updateError');
          print('❌ Update data: $updateData');
          print('❌ Current status: $currentStatus');
          print('❌ Period ID: $periodId');
          print('❌ Current user: ${currentUser.id}');
          
          // Provide more helpful error message
          final errorMessage = updateError.toString();
          if (errorMessage.contains('RLS') || errorMessage.contains('policy')) {
            throw Exception('Permission denied. Please check your Row Level Security (RLS) policies for the time_periods table.');
          } else if (errorMessage.contains('null') || errorMessage.contains('constraint')) {
            throw Exception('Database constraint error. Some fields may not allow null values.');
          } else {
            rethrow;
          }
        }
      }

      _loadTimePeriods();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Toggle Approval',
        type: 'Database',
        description: 'Error toggling approval: $e',
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _approveTimePeriod(String periodId) async {
    await _toggleApproval(periodId, true);
  }

  Future<void> _approveSelected() async {
    if (_selectedPeriods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No time periods selected'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final isAdmin = _currentUserSecurityLevel == 1;
    final isSupervisor = _currentUserSecurityLevel == 2 || _currentUserSecurityLevel == 3;
    
    if (!isAdmin && !isSupervisor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insufficient permissions to approve time periods'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Selected'),
        content: Text('Approve ${_selectedPeriods.length} time period(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final currentUser = AuthService.getCurrentUser();
      if (currentUser == null) throw Exception('User not authenticated');
      
      int successCount = 0;
      int failCount = 0;

      for (final periodId in _selectedPeriods) {
        try {
          // Get the time period to check current status
          final timePeriod = await DatabaseService.readById('time_periods', periodId);
          if (timePeriod == null) {
            failCount++;
            continue;
          }
          
          final currentStatus = timePeriod['status']?.toString() ?? '';
          final now = DateTime.now();
          
          // Check if edits were made before approval
          final revisionNumber = timePeriod['revision_number'] as int? ?? 0;
          final hasBeenEdited = revisionNumber > 0;
          
          // Approve if status is 'submitted' or 'imported'
          if (currentStatus != 'submitted' && currentStatus != 'imported') {
            failCount++;
            continue;
          }
          
          // Approve based on security level
          final updateData = <String, dynamic>{};
          
          // This screen only performs supervisor approval (admin approval is a separate screen)
          if (isAdmin || isSupervisor) {
            updateData['status'] = 'supervisor_approved';
            updateData['supervisor_id'] = currentUser.id;
            updateData['supervisor_approved_at'] = now.toIso8601String();
            updateData['supervisor_edited_before_approval'] = hasBeenEdited;
            await _trackApprovalRevision(
              periodId,
              timePeriod,
              isAdmin ? 'admin_approval' : 'supervisor_approval',
              'supervisor_review',
            );
          }
          await DatabaseService.update('time_periods', periodId, updateData);
          successCount++;
        } catch (e) {
          print('Error approving period $periodId: $e');
          failCount++;
        }
      }

      if (mounted) {
        if (failCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$successCount approved, $failCount failed'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$successCount time period(s) approved'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      _loadTimePeriods();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Approve Selected',
        type: 'Database',
        description: 'Error approving selected time periods: $e',
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Track approval in revision history
  Future<void> _trackApprovalRevision(String periodId, Map<String, dynamic> timePeriod, String changeType, String workflowStage) async {
    try {
      // Get current user's users_data record to get the id for changed_by
      final currentUserData = await UserService.getCurrentUserData();
      if (currentUserData == null) {
        print('⚠️ Could not get current user data for revision tracking');
        return;
      }
      
      final changedById = currentUserData['id']?.toString();
      if (changedById == null) {
        print('⚠️ Could not get users_data.id for revision tracking');
        return;
      }
      
      // Get user's name and role
      String? changedByName;
      String? changedByRole;
      
      final userSetup = await UserService.getCurrentUserSetup();
      if (userSetup != null && userSetup['display_name'] != null) {
        changedByName = userSetup['display_name']?.toString();
      } else if (currentUserData['forename'] != null || currentUserData['surname'] != null) {
        final forename = currentUserData['forename']?.toString() ?? '';
        final surname = currentUserData['surname']?.toString() ?? '';
        changedByName = '$forename $surname'.trim();
      }
      
      if (currentUserData['role'] != null) {
        changedByRole = currentUserData['role']?.toString();
      } else if (userSetup != null && userSetup['role'] != null) {
        changedByRole = userSetup['role']?.toString();
      }
      
      final revisionNumber = timePeriod['revision_number'] as int? ?? 0;
      
      // Create revision record for approval
      await DatabaseService.create('time_period_revisions', {
        'time_period_id': periodId,
        'revision_number': revisionNumber, // Use current revision number for approval
        'changed_by': changedById,
        'changed_by_name': changedByName,
        'changed_by_role': changedByRole,
        'change_type': changeType, // 'supervisor_approval' or 'admin_approval'
        'workflow_stage': workflowStage, // 'supervisor_review' or 'approved'
        'field_name': 'status', // Approval changes the status
        'old_value': timePeriod['status']?.toString() ?? '',
        'new_value': 'supervisor_approved', // This screen only performs supervisor approval
        'change_reason': null,
        'is_revision': false, // Approval is not a revision
        'is_approval': true,
        'is_edit': false,
        'original_submission': false,
      });
      
      print('✅ Tracked approval revision for time period: $periodId');
    } catch (e, stackTrace) {
      print('❌ Error tracking approval revision: $e');
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Track Approval Revision',
        type: 'Database',
        description: 'Failed to track approval revision: $e',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _deleteTimePeriod(String periodId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Time Period'),
        content: const Text('Are you sure you want to delete this time period?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final currentUser = AuthService.getCurrentUser();
      if (currentUser == null) throw Exception('User not authenticated');
      
      // Soft delete: set is_active to FALSE and update deleted_by and deleted_at
      await DatabaseService.update('time_periods', periodId, {
        'is_active': false,
        'deleted_by': currentUser.id,
        'deleted_at': DateTime.now().toIso8601String(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Time period deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadTimePeriods();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Delete Time Period',
        type: 'Database',
        description: 'Error deleting time period: $e',
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedPeriods = _timePeriods
            .where((p) {
              final s = p['status']?.toString() ?? '';
              return s == 'submitted' || s == 'imported';
            })
            .map((p) => p['id'].toString())
            .toSet();
      } else {
        _selectedPeriods.clear();
      }
    });
  }

  void _toggleSelection(String periodId) {
    setState(() {
      if (_selectedPeriods.contains(periodId)) {
        _selectedPeriods.remove(periodId);
        _selectAll = false;
      } else {
        _selectedPeriods.add(periodId);
      }
    });
  }
  
  /// Check if approve button should be shown based on status and user security level
  bool _shouldShowApproveButton(String status) {
    final isAdmin = _currentUserSecurityLevel == 1;
    final isSupervisor = _currentUserSecurityLevel == 2 || _currentUserSecurityLevel == 3;
    
    if (isAdmin) {
      // Admin can approve 'submitted', 'imported', or 'supervisor_approved' periods
      return status == 'submitted' || status == 'imported' || status == 'supervisor_approved';
    } else if (isSupervisor) {
      // Supervisor can approve 'submitted' or 'imported' periods
      return status == 'submitted' || status == 'imported';
    }
    
    return false;
  }
  
  /// Get appropriate tooltip text for approve button
  String _getApproveTooltip(String status) {
    final isAdmin = _currentUserSecurityLevel == 1;
    
    if (isAdmin) {
      if (status == 'submitted' || status == 'imported') {
        return 'Approve as Admin (skipping supervisor)';
      } else if (status == 'supervisor_approved') {
        return 'Approve as Admin (final approval)';
      }
    } else {
      return status == 'imported' ? 'Approve imported period as Supervisor' : 'Approve as Supervisor';
    }
    
    return 'Approve';
  }

  String _formatDuration(DateTime? start, DateTime? finish) {
    if (start == null || finish == null) return '--';
    final duration = finish.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h${minutes > 0 ? " ${minutes}m" : ""}';
  }
  
  /// Format time as HH:mm
  String _formatTimeAsHHMM(DateTime? time) {
    if (time == null) return '--';
    return DateFormat('HH:mm').format(time);
  }
  
  /// Format break duration as HH:mm
  String _formatBreakDuration(int minutes) {
    if (minutes == 0) return '--';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }
  
  /// Calculate total worked time (finish - start - break) as HH:mm
  String _calculateTotalTime(DateTime? start, DateTime? finish, int breakMinutes) {
    if (start == null || finish == null) return '--';
    final totalMinutes = finish.difference(start).inMinutes - breakMinutes;
    if (totalMinutes < 0) return '--';
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }
  
  /// Format day as ddd (e.g., Mon, Tue)
  String _formatDay(DateTime? date) {
    if (date == null) return '--';
    return DateFormat('EEE').format(date);
  }
  
  /// Check if period is approved
  bool _isApproved(Map<String, dynamic> period) {
    final supervisorId = period['supervisor_id'];
    final supervisorApprovedAt = period['supervisor_approved_at'];
    return supervisorId != null && supervisorApprovedAt != null;
  }
  
  /// Get concrete mix name from ID
  String _getConcreteMixName(String? mixId) {
    if (mixId == null || mixId.isEmpty) return '';
    return _concreteMixNames[mixId] ?? mixId;
  }
  
  /// Calculate total allowances in minutes
  int _calculateTotalAllowances(Map<String, dynamic> period) {
    final travelTo = (period['travel_to_site_min'] as int?) ?? 0;
    final travelFrom = (period['travel_from_site_min'] as int?) ?? 0;
    final misc = (period['misc_allowance_min'] as int?) ?? 0;
    return travelTo + travelFrom + misc;
  }
  
  /// Format allowances as HH:mm
  String _formatAllowances(int minutes) {
    if (minutes == 0) return '--';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }
  
  /// Show allowances popup
  void _showAllowancesPopup(Map<String, dynamic> period) {
    final travelTo = (period['travel_to_site_min'] as int?) ?? 0;
    final travelFrom = (period['travel_from_site_min'] as int?) ?? 0;
    final misc = (period['misc_allowance_min'] as int?) ?? 0;
    final distance = period['distance_from_home']?.toString() ?? '--';
    final travelTimeText = period['travel_time_text']?.toString() ?? '--';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allowances Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Travel to Site: ${_formatAllowances(travelTo)}'),
            Text('Travel from Site: ${_formatAllowances(travelFrom)}'),
            Text('Misc Allowance: ${_formatAllowances(misc)}'),
            const SizedBox(height: 8),
            Text('Distance from Home: $distance'),
            Text('Travel Time: $travelTimeText'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  /// Show GPS map popup with line between submission location and project location
  /// Note: This displays existing coordinates from the database, so no API calls are needed.
  /// The Google Maps API key should be configured in web/index.html for web platform.
  void _showGPSMapPopup(Map<String, dynamic> period) async {
    final submissionLat = period['submission_lat'] as double?;
    final submissionLng = period['submission_lng'] as double?;
    final projectLat = period['project_lat'] as double?;
    final projectLng = period['project_lng'] as double?;
    final clockInDistance = period['clock_in_distance']?.toString() ?? '--';
    
    // Check if we have valid coordinates
    if (submissionLat == null || submissionLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No GPS coordinates available for this time period'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Load Google Maps API if not already loaded (web only)
    try {
      await loadGoogleMapsApi();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load Google Maps: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Create markers
    final markers = <Marker>{};
    
    // Submission location marker (User's location - Green for "You are here")
    markers.add(
      Marker(
        markerId: const MarkerId('submission'),
        position: LatLng(submissionLat, submissionLng),
        infoWindow: const InfoWindow(
          title: '👤 User Location',
          snippet: 'Where the employee submitted the time period',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );
    
    // Project location marker (if available - Orange/Red for destination)
    if (projectLat != null && projectLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('project'),
          position: LatLng(projectLat, projectLng),
          infoWindow: InfoWindow(
            title: '🏗️ Project Location',
            snippet: 'Distance from user: $clockInDistance km',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      );
    }
    
    // Create polyline if both locations are available
    final polylines = <Polyline>{};
    if (projectLat != null && projectLng != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [
            LatLng(submissionLat, submissionLng),
            LatLng(projectLat, projectLng),
          ],
          color: Colors.blue,
          width: 3,
        ),
      );
    }
    
    // Calculate camera position to show both points
    LatLngBounds? bounds;
    if (projectLat != null && projectLng != null) {
      bounds = LatLngBounds(
        southwest: LatLng(
          submissionLat < projectLat ? submissionLat : projectLat,
          submissionLng < projectLng ? submissionLng : projectLng,
        ),
        northeast: LatLng(
          submissionLat > projectLat ? submissionLat : projectLat,
          submissionLng > projectLng ? submissionLng : projectLng,
        ),
      );
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS Location Map'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.6,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(submissionLat, submissionLng),
              zoom: projectLat != null && projectLng != null ? 12.0 : 15.0,
            ),
            markers: markers,
            polylines: polylines,
            mapType: MapType.normal,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              if (bounds != null) {
                // Fit bounds to show both markers
                controller.animateCamera(
                  CameraUpdate.newLatLngBounds(bounds!, 100),
                );
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  /// Increment the Google API call counter in system_settings
  /// (Following the same pattern as user_edit_screen.dart)
  Future<void> _incrementApiCallCounter() async {
    try {
      print('🔍 [COUNTER] Fetching system_settings...');
      // Get the first (and should be only) system_settings record
      final settings = await SupabaseService.client
          .from('system_settings')
          .select('id, google_api_calls')
          .limit(1)
          .maybeSingle();

      print('🔍 [COUNTER] Settings result: $settings');

      if (settings != null) {
        // Update existing record
        final currentCount = (settings['google_api_calls'] as int?) ?? 0;
        final settingsId = settings['id']?.toString();
        print('🔍 [COUNTER] Current count: $currentCount, ID: $settingsId');
        
        // Try using RPC function if available, otherwise use direct update
        try {
          // Attempt direct update without select
          await SupabaseService.client
              .from('system_settings')
              .update({'google_api_calls': currentCount + 1})
              .eq('id', settingsId ?? '');
          
          print('✅ [COUNTER] Incremented API call counter to ${currentCount + 1}');
        } catch (triggerError, triggerStackTrace) {
          // If trigger fails, try using RPC function as workaround
          print('⚠️ [COUNTER] Direct update failed (trigger issue), trying alternative...');
          await ErrorLogService.logError(
            location: 'Supervisor Approval Screen - Increment API Call Counter',
            type: 'Database',
            description: 'Direct update failed (trigger issue) for API call counter: $triggerError',
            stackTrace: triggerStackTrace,
          );
          try {
            // Try using a stored procedure/RPC if available
            await SupabaseService.client.rpc('increment_google_api_calls', params: {
              'p_id': settingsId,
            });
            print('✅ [COUNTER] Incremented via RPC function');
          } catch (rpcError, rpcStackTrace) {
            print('❌ [COUNTER] RPC also failed: $rpcError');
            await ErrorLogService.logError(
              location: 'Supervisor Approval Screen - Increment API Call Counter (RPC)',
              type: 'Database',
              description: 'RPC function also failed for API call counter: $rpcError',
              stackTrace: rpcStackTrace,
            );
            throw triggerError; // Re-throw original error
          }
        }
      } else {
        // Create new record if none exists
        print('🔍 [COUNTER] No settings found, creating new record...');
        await SupabaseService.client.from('system_settings').insert({
          'google_api_calls': 1,
          'google_api_saves': 0,
          'week_start': 1,
        });
        print('✅ [COUNTER] Created system_settings record with API call count: 1');
      }
    } catch (e, stackTrace) {
      print('❌ [COUNTER] Error incrementing API call counter: $e');
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Increment API Call Counter (Outer)',
        type: 'Database',
        description: 'Error incrementing API call counter: $e',
        stackTrace: stackTrace,
      );
      // Don't fail the operation if counter update fails
    }
  }

  /// Increment the Google API save counter in system_settings
  /// (Following the same pattern as user_edit_screen.dart)
  Future<void> _incrementApiSaveCounter() async {
    try {
      print('🔍 [COUNTER] Fetching system_settings for save counter...');
      // Get the first (and should be only) system_settings record
      final settings = await SupabaseService.client
          .from('system_settings')
          .select('id, google_api_saves')
          .limit(1)
          .maybeSingle();

      print('🔍 [COUNTER] Settings result: $settings');

      if (settings != null) {
        // Update existing record
        final currentCount = (settings['google_api_saves'] as int?) ?? 0;
        final settingsId = settings['id']?.toString();
        print('🔍 [COUNTER] Current save count: $currentCount, ID: $settingsId');
        
        // Try using RPC function if available, otherwise use direct update
        try {
          // Attempt direct update without select
          await SupabaseService.client
              .from('system_settings')
              .update({'google_api_saves': currentCount + 1})
              .eq('id', settingsId ?? '');
          
          print('✅ [COUNTER] Incremented API save counter to ${currentCount + 1}');
        } catch (triggerError, triggerStackTrace) {
          // If trigger fails, try using RPC function as workaround
          print('⚠️ [COUNTER] Direct update failed (trigger issue), trying alternative...');
          await ErrorLogService.logError(
            location: 'Supervisor Approval Screen - Increment API Save Counter',
            type: 'Database',
            description: 'Direct update failed (trigger issue) for API save counter: $triggerError',
            stackTrace: triggerStackTrace,
          );
          try {
            // Try using a stored procedure/RPC if available
            await SupabaseService.client.rpc('increment_google_api_saves', params: {
              'p_id': settingsId,
            });
            print('✅ [COUNTER] Incremented via RPC function');
          } catch (rpcError, rpcStackTrace) {
            print('❌ [COUNTER] RPC also failed: $rpcError');
            await ErrorLogService.logError(
              location: 'Supervisor Approval Screen - Increment API Save Counter (RPC)',
              type: 'Database',
              description: 'RPC function also failed for API save counter: $rpcError',
              stackTrace: rpcStackTrace,
            );
            throw triggerError; // Re-throw original error
          }
        }
      } else {
        // Create new record if none exists
        print('🔍 [COUNTER] No settings found, creating new record...');
        await SupabaseService.client.from('system_settings').insert({
          'google_api_calls': 0,
          'google_api_saves': 1,
          'week_start': 1,
        });
        print('✅ [COUNTER] Created system_settings record with API save count: 1');
      }
    } catch (e, stackTrace) {
      print('❌ [COUNTER] Error incrementing API save counter: $e');
      await ErrorLogService.logError(
        location: 'Supervisor Approval Screen - Increment API Save Counter (Outer)',
        type: 'Database',
        description: 'Error incrementing API save counter: $e',
        stackTrace: stackTrace,
      );
      // Don't fail the operation if counter update fails
    }
  }
  
  /// Show comments popup
  void _showCommentsPopup(String? comments) {
    if (comments == null || comments.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comments'),
        content: SingleChildScrollView(
          child: Text(comments),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  /// Build a filterable column header with Excel-style dropdown
  Widget _buildFilterableHeader({
    required double width,
    required String label,
    required String filterKey,
    required bool hasActiveFilter,
    bool isResizable = false,
    Function(double)? onResize,
  }) {
    return Builder(
      builder: (builderContext) => Container(
        width: width,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey, width: 1)),
        ),
        child: Stack(
          children: [
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: hasActiveFilter ? Colors.blue : Colors.black,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      final isOpen = _openFilterDropdown == filterKey;
                      setState(() {
                        if (isOpen) {
                          _hideFilterDropdown();
                          _openFilterDropdown = null;
                        } else {
                          _hideFilterDropdown(); // Close any other open dropdown
                          _openFilterDropdown = filterKey;
                          // Use a post-frame callback to get the correct context
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _showFilterDropdown(filterKey, builderContext);
                          });
                        }
                      });
                    },
                    child: Icon(
                      Icons.filter_list,
                      size: 16,
                      color: hasActiveFilter ? Colors.blue : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (isResizable && onResize != null)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: Container(
                      width: 4,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  OverlayEntry? _filterOverlayEntry;
  
  /// Show filter dropdown using Overlay
  void _showFilterDropdown(String filterKey, BuildContext context) {
    // Remove existing overlay if any
    _hideFilterDropdown();
    
    // Get the header row position using GlobalKey
    final RenderBox? headerBox = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (headerBox == null) return;
    
    final headerPosition = headerBox.localToGlobal(Offset.zero);
    final headerSize = headerBox.size;
    
    // Calculate position based on column widths
    double left = headerPosition.dx + 8.0; // padding
    double width = 200.0;
    
    if (filterKey == 'day') {
      left = headerPosition.dx + 8.0; // After padding
      width = 200.0;
    } else if (filterKey == 'employee') {
      left = headerPosition.dx + 8.0 + 60.0; // After Day
      width = _employeeColumnWidth.clamp(200.0, 400.0);
    } else if (filterKey == 'project') {
      left = headerPosition.dx + 8.0 + 60.0 + _employeeColumnWidth; // After Day + Employee
      width = _projectColumnWidth.clamp(200.0, 600.0);
    }
    
    final top = headerPosition.dy + headerSize.height;
    
    _filterOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          elevation: 20,
          child: _buildFilterDropdown(filterKey, width),
        ),
      ),
    );
    
    Overlay.of(context).insert(_filterOverlayEntry!);
  }
  
  /// Hide filter dropdown
  void _hideFilterDropdown() {
    _filterOverlayEntry?.remove();
    _filterOverlayEntry = null;
  }

  /// Rebuild the filter dropdown overlay so checkbox state updates visually (e.g. after toggling a selection).
  void _refreshFilterDropdown() {
    _filterOverlayEntry?.markNeedsBuild();
  }

  /// Apply current filter and close the dropdown (used by Apply button).
  void _applyFilterAndClose() {
    _hideFilterDropdown();
    setState(() => _openFilterDropdown = null);
    _loadTimePeriods();
  }

  /// Build the three buttons row for filter dropdowns: Select All, Clear, Apply (horizontal - for wide dropdowns).
  Widget _buildFilterDropdownButtons({
    required VoidCallback onSelectAll,
    required VoidCallback onClear,
    required VoidCallback onApply,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: onSelectAll,
            child: const Text('Select All'),
          ),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: onApply,
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  /// Build the three buttons stacked vertically (for narrow dropdowns: Employee, Role).
  Widget _buildFilterDropdownButtonsVertical({
    required VoidCallback onSelectAll,
    required VoidCallback onClear,
    required VoidCallback onApply,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton(
            onPressed: onSelectAll,
            child: const Text('Select All'),
          ),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: onApply,
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
  
  /// Get left position for filter dropdown (deprecated - using Overlay now)
  double _getFilterDropdownLeft(String filterKey) {
    double left = 8; // padding
    if (filterKey == 'day') {
      return left;
    } else if (filterKey == 'employee') {
      return left + 60; // Day width
    } else if (filterKey == 'project') {
      return left + 60 + _employeeColumnWidth; // Day + Employee width
    }
    return left;
  }
  
  /// Get width for filter dropdown
  double _getFilterDropdownWidth(String filterKey) {
    if (filterKey == 'day') {
      return 200;
    } else if (filterKey == 'employee') {
      return _employeeColumnWidth.clamp(200.0, 400.0);
    } else if (filterKey == 'project') {
      return _projectColumnWidth.clamp(200.0, 400.0);
    }
    return 200;
  }
  
  /// Build filter dropdown for a column
  Widget _buildFilterDropdown(String filterKey, double width) {
    final content = switch (filterKey) {
      'day' => _buildDayFilter(),
      'employee' => _buildEmployeeFilter(),
      'project' => _buildProjectFilter(),
      'role' => _buildRoleFilter(),
      _ => const SizedBox.shrink(),
    };
    return GestureDetector(
      onTap: () {}, // Prevent closing when clicking inside
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey, width: 2),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
  
  static const List<String> _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Build day filter dropdown. No Select All/Clear/Apply (Status line has equivalent); changes apply on toggle.
  Widget _buildDayFilter() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filter by Day (${_allDays.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _hideFilterDropdown();
                  setState(() => _openFilterDropdown = null);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const Divider(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: _allDays.map((day) {
              final isSelected = !_dayFilterExplicitNone && (_selectedDays.isEmpty || _selectedDays.contains(day));
              return CheckboxListTile(
                title: Text(day),
                value: isSelected,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (selected) {
                  setState(() {
                    _dayFilterExplicitNone = false;
                    if (selected == true) {
                      _selectedDays.add(day);
                      if (_selectedDays.length == _allDays.length) _selectedDays.clear();
                    } else {
                      _selectedDays = Set.from(_allDays)..remove(day);
                      if (_selectedDays.isEmpty) _dayFilterExplicitNone = true;
                    }
                  });
                  _refreshFilterDropdown();
                  _loadTimePeriods();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  /// Back / Next buttons when exactly one employee is selected (same row as Status). Uses employees from displayed data (respects prefix filter).
  Widget _buildEmployeeNextBackButtons() {
    final list = _employeesFromDisplayedPeriods;
    if (list.isEmpty) return const SizedBox.shrink();
    final selectedId = _selectedUserIds.single;
    final idx = list.indexWhere((e) => e['user_id']?.toString() == selectedId);
    if (idx < 0) return const SizedBox.shrink();
    final canPrev = idx > 0;
    final canNext = idx < list.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: canPrev
              ? () {
                  final prevId = list[idx - 1]['user_id']?.toString();
                  if (prevId != null) {
                    setState(() => _selectedUserIds = {prevId});
                    _loadTimePeriods();
                  }
                }
              : null,
          tooltip: 'Previous employee',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        Text(
          '${idx + 1} / ${list.length}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward, size: 20),
          onPressed: canNext
              ? () {
                  final nextId = list[idx + 1]['user_id']?.toString();
                  if (nextId != null) {
                    setState(() => _selectedUserIds = {nextId});
                    _loadTimePeriods();
                  }
                }
              : null,
          tooltip: 'Next employee',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  /// Build employee filter dropdown (only employees that appear in displayed data, so prefix filter applies).
  Widget _buildEmployeeFilter() {
    final employeeList = _employeesFromDisplayedPeriods;
    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 400, minWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filter by Employee (${employeeList.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _hideFilterDropdown();
                  setState(() => _openFilterDropdown = null);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const Divider(),
          _buildFilterDropdownButtonsVertical(
            onSelectAll: () {
              setState(() {
                _selectedUserIds.clear();
                _employeeFilterExplicitNone = false;
              });
              _refreshFilterDropdown();
            },
            onClear: () {
              setState(() {
                _selectedUserIds.clear();
                _employeeFilterExplicitNone = true;
              });
              _refreshFilterDropdown();
            },
            onApply: _applyFilterAndClose,
          ),
          Expanded(
            child: employeeList.isEmpty
                ? const Center(child: Text('No employees in current data'))
                : ListView.builder(
                    shrinkWrap: false,
                    itemCount: employeeList.length,
                    itemBuilder: (context, index) {
                      final user = employeeList[index];
                      final userId = user['user_id']?.toString() ?? '';
                      final userName = user['display_name']?.toString() ?? 'Unknown';
                      final isSelected = !_employeeFilterExplicitNone && (_selectedUserIds.isEmpty || _selectedUserIds.contains(userId));
                      final allIds = employeeList.map((e) => e['user_id']?.toString()).whereType<String>().toSet();
                      return CheckboxListTile(
                        title: Text(userName, overflow: TextOverflow.ellipsis),
                        value: isSelected,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (selected) {
                          setState(() {
                            _employeeFilterExplicitNone = false;
                            if (selected == true) {
                              _selectedUserIds.add(userId);
                              if (_selectedUserIds.length == allIds.length) _selectedUserIds.clear();
                            } else {
                              _selectedUserIds = Set.from(allIds)..remove(userId);
                              if (_selectedUserIds.isEmpty) _employeeFilterExplicitNone = true;
                            }
                          });
                          _refreshFilterDropdown();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  
  /// Build project filter dropdown (from displayed data so prefix filter applies).
  Widget _buildProjectFilter() {
    final list = _displayedPeriodsForEmployeeSource;
    final uniqueProjects = <String, Map<String, dynamic>>{};
    for (final period in list) {
      final projectId = period['project_id']?.toString() ?? '';
      final projectName = period['project_name']?.toString() ?? 'Unknown';
      if (!uniqueProjects.containsKey(projectId)) {
        uniqueProjects[projectId] = {'id': projectId, 'project_name': projectName};
      }
    }
    var projectList = uniqueProjects.values.toList()
      ..sort((a, b) => (a['project_name'] ?? '').toString().compareTo((b['project_name'] ?? '').toString()));
    
    // Apply text filter if set
    if (_projectFilter.isNotEmpty) {
      final filterTerms = _projectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
      projectList = projectList.where((project) {
        final name = (project['project_name']?.toString() ?? '').toLowerCase();
        return filterTerms.every((term) => name.contains(term));
      }).toList();
    }
    
    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 400, minWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filter by Project (${projectList.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _hideFilterDropdown();
                  setState(() => _openFilterDropdown = null);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const Divider(),
          _buildFilterDropdownButtons(
            onSelectAll: () {
              setState(() {
                _selectedProjectIds.clear();
                _projectFilterExplicitNone = false;
              });
              _refreshFilterDropdown();
            },
            onClear: () {
              setState(() {
                _selectedProjectIds.clear();
                _projectFilterExplicitNone = true;
              });
              _refreshFilterDropdown();
            },
            onApply: _applyFilterAndClose,
          ),
          TextField(
            key: ValueKey('project_filter_dropdown_$_projectFilterResetCounter'),
            decoration: const InputDecoration(
              hintText: 'Search projects...',
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() {
                _projectFilter = value;
              });
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: projectList.isEmpty
                ? const Center(child: Text('No projects match filter'))
                : ListView.builder(
                    shrinkWrap: false,
                    itemCount: projectList.length,
                    itemBuilder: (context, index) {
                      final project = projectList[index];
                      final projectId = project['id']?.toString() ?? '';
                      final projectName = project['project_name']?.toString() ?? 'Unknown';
                      final allIds = projectList.map((p) => p['id']?.toString()).whereType<String>().toSet();
                      final isSelected = !_projectFilterExplicitNone && (_selectedProjectIds.isEmpty || _selectedProjectIds.contains(projectId));
                      return CheckboxListTile(
                        title: Text(projectName, overflow: TextOverflow.ellipsis),
                        value: isSelected,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (selected) {
                          setState(() {
                            _projectFilterExplicitNone = false;
                            if (selected == true) {
                              _selectedProjectIds.add(projectId);
                              if (_selectedProjectIds.length == allIds.length) _selectedProjectIds.clear();
                            } else {
                              _selectedProjectIds = Set.from(allIds)..remove(projectId);
                              if (_selectedProjectIds.isEmpty) _projectFilterExplicitNone = true;
                            }
                          });
                          _refreshFilterDropdown();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Build role filter dropdown (from displayed data so prefix filter applies).
  Widget _buildRoleFilter() {
    final list = _displayedPeriodsForEmployeeSource;
    final uniqueRoles = <String>{};
    for (final period in list) {
      final role = period['user_role']?.toString() ?? '--';
      uniqueRoles.add(role);
    }
    final roleList = uniqueRoles.toList()..sort();
    final allRoles = roleList.toSet();
    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 400, minWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filter by Role (${roleList.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _hideFilterDropdown();
                  setState(() => _openFilterDropdown = null);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const Divider(),
          _buildFilterDropdownButtonsVertical(
            onSelectAll: () {
              setState(() {
                _selectedRoles.clear();
                _roleFilterExplicitNone = false;
              });
              _refreshFilterDropdown();
            },
            onClear: () {
              setState(() {
                _selectedRoles.clear();
                _roleFilterExplicitNone = true;
              });
              _refreshFilterDropdown();
            },
            onApply: _applyFilterAndClose,
          ),
          Expanded(
            child: roleList.isEmpty
                ? const Center(child: Text('No roles in current data'))
                : ListView.builder(
                    shrinkWrap: false,
                    itemCount: roleList.length,
                    itemBuilder: (context, index) {
                      final role = roleList[index];
                      final isSelected = !_roleFilterExplicitNone && (_selectedRoles.isEmpty || _selectedRoles.contains(role));
                      return CheckboxListTile(
                        title: Text(role, overflow: TextOverflow.ellipsis),
                        value: isSelected,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (selected) {
                          setState(() {
                            _roleFilterExplicitNone = false;
                            if (selected == true) {
                              _selectedRoles.add(role);
                              if (_selectedRoles.length == allRoles.length) _selectedRoles.clear();
                            } else {
                              _selectedRoles = Set.from(allRoles)..remove(role);
                              if (_selectedRoles.isEmpty) _roleFilterExplicitNone = true;
                            }
                          });
                          _refreshFilterDropdown();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'submitted':
        return Colors.orange;
      case 'imported':
        return Colors.orange.shade700; // Slightly darker to distinguish from submitted
      case 'supervisor_approved':
        return Colors.blue;
      case 'admin_approved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupervisor) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Time Period Approval',
            style: TextStyle(color: Colors.black),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0081FB),
          foregroundColor: Colors.black,
          actions: const [ScreenInfoIcon(screenName: 'supervisor_approval_screen.dart')],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                'Access Denied',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'You need Supervisor or Manager privileges',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Approve Time Periods',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [
          const ScreenInfoIcon(screenName: 'supervisor_approval_screen.dart'),
          // Create Time Period for User
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Time Period for User',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TimeTrackingScreen(),
                ),
              ).then((_) => _loadTimePeriods());
            },
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadTimePeriods,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          // Close filter dropdown when clicking outside
          if (_openFilterDropdown != null) {
            _hideFilterDropdown();
            setState(() => _openFilterDropdown = null);
          }
        },
        child: Column(
          children: [
          // Week Navigation with arrows beside date range (compact row)
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Center(
              child: UnconstrainedBox(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _previousWeek,
                      tooltip: 'Previous Week',
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${DateFormat('MMM dd').format(_selectedWeekStart)} - ${DateFormat('MMM dd, yyyy').format(_getWeekEnd(_selectedWeekStart))}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (!_selectedWeekStart.isAtSameMomentAs(_getWeekStart(DateTime.now())))
                          TextButton(
                            onPressed: _goToCurrentWeek,
                            child: const Text('Go to Current Week'),
                          ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _canNavigateNext() ? _nextWeek : null,
                      tooltip: 'Next Week',
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Status Filter Bar: Status, Day, Prefix Filter, Next/Back (when 1 employee), Approve Selected
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey[100],
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _statusFilter = 'submitted');
                    _loadTimePeriods();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _statusFilter == 'submitted' ? Colors.green : null,
                    foregroundColor: _statusFilter == 'submitted' ? Colors.white : null,
                  ),
                  child: const Text('Submitted'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _statusFilter = 'supervisor_approved');
                    _loadTimePeriods();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _statusFilter == 'supervisor_approved' ? Colors.green : null,
                    foregroundColor: _statusFilter == 'supervisor_approved' ? Colors.white : null,
                  ),
                  child: const Text('Approved'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _statusFilter = 'all');
                    _loadTimePeriods();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _statusFilter == 'all' ? Colors.green : null,
                    foregroundColor: _statusFilter == 'all' ? Colors.white : null,
                  ),
                  child: const Text('All'),
                ),
                const SizedBox(width: 24),
                // Day filter buttons
                ...['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((day) {
                  final isSelected = _selectedDays.contains(day);
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (isSelected) {
                            _selectedDays.remove(day);
                          } else {
                            _selectedDays.add(day);
                          }
                        });
                        _loadTimePeriods();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.green : null,
                        foregroundColor: isSelected ? Colors.white : null,
                      ),
                      child: Text(day),
                    ),
                  );
                }),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _selectedDays.clear());
                    _loadTimePeriods();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedDays.isEmpty ? Colors.green : null,
                    foregroundColor: _selectedDays.isEmpty ? Colors.white : null,
                  ),
                  child: const Text('All Week'),
                ),
                const SizedBox(width: 12),
                // Prefix Filter (same row)
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _prefixFilterController,
                    decoration: InputDecoration(
                      labelText: 'Prefix Filter',
                      hintText: 'e.g. A, B, C',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      prefixIcon: const Icon(Icons.filter_list, size: 18),
                      suffixIcon: _prefixFilterController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _prefixFilterController.clear();
                                setState(() {});
                              },
                              tooltip: 'Clear',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                // Next / Back when exactly one employee selected
                if (_selectedUserIds.length == 1) ...[
                  const SizedBox(width: 12),
                  _buildEmployeeNextBackButtons(),
                ],
                const SizedBox(width: 12),
                // Sort by
                const Text('Sort:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(width: 4),
                DropdownButton<String>(
                  value: _sortBy,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 'day', child: Text('Day')),
                    DropdownMenuItem(value: 'employee', child: Text('Employee')),
                    DropdownMenuItem(value: 'role', child: Text('Role')),
                    DropdownMenuItem(value: 'project', child: Text('Project')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortBy = v);
                  },
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                  onPressed: _resetAllFilters,
                ),
                if (_selectedPeriods.isNotEmpty) ...[
                  const Spacer(),
                  Text(
                    '${_selectedPeriods.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Approve Selected'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _approveSelected,
                  ),
                ],
              ],
            ),
          ),
          ),

          // Time Periods List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _timePeriods.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No time periods found',
                              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // Sticky Header Row
                          Container(
                            key: _headerKey,
                            padding: const EdgeInsets.only(left: 0, right: 0, top: 12, bottom: 12),
                            margin: EdgeInsets.zero,
                            color: Colors.grey[200],
                            alignment: Alignment.centerLeft,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                      // Day (with filter)
                                      _buildFilterableHeader(
                                        width: 60,
                                        label: 'Day',
                                        filterKey: 'day',
                                        hasActiveFilter: _dayFilterExplicitNone || _selectedDays.isNotEmpty,
                                      ),
                                      // Employee (resizable, with filter)
                                      _buildFilterableHeader(
                                        width: _employeeColumnWidth,
                                        label: 'Employee',
                                        filterKey: 'employee',
                                        hasActiveFilter: _employeeFilterExplicitNone || _selectedUserIds.isNotEmpty,
                                        isResizable: true,
                                        onResize: (delta) {
                                          setState(() {
                                            _employeeColumnWidth = (_employeeColumnWidth + delta).clamp(80.0, 300.0);
                                          });
                                        },
                                      ),
                                      // Role (filter by users_setup.role)
                                      _buildFilterableHeader(
                                        width: 100,
                                        label: 'Role',
                                        filterKey: 'role',
                                        hasActiveFilter: _roleFilterExplicitNone || _selectedRoles.isNotEmpty,
                                      ),
                                      // Project (resizable, with filter)
                                      _buildFilterableHeader(
                                        width: _projectColumnWidth,
                                        label: 'Project',
                                        filterKey: 'project',
                                        hasActiveFilter: _projectFilterExplicitNone || _selectedProjectIds.isNotEmpty || _projectFilter.isNotEmpty,
                                        isResizable: true,
                                        onResize: (delta) {
                                          setState(() {
                                            _projectColumnWidth = (_projectColumnWidth + delta).clamp(80.0, 600.0);
                                          });
                                        },
                                      ),
                                      const SizedBox(
                                        width: 60,
                                        child: Center(
                                          child: Text('Start', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                      ),
                                      const SizedBox(
                                        width: 60,
                                        child: Center(
                                          child: Text('Break', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                      ),
                                      const SizedBox(
                                        width: 60,
                                        child: Center(
                                          child: Text('Finish', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                      ),
                                      // Total (with border after)
                                      Container(
                                        width: 60,
                                        decoration: const BoxDecoration(
                                          border: Border(right: BorderSide(color: Colors.grey, width: 1)),
                                        ),
                                        child: const Center(
                                          child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                      ),
                                      // Used Plant & Equipment (merged header spanning 6 columns)
                                      Container(
                                        width: (30 * _maxUsedFleet).toDouble(),
                                        decoration: const BoxDecoration(
                                          border: Border(right: BorderSide(color: Colors.grey, width: 1)),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            'Used Plant & Equipment',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      // Mobilised Plant (merged header spanning all 4 columns)
                                      Container(
                                        width: (30 * _maxMobilisedFleet).toDouble(),
                                        decoration: const BoxDecoration(
                                          border: Border(right: BorderSide(color: Colors.grey, width: 1)),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            'Mobilised Plant',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      // Concrete Mix (merged header)
                                      Container(
                                        width: 180,
                                        child: const Center(
                                          child: Text(
                                            'Concrete Mix',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      // Allowances
                                      const SizedBox(
                                        width: 80,
                                        child: Text('Allowances', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                      // On Call
                                      const SizedBox(
                                        width: 60,
                                        child: Center(
                                          child: Icon(Icons.phone, size: 18),
                                        ),
                                      ),
                                      // GPS
                                      const SizedBox(
                                        width: 60,
                                        child: Center(
                                          child: Text('GPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                        ),
                                      ),
                                      // Comments
                                      const SizedBox(
                                        width: 60,
                                        child: Center(
                                          child: Icon(Icons.comment, size: 18),
                                        ),
                                      ),
                                      // Checkbox (moved here - after Comments, before Actions)
                                      SizedBox(
                                        width: 40,
                                        child: Checkbox(
                                          value: _selectAll,
                                          onChanged: (_) => _toggleSelectAll(),
                                        ),
                                      ),
                                      // Actions (compact, same as review screen)
                                      const SizedBox(
                                        width: 72,
                                        child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                ],
                              ),
                            ),
                          ),
                          // Scrollable Data Rows (filtered by prefix, sorted: weekday, employee, start)
                          Expanded(
                            child: ListView.builder(
                              itemCount: _displayedPeriods.length,
                              itemBuilder: (context, index) {
                                return _buildTimePeriodRow(_displayedPeriods[index], index);
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
        ),
      ),
    );
  }

  /// Check if there's a time gap between this period and the previous period for the same user/day (in the displayed list).
  bool _hasTimeGap(List<Map<String, dynamic>> list, Map<String, dynamic> period, int index) {
    if (index == 0) return false;
    
    final userId = period['user_id']?.toString() ?? '';
    final workDate = period['work_date']?.toString() ?? '';
    final startTime = period['start_time'] != null
        ? DateTime.parse(period['start_time']?.toString() ?? '')
        : null;
    
    if (userId.isEmpty || workDate.isEmpty || startTime == null) return false;
    
    final prevPeriod = list[index - 1];
    final prevUserId = prevPeriod['user_id']?.toString() ?? '';
    final prevWorkDate = prevPeriod['work_date']?.toString() ?? '';
    
    if (prevUserId != userId || prevWorkDate != workDate) return false;
    
    final prevFinishTime = prevPeriod['finish_time'] != null
        ? DateTime.parse(prevPeriod['finish_time']?.toString() ?? '')
        : null;
    
    if (prevFinishTime == null) return false;
    final gap = startTime.difference(prevFinishTime).inMinutes;
    return gap > 0;
  }

  Widget _buildTimePeriodRow(Map<String, dynamic> period, int index) {
    final periodId = period['id']?.toString() ?? '';
    final isSelected = _selectedPeriods.contains(periodId);
    final status = period['status']?.toString() ?? '';
    final canSelect = _shouldShowApproveButton(status);
    
    final userName = period['user_name']?.toString() ?? 'Unknown';
    final workDate = period['work_date'] != null
        ? DateTime.parse(period['work_date']?.toString() ?? '')
        : null;
    final day = _formatDay(workDate);
    
    final startTime = period['start_time'] != null
        ? DateTime.parse(period['start_time']?.toString() ?? '')
        : null;
    final finishTime = period['finish_time'] != null
        ? DateTime.parse(period['finish_time']?.toString() ?? '')
        : null;
    
    final breakMinutes = _breakDurationsCache[periodId] ?? 0;
    final breakTime = _formatBreakDuration(breakMinutes);
    final totalTime = _calculateTotalTime(startTime, finishTime, breakMinutes);
    
    final projectName = period['project_name']?.toString() ?? '--';
    final userRole = period['user_role']?.toString() ?? '--';
    
    final usedFleet = _usedFleetCache[periodId] ?? [];
    final mobilisedFleet = _mobilisedFleetCache[periodId] ?? [];
    
    final isApproved = _isApproved(period);
    
    // Concrete mix data
    final concreteTicketNo = period['concrete_ticket_no']?.toString() ?? '';
    final concreteMixTypeId = period['concrete_mix_type']?.toString() ?? '';
    final concreteMixTypeName = _getConcreteMixName(concreteMixTypeId);
    final concreteQty = period['concrete_qty']?.toString() ?? '';
    final concreteMixText = [concreteTicketNo, concreteMixTypeName, concreteQty]
        .where((s) => s.isNotEmpty)
        .join(', ');
    
    // Allowances
    final totalAllowances = _calculateTotalAllowances(period);
    final allowancesText = _formatAllowances(totalAllowances);
    
    // On Call
    final onCall = period['on_call'] == true;
    
    // GPS
    final clockInDistance = period['clock_in_distance']?.toString() ?? '--';
    
    // Comments
    final comments = period['comments']?.toString() ?? '';
    final hasComments = comments.isNotEmpty;
    
    // Check for time gap with previous period (same user, same day)
    final hasTimeGap = _hasTimeGap(_displayedPeriods, period, index);
    
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: hasTimeGap 
              ? const BorderSide(color: Colors.red, width: 3)
              : BorderSide(color: Colors.grey[300]!),
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
        color: isSelected ? Colors.blue[50] : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 2),
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Day (with border, center justified)
            Container(
              width: 60,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey, width: 1)),
              ),
              child: Center(
                child: Text(
                  day,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            
            // Employee (resizable, with border, center justified)
            Container(
              width: _employeeColumnWidth,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey, width: 1)),
              ),
              child: Center(
                child: Text(
                  userName,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            
            // Role (users_setup.role)
            Container(
              width: 100,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey, width: 1)),
              ),
              child: Center(
                child: Text(
                  userRole,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            
            // Project (resizable, with border, left justified)
            Container(
              width: _projectColumnWidth,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey, width: 1)),
              ),
              child: Text(
                projectName,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
            ),
            
            // Start (center justified)
            SizedBox(
              width: 60,
              child: Center(
                child: Text(
                  _formatTimeAsHHMM(startTime),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            
            // Break (center justified)
            SizedBox(
              width: 60,
              child: Center(
                child: Text(
                  breakTime,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            
            // Finish (center justified)
            SizedBox(
              width: 60,
              child: Center(
                child: Text(
                  _formatTimeAsHHMM(finishTime),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            
            // Total (with border, center justified)
            Container(
              width: 60,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey, width: 1)),
              ),
              child: Center(
                child: Text(
                  totalTime,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            // Used Plant columns (6 columns, with border after, center justified, clickable)
            ...List.generate(_maxUsedFleet, (index) {
              final isLast = index == _maxUsedFleet - 1;
              final plantNo = index < usedFleet.length ? usedFleet[index] : null;
              return Container(
                width: 30,
                decoration: isLast
                    ? const BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey, width: 1)),
                      )
                    : null,
                child: Center(
                  child: plantNo != null && plantNo.isNotEmpty && plantNo != '--'
                      ? GestureDetector(
                          onTap: () => _showPlantDescriptionPopup(plantNo),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Text(
                              plantNo,
                              style: const TextStyle(fontSize: 11, color: Colors.blue, decoration: TextDecoration.underline),
                            ),
                          ),
                        )
                      : Text(
                          '--',
                          style: const TextStyle(fontSize: 11),
                        ),
                ),
              );
            }),
            
            // Mobilised columns (all 4 columns merged, with border after, center justified, clickable)
            ...List.generate(_maxMobilisedFleet, (index) {
              final isLast = index == _maxMobilisedFleet - 1;
              final plantNo = index < mobilisedFleet.length ? mobilisedFleet[index] : null;
              return Container(
                width: 30,
                decoration: isLast
                    ? const BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey, width: 1)),
                      )
                    : null,
                child: Center(
                  child: plantNo != null && plantNo.isNotEmpty && plantNo != '--'
                      ? GestureDetector(
                          onTap: () => _showPlantDescriptionPopup(plantNo),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Text(
                              plantNo,
                              style: const TextStyle(fontSize: 11, color: Colors.blue, decoration: TextDecoration.underline),
                            ),
                          ),
                        )
                      : Text(
                          '--',
                          style: const TextStyle(fontSize: 11),
                        ),
                ),
              );
            }),
            
            // Concrete Mix (merged: ticket, mix_type, qty, center justified)
            SizedBox(
              width: 180,
              child: Center(
                child: Text(
                  concreteMixText.isEmpty ? '--' : concreteMixText,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            
            // Allowances (clickable, center justified)
            GestureDetector(
              onTap: totalAllowances > 0 ? () => _showAllowancesPopup(period) : null,
              child: SizedBox(
                width: 80,
                child: Center(
                  child: Text(
                    allowancesText,
                    style: TextStyle(
                      fontSize: 11,
                      color: totalAllowances > 0 ? Colors.blue : Colors.black,
                      decoration: totalAllowances > 0 ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ),
            ),
            
            // On Call (telephone icon, center justified)
            SizedBox(
              width: 60,
              child: Center(
                child: onCall
                    ? const Icon(Icons.phone, size: 18, color: Colors.green)
                    : const SizedBox(width: 18, height: 18),
              ),
            ),
            
            // GPS (center justified, clickable)
            GestureDetector(
              onTap: () => _showGPSMapPopup(period),
              child: SizedBox(
                width: 60,
                child: Center(
                  child: Text(
                    clockInDistance,
                    style: TextStyle(
                      fontSize: 11,
                      color: clockInDistance != '--' ? Colors.blue : Colors.black,
                      decoration: clockInDistance != '--' ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ),
            ),
            
            // Comments (speech bubble icon, clickable, center justified)
            GestureDetector(
              onTap: hasComments ? () => _showCommentsPopup(comments) : null,
              child: SizedBox(
                width: 60,
                child: Center(
                  child: hasComments
                      ? const Icon(Icons.comment, size: 18, color: Colors.blue)
                      : const SizedBox(width: 18, height: 18),
                ),
              ),
            ),
            
            // Checkbox (moved here - after Comments, before Actions)
            SizedBox(
              width: 40,
              child: Checkbox(
                value: isSelected,
                onChanged: canSelect ? (_) => _toggleSelection(periodId) : null,
              ),
            ),
            
            // Actions (compact: arrows closer to row, same as review screen)
            SizedBox(
              width: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isApproved)
                    GestureDetector(
                      onTap: () => _toggleApproval(periodId, false),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: status == 'admin_approved' ? Colors.orange : Colors.green,
                          border: Border.all(
                            color: status == 'admin_approved' ? Colors.orange : Colors.green,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                    ),
                  if (isApproved) const SizedBox(width: 4),
                  if (status == 'submitted' || status == 'imported' || status == 'supervisor_approved')
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      color: Colors.blue,
                      tooltip: 'Edit',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      onPressed: () => _editTimePeriod(period),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    color: Colors.red,
                    tooltip: 'Delete',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    onPressed: () => _deleteTimePeriod(periodId),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

