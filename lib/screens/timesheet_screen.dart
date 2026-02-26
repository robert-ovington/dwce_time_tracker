/// Timesheet Screen
/// 
/// Main screen for recording time entries with offline support.
/// Based on the base44.com timesheet implementation.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/errors/error_log_service.dart';
import 'package:dwce_time_tracker/modules/offline/offline_storage_service.dart';
import 'package:dwce_time_tracker/modules/offline/sync_service.dart';
import 'package:dwce_time_tracker/modules/users/user_edit_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';
import 'package:dwce_time_tracker/widgets/fleet_keyboard.dart';
import 'package:dwce_time_tracker/widgets/screen_info_icon.dart';

class TimeTrackingScreen extends StatefulWidget {
  final String? timePeriodId; // Optional: If provided, we're editing an existing time period
  
  const TimeTrackingScreen({super.key, this.timePeriodId});

  @override
  State<TimeTrackingScreen> createState() => _TimeTrackingScreenState();
}

class _TimeTrackingScreenState extends State<TimeTrackingScreen> {
  // Connectivity and sync
  bool _isOnline = true;
  int _pendingCount = 0;
  bool _isSyncing = false;
  bool _isSaving = false; // Flag to prevent multiple save clicks
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // User data
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _userSetup; // Store users_setup for display_name fallback
  bool _canEnterForOthers = false;
  List<Map<String, dynamic>> _allUsers = [];
  bool _recordForAnotherPerson = false; // Checkbox state for recording for another person

  // Form fields
  String _selectedEmployee = ''; // Stores email for current user, or user_id for others
  String? _selectedEmployeeUserId; // Store user_id when selecting other users from dropdown
  List<String> _employers = [];
  String? _selectedEmployerForOther; // Employer when entering data for another user (users_data.employer_name)
  String _date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _startTime = '';
  String _finishTime = '';
  List<Map<String, dynamic>> _breaks = [];
  String _selectedProject = '';
  String _selectedProjectDescription = ''; // Store description from dropdown selection
  List<String> _usedFleet = [];
  List<String> _mobilisedFleet = [];
  String _travelToSite = '';
  String _travelFromSite = '';
  String _miscellaneous = '';
  String _projectFilter = ''; // Filter text for project dropdown
  int _projectFilterResetCounter = 0; // Counter to force project filter field to rebuild when cleared
  String _plantFilter = ''; // Filter text for fleet dropdown
  String _travelToSiteTime = '00:00'; // Time format for allowances
  String _travelFromSiteTime = '00:00';
  String _miscellaneousTime = '00:00';
  bool _onCall = false;
  String _ticketNumber = '';
  String _concreteMix = '';
  String _quantity = '';
  String _comments = '';
  int _commentResetCounter = 0; // Counter to force comment field to rebuild when cleared

  // Calculated fields
  String _calculatedTravelTime = '';
  String _calculatedDistance = '';
  
  // Travel summary fields
  int _totalTravelTimeMinutes = 0;
  int _availableAllowanceMinutes = 0;
  int _availableAllowanceTotalMinutes = 0;
  String _roundedOneWay = '';
  String _roundedTwoWay = '';
  double _totalDistanceKm = 0.0;

  // Data lists
  List<Map<String, dynamic>> _allProjects = [];
  List<Map<String, dynamic>> _allPlant = [];
  List<Map<String, dynamic>> _allConcreteMixes = [];
  
  // Map for fast plant lookups by plant_no (uppercase)
  Map<String, Map<String, dynamic>> _plantMapByNo = {};
  // Map for fast project lookups by project_name
  Map<String, Map<String, dynamic>> _projectMapByName = {};

  // GPS background refresh
  Timer? _gpsRefreshTimer;
  double? _cachedLatitude;
  double? _cachedLongitude;
  int? _cachedGpsAccuracy;
  DateTime? _gpsLastUpdated;

  // Feature flags
  bool _showMaterials = false;
  bool _plantListMode = false;
  bool _showProjectSection = true;
  bool _showFleetSection = true;
  bool _showAllowancesSection = true;
  bool _showCommentsSection = true;

  // Visual feedback states
  bool _projectSelected = false;
  String _findNearestButtonText = 'Find Nearest Job';
  bool _isFindingNearest = false;
  bool _isFindingLast = false;
  List<String> _foundNearestProjects = []; // Track previously found projects for "Find Next"
  
  // Diagnostic timing for dropdown selection
  int _detailsRenderTimeMs = 0; // Time in milliseconds from selection to Details section render

  // Week start from system_settings: integer 0-6 (PostgreSQL DOW: 0=Sunday .. 6=Saturday)
  int? _weekStartDow;

  // Controllers
  final _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  // Debounce timers for fleet lookups
  final Map<int, Timer?> _fleetDebounceTimers = {}; // For used fleet
  final Map<int, Timer?> _mobilisedFleetDebounceTimers = {}; // For mobilised fleet
  // Cache for fleet descriptions (fleet number -> description)
  final Map<String, String> _fleetDescriptions = {};
  // Track invalid fleet numbers (for red highlighting)
  final Set<String> _invalidFleetNumbers = {};
  // Track focus state for fleet input fields (to hide/show input box)
  final Map<int, bool> _fleetFieldHasFocus = {}; // For used fleet
  final Map<int, bool> _mobilisedFleetFieldHasFocus = {}; // For mobilised fleet


  // Validate fleet number and update description (called on focus loss)
  void _validateFleetNumber(int index, String fleetNumber, bool isMobilised) {
    final upperFleetNumber = fleetNumber.toUpperCase().trim();
    
    // Clear description immediately if field is empty
    if (upperFleetNumber.isEmpty) {
      final cacheKey = '${isMobilised ? 'm' : 'u'}_$index';
      _fleetDescriptions.remove(cacheKey);
      _invalidFleetNumbers.remove(upperFleetNumber);
      setState(() {}); // Trigger rebuild to clear description
      return;
    }
    
    // Perform lookup immediately (validation happens on focus loss)
    final plant = _allPlant.firstWhere(
      (p) {
        final dbPlantNo = p['plant_no']?.toString() ?? '';
        return dbPlantNo.toUpperCase().trim() == upperFleetNumber;
      },
      orElse: () => <String, dynamic>{},
    );
    
    // Use plant_description instead of short_description
    final plantDesc = plant.isNotEmpty 
        ? (plant['plant_description']?.toString() ?? plant['short_description']?.toString() ?? '')
        : '';
    
    // Update description cache and invalid fleet tracking
    final cacheKey = '${isMobilised ? 'm' : 'u'}_$index';
    if (mounted) {
      setState(() {
        if (plantDesc.isNotEmpty) {
          _fleetDescriptions[cacheKey] = plantDesc;
          _invalidFleetNumbers.remove(upperFleetNumber);
        } else {
          _fleetDescriptions[cacheKey] = 'Fleet Number is not valid';
          _invalidFleetNumbers.add(upperFleetNumber);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initialize();
    _setupConnectivityListener();
    _initializeOfflineStorage();
    _startGpsBackgroundRefresh();
    // Autofill will happen after user data is loaded
  }

  @override
  void dispose() {
    // Cancel connectivity subscription
    _connectivitySubscription?.cancel();
    // Cancel GPS refresh timer
    _gpsRefreshTimer?.cancel();
    // Dispose scroll controller
    _scrollController.dispose();
    // Cancel all debounce timers
    for (final timer in _fleetDebounceTimers.values) {
      timer?.cancel();
    }
    for (final timer in _mobilisedFleetDebounceTimers.values) {
      timer?.cancel();
    }
    _fleetDebounceTimers.clear();
    _mobilisedFleetDebounceTimers.clear();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadCurrentUser();
    await _loadUserData();
    await _loadWeekStart();
    await _loadProjects();
    await _loadPlant();
    await _loadConcreteMixes();
    await _updatePendingCount();
    
    // If editing an existing time period, load its data
    if (widget.timePeriodId != null && widget.timePeriodId!.isNotEmpty) {
      await _loadTimePeriodForEdit(widget.timePeriodId!);
    }
  }

  /// Load time period data for editing
  Future<void> _loadTimePeriodForEdit(String timePeriodId) async {
    try {
      print('🔍 Loading time period for edit: $timePeriodId');
      
      // Load the time period
      final timePeriod = await DatabaseService.readById('time_periods', timePeriodId);
      if (timePeriod == null) {
        throw Exception('Time period not found');
      }
      
      // Check if status allows editing
      // Regular users can only edit 'submitted' periods
      // Supervisors/admins can edit 'submitted' or 'supervisor_approved' periods (but not 'admin_approved')
      final status = timePeriod['status']?.toString() ?? '';
      
      // Check if current user is supervisor/admin
      final userSetup = await UserService.getCurrentUserSetup();
      final security = userSetup?['security'];
      final securityInt = security is int ? security : (security != null ? int.tryParse(security.toString()) : null);
      final isSupervisorOrAdmin = securityInt != null && (securityInt == 1 || securityInt == 2 || securityInt == 3);
      
      if (status == 'admin_approved') {
        // No one can edit admin-approved periods
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This time period has been approved by admin and cannot be edited.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
        return;
      } else if (status != 'submitted' && status != 'supervisor_approved') {
        // Invalid status
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('This time period has status "$status" and cannot be edited.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
        return;
      } else if (status == 'supervisor_approved' && !isSupervisorOrAdmin) {
        // Only supervisors/admins can edit supervisor-approved periods
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This time period has been approved by supervisor and can only be edited by supervisors or admins.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
        return;
      }
      
      // Verify this time period belongs to the current user, OR user is supervisor/admin
      final currentUser = await AuthService.getCurrentUser();
      final periodUserId = timePeriod['user_id']?.toString();
      final currentUserId = currentUser?.id;
      
      // Allow editing if user owns the period OR is supervisor/admin
      if (periodUserId != currentUserId && !isSupervisorOrAdmin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can only edit your own time periods.'),
              backgroundColor: Colors.red,
            ),
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
        return;
      }
      
      print('✅ Time period loaded, populating form fields...');
      
      // Populate form fields with time period data
      setState(() {
        // Date
        if (timePeriod['work_date'] != null) {
          _date = timePeriod['work_date']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
        }
        
        // Start time
        if (timePeriod['start_time'] != null) {
          final startTime = DateTime.parse(timePeriod['start_time']?.toString() ?? '');
          _startTime = DateFormat('HH:mm').format(startTime);
        }
        
        // Finish time
        if (timePeriod['finish_time'] != null) {
          final finishTime = DateTime.parse(timePeriod['finish_time']?.toString() ?? '');
          _finishTime = DateFormat('HH:mm').format(finishTime);
        }
        
        // Determine mode from time period data (Fleet mode if large_plant_id or workshop_tasks_id is set)
        final isMechanicMode = timePeriod['large_plant_id'] != null || timePeriod['workshop_tasks_id'] != null;
        
        // Set plant list mode based on time period data
        _plantListMode = isMechanicMode;
        
        // Project (if not in mechanic mode)
        if (timePeriod['project_id'] != null && !isMechanicMode) {
          final projectId = timePeriod['project_id']?.toString();
          final project = _projectMapByName.values.firstWhere(
            (p) => p['id']?.toString() == projectId,
            orElse: () => <String, dynamic>{},
          );
          if (project.isNotEmpty) {
            _selectedProject = project['project_name']?.toString() ?? '';
            _selectedProjectDescription = project['description']?.toString() ?? '';
            _projectSelected = true;
          }
        }
        
        // Fleet: large_plant (if in mechanic mode)
        if (timePeriod['large_plant_id'] != null && isMechanicMode) {
          final plantId = timePeriod['large_plant_id']?.toString();
          final plant = _allPlant.firstWhere(
            (p) => p['id']?.toString() == plantId,
            orElse: () => <String, dynamic>{},
          );
          if (plant.isNotEmpty) {
            _selectedProject = plant['plant_no']?.toString() ?? plant['plant_description']?.toString() ?? '';
            _selectedProjectDescription = plant['short_description']?.toString() ?? '';
            _projectSelected = true;
          }
        }
        
        // Fleet: workshop task (if in mechanic mode and workshop_tasks_id is set)
        if (timePeriod['workshop_tasks_id'] != null && isMechanicMode && _selectedProject.isEmpty) {
          final taskId = timePeriod['workshop_tasks_id']?.toString();
          final plant = _allPlant.firstWhere(
            (p) => p['id']?.toString() == taskId,
            orElse: () => <String, dynamic>{},
          );
          if (plant.isNotEmpty) {
            _selectedProject = plant['plant_no']?.toString() ?? plant['plant_description']?.toString() ?? '';
            _selectedProjectDescription = plant['short_description']?.toString() ?? plant['description_of_work']?.toString() ?? '';
            _projectSelected = true;
          }
        }
        
        // Travel allowances
        if (timePeriod['travel_to_site_min'] != null) {
          final minutes = timePeriod['travel_to_site_min'] as int;
          final hours = minutes ~/ 60;
          final mins = minutes % 60;
          _travelToSiteTime = '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
          _travelToSite = '${hours}h ${mins}m';
        }
        
        if (timePeriod['travel_from_site_min'] != null) {
          final minutes = timePeriod['travel_from_site_min'] as int;
          final hours = minutes ~/ 60;
          final mins = minutes % 60;
          _travelFromSiteTime = '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
          _travelFromSite = '${hours}h ${mins}m';
        }
        
        // Distance
        if (timePeriod['distance_from_home'] != null) {
          _calculatedDistance = timePeriod['distance_from_home']?.toString() ?? '';
        }
        
        // On call
        if (timePeriod['on_call'] != null) {
          _onCall = timePeriod['on_call'] as bool? ?? false;
        }
        
        // Miscellaneous allowance
        if (timePeriod['misc_allowance_min'] != null) {
          final minutes = timePeriod['misc_allowance_min'] as int;
          final hours = minutes ~/ 60;
          final mins = minutes % 60;
          _miscellaneousTime = '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
          _miscellaneous = '${hours}h ${mins}m';
        }
        
        // Concrete/Materials
        if (timePeriod['concrete_ticket_no'] != null) {
          _ticketNumber = timePeriod['concrete_ticket_no']?.toString() ?? '';
        }
        if (timePeriod['concrete_mix_type'] != null) {
          _concreteMix = timePeriod['concrete_mix_type']?.toString() ?? '';
        }
        if (timePeriod['concrete_qty'] != null) {
          _quantity = timePeriod['concrete_qty']?.toString() ?? '';
        }
        
        // Comments
        if (timePeriod['comments'] != null) {
          _comments = timePeriod['comments']?.toString() ?? '';
        }
      });
      
      // Load breaks
      await _loadBreaksForEdit(timePeriodId);
      
      // Load used fleet
      await _loadUsedFleetForEdit(timePeriodId);
      
      // Load mobilised fleet
      await _loadMobilisedFleetForEdit(timePeriodId);
      
      print('✅ Time period data loaded successfully');
    } catch (e, stackTrace) {
      print('❌ Error loading time period for edit: $e');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Load Time Period For Edit',
        type: 'Database',
        description: 'Failed to load time period for edit: $e',
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading time period: $e'),
            backgroundColor: Colors.red,
          ),
        );
        // Navigate back on error
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    }
  }
  
  /// Load breaks for editing
  Future<void> _loadBreaksForEdit(String timePeriodId) async {
    try {
      final breaksResponse = await SupabaseService.client
          .from('time_period_breaks')
          .select('break_start, break_finish, break_reason')
          .eq('time_period_id', timePeriodId)
          .order('break_start', ascending: true);
      
      final breaksList = List<Map<String, dynamic>>.from(breaksResponse as List);
      final loadedBreaks = <Map<String, dynamic>>[];
      
      for (final breakData in breaksList) {
        final breakStart = breakData['break_start']?.toString();
        final breakFinish = breakData['break_finish']?.toString();
        final reason = breakData['break_reason']?.toString() ?? '';
        
        String startTimeStr = '';
        String finishTimeStr = '';
        
        if (breakStart != null) {
          try {
            final startDateTime = DateTime.parse(breakStart);
            startTimeStr = DateFormat('HH:mm').format(startDateTime);
          } catch (e) {
            print('⚠️ Error parsing break start time: $e');
          }
        }
        
        if (breakFinish != null) {
          try {
            final finishDateTime = DateTime.parse(breakFinish);
            finishTimeStr = DateFormat('HH:mm').format(finishDateTime);
          } catch (e) {
            print('⚠️ Error parsing break finish time: $e');
          }
        }
        
        loadedBreaks.add({
          'start': startTimeStr,
          'finish': finishTimeStr,
          'reason': reason,
        });
      }
      
      setState(() {
        _breaks = loadedBreaks;
      });
      
      print('✅ Loaded ${loadedBreaks.length} breaks');
    } catch (e) {
      print('❌ Error loading breaks: $e');
      setState(() {
        _breaks = [];
      });
    }
  }
  
  /// Load used fleet for editing
  Future<void> _loadUsedFleetForEdit(String timePeriodId) async {
    try {
      final fleetResponse = await SupabaseService.client
          .from('time_period_used_fleet')
          .select('large_plant_id, large_plant(plant_no)')
          .eq('time_period_id', timePeriodId)
          .order('display_order', ascending: true);
      
      final loadedFleet = <String>[];
      for (final item in (fleetResponse as List)) {
        final plant = (item as Map<String, dynamic>)['large_plant'] as Map<String, dynamic>?;
        if (plant != null && plant['plant_no'] != null) {
          loadedFleet.add(plant['plant_no']?.toString() ?? '');
        }
      }
      
      setState(() {
        _usedFleet = loadedFleet;
      });
      
      print('✅ Loaded ${loadedFleet.length} used fleet items');
    } catch (e) {
      print('❌ Error loading used fleet: $e');
      setState(() {
        _usedFleet = [];
      });
    }
  }
  
  /// Load mobilised fleet for editing
  Future<void> _loadMobilisedFleetForEdit(String timePeriodId) async {
    try {
      final fleetResponse = await SupabaseService.client
          .from('time_period_mobilised_fleet')
          .select('large_plant_id, large_plant(plant_no)')
          .eq('time_period_id', timePeriodId)
          .order('display_order', ascending: true);
      
      final loadedFleet = <String>[];
      for (final item in (fleetResponse as List)) {
        final plant = (item as Map<String, dynamic>)['large_plant'] as Map<String, dynamic>?;
        if (plant != null && plant['plant_no'] != null) {
          loadedFleet.add(plant['plant_no']?.toString() ?? '');
        }
      }
      
      setState(() {
        _mobilisedFleet = loadedFleet;
      });
      
      print('✅ Loaded ${loadedFleet.length} mobilised fleet items');
    } catch (e) {
      print('❌ Error loading mobilised fleet: $e');
      setState(() {
        _mobilisedFleet = [];
      });
    }
  }

  Future<void> _initializeOfflineStorage() async {
    try {
      // Initialize offline storage (only on mobile platforms)
      if (OfflineStorageService.isSupported) {
        await OfflineStorageService.database;
      }
      print('✅ Offline storage initialized');
    } catch (e, stackTrace) {
      print('❌ Error initializing offline storage: $e');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Initialization',
        type: 'Database',
        description: 'Failed to initialize offline storage: $e',
        stackTrace: stackTrace,
      );
    }
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        // Check if any connection type is available (not none)
        final isOnline = results.any((result) => result != ConnectivityResult.none);
        setState(() {
          _isOnline = isOnline;
        });

        if (isOnline && _pendingCount > 0) {
          // Auto-sync when coming back online
          _autoSync();
        }
      },
    );

    // Check initial connectivity
    Connectivity().checkConnectivity().then((results) {
      // Handle both single result (old API) and list (new API)
      final isOnline = results.any((result) => result != ConnectivityResult.none);
      setState(() {
        _isOnline = isOnline;
      });
    });
  }

  /// Autofill start and finish times based on day of week
  Future<void> _autofillTimesForDate() async {
    if (_date.isEmpty || _currentUser == null) return;
    
    try {
      // Always use day-specific start_time or default (removed check for existing periods)
      final date = DateTime.parse(_date);
      final dayOfWeek = date.weekday;
      final dayNames = ['', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
      final dayName = dayNames[dayOfWeek];
      
      setState(() {
        if (_userData != null && _userData!['${dayName}_start_time'] != null) {
          _startTime = _userData!['${dayName}_start_time'].toString();
        } else {
          _startTime = '07:30'; // Default
        }
        
        // Use day-specific finish_time if available, otherwise calculate as start time + 30 minutes
        if (_userData != null && _userData!['${dayName}_finish_time'] != null) {
          _finishTime = _userData!['${dayName}_finish_time'].toString();
        } else if (_startTime.isNotEmpty) {
          final timeParts = _startTime.split(':');
          if (timeParts.length == 2) {
            final hours = int.tryParse(timeParts[0]) ?? 7;
            final minutes = int.tryParse(timeParts[1]) ?? 30;
            final startDateTime = DateTime(2000, 1, 1, hours, minutes);
            final finishDateTime = startDateTime.add(const Duration(minutes: 30));
            _finishTime = '${finishDateTime.hour.toString().padLeft(2, '0')}:${finishDateTime.minute.toString().padLeft(2, '0')}';
          }
        }
      });
    } catch (e, stackTrace) {
      print('⚠️ Error autofilling times: $e');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Autofill Times',
        type: 'Data Processing',
        description: 'Error autofilling times for date $_date: $e',
        stackTrace: stackTrace,
      );
      // On error, use default
      setState(() {
        if (_startTime.isEmpty) {
          _startTime = '07:30';
          _finishTime = '08:00';
        }
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = AuthService.getCurrentUser();
      if (user != null) {
        setState(() {
          _currentUser = {
            'email': user.email,
            'id': user.id,
          };
        });

        // Can enter time on behalf of others only when users_setup.security_limit is set.
        // NULL = cannot submit for others. 1-9 = can submit for users whose security >= security_limit (up to 9).
        final userSetup = await UserService.getCurrentUserSetup();
        if (userSetup != null) {
          setState(() {
            _userSetup = userSetup;
            final securityLimit = userSetup['security_limit'] as int?;
            _canEnterForOthers = securityLimit != null && securityLimit >= 1 && securityLimit <= 9;
          });
        }

        // Only load all users if user can enter for others (security_limit is set)
        final currentUserId = user.id;
        if (_canEnterForOthers) {
          await _loadAllUsers();
          await _loadEmployers();
          
          // Set selectedEmployeeUserId to current user's id if available in the list
          final matchingUser = _allUsers.firstWhere(
            (u) => u['user_id']?.toString() == currentUserId,
            orElse: () => {},
          );
          
          if (matchingUser.isNotEmpty) {
            setState(() {
              _selectedEmployeeUserId = currentUserId;
              _selectedEmployee = currentUserId; // Use user_id instead of email
            });
          } else {
            // If current user not found in list, set to first user or null
            setState(() {
              _selectedEmployeeUserId = _allUsers.isNotEmpty 
                  ? _allUsers.first['user_id']?.toString() 
                  : null;
              _selectedEmployee = _selectedEmployeeUserId ?? '';
            });
          }
        } else {
          // If can't enter for others, don't set selectedEmployeeUserId (dropdown won't be shown)
          setState(() {
            _selectedEmployeeUserId = null;
            _selectedEmployee = currentUserId; // Store for internal use
          });
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error loading current user: $e');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Load Current User',
        type: 'Database',
        description: 'Failed to load current user data: $e',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadAllUsers() async {
    try {
      final users = await UserEditService.getAllUsers();
      // users_data has user_id but not email, so we need to get email from auth.users
      // For now, we'll store user_id and try to match by user_id when needed
      // The selectedEmployee is stored as email, so we need a way to map email to user_id
      
      // Remove duplicates based on user_id
      final uniqueUsers = <String, Map<String, dynamic>>{};
      for (final user in users) {
        final userId = user['user_id']?.toString();
        if (userId != null && userId.isNotEmpty) {
          if (!uniqueUsers.containsKey(userId)) {
            uniqueUsers[userId] = user;
          }
        }
      }
      
      setState(() {
        _allUsers = uniqueUsers.values.toList();
      });
      
      // TODO: Create a mapping of user_id to email
      // This might require an Edge Function or joining with auth.users
    } catch (e, stackTrace) {
      print('❌ Error loading users: $e');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Load All Users',
        type: 'Database',
        description: 'Failed to load all users: $e',
        stackTrace: stackTrace,
      );
    }
  }

  /// Load employer names from public.employers for the "other user" employer dropdown.
  Future<void> _loadEmployers() async {
    try {
      final response = await SupabaseService.client
          .from('employers')
          .select('employer_name')
          .order('employer_name');
      final employers = <String>[];
      for (final item in response) {
        final name = item['employer_name'] as String?;
        if (name != null && name.isNotEmpty) {
          employers.add(name);
        }
      }
      employers.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (mounted) {
        setState(() => _employers = employers);
      }
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Load Employers',
        type: 'Database',
        description: 'Failed to load employers: $e',
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _employers = []);
      }
    }
  }

  /// Update the selected employee's employer_name in users_data (when entering for another user).
  Future<void> _updateEmployeeEmployer(String? userId, String? employerName) async {
    if (userId == null || userId.isEmpty) return;
    try {
      await SupabaseService.client
          .from('users_data')
          .update({'employer_name': employerName})
          .eq('user_id', userId);
      // Keep _allUsers in sync so next time we select this user we show correct employer
      if (_allUsers.isNotEmpty) {
        final idx = _allUsers.indexWhere((u) => u['user_id']?.toString() == userId);
        if (idx >= 0) {
          _allUsers[idx]['employer_name'] = employerName;
        }
      }
    } catch (e) {
      print('❌ Error updating employer for user $userId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save employer: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      if (_currentUser == null) return;

      final userData = await UserService.getCurrentUserData();
      if (userData != null) {
        setState(() {
          _userData = userData;
          _showMaterials = userData['concrete_mix_lorry'] == true;
          _plantListMode = userData['is_mechanic'] == true;
          _showProjectSection = userData['show_project'] == true;
          _showFleetSection = userData['show_fleet'] == true;
          _showAllowancesSection = userData['show_allowances'] == true;
          _showCommentsSection = userData['show_comments'] == true;
          
          // Auto-populate ticket number if Materials section is visible and not editing
          // Only set if ticket number is empty (avoid overwriting on re-load)
          if (_showMaterials && (widget.timePeriodId == null || widget.timePeriodId!.isEmpty) && _ticketNumber.isEmpty) {
            final lastTicketNumber = userData['last_ticket_number'];
            if (lastTicketNumber != null) {
              final lastTicket = int.tryParse(lastTicketNumber.toString()) ?? 0;
              // Set to lastTicket + 1 for the next ticket
              _ticketNumber = (lastTicket + 1).toString();
            } else {
              // If last_ticket_number is null, start at 1
              _ticketNumber = '1';
            }
          }
        });
        // Autofill times after user data is loaded
        _autofillTimesForDate();
      }
    } catch (e, stackTrace) {
      print('❌ Error loading user data: $e');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Load User Data',
        type: 'Database',
        description: 'Failed to load user data: $e',
        stackTrace: stackTrace,
      );
    }
  }

  /// Load week_start from system_settings (integer 0-6, DOW)
  Future<void> _loadWeekStart() async {
    try {
      final response = await SupabaseService.client
          .from('system_settings')
          .select('week_start')
          .limit(1)
          .maybeSingle();
      int? v;
      if (response != null) {
        v = int.tryParse(response['week_start']?.toString() ?? '');
        if (v != null && (v < 0 || v > 6)) v = 1;
      }
      setState(() => _weekStartDow = v ?? 1);
      _validateAndAdjustDate();
    } catch (e, stackTrace) {
      print('❌ Error loading week_start: $e');
      setState(() => _weekStartDow = 1);
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Load Week Start',
        type: 'Database',
        description: 'Failed to load week_start: $e',
        stackTrace: stackTrace,
      );
    }
  }

  /// Validate and adjust date to ensure it's within allowed range
  void _validateAndAdjustDate() {
    if (_date.isEmpty) return;
    
    try {
      final selectedDate = DateTime.parse(_date);
      final today = DateTime.now();
      final maxDate = DateTime(today.year, today.month, today.day);
      final minDate = _getMinDate(today);
      
      // If date is before minDate, set to minDate
      if (selectedDate.isBefore(minDate)) {
        setState(() {
          _date = DateFormat('yyyy-MM-dd').format(minDate);
        });
      }
      // If date is after maxDate (today), set to maxDate
      else if (selectedDate.isAfter(maxDate)) {
        setState(() {
          _date = DateFormat('yyyy-MM-dd').format(maxDate);
        });
      }
    } catch (e) {
      print('⚠️ Error validating date: $e');
    }
  }

  /// Load user data for selected employee (when recording for another person).
  /// Section visibility (project, fleet, allowances, comments, materials, plant list mode)
  /// is driven by the selected employee's users_data when "Other User" is selected,
  /// otherwise by the logged-in user's users_data.
  Future<void> _loadEmployeeUserData() async {
    final previousPlantListMode = _plantListMode;

    if (!_recordForAnotherPerson || _selectedEmployeeUserId == null || _selectedEmployeeUserId!.isEmpty) {
      // Use logged-in user's users_data for section options
      if (_userData != null) {
        setState(() {
          _showMaterials = _userData!['concrete_mix_lorry'] == true;
          _plantListMode = _userData!['is_mechanic'] == true;
          _showProjectSection = _userData!['show_project'] == true;
          _showFleetSection = _userData!['show_fleet'] == true;
          _showAllowancesSection = _userData!['show_allowances'] == true;
          _showCommentsSection = _userData!['show_comments'] == true;
        });
      }
    } else {
      try {
        final selectedUserId = _selectedEmployeeUserId!;
        final response = await SupabaseService.client
            .from('users_data')
            .select('is_mechanic, show_project, show_fleet, show_allowances, show_comments, concrete_mix_lorry')
            .eq('user_id', selectedUserId)
            .maybeSingle();

        if (response != null) {
          setState(() {
            _showMaterials = response['concrete_mix_lorry'] == true;
            _plantListMode = response['is_mechanic'] == true;
            _showProjectSection = response['show_project'] == true;
            _showFleetSection = response['show_fleet'] == true;
            _showAllowancesSection = response['show_allowances'] == true;
            _showCommentsSection = response['show_comments'] == true;
          });
        } else {
          // Fallback to logged-in user if no record found for selected employee
          if (_userData != null) {
            setState(() {
              _showMaterials = _userData!['concrete_mix_lorry'] == true;
              _plantListMode = _userData!['is_mechanic'] == true;
              _showProjectSection = _userData!['show_project'] == true;
              _showFleetSection = _userData!['show_fleet'] == true;
              _showAllowancesSection = _userData!['show_allowances'] == true;
              _showCommentsSection = _userData!['show_comments'] == true;
            });
          }
        }
      } catch (e) {
        print('❌ Error loading employee user data: $e');
        if (_userData != null) {
          setState(() {
            _showMaterials = _userData!['concrete_mix_lorry'] == true;
            _plantListMode = _userData!['is_mechanic'] == true;
            _showProjectSection = _userData!['show_project'] == true;
            _showFleetSection = _userData!['show_fleet'] == true;
            _showAllowancesSection = _userData!['show_allowances'] == true;
            _showCommentsSection = _userData!['show_comments'] == true;
          });
        }
      }
    }

    // Reload plants if plant list mode changed (to include/exclude workshop_tasks)
    if (previousPlantListMode != _plantListMode) {
      await _loadPlant();
    }
  }

  Future<void> _loadProjects() async {
    try {
      // Load only active projects (is_active = true) to reduce data transfer
      // Set limit to 10000 to handle growth (currently ~7000 active, allowing for future growth)
      var projects = await DatabaseService.read(
        'projects',
        filterColumn: 'is_active',
        filterValue: true,
        limit: 10000,
      );
      
      setState(() {
        _allProjects = projects;
        // Build map for fast lookups by project_name
        _projectMapByName = {};
        for (final p in projects) {
          final projectName = p['project_name']?.toString();
          if (projectName != null && projectName.isNotEmpty) {
            _projectMapByName[projectName] = p;
          }
        }
      });
      print('✅ Loaded ${_allProjects.length} projects');
      
      // If still empty, log a warning about possible RLS issues
      if (_allProjects.isEmpty) {
        print('⚠️ WARNING: No projects loaded. This could be due to:');
        print('   1. Table is empty');
        print('   2. RLS policies blocking access');
        print('   3. Incorrect table name or schema');
        print('   Please check Supabase RLS policies for "projects" table');
      } else {
        // Log sample project data for debugging
        print('🔍 Sample project data: ${_allProjects.take(3).map((p) => {
          'id': p['id'],
          'project_name': p['project_name'],
          'is_active': p['is_active'],
        }).toList()}');
      }
    } catch (e) {
      print('❌ Error loading projects: $e');
      print('   This might be an RLS policy issue. Check Supabase dashboard.');
      // Try loading active projects as fallback
      try {
        // Set limit to 10000 to handle growth (currently ~7000 active, allowing for future growth)
        final projects = await DatabaseService.read(
          'projects',
          filterColumn: 'is_active',
          filterValue: true,
          limit: 10000,
        );
        setState(() {
          _allProjects = projects;
          _projectMapByName = {};
          for (final p in projects) {
            final projectName = p['project_name']?.toString();
            if (projectName != null && projectName.isNotEmpty) {
              _projectMapByName[projectName] = p;
            }
          }
        });
        print('✅ Loaded ${_allProjects.length} projects (fallback)');
      } catch (e2) {
        print('❌ Error loading projects (fallback): $e2');
        print('   Please verify RLS policies allow SELECT on projects table');
      }
    }
  }

  Future<void> _loadPlant() async {
    try {
      // Try to load active fleet first, fallback to all fleet if no active ones
      var plant = await DatabaseService.read(
        'large_plant',
        filterColumn: 'is_active',
        filterValue: true,
      );
      
      // If no active fleet found, load all fleet
      if (plant.isEmpty) {
        print('⚠️ No active fleet found, loading all fleet...');
        plant = await DatabaseService.read('large_plant');
      }
      
      // If in Plant Mode, load workshop_tasks and prepend to plant list
      List<Map<String, dynamic>> workshopTasks = [];
      if (_plantListMode) {
        try {
          print('🔍 Loading workshop_tasks for Plant Mode...');
          final tasks = await DatabaseService.read('workshop_tasks');
          
          // Map workshop_tasks to plant format: task -> plant_no and plant_description, task_description -> description_of_work
          workshopTasks = tasks.map((task) {
            return {
              'plant_no': task['task']?.toString() ?? '',
              'plant_description': task['task']?.toString() ?? '',
              'short_description': task['task']?.toString() ?? '',
              'description_of_work': task['task_description']?.toString() ?? '',
              'id': task['id']?.toString(), // Include id from workshop_tasks table
              'is_workshop_task': true, // Flag to identify workshop tasks
            };
          }).toList();
          
          print('✅ Loaded ${workshopTasks.length} workshop tasks');
        } catch (e, stackTrace) {
          print('⚠️ Error loading workshop_tasks: $e');
          await ErrorLogService.logError(
            location: 'Timesheet Screen - Load Workshop Tasks',
            type: 'Database',
            description: 'Failed to load workshop_tasks: $e',
            stackTrace: stackTrace,
          );
        }
      }
      
      // Prepend workshop_tasks to the beginning of plant list
      final combinedPlant = [...workshopTasks, ...plant];
      
      setState(() {
        _allPlant = combinedPlant;
        // Build map for fast lookups by plant_no (uppercase)
        _plantMapByNo = {};
        for (final p in combinedPlant) {
          final plantNo = p['plant_no']?.toString().toUpperCase().trim();
          if (plantNo != null && plantNo.isNotEmpty) {
            _plantMapByNo[plantNo] = p;
          }
        }
      });
      print('✅ Loaded ${_allPlant.length} fleet items${workshopTasks.isNotEmpty ? ' (${workshopTasks.length} workshop tasks + ${plant.length} fleet)' : ''}');
      
      // If still empty, log a warning about possible RLS issues
      if (_allPlant.isEmpty) {
        print('⚠️ WARNING: No fleet loaded. This could be due to:');
        print('   1. Table is empty');
        print('   2. RLS policies blocking access');
        print('   3. Incorrect table name or schema');
        print('   Please check Supabase RLS policies for "large_plant" table');
      } else {
        // Log sample fleet data for debugging
        print('🔍 Sample fleet data: ${_allPlant.take(3).map((p) => {
          'plant_no': p['plant_no'],
          'short_description': p['short_description'],
        }).toList()}');
      }
    } catch (e, stackTrace) {
      print('❌ Error loading fleet: $e');
      print('   This might be an RLS policy issue. Check Supabase dashboard.');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Load Fleet',
        type: 'Database',
        description: 'Failed to load fleet (RLS or database issue): $e',
        stackTrace: stackTrace,
      );
      // Try loading all fleet without filter as fallback
      try {
        final plant = await DatabaseService.read('large_plant');
        setState(() {
          _allPlant = plant;
        });
        print('✅ Loaded ${_allPlant.length} fleet items (fallback)');
      } catch (e2, stackTrace2) {
        print('❌ Error loading fleet (fallback): $e2');
        print('   Please verify RLS policies allow SELECT on large_plant table');
        await ErrorLogService.logError(
          location: 'Timesheet Screen - Load Fleet (Fallback)',
          type: 'Database',
          description: 'Failed to load fleet (fallback): $e2',
          stackTrace: stackTrace2,
        );
      }
    }
  }

  Future<void> _loadConcreteMixes() async {
    if (!_showMaterials) return;

    try {
      final mixes = await DatabaseService.read(
        'concrete_mix',
        filterColumn: 'is_active',
        filterValue: true,
      );
      
      // Sort by name in descending order
      final sortedMixes = List<Map<String, dynamic>>.from(mixes);
      sortedMixes.sort((a, b) {
        final nameA = (a['name'] as String?) ?? 
                      (a['user_description'] as String?) ?? 
                      (a['id']?.toString() ?? '');
        final nameB = (b['name'] as String?) ?? 
                      (b['user_description'] as String?) ?? 
                      (b['id']?.toString() ?? '');
        return nameB.compareTo(nameA); // Descending order (Z to A)
      });
      
      setState(() {
        _allConcreteMixes = sortedMixes;
      });
    } catch (e) {
      print('❌ Error loading concrete mixes: $e');
    }
  }

  Future<void> _updatePendingCount() async {
    try {
      final count = await OfflineStorageService.getPendingCount();
      setState(() {
        _pendingCount = count;
      });
    } catch (e) {
      print('❌ Error updating pending count: $e');
    }
  }

  /// Start background GPS refresh timer (updates every 2 minutes)
  void _startGpsBackgroundRefresh() {
    // Get initial GPS location
    _refreshGpsLocation();
    
    // Set up timer to refresh every 2 minutes
    _gpsRefreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _refreshGpsLocation();
    });
  }

  /// Refresh GPS location in background
  Future<void> _refreshGpsLocation() async {
    try {
      if (kIsWeb) {
        // Web platform - get current position
        final position = await Geolocator.getCurrentPosition(
          locationSettings: WebSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          ),
        );
        _cachedLatitude = position.latitude;
        _cachedLongitude = position.longitude;
        _cachedGpsAccuracy = position.accuracy.round();
        _gpsLastUpdated = DateTime.now();
        // ignore: avoid_print
        print('🔄 [GPS] Background refresh: lat=$_cachedLatitude, lng=$_cachedLongitude');
      } else {
        // Mobile platform - get current position
        final position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          ),
        );
        _cachedLatitude = position.latitude;
        _cachedLongitude = position.longitude;
        _cachedGpsAccuracy = position.accuracy.round();
        _gpsLastUpdated = DateTime.now();
        // ignore: avoid_print
        print('🔄 [GPS] Background refresh: lat=$_cachedLatitude, lng=$_cachedLongitude');
      }
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ [GPS] Background refresh failed: $e');
      // Don't show error to user - GPS is optional
    }
  }

  Future<void> _autoSync() async {
    if (!_isOnline || _pendingCount == 0) return;

    try {
      await SyncService.scheduleAutoSync(
        onComplete: (results) {
          if (results['success'] as int > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Auto-sync: ${results['success']} ${results['success'] == 1 ? 'entry' : 'entries'} synced',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
          _updatePendingCount();
        },
      );
    } catch (e) {
      print('❌ Auto-sync error: $e');
    }
  }

  Future<void> _manualSync() async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be online to sync data.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final results = await SyncService.syncOfflineData();

      if (results['success'] as int > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync successful: ${results['success']} ${results['success'] == 1 ? 'entry' : 'entries'} uploaded',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (results['failed'] as int > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync issues: ${results['failed']} ${results['failed'] == 1 ? 'entry' : 'entries'} failed',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }

      if (results['success'] == 0 && results['failed'] == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No data to sync.'),
          ),
        );
      }

      await _updatePendingCount();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  // Continue with helper methods and UI in next part...
  // This is getting long, so I'll continue in the next message

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0081FB),
        title: const Text(
          'Timesheet',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        foregroundColor: Colors.black,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: Container(
            height: 4.0,
            color: const Color(0xFFFEFE00), // Yellow #FEFE00
          ),
        ),
        actions: const [ScreenInfoIcon(screenName: 'timesheet_screen.dart')],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Offline indicator and sync button
              _buildOfflineIndicator(),
              const SizedBox(height: 16),
              
              // Employee section
              _buildEmployeeSection(),
              const SizedBox(height: 16),
              
              // Date/Time/Breaks section
              _buildDateTimeBreaksSection(),
              const SizedBox(height: 16),
              
              // Project section
              if (_showProjectSection) ...[
                _buildProjectSection(),
                const SizedBox(height: 16),
              ],
              
              // Fleet section
              if (_showFleetSection) ...[
                _buildFleetSection(),
                const SizedBox(height: 16),
              ],
              
              // Allowances section
              if (_showAllowancesSection) ...[
                _buildAllowancesSection(),
                const SizedBox(height: 16),
              ],
              
              // Materials section
              if (_showMaterials) ...[
                _buildMaterialsSection(),
                const SizedBox(height: 16),
              ],
              
              // Comments section
              if (_showCommentsSection) ...[
                _buildCommentsSection(),
                const SizedBox(height: 16),
              ],
              
              // Submit button
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineIndicator() {
    return Card(
      color: _isOnline ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(
              _isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _isOnline ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isOnline
                    ? 'Online'
                    : 'Offline - ${_pendingCount} ${_pendingCount == 1 ? 'entry' : 'entries'} pending',
                style: TextStyle(
                  color: _isOnline ? Colors.green.shade700 : Colors.orange.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_isOnline && _pendingCount > 0)
              ElevatedButton.icon(
                onPressed: _isSyncing ? null : _manualSync,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload, size: 18),
                label: Text('Sync (${_pendingCount})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0081FB),
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper function to generate time options (15-minute intervals)
  List<String> _generateTimeOptions() {
    final times = <String>[];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 15) {
        final timeString = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        times.add(timeString);
      }
    }
    return times;
  }

  /// Convert 24-hour time to 12-hour format with AM/PM
  String _convertTo12Hour(String time24) {
    if (time24.isEmpty) return '';
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Generate time options limited to start 0:15 after a given time
  List<String> _generateLimitedTimeOptions(String? afterTime, String? beforeTime) {
    final allOptions = _generateTimeOptions();
    if (afterTime == null && beforeTime == null) {
      return allOptions;
    }
    
    return allOptions.where((time) {
      if (afterTime != null && _timeStringToMinutes(time) < _timeStringToMinutes(afterTime) + 0) {
        return false;
      }
      if (beforeTime != null && _timeStringToMinutes(time) > _timeStringToMinutes(beforeTime) - 0) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Add 30 minutes to a time string
  String _addMinutesToTime(String timeString, int minutes) {
    if (timeString.isEmpty) return '';
    final timeParts = timeString.split(':');
    if (timeParts.length != 2) return '';
    final hours = int.tryParse(timeParts[0]) ?? 0;
    final mins = int.tryParse(timeParts[1]) ?? 0;
    final totalMinutes = hours * 60 + mins + minutes;
    final newHours = (totalMinutes ~/ 60) % 24;
    final newMinutes = totalMinutes % 60;
    return '${newHours.toString().padLeft(2, '0')}:${newMinutes.toString().padLeft(2, '0')}';
  }

  // Helper function to convert time string (HH:mm) to minutes
  int _timeStringToMinutes(String timeString) {
    if (timeString.isEmpty) return 0;
    final parts = timeString.split(':');
    if (parts.length != 2) return 0;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    return hours * 60 + minutes;
  }

  Widget _buildEmployeeSection() {
    // Get current user forename & surname
    String currentUserDisplay = 'Unknown';
    
    // First try to get from _allUsers list (explicitly loaded with forename/surname)
    if (_currentUser != null && _allUsers.isNotEmpty) {
      final currentUserId = _currentUser!['id'];
      try {
        final matchingUser = _allUsers.firstWhere(
          (u) => u['user_id']?.toString() == currentUserId,
        );
        final forename = matchingUser['forename']?.toString() ?? '';
        final surname = matchingUser['surname']?.toString() ?? '';
        if (forename.isNotEmpty || surname.isNotEmpty) {
          currentUserDisplay = '$forename $surname'.trim();
        } else if (matchingUser['display_name'] != null) {
          // Parse display_name like "Ovington, Robert" to "Robert Ovington"
          final displayName = matchingUser['display_name'].toString();
          if (displayName.contains(',')) {
            final parts = displayName.split(',');
            if (parts.length == 2) {
              currentUserDisplay = '${parts[1].trim()} ${parts[0].trim()}';
            } else {
              currentUserDisplay = displayName;
            }
          } else {
            currentUserDisplay = displayName;
          }
        }
      } catch (e) {
        // User not found in _allUsers list
      }
    }
    
    // If not found in _allUsers, try from _userData (loaded user profile)
    if (currentUserDisplay == 'Unknown' && _userData != null) {
      final forename = _userData!['forename']?.toString() ?? '';
      final surname = _userData!['surname']?.toString() ?? '';
      if (forename.isNotEmpty || surname.isNotEmpty) {
        currentUserDisplay = '$forename $surname'.trim();
      } else if (_userData!['display_name'] != null) {
        // Parse display_name like "Ovington, Robert" to "Robert Ovington"
        final displayName = _userData!['display_name'].toString();
        if (displayName.contains(',')) {
          final parts = displayName.split(',');
          if (parts.length == 2) {
            currentUserDisplay = '${parts[1].trim()} ${parts[0].trim()}';
          } else {
            currentUserDisplay = displayName;
          }
        } else {
          currentUserDisplay = displayName;
        }
      }
    }
    
    // Try from users_setup display_name (format: "Surname, Forename")
    if (currentUserDisplay == 'Unknown' && _userSetup != null && _userSetup!['display_name'] != null) {
      final displayName = _userSetup!['display_name'].toString();
      if (displayName.contains(',')) {
        final parts = displayName.split(',');
        if (parts.length == 2) {
          currentUserDisplay = '${parts[1].trim()} ${parts[0].trim()}';
        } else {
          currentUserDisplay = displayName;
        }
      } else {
        currentUserDisplay = displayName;
      }
    }
    
    // Last resort: fallback to email
    if (currentUserDisplay == 'Unknown' && _currentUser != null) {
      currentUserDisplay = (_currentUser!['email'] as String?) ?? 'Unknown';
    }

    // Employee Details Section - styled like Date, Time & Breaks
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2), // #005AB0
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header in border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF), // #BADDFF
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2), // #005AB0
                ),
              ),
              child: const Center(
                child: Text(
                  'Employee Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display logged in user and checkbox on same row
                  Row(
                    children: [
                      const Icon(Icons.person, color: Color(0xFF0081FB)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentUserDisplay,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Checkbox for recording for another person
                      if (_canEnterForOthers)
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _recordForAnotherPerson,
                                onChanged: (value) {
                                setState(() {
                                  _recordForAnotherPerson = value ?? false;
                                  if (!_recordForAnotherPerson) {
                                    // Reset to current user
                                    final currentUserId = _currentUser?['id'] as String?;
                                    _selectedEmployeeUserId = currentUserId;
                                    _selectedEmployee = currentUserId ?? '';
                                    // Check logged-in user's is_mechanic
                                    _loadEmployeeUserData();
                                  } else {
                                    // Check selected employee's is_mechanic if one is selected
                                    if (_selectedEmployeeUserId != null && _selectedEmployeeUserId!.isNotEmpty) {
                                      _loadEmployeeUserData();
                                    }
                                  }
                                });
                              },
                            ),
                            const Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Other',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  Text(
                                    'User',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Employer then Employee dropdowns (only shown if checkbox is checked)
                  if (_canEnterForOthers && _recordForAnotherPerson) ...[
                    const SizedBox(height: 16),
                    // Employer dropdown (filters the employee list below)
                    _buildLabeledInput(
                      label: 'EMPLOYER',
                      child: DropdownButtonFormField<String>(
                        value: _selectedEmployerForOther != null && _employers.contains(_selectedEmployerForOther)
                            ? _selectedEmployerForOther
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Employer',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          helperText: 'Select employer to filter employees (saved to employee\'s record)',
                        ),
                        items: _employers.isEmpty
                            ? [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('No employers available'),
                                )
                              ]
                            : [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('All'),
                                ),
                                ..._employers.map((employer) {
                                  return DropdownMenuItem<String>(
                                    value: employer,
                                    child: Text(employer),
                                  );
                                }),
                              ],
                        onChanged: (value) {
                          setState(() => _selectedEmployerForOther = value);
                          if (_selectedEmployeeUserId != null && _selectedEmployeeUserId!.isNotEmpty) {
                            _updateEmployeeEmployer(_selectedEmployeeUserId, value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Employee dropdown (filtered by employer above)
                    Builder(
                      builder: (context) {
                        // Exclude current user from dropdown list
                        // Filter users based on security_limit permissions
                        final currentUserId = _currentUser?['id'];
                        final currentUserSecurityLimit = _userSetup?['security_limit'] as int?;
                        
                        print('🔍 [EMPLOYEE FILTER] ========== START FILTERING ==========');
                        print('🔍 [EMPLOYEE FILTER] Total users loaded: ${_allUsers.length}');
                        print('🔍 [EMPLOYEE FILTER] Current user ID: $currentUserId');
                        print('🔍 [EMPLOYEE FILTER] Current user security_limit: $currentUserSecurityLimit');
                        
                        if (_allUsers.isEmpty) {
                          print('❌ [EMPLOYEE FILTER] ERROR: _allUsers is empty! Users were not loaded.');
                          print('💡 Check if _loadAllUsers() was called and completed successfully.');
                        } else {
                          print('🔍 [EMPLOYEE FILTER] First user structure:');
                          final firstUser = _allUsers[0];
                          print('   - user_id: ${firstUser['user_id']}');
                          print('   - display_name: ${firstUser['display_name']}');
                          print('   - employer_name: ${firstUser['employer_name']}');
                          print('   - users_setup type: ${firstUser['users_setup']?.runtimeType}');
                          print('   - users_setup value: ${firstUser['users_setup']}');
                          if (firstUser['users_setup'] != null) {
                            final setup = firstUser['users_setup'];
                            if (setup is Map) {
                              print('   - users_setup.security: ${setup['security']}');
                            } else if (setup is List && setup.isNotEmpty) {
                              print('   - users_setup[0].security: ${setup[0]['security']}');
                            }
                          }
                        }
                        
                        final filteredUsers = <Map<String, dynamic>>[];
                        int excludedCurrentUser = 0;
                        int excludedSecurity = 0;
                        int excludedNoSecurity = 0;
                        
                        // Only filter if current user has a security_limit set
                        if (currentUserSecurityLimit != null && currentUserSecurityLimit >= 1 && currentUserSecurityLimit <= 9) {
                          for (final user in _allUsers) {
                            final userId = user['user_id']?.toString() ?? '';
                            final displayName = user['display_name']?.toString() ?? 'Unknown';
                            
                            // Exclude empty user_id or current user
                            if (userId.isEmpty || userId == currentUserId) {
                              excludedCurrentUser++;
                              print('   ❌ Excluded: $displayName (current user or empty ID)');
                              continue;
                            }
                            
                            // Allowed: target user's security >= current user's security_limit (and <= 9).
                            final userSetup = user['users_setup'];
                            int? targetUserSecurity;
                            
                            if (userSetup != null) {
                              if (userSetup is List && userSetup.isNotEmpty) {
                                targetUserSecurity = userSetup[0]['security'] as int?;
                              } else if (userSetup is Map) {
                                targetUserSecurity = userSetup['security'] as int?;
                              }
                            }
                            
                            if (targetUserSecurity != null) {
                              // Can submit for others whose security is >= security_limit
                              final passesSecurity = targetUserSecurity >= currentUserSecurityLimit && targetUserSecurity <= 9;
                              
                              if (!passesSecurity) {
                                excludedSecurity++;
                                print('   ❌ Excluded: $displayName (security level $targetUserSecurity not in range [$currentUserSecurityLimit-9])');
                                continue;
                              }
                            } else {
                              // If we can't get security level, exclude the user (strict filtering)
                              excludedNoSecurity++;
                              print('   ❌ Excluded: $displayName (no security level data)');
                              continue;
                            }
                            
                            // Filter by selected employer (users_data.employer_name)
                            if (_selectedEmployerForOther != null && _selectedEmployerForOther!.isNotEmpty) {
                              if (user['employer_name'] != _selectedEmployerForOther) {
                                continue;
                              }
                            }
                            
                            // User passed all filters
                            filteredUsers.add(user);
                            print('   ✅ Included: $displayName (security: $targetUserSecurity)');
                          }
                        } else {
                          // If no security_limit set, no users should be available (shouldn't reach here if _canEnterForOthers is false)
                          print('   ⚠️  Warning: Current user has no valid security_limit, cannot filter users');
                        }
                        
                        print('🔍 [EMPLOYEE FILTER] ========== FILTERING SUMMARY ==========');
                        print('🔍 [EMPLOYEE FILTER] Total users: ${_allUsers.length}');
                        print('🔍 [EMPLOYEE FILTER] Filtered users: ${filteredUsers.length}');
                        print('🔍 [EMPLOYEE FILTER] Excluded - Current user: $excludedCurrentUser');
                        print('🔍 [EMPLOYEE FILTER] Excluded - Security level: $excludedSecurity');
                        print('🔍 [EMPLOYEE FILTER] Excluded - No security data: $excludedNoSecurity');
                        print('🔍 [EMPLOYEE FILTER] ========================================');
                        
                        if (filteredUsers.isNotEmpty) {
                          print('🔍 [EMPLOYEE FILTER] Sample filtered user: ${filteredUsers[0]['display_name']}');
                        } else {
                          print('❌ [EMPLOYEE FILTER] No users passed the filter!');
                        }
                        
                        // Sort employees alphabetically by display_name (A at top)
                        filteredUsers.sort((a, b) {
                          final na = (a['display_name'] as String? ?? '').toLowerCase();
                          final nb = (b['display_name'] as String? ?? '').toLowerCase();
                          return na.compareTo(nb);
                        });
                        
                        // Ensure the selected value exists in the items list
                        final validValue = _selectedEmployeeUserId != null &&
                            filteredUsers.any((u) => u['user_id']?.toString() == _selectedEmployeeUserId)
                            ? _selectedEmployeeUserId
                            : null;
                        
                        return _buildLabeledInput(
                          label: 'EMPLOYEE',
                          child: DropdownButtonFormField<String>(
                            value: validValue,
                            decoration: const InputDecoration(
                              labelText: 'Select Employee',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: filteredUsers.map((user) {
                            final userId = user['user_id']?.toString() ?? '';
                            final name = (user['display_name'] as String?) ?? userId;
                            return DropdownMenuItem(
                              value: userId, // Store user_id
                              child: Text(name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedEmployeeUserId = value; // Store user_id
                              _selectedEmployee = value ?? ''; // Also store for compatibility
                              // Sync employer from selected user's users_data.employer_name
                              if (value != null && value.isNotEmpty) {
                                Map<String, dynamic>? selectedUser;
                                for (final u in _allUsers) {
                                  if (u['user_id']?.toString() == value) {
                                    selectedUser = u;
                                    break;
                                  }
                                }
                                _selectedEmployerForOther = selectedUser?['employer_name'] as String?;
                                _loadEmployeeUserData();
                              } else {
                                _selectedEmployerForOther = null;
                              }
                            });
                          },
                        ),
                      );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dart weekday for week start (1=Mon .. 7=Sun) from DOW 0-6
  int _weekStartDartWeekday() => _weekStartDow == 0 ? 7 : (_weekStartDow ?? 1);

  /// Calculate the start date of the current week based on week_start (DOW 0-6)
  DateTime _getCurrentWeekStart(DateTime date) {
    final w = _weekStartDartWeekday();
    final daysToSubtract = (date.weekday - w + 7) % 7;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysToSubtract));
  }

  /// Check if today is the first day of the week
  bool _isFirstDayOfWeek(DateTime date) {
    return date.weekday == _weekStartDartWeekday();
  }

  /// Calculate minimum date based on week rules
  /// - If today is first day of week: allow previous week (week start - 7 days)
  /// - Otherwise: only current week (current week start)
  DateTime _getMinDate(DateTime today) {
    final currentWeekStart = _getCurrentWeekStart(today);
    
    if (_isFirstDayOfWeek(today)) {
      // Allow previous week on first day
      return currentWeekStart.subtract(const Duration(days: 7));
    } else {
      // Only current week after first day
      return currentWeekStart;
    }
  }

  Widget _buildDateTimeBreaksSection() {
    final timeOptions = _generateTimeOptions();
    final currentDate = DateTime.now();
    final selectedDate = DateTime.parse(_date);
    final dateFormat = DateFormat('EEE (d MMM)'); // e.g., "Mon (7 Dec)"
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2), // #005AB0
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header in border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF), // #BADDFF
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2), // #005AB0
                ),
              ),
              child: const Center(
                child: Text(
                  'Date, Time & Breaks',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Centered date with arrows and highlighting
            Builder(
              builder: (context) {
                final maxDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
                final minDate = _getMinDate(currentDate);
                final isCurrentDate = selectedDate.year == maxDate.year &&
                                      selectedDate.month == maxDate.month &&
                                      selectedDate.day == maxDate.day;
                final isPastDate = selectedDate.isBefore(maxDate);
                final isAtMinDate = selectedDate.year == minDate.year &&
                                    selectedDate.month == minDate.month &&
                                    selectedDate.day == minDate.day;
                
                // Determine background color based on date
                Color backgroundColor;
                if (_isOnline) {
                  backgroundColor = isCurrentDate 
                      ? Colors.green.withOpacity(0.1) // Same as online indicator
                      : isPastDate 
                          ? Colors.red.withOpacity(0.1) // Reddish theme for past dates
                          : Colors.grey.withOpacity(0.1);
                } else {
                  backgroundColor = Colors.orange.withOpacity(0.1); // Offline theme
                }
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrentDate 
                          ? Colors.green 
                          : isPastDate 
                              ? Colors.red 
                              : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 24),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: isAtMinDate
                              ? null
                              : () {
                                  final newDate = selectedDate.subtract(const Duration(days: 1));
                                  // Only allow if new date is not before minDate
                                  if (newDate.isAfter(minDate) || 
                                      (newDate.year == minDate.year &&
                                       newDate.month == minDate.month &&
                                       newDate.day == minDate.day)) {
                                    setState(() {
                                      _date = DateFormat('yyyy-MM-dd').format(newDate);
                                    });
                                    _autofillTimesForDate();
                                  }
                                },
                        ),
                        Flexible(
                          child: GestureDetector(
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: minDate,
                                lastDate: maxDate,
                                selectableDayPredicate: (DateTime date) {
                                  // Only enable dates between minDate and maxDate (inclusive)
                                  return !date.isBefore(minDate) && !date.isAfter(maxDate);
                                },
                              );
                              if (pickedDate != null) {
                                setState(() {
                                  _date = DateFormat('yyyy-MM-dd').format(pickedDate);
                                });
                                _autofillTimesForDate();
                              }
                            },
                            child: Text(
                              dateFormat.format(selectedDate),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final isAtMaxDate = selectedDate.year == maxDate.year &&
                                                selectedDate.month == maxDate.month &&
                                                selectedDate.day == maxDate.day;
                            
                            return IconButton(
                              icon: const Icon(Icons.chevron_right, size: 24),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: isAtMaxDate
                                  ? null
                                  : () {
                                      final newDate = selectedDate.add(const Duration(days: 1));
                                      // Only allow if new date is not after current date
                                      if (newDate.isBefore(maxDate) || 
                                          (newDate.year == maxDate.year &&
                                           newDate.month == maxDate.month &&
                                           newDate.day == maxDate.day)) {
                                        setState(() {
                                          _date = DateFormat('yyyy-MM-dd').format(newDate);
                                        });
                                        _autofillTimesForDate();
                                      }
                                    },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // Reset to Today button when date is not today
            Builder(
              builder: (context) {
                final maxDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
                final isCurrentDate = selectedDate.year == maxDate.year &&
                                      selectedDate.month == maxDate.month &&
                                      selectedDate.day == maxDate.day;
                
                if (isCurrentDate) {
                  return const SizedBox.shrink();
                }
                
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _date = DateFormat('yyyy-MM-dd').format(DateTime.now());
                        });
                        _autofillTimesForDate();
                      },
                      child: const Text(
                        'Reset to Today',
                        style: TextStyle(
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Time dropdowns
            Row(
              children: [
                Expanded(
                  child: _buildLabeledInput(
                    label: 'START',
                    child: DropdownButtonFormField<String>(
                      value: _startTime.isEmpty ? null : _startTime,
                      decoration: const InputDecoration(
                        labelText: 'Start Time',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    ),
                    selectedItemBuilder: (BuildContext context) {
                      return timeOptions.map((time) {
                        return Text(
                          _convertTo12Hour(time), // Show 12-hour format when selected
                          textAlign: TextAlign.center,
                        );
                      }).toList();
                    },
                    items: timeOptions.map((time) {
                      return DropdownMenuItem(
                        value: time,
                        child: Text(
                          _convertTo12Hour(time), // Show 12-hour format in dropdown
                          textAlign: TextAlign.center,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _startTime = value ?? '';
                        // Autofill finish time as start time + 30 minutes
                        if (_startTime.isNotEmpty) {
                          _finishTime = _addMinutesToTime(_startTime, 30);
                        } else {
                          _finishTime = '';
                        }
                      });
                    },
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildLabeledInput(
                    label: 'FINISH',
                    child: DropdownButtonFormField<String>(
                      value: _finishTime.isEmpty ? null : _finishTime,
                      decoration: const InputDecoration(
                        labelText: 'Finish Time',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    ),
                    selectedItemBuilder: (BuildContext context) {
                      final options = _generateLimitedTimeOptions(_startTime, null);
                      return options.map((time) {
                        return Text(
                          _convertTo12Hour(time), // Show 12-hour format when selected
                          textAlign: TextAlign.center,
                        );
                      }).toList();
                    },
                    items: _generateLimitedTimeOptions(_startTime, null).map((time) {
                      return DropdownMenuItem(
                        value: time,
                        child: Text(
                          _convertTo12Hour(time), // Show 12-hour format in dropdown
                          textAlign: TextAlign.center,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _finishTime = value ?? '';
                      });
                    },
                    ),
                  ),
                ),
              ],
            ),
                  const SizedBox(height: 16),
                  ..._buildBreaksList(),
                  const SizedBox(height: 16),
                  // Buttons below Add Break
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _userData != null ? _handleLoadStandardBreaks : null,
                        icon: const Icon(Icons.access_time, size: 18),
                        label: const Text('Load Standard Breaks'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0081FB),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _userData != null ? _handleLoadFullDay : null,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Load Full Day'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0081FB),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBreaksList() {
    final widgets = <Widget>[];
    for (int i = 0; i < _breaks.length; i++) {
      widgets.add(_buildBreakRow(i));
      widgets.add(const SizedBox(height: 8));
    }
    if (_breaks.length < 3) {
      widgets.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _handleAddBreak,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Custom Break'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0081FB),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  // Helper method to build fleet input field with custom keyboard on mobile
  Widget _buildProjectDetailsContent() {
    // Find the selected project data using fast O(1) map lookup
    final project = _projectMapByName[_selectedProject];
    
    if (project == null) {
      return const Text(
        'Project details not available',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      );
    }
    
    final clientName = project['client_name']?.toString() ?? 'Not specified';
    final descriptionOfWork = project['description_of_work']?.toString() ?? 'Not specified';
    final projectName = project['project_name']?.toString() ?? 'Not specified';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Project Name:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              projectName,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Client Name:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              clientName,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Description of Work:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              descriptionOfWork,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFleetDetailsContent() {
    // Find the selected fleet data using fast O(1) map lookup
    final plantNoUpper = _selectedProject.toUpperCase();
    final plant = _plantMapByNo[plantNoUpper];
    
    if (plant == null) {
      return const Text(
        'Fleet details not available',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      );
    }
    
    // Check if this is a workshop task
    final isWorkshopTask = plant['is_workshop_task'] == true;
    
    if (isWorkshopTask) {
      // For workshop tasks, display like Project mode with "Description of Work:"
      final descriptionOfWork = plant['description_of_work']?.toString() ?? 'Not specified';
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Description of Work:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                descriptionOfWork,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ],
      );
    } else {
      // For regular fleet, display "Description:" as before
      final fullDescription = plant['plant_description']?.toString() ?? 
                               plant['short_description']?.toString() ?? 
                               'Not specified';
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fullDescription,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ],
      );
    }
  }

  Widget _buildFleetInputField({
    Key? key,
    required String initialValue,
    required String labelText,
    required bool isDuplicate,
    required bool isInvalid,
    required Function(String) onChanged,
    required Function()? onFocusLost,
    required Function()? onFocusGained,
  }) {
    return _FleetInputField(
      key: key,
      initialValue: initialValue,
      labelText: labelText,
      isDuplicate: isDuplicate,
      isInvalid: isInvalid,
      onChanged: onChanged,
      onFocusLost: onFocusLost,
      onFocusGained: onFocusGained,
    );
  }

  List<Widget> _buildFleetList() {
    final widgets = <Widget>[];
    
    // Determine how many fleet boxes to show
    // Start with 1 box, show next box when previous one has data
    int boxesToShow = 1;
    for (int i = 0; i < 6; i++) {
      // Ensure list is long enough
      while (_usedFleet.length <= i) {
        _usedFleet.add('');
      }
      // If this box has data, show the next box too
      if (_usedFleet[i].isNotEmpty) {
        boxesToShow = i + 2; // Show next box (i+1 becomes i+2 total boxes)
      }
    }
    // Cap at 6
    boxesToShow = boxesToShow > 6 ? 6 : boxesToShow;
    
    // Check for duplicate fleet numbers
    final plantNoCounts = <String, int>{};
    for (int i = 0; i < boxesToShow; i++) {
      final plantNo = i < _usedFleet.length ? _usedFleet[i].toUpperCase() : '';
      if (plantNo.isNotEmpty) {
        plantNoCounts[plantNo] = (plantNoCounts[plantNo] ?? 0) + 1;
      }
    }
    
    for (int index = 0; index < boxesToShow; index++) {
      final plantNo = index < _usedFleet.length ? _usedFleet[index] : '';
      final plantNoUpper = plantNo.toUpperCase();
      final isDuplicate = plantNoUpper.isNotEmpty && (plantNoCounts[plantNoUpper] ?? 0) > 1;
      final isInvalid = plantNoUpper.isNotEmpty && _invalidFleetNumbers.contains(plantNoUpper);
      final hasFocus = _fleetFieldHasFocus[index] ?? false;
      
      // Get description from cache
      final cacheKey = 'u_$index';
      final plantDesc = _fleetDescriptions[cacheKey] ?? '';
      
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              // Fleet number box - hide when fleet number is entered AND focus is lost
              if (plantNo.isEmpty || hasFocus)
                SizedBox(
                  width: 100,
                  child: _buildFleetInputField(
                    key: ValueKey('fleet_${index}'),
                    initialValue: plantNo,
                    labelText: 'Fleet ${index + 1}',
                    isDuplicate: isDuplicate,
                    isInvalid: isInvalid,
                    onChanged: (value) {
                      setState(() {
                        while (_usedFleet.length <= index) {
                          _usedFleet.add('');
                        }
                        _usedFleet[index] = value.toUpperCase();
                        // Trigger rebuild to show next box if needed
                      });
                    },
                    onFocusLost: () {
                      setState(() {
                        _fleetFieldHasFocus[index] = false;
                      });
                      // Validate on focus loss
                      final currentValue = index < _usedFleet.length ? _usedFleet[index] : '';
                      _validateFleetNumber(index, currentValue, false);
                    },
                    onFocusGained: () {
                      setState(() {
                        _fleetFieldHasFocus[index] = true;
                      });
                    },
                  ),
                ),
              if (plantNo.isEmpty || hasFocus) const SizedBox(width: 8),
              // Description display (red if invalid, grey if valid)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    color: _invalidFleetNumbers.contains(plantNoUpper) 
                        ? Colors.red.shade50 
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: _invalidFleetNumbers.contains(plantNoUpper)
                        ? Border.all(color: Colors.red, width: 2)
                        : null,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      plantDesc,
                      style: TextStyle(
                        color: _invalidFleetNumbers.contains(plantNoUpper)
                            ? Colors.red
                            : Colors.grey.shade700,
                        fontSize: 14,
                        fontWeight: _invalidFleetNumbers.contains(plantNoUpper)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Search button (?) - only show when no fleet number entered
              if (plantNo.isEmpty)
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 20),
                  color: Colors.blue.shade700,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Search for Fleet Number',
                  onPressed: () => _showFleetSearchDialog(index, false),
                ),
              if (plantNo.isEmpty) const SizedBox(width: 4),
              // Clear button (X) - only show when fleet number is entered
              if (plantNo.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: Colors.grey.shade700,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      while (_usedFleet.length <= index) {
                        _usedFleet.add('');
                      }
                      _usedFleet[index] = '';
                      // Clear cached description
                      _fleetDescriptions.remove('u_$index');
                      _fleetFieldHasFocus[index] = false;
                      _invalidFleetNumbers.remove(plantNoUpper);
                    });
                  },
                ),
            ],
          ),
        ),
      );
    }
    
    return widgets;
  }

  List<Widget> _buildMobilisedFleetList() {
    final widgets = <Widget>[];
    
    // Determine how many mobilised fleet boxes to show (max 4)
    int boxesToShow = 1;
    for (int i = 0; i < 4; i++) {
      while (_mobilisedFleet.length <= i) {
        _mobilisedFleet.add('');
      }
      if (_mobilisedFleet[i].isNotEmpty) {
        boxesToShow = i + 2;
      }
    }
    boxesToShow = boxesToShow > 4 ? 4 : boxesToShow;
    
    // Check for duplicate fleet numbers
    final plantNoCounts = <String, int>{};
    for (int i = 0; i < boxesToShow; i++) {
      final plantNo = i < _mobilisedFleet.length ? _mobilisedFleet[i].toUpperCase() : '';
      if (plantNo.isNotEmpty) {
        plantNoCounts[plantNo] = (plantNoCounts[plantNo] ?? 0) + 1;
      }
    }
    
    for (int index = 0; index < boxesToShow; index++) {
      final plantNo = index < _mobilisedFleet.length ? _mobilisedFleet[index] : '';
      final plantNoUpper = plantNo.toUpperCase();
      final isDuplicate = plantNoUpper.isNotEmpty && (plantNoCounts[plantNoUpper] ?? 0) > 1;
      final hasFocus = _mobilisedFleetFieldHasFocus[index] ?? false;
      
      // Get description from cache
      final cacheKey = 'm_$index';
      final plantDesc = _fleetDescriptions[cacheKey] ?? '';
      
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              // Fleet number box - hide when fleet number is entered AND focus is lost
              if (plantNo.isEmpty || hasFocus)
                SizedBox(
                  width: 100,
                  child: _buildFleetInputField(
                    key: ValueKey('mobilised_${index}'),
                    initialValue: plantNo,
                    labelText: 'Mobilised ${index + 1}',
                    isDuplicate: isDuplicate,
                    isInvalid: false, // Mobilised fleet doesn't need validation (optional field)
                    onChanged: (value) {
                      setState(() {
                        while (_mobilisedFleet.length <= index) {
                          _mobilisedFleet.add('');
                        }
                        _mobilisedFleet[index] = value.toUpperCase();
                      });
                    },
                    onFocusLost: () {
                      setState(() {
                        _mobilisedFleetFieldHasFocus[index] = false;
                      });
                      // Validate on focus loss (for description lookup)
                      final currentValue = index < _mobilisedFleet.length ? _mobilisedFleet[index] : '';
                      _validateFleetNumber(index, currentValue, true);
                    },
                    onFocusGained: () {
                      setState(() {
                        _mobilisedFleetFieldHasFocus[index] = true;
                      });
                    },
                  ),
                ),
              if (plantNo.isEmpty || hasFocus) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    plantDesc.isNotEmpty ? plantDesc : '',
                    style: TextStyle(
                      fontSize: 14,
                      color: plantDesc.isNotEmpty ? Colors.black87 : Colors.grey,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Search button (?) - only show when no fleet number entered
              if (plantNo.isEmpty)
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 20),
                  color: Colors.blue.shade700,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Search for Fleet Number',
                  onPressed: () => _showFleetSearchDialog(index, true),
                ),
              if (plantNo.isEmpty) const SizedBox(width: 4),
              // Clear button (X) - only show when fleet number is entered
              if (plantNo.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: Colors.grey.shade700,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      while (_mobilisedFleet.length <= index) {
                        _mobilisedFleet.add('');
                      }
                      _mobilisedFleet[index] = '';
                      // Clear cached description
                      _fleetDescriptions.remove('m_$index');
                      _mobilisedFleetFieldHasFocus[index] = false;
                    });
                  },
                ),
            ],
          ),
        ),
      );
    }
    
    return widgets;
  }

  Widget _buildBreakRow(int index) {
    final breakData = _breaks[index];
    
    // Determine limits for break start: 0:15 after previous break finish (or start time) and 0:15 before finish time
    String? breakStartAfter;
    if (index > 0 && _breaks[index - 1]['finish']?.toString().isNotEmpty == true) {
      breakStartAfter = _breaks[index - 1]['finish']?.toString();
    } else if (_startTime.isNotEmpty) {
      breakStartAfter = _startTime;
    }
    
    // Generate break start options and ensure no duplicates
    final breakStartOptionsRaw = _generateLimitedTimeOptions(breakStartAfter, _finishTime.isNotEmpty ? _finishTime : null);
    final breakStartOptions = breakStartOptionsRaw.toSet().toList(); // Remove duplicates
    
    // Determine limits for break finish: minimum 15 minutes after break start and 0 minutes before finish time
    // If break start has no options, break finish should also have no options
    final breakStartValue = breakData['start']?.toString();
    final breakFinishAfter = breakStartValue != null && breakStartValue.isNotEmpty 
        ? _addMinutesToTime(breakStartValue, 15) // Minimum 15 minutes after break start
        : null;
    List<String> breakFinishOptions;
    if (breakStartOptions.isEmpty) {
      // If start has no options, finish should also have no options
      breakFinishOptions = [];
    } else {
      final breakFinishOptionsRaw = _generateLimitedTimeOptions(breakFinishAfter, _finishTime.isNotEmpty ? _finishTime : null);
      breakFinishOptions = breakFinishOptionsRaw.toSet().toList(); // Remove duplicates
      
      // If break start is set but no finish, default to 30 minutes after start
      if (breakStartValue != null && breakStartValue.isNotEmpty && 
          (breakData['finish']?.toString().isEmpty ?? true)) {
        final defaultFinish = _addMinutesToTime(breakStartValue, 30);
        if (breakFinishOptions.contains(defaultFinish)) {
          // Set default finish time
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _breaks.length > index) {
              setState(() {
                _breaks[index]['finish'] = defaultFinish;
              });
            }
          });
        }
      }
    }
    
    // Validate break start value - ensure it exists in the options list
    // If the value is not in the list, use null to prevent dropdown errors
    String? validBreakStart;
    // breakStartValue is already declared above, reuse it
    if (breakStartValue != null && breakStartValue.isNotEmpty && breakStartOptions.contains(breakStartValue)) {
      validBreakStart = breakStartValue;
    } else {
      // Value is not in the list or is empty - use null and clear it after build
      if (breakStartValue != null && breakStartValue.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _breaks.length > index && _breaks[index]['start']?.toString() == breakStartValue) {
            setState(() {
              _breaks[index]['start'] = '';
              // Also clear finish if start is cleared
              _breaks[index]['finish'] = '';
            });
          }
        });
      }
      validBreakStart = null;
    }
    
    // Validate break finish value - ensure it exists in the options list
    // If the value is not in the list, use null to prevent dropdown errors
    String? validBreakFinish;
    final breakFinishValue = breakData['finish']?.toString();
    if (breakFinishValue != null && breakFinishValue.isNotEmpty && breakFinishOptions.contains(breakFinishValue)) {
      validBreakFinish = breakFinishValue;
    } else {
      // Value is not in the list or is empty - use null and clear it after build
      if (breakFinishValue != null && breakFinishValue.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _breaks.length > index && _breaks[index]['finish']?.toString() == breakFinishValue) {
            setState(() {
              _breaks[index]['finish'] = '';
            });
          }
        });
      }
      validBreakFinish = null;
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('break_start_${index}_${breakStartOptions.length}_${validBreakStart ?? 'null'}'),
                value: validBreakStart,
                decoration: InputDecoration(
                  labelText: 'Break ${index + 1} Start',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
                selectedItemBuilder: (BuildContext context) {
                  if (breakStartOptions.isEmpty) {
                    return [const Text('No options', textAlign: TextAlign.center)];
                  }
                  return breakStartOptions.map((time) {
                    return Text(
                      _convertTo12Hour(time), // Show 12-hour format when selected
                      textAlign: TextAlign.center,
                    );
                  }).toList();
                },
                items: breakStartOptions.isEmpty
                    ? [const DropdownMenuItem(value: null, child: Text('No options available'))]
                    : breakStartOptions.map((time) {
                        return DropdownMenuItem(
                          value: time,
                          child: Text(
                            _convertTo12Hour(time), // Show 12-hour format in dropdown
                            textAlign: TextAlign.center,
                          ),
                        );
                      }).toList(),
                onChanged: (value) {
                  setState(() {
                    _breaks[index]['start'] = value ?? '';
                    // Clear finish if it's now invalid
                    if (value != null && breakData['finish']?.toString().isNotEmpty == true) {
                      final finishMinutes = _timeStringToMinutes(breakData['finish']?.toString() ?? '');
                      final startMinutes = _timeStringToMinutes(value);
                      if (finishMinutes <= startMinutes + 0) {
                        _breaks[index]['finish'] = '';
                      }
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('break_finish_${index}_${breakFinishOptions.length}_${validBreakFinish ?? 'null'}'),
                value: validBreakFinish,
                decoration: InputDecoration(
                  labelText: 'Break ${index + 1} Finish',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
                selectedItemBuilder: (BuildContext context) {
                  if (breakFinishOptions.isEmpty) {
                    return [const Text('No options', textAlign: TextAlign.center)];
                  }
                  return breakFinishOptions.map((time) {
                    return Text(
                      _convertTo12Hour(time), // Show 12-hour format when selected
                      textAlign: TextAlign.center,
                    );
                  }).toList();
                },
                items: breakFinishOptions.isEmpty
                    ? [const DropdownMenuItem(value: null, child: Text('No options available'))]
                    : breakFinishOptions.map((time) {
                        return DropdownMenuItem(
                          value: time,
                          child: Text(
                            _convertTo12Hour(time), // Show 12-hour format in dropdown
                            textAlign: TextAlign.center,
                          ),
                        );
                      }).toList(),
                onChanged: (value) {
                  setState(() {
                    _breaks[index]['finish'] = value ?? '';
                  });
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _handleRemoveBreak(index),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: (breakData['reason'] as String?) ?? '',
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Only add reason if leaving work for short periods, long breaks should be entered as a gap between two time periods.',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: (value) {
            setState(() {
              _breaks[index]['reason'] = value;
            });
          },
        ),
      ],
    );
  }

  void _handleAddBreak() {
    if (_breaks.length < 3) {
      // Check if time period is long enough for a break (need at least 0 minutes: breaks can be at start or end)
      if (_startTime.isNotEmpty && _finishTime.isNotEmpty) {
        final startMinutes = _timeStringToMinutes(_startTime);
        final finishMinutes = _timeStringToMinutes(_finishTime);
        final duration = finishMinutes - startMinutes;
        
        // Need at least 0 minutes for a break (breaks can be at start or end of time period)
        if (duration < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Time period is not valid. Finish time must be after start time.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        
        // Check if there are any valid break start options
        String? breakStartAfter;
        if (_breaks.isNotEmpty && _breaks.last['finish']?.toString().isNotEmpty == true) {
          breakStartAfter = _breaks.last['finish']?.toString();
        } else if (_startTime.isNotEmpty) {
          breakStartAfter = _startTime;
        }
        
        final breakStartOptions = _generateLimitedTimeOptions(breakStartAfter, _finishTime.isNotEmpty ? _finishTime : null);
        
        if (breakStartOptions.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Time period is not long enough to insert a break.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }
      
      setState(() {
        // Check if we should autofill from users_data
        String? breakStart;
        String? breakFinish;
        
        if (_userData != null && _startTime.isNotEmpty && _finishTime.isNotEmpty) {
          final date = DateTime.parse(_date);
          final dayOfWeek = date.weekday;
          if (dayOfWeek >= 1 && dayOfWeek <= 6) { // Monday to Saturday
            final dayNames = ['', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
            final dayName = dayNames[dayOfWeek];
            
            // Check break 1 if this is the first break, break 2 if second
            final breakNum = _breaks.length + 1;
            final breakStartKey = '${dayName}_break_${breakNum}_start';
            final breakFinishKey = '${dayName}_break_${breakNum}_finish';
            
            final savedStart = _userData![breakStartKey]?.toString();
            final savedFinish = _userData![breakFinishKey]?.toString();
            
            // Only use saved break times if they fall within Start Time and Finish Time range
            if (savedStart != null && savedFinish != null && 
                savedStart.isNotEmpty && savedFinish.isNotEmpty) {
              final startMinutes = _timeStringToMinutes(_startTime);
              final finishMinutes = _timeStringToMinutes(_finishTime);
              final savedStartMinutes = _timeStringToMinutes(savedStart);
              final savedFinishMinutes = _timeStringToMinutes(savedFinish);
              
              if (savedStartMinutes >= startMinutes && savedFinishMinutes <= finishMinutes) {
                breakStart = savedStart;
                breakFinish = savedFinish;
              }
            }
          }
        }
        
        _breaks.add({
          'start': breakStart ?? '',
          'finish': breakFinish ?? '',
          'reason': ''
        });
      });
    }
  }

  void _handleRemoveBreak(int index) {
    setState(() {
      _breaks.removeAt(index);
    });
  }

  void _handleLoadStandardBreaks() {
    if (_userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile not found. Standard breaks cannot be loaded.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if Start Time and Finish Time are entered
    if (_startTime.isEmpty || _finishTime.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Start Time and Finish Time before loading standard breaks.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final date = DateTime.parse(_date);
    final dayOfWeek = date.weekday; // 1 = Monday, 6 = Saturday, 7 = Sunday
    if (dayOfWeek == 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Standard breaks are not available for Sunday.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final dayNames = ['', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
    final dayName = dayNames[dayOfWeek];

    // Convert Start Time and Finish Time to minutes for comparison
    final startMinutes = _timeStringToMinutes(_startTime);
    final finishMinutes = _timeStringToMinutes(_finishTime);

    final standardBreaks = <Map<String, dynamic>>[];
    
    // Check break 1 - only add if it falls within Start Time and Finish Time
    final break1Start = _userData!['${dayName}_break_1_start']?.toString();
    final break1Finish = _userData!['${dayName}_break_1_finish']?.toString();
    if (break1Start != null && break1Finish != null && 
        break1Start.isNotEmpty && break1Finish.isNotEmpty) {
      final break1StartMinutes = _timeStringToMinutes(break1Start);
      final break1FinishMinutes = _timeStringToMinutes(break1Finish);
      
      // Only add break if it falls within the entered Start Time and Finish Time range
      if (break1StartMinutes >= startMinutes && break1FinishMinutes <= finishMinutes) {
        standardBreaks.add({
          'start': break1Start,
          'finish': break1Finish,
          'reason': '',
        });
      }
    }

    // Check break 2 - only add if it falls within Start Time and Finish Time
    final break2Start = _userData!['${dayName}_break_2_start']?.toString();
    final break2Finish = _userData!['${dayName}_break_2_finish']?.toString();
    if (break2Start != null && break2Finish != null && 
        break2Start.isNotEmpty && break2Finish.isNotEmpty) {
      final break2StartMinutes = _timeStringToMinutes(break2Start);
      final break2FinishMinutes = _timeStringToMinutes(break2Finish);
      
      // Only add break if it falls within the entered Start Time and Finish Time range
      if (break2StartMinutes >= startMinutes && break2FinishMinutes <= finishMinutes) {
        standardBreaks.add({
          'start': break2Start,
          'finish': break2Finish,
          'reason': '',
        });
      }
    }

    setState(() {
      _breaks = standardBreaks;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded ${standardBreaks.length} break${standardBreaks.length != 1 ? 's' : ''} for $dayName.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _handleLoadFullDay() {
    if (_userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile not found. Full day schedule cannot be loaded.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final date = DateTime.parse(_date);
    final dayOfWeek = date.weekday; // 1 = Monday, 6 = Saturday, 7 = Sunday
    if (dayOfWeek == 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full day schedule is not available for Sunday.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final dayNames = ['', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
    final dayName = dayNames[dayOfWeek];

    setState(() {
      if (_userData!['${dayName}_start_time'] != null) {
        _startTime = _userData!['${dayName}_start_time'].toString();
      }
      if (_userData!['${dayName}_finish_time'] != null) {
        _finishTime = _userData!['${dayName}_finish_time'].toString();
      }

      final standardBreaks = <Map<String, dynamic>>[];
      final break1Start = _userData!['${dayName}_break_1_start'];
      final break1Finish = _userData!['${dayName}_break_1_finish'];
      if (break1Start != null && break1Finish != null) {
        standardBreaks.add({
          'start': break1Start.toString(),
          'finish': break1Finish.toString(),
          'reason': '',
        });
      }

      final break2Start = _userData!['${dayName}_break_2_start'];
      final break2Finish = _userData!['${dayName}_break_2_finish'];
      if (break2Start != null && break2Finish != null) {
        standardBreaks.add({
          'start': break2Start.toString(),
          'finish': break2Finish.toString(),
          'reason': '',
        });
      }

      _breaks = standardBreaks;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded complete schedule for $dayName.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildProjectSection() {
    // Determine color scheme based on fleet mode (reddish theme when fleet mode is active)
    final backgroundColor = _plantListMode 
        ? Colors.red.withOpacity(0.1) // Reddish theme for fleet mode
        : const Color(0xFFBADDFF); // Normal blue background
    final borderColor = _plantListMode
        ? Colors.red // Red border for fleet mode
        : const Color(0xFF005AB0); // Normal blue border
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header in border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Project',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: !_plantListMode ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Switch(
                    value: _plantListMode,
                    onChanged: (value) async {
                      setState(() {
                        _plantListMode = value;
                        _selectedProject = '';
                        _selectedProjectDescription = '';
                      });
                      // Reload plants to include/exclude workshop_tasks based on mode
                      await _loadPlant();
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Fleet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: _plantListMode ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Project filter text box
                  if (!_plantListMode)
                    _buildLabeledInput(
                      label: 'PROJ_FILTER',
                      child: TextFormField(
                        key: ValueKey('project_filter_$_projectFilterResetCounter'),
                        initialValue: _projectFilter,
                        decoration: InputDecoration(
                          labelText: 'Filter Projects (multiple search strings)',
                        hintText: 'Enter search terms separated by spaces',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _projectFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _projectFilter = '';
                                    _projectFilterResetCounter++;
                                  });
                                },
                                tooltip: 'Clear filter',
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _projectFilter = value;
                          
                          // Check if the currently selected project is still in the filtered list
                          if (_selectedProject.isNotEmpty) {
                            final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                            final selectedProjectName = _selectedProject.toLowerCase();
                            
                            // Check if all filter terms are in the selected project name
                            final isStillInFilter = filterTerms.isEmpty || 
                                filterTerms.every((term) => selectedProjectName.contains(term));
                            
                            // Also check if the project exists in the filtered list
                            final filteredProjects = _allProjects.where((project) {
                              if (value.isEmpty) return true;
                              final name = project['project_name']?.toString().toLowerCase() ?? '';
                              return filterTerms.every((term) => name.contains(term));
                            }).toList();
                            
                            final projectExists = filteredProjects.any(
                              (p) => p['project_name']?.toString() == _selectedProject
                            );
                            
                            if (!isStillInFilter || !projectExists) {
                              // Selected project is no longer in filtered list, clear selection
                              _selectedProject = '';
                        _selectedProjectDescription = '';
                              _projectSelected = false;
                            }
                          }
                        });
                      },
                    ),
                  ),
                  // Fleet filter text box
                  if (_plantListMode)
                    _buildLabeledInput(
                      label: 'FLEET_FILTER',
                      child: TextFormField(
                        initialValue: _plantFilter,
                        decoration: InputDecoration(
                          labelText: 'Filter Fleet (multiple search strings)',
                        hintText: 'Enter search terms separated by spaces',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _plantFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _plantFilter = '';
                                  });
                                },
                                tooltip: 'Clear filter',
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _plantFilter = value;
                          
                          // Check if the currently selected fleet is still in the filtered list
                          if (_selectedProject.isNotEmpty) {
                            final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                            
                            // Check if all filter terms are in the selected fleet (number or description)
                            final selectedPlant = _allPlant.firstWhere(
                              (p) => p['plant_no']?.toString() == _selectedProject,
                              orElse: () => <String, dynamic>{},
                            );
                            
                            if (selectedPlant.isNotEmpty) {
                              final plantNo = (selectedPlant['plant_no']?.toString() ?? '').toLowerCase();
                              final desc = (selectedPlant['plant_description']?.toString() ?? 
                                           selectedPlant['short_description']?.toString() ?? '').toLowerCase();
                              
                              // Check if all filter terms are in either plant_no or description
                              final isStillInFilter = filterTerms.isEmpty || 
                                  filterTerms.every((term) => plantNo.contains(term) || desc.contains(term));
                              
                              // Also check if the fleet exists in the filtered list
                              final filteredFleet = _allPlant.where((plant) {
                                if (value.isEmpty) return true;
                                final plantNo = (plant['plant_no']?.toString() ?? '').toLowerCase();
                                final desc = (plant['plant_description']?.toString() ?? 
                                             plant['short_description']?.toString() ?? '').toLowerCase();
                                final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                                return filterTerms.every((term) => plantNo.contains(term) || desc.contains(term));
                              }).toList();
                              
                              final fleetExists = filteredFleet.any(
                                (p) => p['plant_no']?.toString() == _selectedProject
                              );
                              
                              if (!isStillInFilter || !fleetExists) {
                                // Selected fleet is no longer in filtered list, clear selection
                                _selectedProject = '';
                        _selectedProjectDescription = '';
                                _projectSelected = false;
                              }
                            } else {
                              // Selected fleet not found in _allPlant, clear selection
                              _selectedProject = '';
                        _selectedProjectDescription = '';
                              _projectSelected = false;
                            }
                          }
                        });
                      },
                      ),
                    ),
            if (!_plantListMode) const SizedBox(height: 16),
            if (_plantListMode) const SizedBox(height: 16),
            _buildLabeledInput(
              label: _plantListMode ? 'FLEET' : 'PROJECT',
              child: DropdownButtonFormField<String>(
                value: _selectedProject.isEmpty ? null : _selectedProject,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _plantListMode ? 'Select Fleet' : 'Select Project',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                selectedItemBuilder: _plantListMode 
                    ? null
                    : (BuildContext context) {
                        // Build project items list for selectedItemBuilder (must match items exactly)
                        final filteredProjects = _allProjects.where((project) {
                          if (_projectFilter.isEmpty) return true;
                          final name = project['project_name']?.toString().toLowerCase() ?? '';
                          final filterTerms = _projectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                          return filterTerms.every((term) => name.contains(term));
                        }).toList();
                        
                        final seenNames = <String>{};
                        final uniqueProjects = <Map<String, dynamic>>[];
                        for (final project in filteredProjects) {
                          final name = project['project_name']?.toString() ?? '';
                          if (name.isNotEmpty && !seenNames.contains(name)) {
                            seenNames.add(name);
                            uniqueProjects.add(project);
                          }
                        }
                        
                        return uniqueProjects.map((project) {
                          final name = project['project_name']?.toString() ?? '';
                          final commaIndex = name.indexOf(',');
                          final projectNumber = commaIndex > 0 ? name.substring(0, commaIndex).trim() : name.trim();
                          
                          return Text(
                            projectNumber,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          );
                        }).toList();
                      },
                items: _plantListMode
                    ? _allPlant.where((plant) {
                        if (_plantFilter.isEmpty) return true;
                        final plantNo = (plant['plant_no']?.toString() ?? '').toLowerCase();
                        final desc = (plant['plant_description']?.toString() ?? 
                                     plant['short_description']?.toString() ?? '').toLowerCase();
                        final filterTerms = _plantFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                        return filterTerms.every((term) => plantNo.contains(term) || desc.contains(term));
                      }).map((plant) {
                        final plantNo = plant['plant_no']?.toString() ?? '';
                        final desc = plant['plant_description']?.toString() ?? 
                                    plant['short_description']?.toString() ?? 
                                    plantNo;
                        return DropdownMenuItem<String>(
                          value: plantNo,
                          child: Text(
                            desc,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        );
                      }).toList()
                    : _allProjects.where((project) {
                        if (_projectFilter.isEmpty) return true;
                        final name = project['project_name']?.toString().toLowerCase() ?? '';
                        final filterTerms = _projectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                        return filterTerms.every((term) => name.contains(term));
                      }).map((project) {
                        final name = project['project_name']?.toString() ?? '';
                        return DropdownMenuItem(
                          value: name,
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        );
                      }).toList(),
                onChanged: (String? value) {
                  // Record start time for diagnostic timing
                  final selectionStartTime = DateTime.now().millisecondsSinceEpoch;
                  
                  if (_plantListMode && value != null && value.isNotEmpty) {
                    final plantNoUpper = value.toUpperCase();
                    final plant = _plantMapByNo[plantNoUpper] ?? <String, dynamic>{};
                    
                    final description = plant.isNotEmpty
                        ? (plant['plant_description']?.toString() ?? 
                           plant['short_description']?.toString() ?? 
                           value)
                        : value;
                    
                    setState(() {
                      _selectedProject = value;
                      _projectSelected = true;
                      _selectedProjectDescription = description;
                    });
                    
                    // Measure time until Details section is rendered (non-blocking)
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final renderTime = DateTime.now().millisecondsSinceEpoch;
                      final elapsed = renderTime - selectionStartTime;
                      if (mounted) {
                        // Use a separate microtask to avoid blocking the main render
                        Future.microtask(() {
                          if (mounted) {
                            setState(() {
                              _detailsRenderTimeMs = elapsed;
                            });
                          }
                        });
                      }
                    });
                  } else {
                    setState(() {
                      _selectedProject = value ?? '';
                      _projectSelected = value != null && value.isNotEmpty;
                      _selectedProjectDescription = value ?? '';
                    });
                    
                    // Measure time until Details section is rendered (non-blocking)
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final renderTime = DateTime.now().millisecondsSinceEpoch;
                      final elapsed = renderTime - selectionStartTime;
                      if (mounted) {
                        // Use a separate microtask to avoid blocking the main render
                        Future.microtask(() {
                          if (mounted) {
                            setState(() {
                              _detailsRenderTimeMs = elapsed;
                            });
                          }
                        });
                      }
                    });
                  }
                },
              ),
            ),
            // Project Details Section
            if (!_plantListMode && _projectSelected && _selectedProject.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Project Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0081FB),
                          ),
                        ),
                        if (_detailsRenderTimeMs > 0)
                          Text(
                            'Render Time: ${_detailsRenderTimeMs}ms',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildProjectDetailsContent(),
                  ],
                ),
              ),
            ],
            // Fleet Details Section (only in Fleet Mode)
            if (_plantListMode && _projectSelected && _selectedProject.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Fleet Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0081FB),
                          ),
                        ),
                        if (_detailsRenderTimeMs > 0)
                          Text(
                            'Render Time: ${_detailsRenderTimeMs}ms',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildFleetDetailsContent(),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Find Nearest Job button - only visible in Project Mode
                if (!_plantListMode)
                  ElevatedButton.icon(
                    onPressed: _isFindingNearest ? null : _handleFindNearestProject,
                    icon: _isFindingNearest
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.near_me, size: 18),
                    label: Text(_findNearestButtonText),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0081FB),
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (!_plantListMode) const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isFindingLast ? null : _handleFindLastJob,
                  icon: _isFindingLast
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.history, size: 18),
                  label: const Text('Find Last Job'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0081FB),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2), // #005AB0
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header in border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF), // #BADDFF
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2), // #005AB0
                ),
              ),
              child: const Center(
                child: Text(
                  'Fleet & Equipment',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Used Fleet subheading
                  const Text('Used Fleet:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._buildFleetList(),
                  const SizedBox(height: 24),
                  const Text('Mobilised Fleet & Equipment:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._buildMobilisedFleetList(),
                  const SizedBox(height: 16),
                  // Buttons at bottom (similar to Project Section)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _handleRecallFleet,
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Recall Fleet'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0081FB),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _handleSaveFleet,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Save Fleet'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0081FB),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _handleClearFleet,
                        icon: const Icon(Icons.clear, size: 18),
                        label: const Text('Clear Fleet'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0081FB),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper widget to wrap input fields with a reference label in top right corner
  Widget _buildLabeledInput({
    required Widget child,
    required String label,
  }) {
    // Return child without label (labels removed per user request)
    return child;
  }

  Widget _buildAllowancesSection() {
    final timeOptions = _generateTimeOptions();
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2), // #005AB0
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header in border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF), // #BADDFF
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2), // #005AB0
                ),
              ),
            child: const Center(
              child: Text(
                'Allowances',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Miscellaneous - centered
                Center(
                  child: SizedBox(
                    width: 200, // Fixed width for centering
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            setState(() {
                              final currentMins = _timeStringToMinutes(_miscellaneousTime);
                              final newMins = (currentMins - 30).clamp(0, 1440); // Max 24 hours
                              final hours = newMins ~/ 60;
                              final mins = newMins % 60;
                              _miscellaneousTime = '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
                              _miscellaneous = newMins.toString();
                            });
                          },
                        ),
                        Expanded(
                          child: _buildLabeledInput(
                            label: 'MISC',
                            child: DropdownButtonFormField<String>(
                              value: _miscellaneousTime,
                              decoration: const InputDecoration(
                                labelText: 'Miscellaneous',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                            items: timeOptions.map((time) {
                              return DropdownMenuItem(
                                value: time,
                                child: Text(
                                  time,
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _miscellaneousTime = value ?? '00:00';
                                _miscellaneous = _timeStringToMinutes(_miscellaneousTime).toString();
                              });
                            },
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setState(() {
                              final currentMins = _timeStringToMinutes(_miscellaneousTime);
                              final newMins = (currentMins + 30).clamp(0, 1440); // Max 24 hours
                              final hours = newMins ~/ 60;
                              final mins = newMins % 60;
                              _miscellaneousTime = '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
                              _miscellaneous = newMins.toString();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildLabeledInput(
                        label: 'TRAVEL_TO',
                        child: DropdownButtonFormField<String>(
                          value: _travelToSiteTime,
                          decoration: const InputDecoration(
                            labelText: 'Travel To Site',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        items: timeOptions.map((time) {
                          return DropdownMenuItem(
                            value: time,
                            child: Text(
                              time,
                              textAlign: TextAlign.center,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _travelToSiteTime = value ?? '00:00';
                            _travelToSite = _timeStringToMinutes(_travelToSiteTime).toString();
                          });
                        },
                      ),
                    ),
                  ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildLabeledInput(
                        label: 'TRAVEL_FROM',
                        child: DropdownButtonFormField<String>(
                          value: _travelFromSiteTime,
                          decoration: const InputDecoration(
                            labelText: 'Travel From Site',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        items: timeOptions.map((time) {
                          return DropdownMenuItem(
                            value: time,
                            child: Text(
                              time,
                              textAlign: TextAlign.center,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _travelFromSiteTime = value ?? '00:00';
                            _travelFromSite = _timeStringToMinutes(_travelFromSiteTime).toString();
                          });
                        },
                      ),
                    ),
                  ),
                  ],
                ),
                const SizedBox(height: 16),
                // Check Travel button on its own row
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleCheckTravel,
                    icon: const Icon(Icons.directions_car, size: 18),
                    label: const Text('Check Travel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0081FB),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                // Travel Summary
                if (_totalTravelTimeMinutes > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Travel Summary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0081FB),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Total Travel Time: ${(_totalTravelTimeMinutes ~/ 60)}:${(_totalTravelTimeMinutes % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Available Allowance: ${(_availableAllowanceMinutes ~/ 60)}:${(_availableAllowanceMinutes % 60).toString().padLeft(2, '0')} / ${(_availableAllowanceTotalMinutes ~/ 60)}:${(_availableAllowanceTotalMinutes % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rounded (One Way): $_roundedOneWay',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rounded (Two Way): $_roundedTwoWay',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total Distance: ${_totalDistanceKm.toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildMaterialsSection() {
    // Get max ticket number
    int maxTicket = 0;
    try {
      // This would need to be fetched from database
      // For now, just use the current ticket number
    } catch (e) {
      print('Error getting max ticket: $e');
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2), // #005AB0
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header in border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF), // #BADDFF
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2), // #005AB0
                ),
              ),
              child: const Center(
                child: Text(
                  'Materials',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // Ticket Number: 30% (flex: 3)
                  Expanded(
                    flex: 3,
                    child: _buildLabeledInput(
                      label: 'TICKET',
                      child: TextFormField(
                        initialValue: _ticketNumber,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'Ticket Number',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: maxTicket > 0 ? 'Next: ${maxTicket + 1}' : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          _ticketNumber = value;
                        });
                      },
                    ),
                  ),
                ),
                  const SizedBox(width: 16),
                  // Concrete Mix: 60% (flex: 6)
                  Expanded(
                    flex: 6,
                    child: _buildLabeledInput(
                      label: 'MIX',
                      child: DropdownButtonFormField<String>(
                        value: _concreteMix.isEmpty ? null : _concreteMix,
                        decoration: const InputDecoration(
                          labelText: 'Concrete Mix',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: _allConcreteMixes.map((mix) {
                        final id = mix['id']?.toString() ?? '';
                        final name = (mix['name'] as String?) ?? 
                                    (mix['user_description'] as String?) ?? 
                                    id;
                        return DropdownMenuItem(
                          value: id,
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _concreteMix = value ?? '';
                        });
                      },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Quantity: 30% (flex: 3)
                  Expanded(
                    flex: 3,
                    child: _buildLabeledInput(
                      label: 'QTY',
                      child: TextFormField(
                        initialValue: _quantity,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          _quantity = value;
                        });
                      },
                    ),
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

  Widget _buildCommentsSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2), // #005AB0
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header in border
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF), // #BADDFF
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2), // #005AB0
                ),
              ),
              child: const Center(
                child: Text(
                  'Comments',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildLabeledInput(
                label: 'COMMENTS',
                child: TextFormField(
                  key: ValueKey('comment_$_commentResetCounter'),
                  initialValue: _comments,
                  decoration: const InputDecoration(
                    labelText: 'Comments',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 4,
                onChanged: (value) {
                  setState(() {
                    _comments = value;
                  });
                },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton.icon(
      onPressed: (_isSyncing || _isSaving) ? null : _handleSaveEntry,
      icon: const Icon(Icons.upload, size: 24),
      label: const Text(
        'Upload Time Period',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Future<String?> _getUserIdFromEmail(String email) async {
    try {
      // If current user matches, use their ID directly from auth
      if (_currentUser != null && _currentUser!['email'] == email) {
        return _currentUser!['id']?.toString();
      }

      // For other users, try to get user_id from users_data
      // Note: This assumes users_data has a way to match email to user_id
      // Since users_data.user_id references auth.users.id, we need to find the auth user
      // The best approach is an Edge Function, but for now we'll try a workaround
      
      // Try Edge Function if available
      try {
        final response = await SupabaseService.client.functions.invoke(
          'get_user_id_from_email',
          body: {'email': email},
        );
        
        if (response.status == 200 && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          return data['user_id']?.toString();
        }
      } catch (e) {
        print('⚠️ Edge Function get_user_id_from_email not available: $e');
        print('💡 You may need to create this Edge Function or use a different approach');
      }

      // If Edge Function doesn't exist, we can't get user_id for other users
      // This is a limitation that needs to be addressed
      print('⚠️ Cannot get user_id for email: $email (not current user and no Edge Function)');
      return null;
    } catch (e) {
      print('❌ Error getting user_id: $e');
      return null;
    }
  }

  /// Check for overlaps and gaps in time periods for the current user on the selected date
  /// [excludeTimePeriodId] - ID of time period to exclude from checks (when editing an existing period)
  Future<Map<String, dynamic>> _checkTimePeriodOverlapsAndGaps(DateTime startTime, DateTime finishTime, {String? excludeTimePeriodId}) async {
    try {
      final userId = _currentUser!['id']?.toString();
      if (userId == null) {
        return {'hasOverlap': false, 'hasGap': false, 'overlapMessage': '', 'gapMessage': ''};
      }

      // Get all time periods for this user on this date
      final existingPeriods = await DatabaseService.read(
        'time_periods',
        filterColumn: 'user_id',
        filterValue: userId,
        orderBy: 'start_time',
      );

      // Filter to only periods on the selected date and exclude the period being edited
      final datePeriods = existingPeriods.where((period) {
        final workDate = period['work_date']?.toString();
        final periodId = period['id']?.toString();
        // Exclude the time period being edited if excludeTimePeriodId is provided
        if (excludeTimePeriodId != null && periodId == excludeTimePeriodId) {
          return false;
        }
        return workDate == _date;
      }).toList();

      // Check for overlaps
      for (final period in datePeriods) {
        final periodStart = DateTime.parse(period['start_time'].toString());
        final periodFinish = DateTime.parse(period['finish_time'].toString());

        // Check if new period overlaps with existing period
        if ((startTime.isBefore(periodFinish) && finishTime.isAfter(periodStart))) {
          return {
            'hasOverlap': true,
            'hasGap': false,
            'overlapMessage': 'This time period overlaps with an existing period (${periodStart.hour.toString().padLeft(2, '0')}:${periodStart.minute.toString().padLeft(2, '0')} - ${periodFinish.hour.toString().padLeft(2, '0')}:${periodFinish.minute.toString().padLeft(2, '0')})',
            'gapMessage': '',
          };
        }
      }

      // Check for gaps (only if there are existing periods)
      if (datePeriods.isNotEmpty) {
        // Sort periods by start time
        datePeriods.sort((a, b) {
          final aStart = DateTime.parse(a['start_time'].toString());
          final bStart = DateTime.parse(b['start_time'].toString());
          return aStart.compareTo(bStart);
        });

        // Check if new period creates a gap before it (warn if gap > 0 minutes)
        final lastPeriodFinish = DateTime.parse(datePeriods.last['finish_time'].toString());
        if (startTime.isAfter(lastPeriodFinish)) {
          final gapMinutes = startTime.difference(lastPeriodFinish).inMinutes;
          if (gapMinutes > 0) {
            return {
              'hasOverlap': false,
              'hasGap': true,
              'overlapMessage': '',
              'gapMessage': 'There is a gap of ${gapMinutes} minutes between the last time period and this one. Please add a comment explaining the gap.',
            };
          }
        }

        // Check if new period creates a gap after it (warn if gap > 0 minutes)
        final firstPeriodStart = DateTime.parse(datePeriods.first['start_time'].toString());
        if (finishTime.isBefore(firstPeriodStart)) {
          final gapMinutes = firstPeriodStart.difference(finishTime).inMinutes;
          if (gapMinutes > 0) {
            return {
              'hasOverlap': false,
              'hasGap': true,
              'overlapMessage': '',
              'gapMessage': 'There is a gap of ${gapMinutes} minutes between this time period and the next one. Please add a comment explaining the gap.',
            };
          }
        }
      }

      return {'hasOverlap': false, 'hasGap': false, 'overlapMessage': '', 'gapMessage': ''};
    } catch (e) {
      print('⚠️ Error checking overlaps/gaps: $e');
      return {'hasOverlap': false, 'hasGap': false, 'overlapMessage': '', 'gapMessage': ''};
    }
  }

  Future<void> _handleSaveEntry() async {
    // Prevent multiple simultaneous save attempts
    if (_isSaving) {
      print('⚠️ [SAVE] Save already in progress, ignoring duplicate call');
      return;
    }

    print('🔍 [SAVE] _handleSaveEntry called');
    print('🔍 [SAVE] Employee: $_selectedEmployee, EmployeeUserId: $_selectedEmployeeUserId');
    print('🔍 [SAVE] Project: $_selectedProject');
    
    // Set saving flag to prevent multiple clicks
    setState(() {
      _isSaving = true;
    });
    
    // Check if employee is selected (use _selectedEmployeeUserId if available, otherwise check _selectedEmployee)
    final hasEmployee = (_selectedEmployeeUserId != null && _selectedEmployeeUserId!.isNotEmpty) || 
                        (_selectedEmployee.isNotEmpty);
    // Check for invalid fleet numbers
    final hasInvalidFleet = _usedFleet.any((fleet) {
      if (fleet.isEmpty) return false;
      final upperFleet = fleet.toUpperCase().trim();
      return _invalidFleetNumbers.contains(upperFleet);
    });
    
    if (hasInvalidFleet) {
      setState(() {
        _isSaving = false;
      });
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Save Entry',
        type: 'Validation',
        description: 'Attempted to save with invalid fleet number(s)',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please remove invalid fleet numbers before saving.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (!hasEmployee || _selectedProject.isEmpty) {
      setState(() {
        _isSaving = false;
      });
      print('🔍 [SAVE] Validation failed - hasEmployee: $hasEmployee, project: $_selectedProject');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Save Entry',
        type: 'Validation',
        description: 'Validation failed - hasEmployee: $hasEmployee, project: $_selectedProject',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an employee and project/fleet.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    print('🔍 [SAVE] Validation passed, continuing...');

    try {
      print('🔍 [SAVE] Starting try block...');
      // Get GPS location
      Position? position;
      double? latitude;
      double? longitude;
      int? gpsAccuracy;

      // Use cached GPS location from background refresh (if available and recent)
      print('🔍 [SAVE] Using cached GPS location...');
      if (_cachedLatitude != null && _cachedLongitude != null && _gpsLastUpdated != null) {
        // Check if cached GPS is recent (within last 5 minutes)
        final age = DateTime.now().difference(_gpsLastUpdated!);
        if (age.inMinutes < 5) {
          latitude = _cachedLatitude;
          longitude = _cachedLongitude;
          gpsAccuracy = _cachedGpsAccuracy;
          print('✅ [SAVE] Using cached GPS (age: ${age.inSeconds}s): lat=$latitude, lng=$longitude');
        } else {
          // Cached GPS is too old, try to get fresh one (non-blocking)
          print('⚠️ [SAVE] Cached GPS is ${age.inMinutes} minutes old, attempting fresh GPS...');
          try {
            position = await Geolocator.getCurrentPosition(
              locationSettings: kIsWeb
                  ? WebSettings(
                      accuracy: LocationAccuracy.high,
                      timeLimit: const Duration(seconds: 3),
                    )
                  : AndroidSettings(
                      accuracy: LocationAccuracy.high,
                      timeLimit: const Duration(seconds: 3),
                    ),
            );
            latitude = position.latitude;
            longitude = position.longitude;
            gpsAccuracy = position.accuracy.round();
            // Update cache
            _cachedLatitude = latitude;
            _cachedLongitude = longitude;
            _cachedGpsAccuracy = gpsAccuracy;
            _gpsLastUpdated = DateTime.now();
            print('✅ [SAVE] Fresh GPS obtained: lat=$latitude, lng=$longitude');
          } catch (e) {
            // Fallback to cached GPS on error
            latitude = _cachedLatitude;
            longitude = _cachedLongitude;
            gpsAccuracy = _cachedGpsAccuracy;
            print('⚠️ [SAVE] GPS error, using cached GPS: $e');
          }
        }
      } else {
        // No cached GPS, try to get one (non-blocking with short timeout)
        print('⚠️ [SAVE] No cached GPS, attempting to get GPS...');
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: kIsWeb
                ? WebSettings(
                    accuracy: LocationAccuracy.high,
                    timeLimit: const Duration(seconds: 3),
                  )
                : AndroidSettings(
                    accuracy: LocationAccuracy.high,
                    timeLimit: const Duration(seconds: 3),
                  ),
          );
          latitude = position.latitude;
          longitude = position.longitude;
          gpsAccuracy = position.accuracy.round();
          // Update cache
          _cachedLatitude = latitude;
          _cachedLongitude = longitude;
          _cachedGpsAccuracy = gpsAccuracy;
          _gpsLastUpdated = DateTime.now();
          print('✅ [SAVE] GPS obtained: lat=$latitude, lng=$longitude');
        } catch (e) {
          print('⚠️ [SAVE] Could not get GPS: $e (continuing without GPS)');
        }
      }
      print('🔍 [SAVE] GPS location step completed');

      // Get user_id - use authenticated user's ID from session for RLS policy
      // The RLS policy requires user_id to match auth.uid() for inserts
      print('🔍 [SAVE] Getting user ID...');
      String? userId;
      try {
        final session = SupabaseService.client.auth.currentSession;
        print('🔍 [SAVE] Session check: ${session != null}, user: ${session?.user.id}');
        if (session?.user.id != null) {
          userId = session!.user.id;
          print('🔍 [SAVE] Got user ID from session: $userId');
        } else {
          // Fallback to _currentUser if session is not available
          print('🔍 [SAVE] Session not available, trying _currentUser...');
          userId = _currentUser?['id']?.toString();
          if (userId == null) {
            // Last resort: try to get from email if _selectedEmployee contains email
            if (_selectedEmployee.isNotEmpty && _selectedEmployee.contains('@')) {
              print('🔍 [SAVE] Trying to get user ID from email...');
              userId = await _getUserIdFromEmail(_selectedEmployee);
            }
          } else {
            print('🔍 [SAVE] Got user ID from _currentUser: $userId');
          }
        }
      } catch (e, stackTrace) {
        print('❌ [SAVE] Error getting user ID: $e');
        print('❌ [SAVE] Stack trace: $stackTrace');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting user ID: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      if (userId == null || userId.isEmpty) {
        print('🔍 [SAVE] No user ID found, returning');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find user ID. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      print('🔍 [SAVE] User ID found: $userId');
      
      // DIAGNOSTIC: Start timing the save process
      final saveStartTime = DateTime.now();
      print('⏱️ [DIAGNOSTIC] Save process started at: ${saveStartTime.toIso8601String()}');
      
      // Note: If you need to create time periods for other employees (admin feature),
      // you'll need to update the RLS policy on time_periods table to allow inserts
      // where the authenticated user has admin permissions, or use an Edge Function
      // with service role permissions.
      
      // For now, we use the authenticated user's ID
      // If _selectedEmployeeUserId is different, log a warning
      if (_selectedEmployeeUserId != null && 
          _selectedEmployeeUserId!.isNotEmpty && 
          _selectedEmployeeUserId != userId) {
        print('⚠️ Warning: Selected employee ID ($_selectedEmployeeUserId) differs from authenticated user ID ($userId). Using authenticated user ID for RLS compliance.');
      }

      // Get project_id, large_plant_id, or workshop_tasks_id
      String? projectId;
      String? largePlantId;
      String? workshopTasksId;
      final projectIdStartTime = DateTime.now();
      print('⏱️ [DIAGNOSTIC] Starting project_id/large_plant_id lookup at: ${projectIdStartTime.toIso8601String()}');
      
      if (_plantListMode) {
        // Find fleet by plant_no using map lookup (O(1))
        // In Fleet Mode we set large_plant_id (fleet) or workshop_tasks_id (workshop task), never project_id.
        try {
          final plantLookupStart = DateTime.now();
          print('⏱️ [DIAGNOSTIC] Starting plant lookup at: ${plantLookupStart.toIso8601String()}');
          final plantNoUpper = _selectedProject.toUpperCase().trim();
          final plant = _plantMapByNo[plantNoUpper];
          if (plant == null) {
            throw Exception('Fleet not found in map');
          }
          final plantLookupEnd = DateTime.now();
          print('⏱️ [DIAGNOSTIC] Plant lookup completed in: ${plantLookupEnd.difference(plantLookupStart).inMilliseconds}ms');
          if (plant['is_workshop_task'] == true) {
            workshopTasksId = plant['id']?.toString();
            largePlantId = null;
          } else {
            largePlantId = plant['id']?.toString();
            workshopTasksId = null;
            if (largePlantId == null) {
              throw Exception('Fleet ID not found');
            }
          }
          print('⏱️ [DIAGNOSTIC] Project ID lookup completed at: ${DateTime.now().toIso8601String()}');
        } catch (e, stackTrace) {
          await ErrorLogService.logError(
            location: 'Timesheet Screen - Save Entry (Fleet Mode)',
            type: 'Validation',
            description: 'Could not find fleet ID for: $_selectedProject. Error: $e',
            stackTrace: stackTrace,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not find fleet ID for: $_selectedProject'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } else {
        // Find project by project_name using map lookup (O(1))
        try {
          final projectLookupStart = DateTime.now();
          print('⏱️ [DIAGNOSTIC] Starting project lookup at: ${projectLookupStart.toIso8601String()}');
          final project = _projectMapByName[_selectedProject];
          if (project == null) {
            throw Exception('Project not found in map');
          }
          final projectLookupEnd = DateTime.now();
          print('⏱️ [DIAGNOSTIC] Project lookup completed in: ${projectLookupEnd.difference(projectLookupStart).inMilliseconds}ms');
          projectId = project['id']?.toString();
          if (projectId == null) {
            throw Exception('Project ID not found');
          }
          print('⏱️ [DIAGNOSTIC] Project ID lookup completed at: ${DateTime.now().toIso8601String()}');
        } catch (e, stackTrace) {
          await ErrorLogService.logError(
            location: 'Timesheet Screen - Save Entry (Project Mode)',
            type: 'Validation',
            description: 'Could not find project ID for: $_selectedProject. Error: $e',
            stackTrace: stackTrace,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not find project ID for: $_selectedProject'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // Convert date + time strings to timestamps
      DateTime? startTimestamp;
      DateTime? finishTimestamp;
      
      try {
        if (_date.isNotEmpty && _startTime.isNotEmpty) {
          final dateTime = DateTime.parse(_date);
          final timeParts = _startTime.split(':');
          if (timeParts.length == 2) {
            startTimestamp = DateTime(
              dateTime.year,
              dateTime.month,
              dateTime.day,
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
          }
        }
        
        if (_date.isNotEmpty && _finishTime.isNotEmpty) {
          final dateTime = DateTime.parse(_date);
          final timeParts = _finishTime.split(':');
          if (timeParts.length == 2) {
            finishTimestamp = DateTime(
              dateTime.year,
              dateTime.month,
              dateTime.day,
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
          }
        }
      } catch (e, stackTrace) {
        print('⚠️ Error parsing date/time: $e');
        await ErrorLogService.logError(
          location: 'Timesheet Screen - Save Entry',
          type: 'Data Processing',
          description: 'Error parsing date/time - date: $_date, start: $_startTime, finish: $_finishTime. Error: $e',
          stackTrace: stackTrace,
        );
      }

      // Convert travel allowances to minutes (integers)
      int travelToSiteMin = 0;
      int travelFromSiteMin = 0;
      int miscAllowanceMin = 0;

      try {
        if (_travelToSite.isNotEmpty) {
          // Try to parse as number (assuming it's already in minutes or convert from time format)
          travelToSiteMin = int.tryParse(_travelToSite) ?? 0;
        }
        if (_travelFromSite.isNotEmpty) {
          travelFromSiteMin = int.tryParse(_travelFromSite) ?? 0;
        }
        if (_miscellaneous.isNotEmpty) {
          miscAllowanceMin = int.tryParse(_miscellaneous) ?? 0;
        }
      } catch (e) {
        print('⚠️ Error parsing allowances: $e');
      }

      // Parse distance from calculatedDistance (e.g., "15.2 km" -> 15.2)
      double? distanceFromHome;
      if (_calculatedDistance.isNotEmpty) {
        final match = RegExp(r'[\d.]+').firstMatch(_calculatedDistance);
        if (match != null) {
          distanceFromHome = double.tryParse(match.group(0)!);
        }
      }

      // Validate timestamps
      if (startTimestamp == null || finishTimestamp == null) {
        setState(() {
          _isSaving = false;
        });
        print('🔍 [SAVE] Timestamps missing - start: $startTimestamp, finish: $finishTimestamp');
        await ErrorLogService.logError(
          location: 'Timesheet Screen - Save Entry',
          type: 'Validation',
          description: 'Timestamps missing - start: $startTimestamp, finish: $finishTimestamp',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter both start and finish times.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      print('🔍 [SAVE] Timestamps valid - start: $startTimestamp, finish: $finishTimestamp');

      // Check for overlaps and gaps
      print('🔍 [SAVE] Checking for overlaps and gaps...');
      final overlapCheckStart = DateTime.now();
      print('⏱️ [DIAGNOSTIC] Overlap check started at: ${overlapCheckStart.toIso8601String()}');
      // Exclude the current time period ID if editing
      final excludeTimePeriodId = widget.timePeriodId != null && widget.timePeriodId!.isNotEmpty ? widget.timePeriodId : null;
      final overlapCheck = await _checkTimePeriodOverlapsAndGaps(startTimestamp, finishTimestamp, excludeTimePeriodId: excludeTimePeriodId);
      final overlapCheckEnd = DateTime.now();
      print('⏱️ [DIAGNOSTIC] Overlap check completed in: ${overlapCheckEnd.difference(overlapCheckStart).inMilliseconds}ms');
      if (overlapCheck['hasOverlap'] == true) {
        setState(() {
          _isSaving = false;
        });
        final overlapMsg = overlapCheck['overlapMessage']?.toString() ?? 'This time period overlaps with an existing period.';
        await ErrorLogService.logError(
          location: 'Timesheet Screen - Save Entry',
          type: 'Validation',
          description: 'Time period overlap detected: $overlapMsg',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(overlapMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return; // Prevent saving overlapping periods
      }

      // Warn about gaps but allow saving (user can add comment)
      if (overlapCheck['hasGap'] == true && _comments.isEmpty) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Time Gap Detected'),
            content: Text(overlapCheck['gapMessage']?.toString() ?? 'There is a gap in your time periods.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (shouldContinue != true) {
          setState(() {
            _isSaving = false;
          });
          return; // User cancelled
        }
      }

      // Pre-calculate all confirmation dialog data before building (optimization)
      print('🔍 [CONFIRMATION] Pre-calculating dialog data...');
      final confirmationDialogStart = DateTime.now();
      print('⏱️ [DIAGNOSTIC] Confirmation dialog started at: ${confirmationDialogStart.toIso8601String()}');
      
      // Pre-format date
      String formattedDate;
      try {
        final dateTime = DateTime.parse(_date);
        final dateFormat = DateFormat('EEE (d MMM)');
        formattedDate = dateFormat.format(dateTime);
      } catch (e) {
        formattedDate = _date;
      }
      
      // Pre-format times
      final startTimeFormatted = _startTime.isEmpty ? 'Not set' : _convertTo12Hour(_startTime);
      final finishTimeFormatted = _finishTime.isEmpty ? 'Not set' : _convertTo12Hour(_finishTime);
      
      // Pre-format project/fleet (use description from dropdown, no lookup needed)
      final projectDisplayName = _selectedProjectDescription.isNotEmpty 
          ? _selectedProjectDescription 
          : (_selectedProject.isEmpty ? 'Not selected' : _selectedProject);
      
      // Pre-calculate break data
      final breaksList = _breaks.where((b) => 
        b['start']?.toString().isNotEmpty == true || 
        b['finish']?.toString().isNotEmpty == true
      ).toList();
      
      int totalBreakMinutes = 0;
      final breakDetails = <String>[];
      for (final breakData in breaksList) {
        final breakStart = breakData['start']?.toString() ?? '';
        final breakFinish = breakData['finish']?.toString() ?? '';
        if (breakStart.isNotEmpty && breakFinish.isNotEmpty) {
          final startMins = _timeStringToMinutes(breakStart);
          final finishMins = _timeStringToMinutes(breakFinish);
          totalBreakMinutes += (finishMins - startMins);
          breakDetails.add('${_convertTo12Hour(breakStart)} - ${_convertTo12Hour(breakFinish)}');
        }
      }
      final totalBreakHours = totalBreakMinutes ~/ 60;
      final totalBreakMins = totalBreakMinutes % 60;
      final totalBreakText = totalBreakHours > 0 
          ? '$totalBreakHours h $totalBreakMins min'
          : '$totalBreakMins min';
      
      // Pre-calculate total worked hours
      int totalWorkMinutes = 0;
      String totalWorkText = '0 min';
      if (_startTime.isNotEmpty && _finishTime.isNotEmpty) {
        final startMins = _timeStringToMinutes(_startTime);
        final finishMins = _timeStringToMinutes(_finishTime);
        totalWorkMinutes = finishMins - startMins;
        totalWorkMinutes -= totalBreakMinutes; // Subtract breaks
        final hours = totalWorkMinutes ~/ 60;
        final minutes = totalWorkMinutes % 60;
        totalWorkText = hours > 0 
            ? '$hours h $minutes min'
            : '$minutes min';
      }
      
      // Format used fleet (plant_description already contains plant_no prefix)
      final usedFleetList = _usedFleet.where((f) => f.isNotEmpty).toList();
      final usedFleetDescriptions = <String>[];
      for (final plantNo in usedFleetList) {
        final cacheKey = 'u_${_usedFleet.indexOf(plantNo)}';
        final plantDesc = _fleetDescriptions[cacheKey] ?? '';
        if (plantDesc.isNotEmpty && !plantDesc.contains('not valid')) {
          usedFleetDescriptions.add(plantDesc);
        } else {
          usedFleetDescriptions.add(plantNo);
        }
      }
      
      // Format mobilised fleet (plant_description already contains plant_no prefix)
      final mobilisedFleetList = _mobilisedFleet.where((f) => f.isNotEmpty).toList();
      final mobilisedFleetDescriptions = <String>[];
      for (final plantNo in mobilisedFleetList) {
        final cacheKey = 'm_${_mobilisedFleet.indexOf(plantNo)}';
        final plantDesc = _fleetDescriptions[cacheKey] ?? '';
        if (plantDesc.isNotEmpty && !plantDesc.contains('not valid')) {
          mobilisedFleetDescriptions.add(plantDesc);
        } else {
          mobilisedFleetDescriptions.add(plantNo);
        }
      }
      
      // Get concrete mix name from ID if provided
      String concreteMixName = _concreteMix;
      if (_concreteMix.isNotEmpty && _allConcreteMixes.isNotEmpty) {
        try {
          final mix = _allConcreteMixes.firstWhere(
            (mix) => mix['id']?.toString() == _concreteMix,
            orElse: () => {},
          );
          if (mix.isNotEmpty) {
            concreteMixName = (mix['name'] as String?) ?? 
                             (mix['user_description'] as String?) ?? 
                             _concreteMix;
          }
        } catch (e) {
          print('⚠️ Error looking up concrete mix name: $e');
          // Keep original ID if lookup fails
        }
      }
      
      print('⏱️ [DIAGNOSTIC] Pre-calculation completed in: ${DateTime.now().difference(confirmationDialogStart).inMilliseconds}ms');
      
      bool shouldSave = false;
      try {
        print('🔍 [CONFIRMATION] Calling showDialog...');
        shouldSave = await showDialog<bool>(
          context: context,
          barrierDismissible: false, // Prevent dismissing by tapping outside
          builder: (BuildContext dialogContext) {
            print('🔍 [CONFIRMATION] Building dialog widget...');
            return _buildSaveConfirmationDialogOptimized(
              formattedDate: formattedDate,
              startTimeFormatted: startTimeFormatted,
              finishTimeFormatted: finishTimeFormatted,
              projectDisplayName: projectDisplayName,
              totalBreakText: totalBreakText,
              breakDetails: breakDetails,
              totalWorkText: totalWorkText,
              usedFleetDescriptions: usedFleetDescriptions,
              mobilisedFleetDescriptions: mobilisedFleetDescriptions,
              travelToSite: _travelToSite,
              travelFromSite: _travelFromSite,
              miscellaneous: _miscellaneous,
              onCall: _onCall,
              comments: _comments,
              ticketNumber: _ticketNumber,
              concreteMix: concreteMixName,
              quantity: _quantity,
            );
          },
        ) ?? false; // Default to false if null
        final confirmationDialogEnd = DateTime.now();
        print('⏱️ [DIAGNOSTIC] Confirmation dialog completed in: ${confirmationDialogEnd.difference(confirmationDialogStart).inMilliseconds}ms');
        print('🔍 [CONFIRMATION] Dialog returned: $shouldSave');
      } catch (e, stackTrace) {
        print('❌ [CONFIRMATION] Error showing confirmation dialog: $e');
        print('❌ [CONFIRMATION] Stack trace: $stackTrace');
        await ErrorLogService.logError(
          location: 'Timesheet Screen - Confirmation Dialog',
          type: 'UI',
          description: 'Error showing confirmation dialog: $e',
          stackTrace: stackTrace,
        );
        // If dialog fails, ask user if they want to continue
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text('Could not show confirmation dialog: $e\n\nDo you want to save anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        shouldSave = shouldContinue ?? false;
      }

      if (!shouldSave) {
        setState(() {
          _isSaving = false;
        });
        print('🔍 [CONFIRMATION] User cancelled save - returning without saving');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Save cancelled'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return; // User cancelled
      }
      print('🔍 [CONFIRMATION] User confirmed save - proceeding with save...');

      // Build time period data matching the schema
      final now = DateTime.now();
      final timePeriodData = <String, dynamic>{
        'user_id': userId,
        if (projectId != null) 'project_id': projectId,
        if (largePlantId != null) 'large_plant_id': largePlantId,
        if (workshopTasksId != null) 'workshop_tasks_id': workshopTasksId,
        // In Fleet Mode, clear the other column when one is set (so edit from task→fleet or fleet→task works)
        if (_plantListMode && largePlantId != null) 'workshop_tasks_id': null,
        if (_plantListMode && workshopTasksId != null) 'large_plant_id': null,
        'work_date': _date, // Date format: 'yyyy-MM-dd'
        if (startTimestamp != null) 'start_time': startTimestamp.toIso8601String(),
        if (finishTimestamp != null) 'finish_time': finishTimestamp.toIso8601String(),
        'status': 'submitted', // approval_status enum (3-stage workflow)
        'submitted_at': now.toIso8601String(),
        'submitted_by': userId,
        'travel_to_site_min': travelToSiteMin,
        'travel_from_site_min': travelFromSiteMin,
        'on_call': _onCall,
        'misc_allowance_min': miscAllowanceMin,
        // Include materials only when at least one of Concrete Mix or Quantity is set
        if (_ticketNumber.isNotEmpty && (_concreteMix.isNotEmpty || _quantity.isNotEmpty))
          'concrete_ticket_no': int.tryParse(_ticketNumber),
        if (_concreteMix.isNotEmpty) 'concrete_mix_type': _concreteMix,
        if (_quantity.isNotEmpty) 'concrete_qty': double.tryParse(_quantity),
        if (_comments.isNotEmpty) 'comments': _comments,
        if (latitude != null) 'submission_lat': latitude,
        if (longitude != null) 'submission_lng': longitude,
        if (gpsAccuracy != null) 'submission_gps_accuracy': gpsAccuracy,
        if (distanceFromHome != null) 'distance_from_home': distanceFromHome,
        if (_calculatedTravelTime.isNotEmpty) 'travel_time_text': _calculatedTravelTime,
        'revision_number': 0,
        'offline_created': !_isOnline,
        'synced': _isOnline,
        // Note: breaks and fleet are stored in separate normalized tables:
        // time_period_breaks, time_period_used_fleet, time_period_mobilised_fleet
        // They are saved after creating the time_period record
      };

      String? timePeriodId;
      final isEditing = widget.timePeriodId != null && widget.timePeriodId!.isNotEmpty;

      if (_isOnline) {
        // Save directly to Supabase (create or update)
        try {
          if (isEditing) {
            // Update existing time period
            print('🔍 Attempting to update time_period with ID: ${widget.timePeriodId}');
            
            // Get old data before updating for revision tracking
            final oldTimePeriodData = await DatabaseService.readById('time_periods', widget.timePeriodId!);
            if (oldTimePeriodData == null) {
              throw Exception('Time period not found for update');
            }
            
            // Get current revision number
            final currentRevisionNumber = oldTimePeriodData['revision_number'] as int? ?? 0;
            
            // Track changes and get new revision number (if there are changes)
            final newRevisionNumber = await _trackTimePeriodChanges(
              widget.timePeriodId!,
              oldTimePeriodData,
              timePeriodData,
              currentRevisionNumber,
            );
            
            // Preserve the current status when editing - don't allow changing status via edit
            // Status will remain as 'submitted' or 'supervisor_approved' depending on current status
            // Only approvals change the status, not edits
            final currentStatus = oldTimePeriodData['status']?.toString() ?? 'submitted';
            timePeriodData['status'] = currentStatus;
            
            print('🔍 Time period data: $timePeriodData');
            final dbUpdateStart = DateTime.now();
            print('⏱️ [DIAGNOSTIC] Database update started at: ${dbUpdateStart.toIso8601String()}');
            
            // If there were changes, update revision tracking fields
            if (newRevisionNumber != null) {
              final now = DateTime.now();
              final currentUser = await AuthService.getCurrentUser();
              final authUserId = currentUser?.id;
              
              timePeriodData['revision_number'] = newRevisionNumber;
              timePeriodData['last_revised_at'] = now.toIso8601String();
              timePeriodData['updated_at'] = now.toIso8601String();
              if (authUserId != null) {
                timePeriodData['last_revised_by'] = authUserId; // auth.users.id (user_id)
              }
            }
            
            await DatabaseService.update('time_periods', widget.timePeriodId!, timePeriodData);
            final dbUpdateEnd = DateTime.now();
            print('⏱️ [DIAGNOSTIC] Database update completed in: ${dbUpdateEnd.difference(dbUpdateStart).inMilliseconds}ms');
            timePeriodId = widget.timePeriodId;
            print('✅ Time period updated successfully with ID: $timePeriodId');
            
            // Delete existing breaks, used fleet, and mobilised fleet before recreating
            await _deleteExistingBreaksAndFleet(timePeriodId!);
          } else {
            // Create new time period
            print('🔍 Attempting to create time_period with user_id: $userId');
            print('🔍 Time period data: $timePeriodData');
            final dbCreateStart = DateTime.now();
            print('⏱️ [DIAGNOSTIC] Database create started at: ${dbCreateStart.toIso8601String()}');
            final result = await DatabaseService.create('time_periods', timePeriodData);
            final dbCreateEnd = DateTime.now();
            print('⏱️ [DIAGNOSTIC] Database create completed in: ${dbCreateEnd.difference(dbCreateStart).inMilliseconds}ms');
            timePeriodId = result['id']?.toString();
            print('✅ Time period created successfully with ID: $timePeriodId');
            
            // Track original submission for revision history
            if (timePeriodId != null) {
              await _trackOriginalSubmission(timePeriodId);
            }
          }
        } catch (e) {
          print('❌ Error saving entry: $e');
          String errorMessage = isEditing 
              ? 'Failed to update entry. '
              : 'Failed to save entry. ';
          if (e.toString().contains('row-level security')) {
            errorMessage += 'Permission denied. Please check that you have permission to ${isEditing ? "update" : "create"} time periods.';
            if (_selectedEmployeeUserId != null && _selectedEmployeeUserId != userId) {
              errorMessage += ' Note: ${isEditing ? "Updating" : "Creating"} time periods for other employees may require admin permissions.';
            }
          } else {
            errorMessage += 'Error: ${e.toString()}';
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
        
        // Save breaks, used fleet and mobilised fleet to separate tables
        if (timePeriodId != null) {
          final breaksSaveStart = DateTime.now();
          print('⏱️ [DIAGNOSTIC] Starting breaks/fleet save at: ${breaksSaveStart.toIso8601String()}');
          
          // Save breaks
          if (_breaks.isNotEmpty) {
            for (int breakIndex = 0; breakIndex < _breaks.length; breakIndex++) {
              final breakData = _breaks[breakIndex];
              if (breakData['start']?.toString().isNotEmpty == true || 
                  breakData['finish']?.toString().isNotEmpty == true) {
                try {
                  // Convert break times to timestamps (combine date + time)
                  DateTime? breakStartTimestamp;
                  DateTime? breakEndTimestamp;
                  
                  if (_date.isNotEmpty && breakData['start']?.toString().isNotEmpty == true) {
                    try {
                      final dateTime = DateTime.parse(_date);
                      final timeParts = breakData['start']?.toString().split(':');
                      if (timeParts != null && timeParts.length == 2) {
                        breakStartTimestamp = DateTime(
                          dateTime.year,
                          dateTime.month,
                          dateTime.day,
                          int.parse(timeParts[0]),
                          int.parse(timeParts[1]),
                        );
                      }
                    } catch (e) {
                      print('⚠️ Error parsing break start time: $e');
                    }
                  }
                  
                  if (_date.isNotEmpty && breakData['finish']?.toString().isNotEmpty == true) {
                    try {
                      final dateTime = DateTime.parse(_date);
                      final timeParts = breakData['finish']?.toString().split(':');
                      if (timeParts != null && timeParts.length == 2) {
                        breakEndTimestamp = DateTime(
                          dateTime.year,
                          dateTime.month,
                          dateTime.day,
                          int.parse(timeParts[0]),
                          int.parse(timeParts[1]),
                        );
                      }
                    } catch (e) {
                      print('⚠️ Error parsing break end time: $e');
                    }
                  }
                  
                  // Calculate break duration in minutes (for logging only, not stored in DB)
                  int? breakDurationMin;
                  if (breakStartTimestamp != null && breakEndTimestamp != null) {
                    breakDurationMin = breakEndTimestamp.difference(breakStartTimestamp).inMinutes;
                  }
                  
                  final breakRecord = <String, dynamic>{
                    'time_period_id': timePeriodId,
                    if (breakStartTimestamp != null) 'break_start': breakStartTimestamp.toIso8601String(),
                    if (breakEndTimestamp != null) 'break_finish': breakEndTimestamp.toIso8601String(),
                    if (breakData['reason']?.toString().isNotEmpty == true) 'break_reason': breakData['reason'] ?? '',
                    'display_order': breakIndex, // Use the index to maintain order
                  };
                  
                  await DatabaseService.create('time_period_breaks', breakRecord);
                  print('✅ Saved break: ${breakData['start']} - ${breakData['finish']} (${breakDurationMin ?? 0} min)');
                } catch (e) {
                  print('⚠️ Error saving break: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Warning: Could not save break: ${e.toString()}'),
                        backgroundColor: Colors.orange,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              }
            }
          }
          
          // Save used fleet
          try {
            await _saveUsedFleet(timePeriodId);
          } catch (e) {
            print('❌ Error saving used fleet: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Warning: Could not save used fleet: ${e.toString()}'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
          
          // Save mobilised fleet
          try {
            await _saveMobilisedFleet(timePeriodId);
          } catch (e) {
            print('❌ Error saving mobilised fleet: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Warning: Could not save mobilised fleet: ${e.toString()}'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
          
          final breaksSaveEnd = DateTime.now();
          print('⏱️ [DIAGNOSTIC] Breaks/fleet save completed in: ${breaksSaveEnd.difference(breaksSaveStart).inMilliseconds}ms');
        }
        
        // Update users_data project history (only for projects, not fleet mode)
        if (!_plantListMode && projectId != null && _selectedProject.isNotEmpty) {
          await _updateUserProjectHistory(userId, _selectedProject, _date);
        }
        
        // DIAGNOSTIC: Calculate total save time
        final saveEndTime = DateTime.now();
        final totalSaveTime = saveEndTime.difference(saveStartTime);
        print('⏱️ [DIAGNOSTIC] Total save process completed in: ${totalSaveTime.inMilliseconds}ms (${totalSaveTime.inSeconds}s)');
        print('⏱️ [DIAGNOSTIC] Save process ended at: ${saveEndTime.toIso8601String()}');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Time period updated successfully.' : 'Entry saved successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Track if quantity was present (before clearing) - check BEFORE any modifications
        final hadQuantity = _quantity.isNotEmpty && _quantity.trim().isNotEmpty;
        final ticketNumberBeforeSave = _ticketNumber;
        bool ticketNumberIncremented = false;
        
        // AFTER successful save, if quantity is present, increment ticket number by 1 and clear quantity
        if (hadQuantity && _showMaterials && _ticketNumber.isNotEmpty) {
          // Increment ticket number for next entry
          final currentTicketNum = int.tryParse(_ticketNumber) ?? 0;
          final newTicketNum = currentTicketNum + 1;
          setState(() {
            _ticketNumber = newTicketNum.toString();
          });
          ticketNumberIncremented = true;
          // Update last_ticket_number in users_data with the NEW incremented value
          await _updateLastTicketNumber(_ticketNumber);
          // Clear quantity
          setState(() {
            _quantity = '';
          });
          print('✅ Incremented ticket number from $currentTicketNum to $newTicketNum and cleared quantity');
        } else if (_ticketNumber.isNotEmpty && _showMaterials) {
          // Update last_ticket_number in users_data if ticket number was used (without quantity)
          await _updateLastTicketNumber(ticketNumberBeforeSave);
        }
        
        // Clear Materials section after successful upload (only when not editing)
        if (!isEditing) {
          setState(() {
            // Don't clear ticket number if it was just incremented (keep it for next entry)
            if (!ticketNumberIncremented) {
              _ticketNumber = '';
            }
            _concreteMix = '';
            // Quantity is already cleared if it was present
            if (!hadQuantity) {
              _quantity = '';
            }
          });
        }
        
        // If editing, navigate back after a short delay with refresh flag
        if (isEditing) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              Navigator.of(context).pop(true); // Return true to indicate data changed
            }
          });
        }
      } else {
        // Save to offline queue
        // Store breaks and fleet data with the entry for later processing
        final offlineEntryData = Map<String, dynamic>.from(timePeriodData);
        offlineEntryData['_breaks'] = _breaks; // Store breaks for later
        offlineEntryData['_usedFleet'] = _usedFleet; // Store fleet for later
        offlineEntryData['_mobilisedFleet'] = _mobilisedFleet; // Store mobilised fleet for later
        
        await OfflineStorageService.addToQueue(offlineEntryData);
        await _updatePendingCount();
        
        // Track if quantity was present (before clearing) - check BEFORE any modifications
        final hadQuantityOffline = _quantity.isNotEmpty && _quantity.trim().isNotEmpty;
        final ticketNumberBeforeSaveOffline = _ticketNumber;
        bool ticketNumberIncrementedOffline = false;
        
        // AFTER successful offline save, if quantity is present, increment ticket number by 1 and clear quantity
        if (hadQuantityOffline && _showMaterials && _ticketNumber.isNotEmpty) {
          // Increment ticket number for next entry
          final currentTicketNum = int.tryParse(_ticketNumber) ?? 0;
          final newTicketNum = currentTicketNum + 1;
          setState(() {
            _ticketNumber = newTicketNum.toString();
          });
          ticketNumberIncrementedOffline = true;
          // Update last_ticket_number in users_data with the NEW incremented value
          await _updateLastTicketNumber(_ticketNumber);
          // Clear quantity
          setState(() {
            _quantity = '';
          });
          print('✅ Incremented ticket number from $currentTicketNum to $newTicketNum and cleared quantity (offline)');
        } else if (_ticketNumber.isNotEmpty && _showMaterials) {
          // Update last_ticket_number in users_data if ticket number was used (offline, without quantity)
          await _updateLastTicketNumber(ticketNumberBeforeSaveOffline);
        }
        
        // Clear Materials section after offline save
        if (!isEditing) {
          setState(() {
            // Don't clear ticket number if it was just incremented (keep it for next entry)
            if (!ticketNumberIncrementedOffline) {
              _ticketNumber = '';
            }
            _concreteMix = '';
            // Quantity is already cleared if it was present
            if (!hadQuantityOffline) {
              _quantity = '';
            }
          });
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Entry saved offline. ${_pendingCount} ${_pendingCount == 1 ? 'entry' : 'entries'} pending sync.'),
            backgroundColor: Colors.orange,
          ),
        );
      }


      // Reset form for next entry, setting start time to the finish time of the saved period
      // Preserve the date so user can continue entering for the same date
      print('🔍 [SAVE] Resetting form...');
      _resetForm(finishTime: _finishTime, preserveDate: true);
      print('🔍 [SAVE] Form reset complete - save process finished successfully');
    } catch (e, stackTrace) {
      print('❌ [SAVE] Error saving entry: $e');
      print('❌ [SAVE] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save entry: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      // Always reset the saving flag, even if there was an error
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Update last_ticket_number in users_data
  Future<void> _updateLastTicketNumber(String ticketNumber) async {
    if (_userData == null) {
      return; // Silently fail if user data not loaded
    }

    try {
      final ticketNum = int.tryParse(ticketNumber);
      if (ticketNum == null) {
        print('⚠️ Invalid ticket number format: $ticketNumber');
        return;
      }

      final updateData = <String, dynamic>{
        'last_ticket_number': ticketNum,
      };

      // users_data table uses id as primary key
      final recordId = _userData!['id']?.toString();
      if (recordId == null) {
        print('⚠️ Record ID not found in user data');
        return;
      }
      
      await SupabaseService.client
          .from('users_data')
          .update(updateData)
          .eq('id', recordId);
      
      print('✅ Updated last_ticket_number to $ticketNum');
      
      // Update local _userData to reflect the change
      if (_userData != null) {
        _userData!['last_ticket_number'] = ticketNum;
      }
    } catch (e) {
      print('❌ Error updating last_ticket_number: $e');
      // Don't throw - this is a non-critical update
    }
  }

  /// Increment the Google API call counter in system_settings
  Future<void> _incrementApiCallCounter() async {
    try {
      final settings = await SupabaseService.client
          .from('system_settings')
          .select('id, google_api_calls')
          .limit(1)
          .maybeSingle();

      if (settings != null) {
        final currentCount = (settings['google_api_calls'] as int?) ?? 0;
        await SupabaseService.client
            .from('system_settings')
            .update({'google_api_calls': currentCount + 1})
            .eq('id', settings['id'] as Object);
        print('✅ Incremented API call counter to ${currentCount + 1}');
      } else {
        await SupabaseService.client.from('system_settings').insert({
          'google_api_calls': 1,
          'google_api_saves': 0,
          'week_start': 1,
        });
        print('✅ Created system_settings record with API call count: 1');
      }
    } catch (e) {
      print('⚠️ Error incrementing API call counter: $e');
    }
  }

  /// Increment the Google API save counter in system_settings
  Future<void> _incrementApiSaveCounter() async {
    try {
      final settings = await SupabaseService.client
          .from('system_settings')
          .select('id, google_api_saves')
          .limit(1)
          .maybeSingle();

      if (settings != null) {
        final currentCount = (settings['google_api_saves'] as int?) ?? 0;
        await SupabaseService.client
            .from('system_settings')
            .update({'google_api_saves': currentCount + 1})
            .eq('id', settings['id'] as Object);
        print('✅ Incremented API save counter to ${currentCount + 1}');
      } else {
        await SupabaseService.client.from('system_settings').insert({
          'google_api_calls': 0,
          'google_api_saves': 1,
          'week_start': 1,
        });
        print('✅ Created system_settings record with API save count: 1');
      }
    } catch (e) {
      print('⚠️ Error incrementing API save counter: $e');
    }
  }

  /// Get Google Maps directions with caching
  Future<Map<String, dynamic>?> _getDirectionsWithCache(
    double homeLat,
    double homeLng,
    double projectLat,
    double projectLng, {
    String? userDisplayName,
    String? projectName,
  }) async {
    try {
      // Check cache first - use unique constraint on (home_latitude, home_longitude, project_latitude, project_longitude)
      try {
        // Try to find exact match using the unique constraint
        final cachedResult = await SupabaseService.client
            .from('google_api_calls')
            .select('travel_time_minutes, distance_kilometers, distance_text, travel_time_formatted, was_cached, display_name')
            .eq('home_latitude', homeLat)
            .eq('home_longitude', homeLng)
            .eq('project_latitude', projectLat)
            .eq('project_longitude', projectLng)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (cachedResult != null) {
          final travelTimeMinutes = cachedResult['travel_time_minutes'] as int?;
          final distanceKm = cachedResult['distance_kilometers'] as double?;
          
          if (travelTimeMinutes != null && distanceKm != null) {
            print('✅ Found cached directions');
            await _incrementApiSaveCounter();
            return {
              'travel_time_minutes': travelTimeMinutes,
              'distance_kilometers': distanceKm,
              'distance_text': cachedResult['distance_text'] as String?,
              'travel_time_formatted': cachedResult['travel_time_formatted'] as String?,
              'was_cached': true,
            };
          }
        }
      } catch (e) {
        print('⚠️ Error checking cache: $e, proceeding with API call...');
      }

      // No cached data - must use Google Maps API via Edge Function
      print('🔍 Calling Google Maps Directions API via Edge Function');
      await _incrementApiCallCounter();
      
      try {
        // Call Edge Function for Google Maps Directions API
        final response = await SupabaseService.client.functions.invoke(
          'get_directions',
          body: {
            'home_latitude': homeLat,
            'home_longitude': homeLng,
            'project_latitude': projectLat,
            'project_longitude': projectLng,
          },
        );
        
        if (response.status == 200 && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          
          if (data['success'] == true) {
            final travelTimeMinutes = data['travel_time_minutes'] as int?;
            final distanceKm = data['distance_kilometers'] as double?;
            final distanceText = data['distance_text'] as String?;
            final travelTimeFormatted = data['travel_time_formatted'] as String?;
            
            if (travelTimeMinutes != null && distanceKm != null) {
              // Build display_name for cache: "User Name - Project Name"
              String? displayName;
              if (userDisplayName != null && userDisplayName.isNotEmpty && 
                  projectName != null && projectName.isNotEmpty) {
                displayName = '$userDisplayName - $projectName';
              }
              
              // Save to cache
              try {
                final cacheData = <String, dynamic>{
                  'home_latitude': homeLat,
                  'home_longitude': homeLng,
                  'project_latitude': projectLat,
                  'project_longitude': projectLng,
                  'distance_kilometers': distanceKm,
                  'distance_text': distanceText ?? '${distanceKm.toStringAsFixed(1)} km',
                  'travel_time_minutes': travelTimeMinutes,
                  'travel_time_formatted': travelTimeFormatted ?? '${(travelTimeMinutes ~/ 60).toString().padLeft(2, '0')}:${(travelTimeMinutes % 60).toString().padLeft(2, '0')}',
                  'time_stamp': DateTime.now().toIso8601String(),
                  'was_cached': false,
                };
                
                if (displayName != null) {
                  cacheData['display_name'] = displayName;
                }
                
                await SupabaseService.client.from('google_api_calls').insert(cacheData);
                print('✅ Saved directions to cache');
              } catch (e) {
                print('⚠️ Error saving to cache: $e');
                // Continue even if cache save fails
              }
              
              return {
                'travel_time_minutes': travelTimeMinutes,
                'distance_kilometers': distanceKm,
                'distance_text': distanceText ?? '${distanceKm.toStringAsFixed(1)} km',
                'travel_time_formatted': travelTimeFormatted ?? '${(travelTimeMinutes ~/ 60).toString().padLeft(2, '0')}:${(travelTimeMinutes % 60).toString().padLeft(2, '0')}',
                'was_cached': false,
              };
            }
          } else {
            // API returned error
            final errorMsg = data['error']?.toString() ?? 'Unknown error';
            print('❌ Directions API error: $errorMsg');
            await ErrorLogService.logError(
              location: 'Timesheet Screen - Travel Calculation',
              type: 'GPS',
              description: 'Google Maps Directions API error: $errorMsg for coordinates: home($homeLat, $homeLng) to project($projectLat, $projectLng)',
            );
          }
        } else {
          // HTTP error
          print('❌ Directions API HTTP error: ${response.status}');
          await ErrorLogService.logError(
            location: 'Timesheet Screen - Travel Calculation',
            type: 'GPS',
            description: 'Google Maps Directions API HTTP error: ${response.status} for coordinates: home($homeLat, $homeLng) to project($projectLat, $projectLng)',
          );
        }
      } catch (e) {
        print('❌ Error calling Directions Edge Function: $e');
        await ErrorLogService.logError(
          location: 'Timesheet Screen - Travel Calculation',
          type: 'GPS',
          description: 'Error calling get_directions Edge Function: $e for coordinates: home($homeLat, $homeLng) to project($projectLat, $projectLng)',
        );
      }
      
      // Return null to indicate failure
      return null;
    } catch (e) {
      print('❌ Error getting directions: $e');
      return null;
    }
  }

  /// Show dialog to select travel type
  Future<String?> _showTravelTypeDialog() async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Travel Type'),
          content: const Text('How would you like to apply the travel time?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('to'),
              child: const Text('Travel To Site'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('from'),
              child: const Text('Travel From Site'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('both'),
              child: const Text('Both'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleCheckTravel() async {
    // Check and request location permissions
    if (!kIsWeb) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are required to calculate travel. Please grant location permissions in app settings.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied. Please enable them in app settings.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
    }
    
    // Clear existing travel data first
    setState(() {
      _travelToSiteTime = '00:00';
      _travelToSite = '';
      _travelFromSiteTime = '00:00';
      _travelFromSite = '';
      _calculatedTravelTime = '';
      _calculatedDistance = '';
      _totalTravelTimeMinutes = 0;
      _availableAllowanceMinutes = 0;
      _availableAllowanceTotalMinutes = 0;
      _roundedOneWay = '';
      _roundedTwoWay = '';
      _totalDistanceKm = 0.0;
    });
    
    // Step 1: Get Home GPS of User Time Period is being logged for
    Map<String, dynamic>? employeeUserData;
    
    if (_recordForAnotherPerson && _selectedEmployeeUserId != null && _selectedEmployeeUserId!.isNotEmpty) {
      // Get the selected employee's user data
      final selectedUserId = _selectedEmployeeUserId!; // Store in local variable for null safety
      try {
        final response = await SupabaseService.client
            .from('users_data')
            .select()
            .eq('user_id', selectedUserId)
            .maybeSingle();
        
        if (response != null) {
          employeeUserData = response;
        }
      } catch (e) {
        print('❌ Error loading employee user data: $e');
      }
    } else {
      // Use logged-in user's data
      employeeUserData = _userData;
    }

    if (employeeUserData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User data not loaded. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final homeLat = employeeUserData['home_latitude'];
    final homeLng = employeeUserData['home_longitude'];

    if (homeLat == null || homeLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User has no Home GPS data. Please set home address in profile.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Step 2: Get GPS Location of Selected Project
    if (_selectedProject.isEmpty || !_projectSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No project selected. Please select a project first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Map<String, dynamic>? selectedProjectData;
    try {
      selectedProjectData = _allProjects.firstWhere(
        (p) => p['project_name']?.toString() == _selectedProject,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected project not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final projectLat = selectedProjectData['latitude'];
    final projectLng = selectedProjectData['longitude'];

    if (projectLat == null || projectLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected project has no GPS data.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Step 3 & 4: Check cache and get directions
      // Get user display name and project name for display_name field
      final userDisplayName = employeeUserData['display_name']?.toString() ?? '';
      final directionsResult = await _getDirectionsWithCache(
        (homeLat as num).toDouble(),
        (homeLng as num).toDouble(),
        (projectLat as num).toDouble(),
        (projectLng as num).toDouble(),
        userDisplayName: userDisplayName,
        projectName: _selectedProject,
      );

      if (directionsResult == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error calculating travel directions.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final travelTimeMinutes = directionsResult['travel_time_minutes'] as int;
      final distanceKm = directionsResult['distance_kilometers'] as double;
      final distanceText = directionsResult['distance_text'] as String?;
      final travelTimeFormatted = directionsResult['travel_time_formatted'] as String?;
      final wasCached = directionsResult['was_cached'] as bool? ?? false;

      // Step 5: Ask user which travel type to apply
      final travelType = await _showTravelTypeDialog();
      if (travelType == null) {
        return; // User cancelled
      }

      // Step 6 & 7: Apply complex calculation logic
      final timeOptions = _generateTimeOptions();
      String? travelToSiteTime;
      String? travelFromSiteTime;

      if (travelType == 'to' || travelType == 'from') {
        // Single direction
        // All travel time up to 1 hour is ineligible, only excess over 1 hour is eligible
        int adjustedMinutes = travelTimeMinutes > 60 ? travelTimeMinutes - 60 : 0;

        // Round to nearest 15 minutes
        final roundedMinutes = ((adjustedMinutes / 15).round() * 15);
        final hours = roundedMinutes ~/ 60;
        final mins = roundedMinutes % 60;
        final timeString = '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';

        // Find closest matching time option
        String? closestTime;
        int minDiff = 9999;
        for (final option in timeOptions) {
          final optionMins = _timeStringToMinutes(option);
          final diff = (roundedMinutes - optionMins).abs();
          if (diff < minDiff) {
            minDiff = diff;
            closestTime = option;
          }
        }

        if (travelType == 'to') {
          travelToSiteTime = closestTime ?? timeString;
        } else {
          travelFromSiteTime = closestTime ?? timeString;
        }
      } else if (travelType == 'both') {
        // Both directions
        // All travel time up to 1 hour is ineligible, only excess over 1 hour is eligible
        int adjustedMinutes = travelTimeMinutes > 60 ? travelTimeMinutes - 60 : 0;
        
        // Multiply by 2
        int totalMinutes = adjustedMinutes * 2;

        // Round to nearest 15 minutes
        final roundedTotal = ((totalMinutes / 15).round() * 15);
        final intervals = roundedTotal ~/ 15;

        int travelToMinutes;
        int travelFromMinutes;

        if (intervals % 2 == 0) {
          // Even number of 15-minute intervals
          final half = roundedTotal ~/ 2;
          travelToMinutes = half;
          travelFromMinutes = half;
        } else {
          // Odd number of 15-minute intervals
          // Subtract 15 minutes from total, add to Travel To Site, then split balance equally
          final balance = roundedTotal - 15;
          final halfBalance = balance ~/ 2;
          travelToMinutes = 15 + halfBalance;
          travelFromMinutes = halfBalance;
        }

        // Convert to time strings and find closest matches
        final toHours = travelToMinutes ~/ 60;
        final toMins = travelToMinutes % 60;
        final toTimeString = '${toHours.toString().padLeft(2, '0')}:${toMins.toString().padLeft(2, '0')}';

        final fromHours = travelFromMinutes ~/ 60;
        final fromMins = travelFromMinutes % 60;
        final fromTimeString = '${fromHours.toString().padLeft(2, '0')}:${fromMins.toString().padLeft(2, '0')}';

        // Find closest matching time options
        String? closestToTime;
        String? closestFromTime;
        int minToDiff = 9999;
        int minFromDiff = 9999;

        for (final option in timeOptions) {
          final optionMins = _timeStringToMinutes(option);
          final toDiff = (travelToMinutes - optionMins).abs();
          final fromDiff = (travelFromMinutes - optionMins).abs();
          
          if (toDiff < minToDiff) {
            minToDiff = toDiff;
            closestToTime = option;
          }
          if (fromDiff < minFromDiff) {
            minFromDiff = fromDiff;
            closestFromTime = option;
          }
        }

        travelToSiteTime = closestToTime ?? toTimeString;
        travelFromSiteTime = closestFromTime ?? fromTimeString;
      }

      // Step 8: Calculate travel summary
      // All travel time up to 1 hour is ineligible, only excess over 1 hour is eligible
      final adjustedMinutes = travelTimeMinutes > 60 ? travelTimeMinutes - 60 : 0;
      final totalAdjusted = adjustedMinutes * 2; // For two-way
      final roundedTotal = ((totalAdjusted / 15).round() * 15);
      final intervals = roundedTotal ~/ 15;
      
      String roundedOneWayStr = '';
      String roundedTwoWayStr = '';
      
      // Calculate rounded one way
      final roundedOneWayMins = ((adjustedMinutes / 15).round() * 15);
      final oneWayHours = roundedOneWayMins ~/ 60;
      final oneWayMins = roundedOneWayMins % 60;
      roundedOneWayStr = '$oneWayHours:${oneWayMins.toString().padLeft(2, '0')}';
      
      // Calculate rounded two way
      if (intervals % 2 == 0) {
        final half = roundedTotal ~/ 2;
        final toHours = half ~/ 60;
        final toMins = half % 60;
        roundedTwoWayStr = '$toHours:${toMins.toString().padLeft(2, '0')} & $toHours:${toMins.toString().padLeft(2, '0')}';
      } else {
        final balance = roundedTotal - 15;
        final halfBalance = balance ~/ 2;
        final toMinutes = 15 + halfBalance;
        final fromMinutes = halfBalance;
        final toHours = toMinutes ~/ 60;
        final toMins = toMinutes % 60;
        final fromHours = fromMinutes ~/ 60;
        final fromMins = fromMinutes % 60;
        roundedTwoWayStr = '$toHours:${toMins.toString().padLeft(2, '0')} & $fromHours:${fromMins.toString().padLeft(2, '0')}';
      }
      
      // Format available allowance (variables removed as unused)

      // Step 9: Update UI with results
      final travelTimeString = travelTimeFormatted ?? 
          '${(travelTimeMinutes ~/ 60).toString().padLeft(2, '0')}:${(travelTimeMinutes % 60).toString().padLeft(2, '0')}';
      final displayDistance = distanceText ?? '${distanceKm.toStringAsFixed(1)} km';

      setState(() {
        if (travelToSiteTime != null) {
          _travelToSiteTime = travelToSiteTime;
          _travelToSite = _timeStringToMinutes(travelToSiteTime).toString();
        }
        if (travelFromSiteTime != null) {
          _travelFromSiteTime = travelFromSiteTime;
          _travelFromSite = _timeStringToMinutes(travelFromSiteTime).toString();
        }
        _calculatedTravelTime = travelTimeString;
        _calculatedDistance = displayDistance;
        _totalTravelTimeMinutes = travelTimeMinutes;
        _availableAllowanceMinutes = adjustedMinutes;
        _availableAllowanceTotalMinutes = totalAdjusted;
        _roundedOneWay = roundedOneWayStr;
        _roundedTwoWay = roundedTwoWayStr;
        _totalDistanceKm = distanceKm;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Travel calculated: $displayDistance, '
            'Time: $travelTimeString${wasCached ? ' (from cache)' : ''}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('❌ Error calculating travel: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error calculating travel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleFindNearestProject() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location services are disabled. Please enable them.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check and request location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are required to find the nearest job. Please grant location permissions in app settings.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied. Please enable them in app settings.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    // If this is "Find Next", don't clear selection - just add to found list
    // If this is "Find Nearest Job", reset the found list
    if (_findNearestButtonText == 'Find Nearest Job') {
      setState(() {
        _projectFilter = '';
        _projectFilterResetCounter++; // Increment counter to force filter field to rebuild
        _selectedProject = '';
        _projectSelected = false;
        _foundNearestProjects = []; // Reset found projects list
        _isFindingNearest = true;
      });
    } else {
      // "Find Next" - add current selection to found list if not already there
      setState(() {
        if (_selectedProject.isNotEmpty && !_foundNearestProjects.contains(_selectedProject)) {
          _foundNearestProjects.add(_selectedProject);
        }
        _isFindingNearest = true;
      });
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: kIsWeb
            ? WebSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 10),
              )
            : AndroidSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 10),
              ),
      );

      // Find nearest project by calculating distance, excluding already found projects
      Map<String, dynamic>? nearestProject;
      double? minDistance;

      for (final project in _allProjects) {
        final projectName = project['project_name']?.toString() ?? '';
        // Skip if this project was already found
        if (_foundNearestProjects.contains(projectName)) {
          continue;
        }
        
        final lat = project['latitude'];
        final lng = project['longitude'];
        if (lat != null && lng != null) {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            (lat as num).toDouble(),
            (lng as num).toDouble(),
          );

          if (nearestProject == null || distance < minDistance!) {
            nearestProject = project;
            minDistance = distance;
          }
        }
      }

      if (nearestProject != null) {
        final projectName = nearestProject['project_name']?.toString() ?? '';
        setState(() {
          _selectedProject = projectName;
          _selectedProjectDescription = projectName; // For projects, description is the name
          _projectSelected = true;
          _findNearestButtonText = 'Find Next';
          // Add to found list if not already there
          if (!_foundNearestProjects.contains(projectName)) {
            _foundNearestProjects.add(projectName);
          }
        });

        final distanceKm = (minDistance! / 1000).toStringAsFixed(1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nearest project: $projectName ($distanceKm km)'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // No more projects found - reset to "Find Nearest Job"
        setState(() {
          _findNearestButtonText = 'Find Nearest Job';
          _foundNearestProjects = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No more projects with location data found.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, stackTrace) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error finding nearest project: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Log error to error_log table
      try {
        await ErrorLogService.logError(
          location: 'Timesheet Screen - Find Nearest Project',
          type: 'GPS',
          description: 'Error finding nearest project: $e',
          stackTrace: stackTrace,
        );
      } catch (logError) {
        // If logging fails, at least print it
        print('❌ Error finding nearest project: $e');
        print('❌ Failed to log error: $logError');
      }
    } finally {
      setState(() {
        _isFindingNearest = false;
      });
    }
  }

  Future<void> _handleFindLastJob() async {
    // Check if employee is selected
    final hasEmployee = (_selectedEmployeeUserId != null && _selectedEmployeeUserId!.isNotEmpty) || 
                        (_selectedEmployee.isNotEmpty);
    if (!hasEmployee) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an employee first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Clear filter and project selection before finding last job
    setState(() {
      _projectFilter = '';
      _projectFilterResetCounter++; // Increment counter to force filter field to rebuild
      _selectedProject = '';
      _projectSelected = false;
      _isFindingLast = true;
    });

    try {
      // Get user_id - either from stored user_id or from current user
      String? userId;
      if (_selectedEmployeeUserId != null && _selectedEmployeeUserId!.isNotEmpty) {
        userId = _selectedEmployeeUserId;
      } else {
        // Current user
        userId = _currentUser?['id']?.toString();
      }

      if (userId == null || userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find user ID.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get user's project history from users_data
      final userDataResponse = await DatabaseService.read(
        'users_data',
        filterColumn: 'user_id',
        filterValue: userId.toString(),
        limit: 1,
      );

      if (userDataResponse.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User data not found.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final userData = userDataResponse.first;
      
      // Collect projects from project_1 to project_10 with their timestamps
      final List<Map<String, dynamic>> lastJobs = [];
      for (int i = 1; i <= 10; i++) {
        final projectName = userData['project_$i']?.toString();
        final changedAt = userData['project_${i}_changed_at']?.toString();
        if (projectName != null && projectName.isNotEmpty) {
          lastJobs.add({
            'project_name': projectName,
            'changed_at': changedAt,
            'index': i,
          });
        }
      }

      // Sort by changed_at date in descending order (most recent first)
      lastJobs.sort((a, b) {
        final aDate = a['changed_at']?.toString();
        final bDate = b['changed_at']?.toString();
        
        // If both have dates, compare them
        if (aDate != null && aDate.isNotEmpty && bDate != null && bDate.isNotEmpty) {
          try {
            final aDateTime = DateTime.parse(aDate);
            final bDateTime = DateTime.parse(bDate);
            return bDateTime.compareTo(aDateTime); // Descending order (newest first)
          } catch (e) {
            // If parsing fails, keep original order
            return 0;
          }
        }
        
        // If only one has a date, prioritize it
        if (aDate != null && aDate.isNotEmpty) return -1;
        if (bDate != null && bDate.isNotEmpty) return 1;
        
        // If neither has a date, keep original order
        return 0;
      });

      if (lastJobs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No previous projects found.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show dialog to browse through projects one at a time
      await _showLastJobsDialog(lastJobs);
    } catch (e) {
      print('❌ Error finding last job: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error finding last job: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isFindingLast = false;
      });
    }
  }

  Future<void> _showLastJobsDialog(List<Map<String, dynamic>> lastJobs) async {
    int currentIndex = 0;
    
    while (currentIndex < lastJobs.length) {
      final job = lastJobs[currentIndex];
      final projectName = job['project_name'] as String;
      final changedAtStr = job['changed_at'] as String?;
      
      // Format date
      String dateText = 'Date not available';
      if (changedAtStr != null && changedAtStr.isNotEmpty) {
        try {
          final dateTime = DateTime.parse(changedAtStr);
          dateText = DateFormat('EEEE, d MMM yyyy').format(dateTime);
        } catch (e) {
          print('Error parsing date: $e');
        }
      }

      // Get project details
      Map<String, dynamic>? projectDetails;
      try {
        projectDetails = _allProjects.firstWhere(
          (p) => p['project_name']?.toString() == projectName,
          orElse: () => <String, dynamic>{},
        );
      } catch (e) {
        print('Project not found in list: $e');
      }

      final result = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
          title: Text('Last Job ${currentIndex + 1} of ${lastJobs.length}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(projectName, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              Text(
                'Date Last Used:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(dateText),
              if (projectDetails != null && projectDetails.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Client Name:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(projectDetails['client_name']?.toString() ?? 'Not specified'),
                const SizedBox(height: 8),
                Text(
                  'Description of Work:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(projectDetails['description_of_work']?.toString() ?? 'Not specified'),
              ],
            ],
          ),
          actions: [
            // Two-row button layout at bottom of popup
            // Buttons centered at 1/3 and 2/3 width positions
            Builder(
              builder: (context) {
                final buttonWidth = 120.0;
                
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top row: Previous (left third) and Skip (right third)
                    Row(
                      children: [
                        // Left third - centered Previous button
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: currentIndex > 0
                                ? ElevatedButton(
                                    onPressed: () => Navigator.of(context).pop('previous'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.yellow,
                                      fixedSize: Size(buttonWidth, 40),
                                    ),
                                    child: const Text('Previous'),
                                  )
                                : const SizedBox(width: 120),
                          ),
                        ),
                        // Middle third - empty spacer
                        const Expanded(flex: 1, child: SizedBox()),
                        // Right third - centered Skip button
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop('skip'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.yellow,
                                fixedSize: Size(buttonWidth, 40),
                              ),
                              child: const Text('Skip'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Bottom row: Cancel (left third) and Select (right third)
                    Row(
                      children: [
                        // Left third - centered Cancel button
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop('cancel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.black,
                                fixedSize: Size(buttonWidth, 40),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                        ),
                        // Middle third - empty spacer
                        const Expanded(flex: 1, child: SizedBox()),
                        // Right third - centered Select button
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(projectName),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.black,
                                fixedSize: Size(buttonWidth, 40),
                              ),
                              child: const Text('Select'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );

      if (result == 'cancel') {
        // User cancelled - exit the dialog
        return;
      } else if (result == projectName) {
        // User selected this project
        setState(() {
          _selectedProject = projectName;
          _selectedProjectDescription = projectName; // For projects, description is the name
          _projectSelected = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project selected.'),
            backgroundColor: Colors.green,
          ),
        );
        return; // Exit the loop
      } else if (result == 'skip') {
        // Move to next project
        currentIndex++;
      } else if (result == 'previous') {
        // Move to previous project
        if (currentIndex > 0) {
          currentIndex--;
        }
      }
    }
  }

  Future<void> _updateUserProjectHistory(String userId, String projectName, String workDate) async {
    try {
      // Get current user data
      final userDataResponse = await DatabaseService.read(
        'users_data',
        filterColumn: 'user_id',
        filterValue: userId,
        limit: 1,
      );

      if (userDataResponse.isEmpty) {
        print('⚠️ User data not found for project history update');
        return;
      }

      final userData = userDataResponse.first;
      
      // Check if project_name is already in project_1 to project_10
      int existingIndex = -1;
      for (int i = 1; i <= 10; i++) {
        final existingProject = userData['project_$i']?.toString();
        if (existingProject == projectName) {
          existingIndex = i;
          break;
        }
      }

      final updateData = <String, dynamic>{};
      final workDateTime = DateTime.parse(workDate);

      if (existingIndex == -1) {
        // Project not found - shift everything down and add to project_1
        for (int i = 9; i >= 1; i--) {
          final projectValue = userData['project_$i']?.toString();
          final timestampValue = userData['project_${i}_changed_at']?.toString();
          if (projectValue != null && projectValue.isNotEmpty) {
            updateData['project_${i + 1}'] = projectValue;
          } else {
            updateData['project_${i + 1}'] = null;
          }
          if (timestampValue != null && timestampValue.isNotEmpty) {
            updateData['project_${i + 1}_changed_at'] = timestampValue;
          } else {
            updateData['project_${i + 1}_changed_at'] = null;
          }
        }
        // Set project_1
        updateData['project_1'] = projectName;
        updateData['project_1_changed_at'] = workDateTime.toIso8601String();
      } else {
        // Project found - move it to project_1 and sort others
        final projects = <Map<String, dynamic>>[];
        
        // Collect all projects with their timestamps
        for (int i = 1; i <= 10; i++) {
          final projName = userData['project_$i']?.toString();
          final timestamp = userData['project_${i}_changed_at']?.toString();
          if (projName != null && projName.isNotEmpty) {
            projects.add({
              'name': projName,
              'timestamp': timestamp,
              'original_index': i,
            });
          }
        }

        // Remove the existing project from the list
        projects.removeWhere((p) => p['name'] == projectName);

        // Sort by timestamp (most recent first)
        projects.sort((a, b) {
          final aTime = a['timestamp'] as String?;
          final bTime = b['timestamp'] as String?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          try {
            final aDate = DateTime.parse(aTime);
            final bDate = DateTime.parse(bTime);
            return bDate.compareTo(aDate);
          } catch (e) {
            return 0;
          }
        });

        // Build update data: project_1 is the selected project, then sorted others
        updateData['project_1'] = projectName;
        updateData['project_1_changed_at'] = workDateTime.toIso8601String();
        
        for (int i = 0; i < projects.length && i < 9; i++) {
          updateData['project_${i + 2}'] = projects[i]['name'];
          updateData['project_${i + 2}_changed_at'] = projects[i]['timestamp'];
        }
        
        // Clear remaining slots
        for (int i = projects.length + 2; i <= 10; i++) {
          updateData['project_$i'] = null;
          updateData['project_${i}_changed_at'] = null;
        }
      }

      // Update users_data
      await DatabaseService.update(
        'users_data',
        userData['id'].toString(),
        updateData,
      );

      print('✅ Updated user project history');
    } catch (e) {
      print('❌ Error updating user project history: $e');
      // Don't throw - this is a non-critical update
    }
  }

  void _handleRecallFleet() {
    if (_userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile not found. Saved fleet cannot be recalled.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final savedFleet = <String>[];
    for (int i = 1; i <= 6; i++) {
      final fleet = _userData!['fleet_$i']?.toString();
      if (fleet != null && fleet.isNotEmpty) {
        savedFleet.add(fleet);
      }
    }

    if (savedFleet.isNotEmpty) {
      setState(() {
        _usedFleet = savedFleet;
      });
      
      // Immediately look up descriptions for all recalled fleet numbers
      // (no debounce needed since we're loading saved data)
      for (int i = 0; i < savedFleet.length; i++) {
        final fleetNumber = savedFleet[i].toUpperCase().trim();
        if (fleetNumber.isNotEmpty && _allPlant.isNotEmpty) {
          final plant = _allPlant.firstWhere(
            (p) {
              final dbPlantNo = p['plant_no']?.toString() ?? '';
              return dbPlantNo.toUpperCase().trim() == fleetNumber;
            },
            orElse: () => <String, dynamic>{},
          );
          
          // Use plant_description instead of short_description
          final plantDesc = plant.isNotEmpty 
              ? (plant['plant_description']?.toString() ?? plant['short_description']?.toString() ?? '')
              : '';
          
          // Update description cache immediately
          final cacheKey = 'u_$i';
          if (plantDesc.isNotEmpty) {
            _fleetDescriptions[cacheKey] = plantDesc;
          } else {
            _fleetDescriptions.remove(cacheKey);
          }
        }
      }
      
      // Trigger rebuild to show descriptions
      setState(() {});
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved fleet information has been loaded.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have any fleet saved in your profile.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Save used fleet to time_period_used_fleet table (normalized schema)
  /// Each fleet item is saved as a separate row
  Future<void> _saveUsedFleet(String timePeriodId) async {
    try {
      int savedCount = 0;
      
      for (final plantNo in _usedFleet) {
        if (plantNo.trim().isEmpty) continue;
        
        final plantNoUpper = plantNo.trim().toUpperCase();
        
        // Look up the plant ID from _allPlant using plant_no
        try {
          final plant = _allPlant.firstWhere(
            (p) {
              final dbPlantNo = p['plant_no']?.toString() ?? '';
              return dbPlantNo.toUpperCase().trim() == plantNoUpper;
            },
            orElse: () => <String, dynamic>{},
          );
          
          if (plant.isNotEmpty) {
            final plantId = plant['id']?.toString();
            if (plantId != null && plantId.isNotEmpty) {
              // Verify the plant ID actually exists in the database (check RLS)
              try {
                final verifyPlant = await DatabaseService.read(
                  'large_plant',
                  filterColumn: 'id',
                  filterValue: plantId,
                  limit: 1,
                );
                
                if (verifyPlant.isEmpty) {
                  print('⚠️ Warning: Plant ID $plantId (plant_no: $plantNoUpper) not accessible - may be filtered by RLS');
                  continue; // Skip this plant
                }
                
                // Create one row per fleet item in normalized table
                final fleetData = {
                  'time_period_id': timePeriodId,
                  'large_plant_id': plantId,
                };
                
                await DatabaseService.create('time_period_used_fleet', fleetData);
                savedCount++;
                print('✅ Saved used fleet: $plantNoUpper (ID: $plantId)');
              } catch (e) {
                print('⚠️ Error verifying plant $plantNoUpper (ID: $plantId): $e');
                continue;
              }
            } else {
              print('⚠️ Warning: Plant $plantNoUpper found but has no ID');
            }
          } else {
            print('⚠️ Warning: Plant number $plantNoUpper not found in large_plant table');
          }
        } catch (e) {
          print('⚠️ Error looking up plant $plantNoUpper: $e');
        }
      }
      
      if (savedCount > 0) {
        print('✅ Saved $savedCount used fleet item(s) to time_period_used_fleet');
      } else {
        print('ℹ️ No valid used fleet items to save');
      }
    } catch (e) {
      print('❌ Error saving used fleet: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Save mobilised fleet to time_period_mobilised_fleet table (normalized schema)
  /// Each fleet item is saved as a separate row
  Future<void> _saveMobilisedFleet(String timePeriodId) async {
    try {
      int savedCount = 0;
      
      for (final plantNo in _mobilisedFleet) {
        if (plantNo.trim().isEmpty) continue;
        
        final plantNoUpper = plantNo.trim().toUpperCase();
        
        // Look up the plant ID from _allPlant using plant_no
        try {
          final plant = _allPlant.firstWhere(
            (p) {
              final dbPlantNo = p['plant_no']?.toString() ?? '';
              return dbPlantNo.toUpperCase().trim() == plantNoUpper;
            },
            orElse: () => <String, dynamic>{},
          );
          
          if (plant.isNotEmpty) {
            final plantId = plant['id']?.toString();
            if (plantId != null && plantId.isNotEmpty) {
              // Create one row per fleet item in normalized table
              final fleetData = {
                'time_period_id': timePeriodId,
                'large_plant_id': plantId,
                // 'distance_km': null, // Optional - can add distance tracking later
              };
              
              await DatabaseService.create('time_period_mobilised_fleet', fleetData);
              savedCount++;
              print('✅ Saved mobilised fleet: $plantNoUpper (ID: $plantId)');
            } else {
              print('⚠️ Warning: Plant $plantNoUpper found but has no ID');
            }
          } else {
            print('⚠️ Warning: Plant number $plantNoUpper not found in large_plant table');
          }
        } catch (e) {
          print('⚠️ Error looking up plant $plantNoUpper: $e');
        }
      }
      
      if (savedCount > 0) {
        print('✅ Saved $savedCount mobilised fleet item(s) to time_period_mobilised_fleet');
      } else {
        print('ℹ️ No valid mobilised fleet items to save');
      }
    } catch (e) {
      print('❌ Error saving mobilised fleet: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Track original submission when creating a new time period
  Future<void> _trackOriginalSubmission(String timePeriodId) async {
    try {
      print('📝 Tracking original submission for time period: $timePeriodId');
      
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
      
      // Try to get name from users_setup first, then users_data
      final userSetup = await UserService.getCurrentUserSetup();
      if (userSetup != null && userSetup['display_name'] != null) {
        changedByName = userSetup['display_name']?.toString();
      } else if (currentUserData['forename'] != null || currentUserData['surname'] != null) {
        final forename = currentUserData['forename']?.toString() ?? '';
        final surname = currentUserData['surname']?.toString() ?? '';
        changedByName = '$forename $surname'.trim();
      }
      
      // Get role from users_data or users_setup
      if (currentUserData['role'] != null) {
        changedByRole = currentUserData['role']?.toString();
      } else if (userSetup != null && userSetup['role'] != null) {
        changedByRole = userSetup['role']?.toString();
      }
      
      // Get the time period to get initial revision number
      final timePeriod = await DatabaseService.readById('time_periods', timePeriodId);
      if (timePeriod == null) {
        print('⚠️ Could not load time period for revision tracking');
        return;
      }
      
      final revisionNumber = timePeriod['revision_number'] as int? ?? 0;
      
      // Create revision records for all fields that were set during creation
      final fieldsToTrack = [
        'work_date',
        'start_time',
        'finish_time',
        'project_id',
        'large_plant_id',
        'workshop_tasks_id',
        'travel_to_site_min',
        'travel_from_site_min',
        'distance_from_home',
        'travel_time_text',
        'on_call',
        'misc_allowance_min',
        'concrete_ticket_no',
        'concrete_mix_type',
        'concrete_qty',
        'comments',
      ];
      
      for (final fieldName in fieldsToTrack) {
        final newValue = timePeriod[fieldName];
        if (newValue != null) {
          try {
            await DatabaseService.create('time_period_revisions', {
              'time_period_id': timePeriodId,
              'revision_number': revisionNumber,
              'changed_by': changedById, // users_data.id (primary key)
              'changed_by_name': changedByName,
              'changed_by_role': changedByRole,
              'change_type': 'user_submission',
              'workflow_stage': 'submitted',
              'field_name': fieldName,
              'old_value': null, // Original submission has no old value
              'new_value': newValue.toString(),
              'change_reason': null,
              'is_revision': false, // Original submission is not a revision
              'is_approval': false,
              'is_edit': false,
              'original_submission': true,
            });
            print('✅ Tracked original submission for field: $fieldName');
          } catch (e) {
            print('⚠️ Error tracking original submission for field $fieldName: $e');
          }
        }
      }
      
      print('✅ Original submission tracking completed');
    } catch (e, stackTrace) {
      print('❌ Error tracking original submission: $e');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Track Original Submission',
        type: 'Database',
        description: 'Failed to track original submission: $e',
        stackTrace: stackTrace,
      );
    }
  }
  
  /// Track changes when editing a time period
  /// Returns the new revision number (or null if no changes)
  Future<int?> _trackTimePeriodChanges(String timePeriodId, Map<String, dynamic> oldData, Map<String, dynamic> newData, int currentRevisionNumber) async {
    try {
      print('📝 Tracking changes for time period: $timePeriodId');
      
      // Get current user's users_data record to get the id for changed_by
      final currentUserData = await UserService.getCurrentUserData();
      if (currentUserData == null) {
        print('⚠️ Could not get current user data for revision tracking');
        return null;
      }
      
      final changedById = currentUserData['id']?.toString();
      if (changedById == null) {
        print('⚠️ Could not get users_data.id for revision tracking');
        return null;
      }
      
      // Get user's name and role
      String? changedByName;
      String? changedByRole;
      
      // Try to get name from users_setup first, then users_data
      final userSetup = await UserService.getCurrentUserSetup();
      if (userSetup != null && userSetup['display_name'] != null) {
        changedByName = userSetup['display_name']?.toString();
      } else if (currentUserData['forename'] != null || currentUserData['surname'] != null) {
        final forename = currentUserData['forename']?.toString() ?? '';
        final surname = currentUserData['surname']?.toString() ?? '';
        changedByName = '$forename $surname'.trim();
      }
      
      // Get role from users_data or users_setup
      if (currentUserData['role'] != null) {
        changedByRole = currentUserData['role']?.toString();
      } else if (userSetup != null && userSetup['role'] != null) {
        changedByRole = userSetup['role']?.toString();
      }
      
      // Increment revision number
      final newRevisionNumber = currentRevisionNumber + 1;
      
      // Fields to track for changes
      final fieldsToTrack = [
        'work_date',
        'start_time',
        'finish_time',
        'project_id',
        'large_plant_id',
        'workshop_tasks_id',
        'travel_to_site_min',
        'travel_from_site_min',
        'distance_from_home',
        'travel_time_text',
        'on_call',
        'misc_allowance_min',
        'concrete_ticket_no',
        'concrete_mix_type',
        'concrete_qty',
        'comments',
      ];
      
      bool hasChanges = false;
      
      // Compare each field and create revision records for changes
      for (final fieldName in fieldsToTrack) {
        final oldValue = oldData[fieldName];
        final newValue = newData[fieldName];
        
        // Convert to strings for comparison (handling nulls)
        final oldValueStr = oldValue?.toString();
        final newValueStr = newValue?.toString();
        
        // Check if value changed (handling nulls and empty strings)
        // Compare normalized values (treat null and empty string as same)
        final oldNormalized = oldValueStr?.isEmpty == true ? null : oldValueStr;
        final newNormalized = newValueStr?.isEmpty == true ? null : newValueStr;
        
        if (oldNormalized != newNormalized) {
          hasChanges = true;
          try {
            await DatabaseService.create('time_period_revisions', {
              'time_period_id': timePeriodId,
              'revision_number': newRevisionNumber,
              'changed_by': changedById, // users_data.id (primary key)
              'changed_by_name': changedByName,
              'changed_by_role': changedByRole,
              'change_type': 'user_edit',
              'workflow_stage': 'submitted', // Status remains 'submitted' when user edits
              'field_name': fieldName,
              'old_value': oldNormalized ?? '',
              'new_value': newNormalized ?? '',
              'change_reason': null, // User can optionally provide reason in future
              'is_revision': true, // User edit creates a revision
              'is_approval': false,
              'is_edit': true,
              'original_submission': false,
            });
            print('✅ Tracked change for field: $fieldName (${oldNormalized ?? 'null'} -> ${newNormalized ?? 'null'})');
          } catch (e) {
            print('⚠️ Error tracking change for field $fieldName: $e');
            // Continue tracking other fields even if one fails
          }
        }
      }
      
      if (hasChanges) {
        print('✅ Change tracking completed with revision_number: $newRevisionNumber');
        return newRevisionNumber;
      } else {
        print('ℹ️ No changes detected for time period: $timePeriodId');
        return null; // No changes, don't increment revision number
      }
    } catch (e, stackTrace) {
      print('❌ Error tracking changes: $e');
      await ErrorLogService.logError(
        location: 'Timesheet Screen - Track Time Period Changes',
        type: 'Database',
        description: 'Failed to track time period changes: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Delete existing breaks, used fleet, and mobilised fleet for a time period
  /// This is called before updating breaks/fleet when editing a time period
  Future<void> _deleteExistingBreaksAndFleet(String timePeriodId) async {
    try {
      print('🗑️ Deleting existing breaks and fleet for time period: $timePeriodId');
      
      // Delete breaks
      try {
        await SupabaseService.client
            .from('time_period_breaks')
            .delete()
            .eq('time_period_id', timePeriodId);
        print('✅ Deleted existing breaks');
      } catch (e) {
        print('⚠️ Error deleting breaks: $e');
      }
      
      // Delete used fleet
      try {
        await SupabaseService.client
            .from('time_period_used_fleet')
            .delete()
            .eq('time_period_id', timePeriodId);
        print('✅ Deleted existing used fleet');
      } catch (e) {
        print('⚠️ Error deleting used fleet: $e');
      }
      
      // Delete mobilised fleet
      try {
        await SupabaseService.client
            .from('time_period_mobilised_fleet')
            .delete()
            .eq('time_period_id', timePeriodId);
        print('✅ Deleted existing mobilised fleet');
      } catch (e) {
        print('⚠️ Error deleting mobilised fleet: $e');
      }
    } catch (e) {
      print('❌ Error deleting existing breaks and fleet: $e');
      // Don't throw - we'll continue and recreate them anyway
    }
  }

  Future<void> _handleSaveFleet() async {
    if (_userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile not found. Cannot save fleet.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_usedFleet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fleet to save.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final updateData = <String, dynamic>{};
      for (int i = 0; i < 6; i++) {
        updateData['fleet_${i + 1}'] = i < _usedFleet.length ? _usedFleet[i] : '';
      }

      // users_data table uses user_id as primary key, not id
      final userId = _userData!['user_id']?.toString() ?? _currentUser?['id']?.toString();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Update the record using the id field (primary key)
      // The record exists (we have _userData), so we can update it
      // Use id instead of user_id as it's the primary key and may have better RLS support
      final recordId = _userData!['id']?.toString();
      if (recordId == null) {
        throw Exception('Record ID not found in user data');
      }
      
      try {
        await SupabaseService.client
            .from('users_data')
            .update(updateData)
            .eq('id', recordId);
        
        print('✅ Fleet update command sent successfully (using id: $recordId)');
        
        // Wait a moment for the update to complete
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Reload user data to verify the update
        await _loadUserData();
        
        // Verify the update worked by checking the reloaded data
        if (_userData != null) {
          final savedFleet1 = _userData!['fleet_1']?.toString() ?? '';
          final expectedFleet1 = updateData['fleet_1']?.toString() ?? '';
          if (savedFleet1 == expectedFleet1) {
            print('✅ Verified: Fleet data was saved successfully');
          } else {
            print('⚠️ Warning: Fleet data may not have been saved. Expected: $expectedFleet1, Got: $savedFleet1');
            throw Exception('Fleet data was not saved - RLS policy may be blocking the update');
          }
        }
      } catch (e) {
        print('❌ Error during fleet update: $e');
        rethrow;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fleet information has been saved for future use.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save fleet information: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Show fleet search dialog (similar to Fleet Mode in Project Section)
  Future<void> _showFleetSearchDialog(int index, bool isMobilised) async {
    final filterController = TextEditingController();
    String? selectedFleetNo;
    
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Search Fleet'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Filter Fleet text box
                    StatefulBuilder(
                      builder: (context, setFilterState) {
                        return TextFormField(
                          controller: filterController,
                          decoration: InputDecoration(
                            labelText: 'Filter Fleet (multiple search strings)',
                            hintText: 'Enter search terms separated by spaces',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: filterController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      filterController.clear();
                                      setFilterState(() {});
                                      setDialogState(() {
                                        selectedFleetNo = null; // Clear selection when filter clears
                                      });
                                    },
                                    tooltip: 'Clear filter',
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            setFilterState(() {}); // Update suffix icon visibility
                            setDialogState(() {
                              selectedFleetNo = null; // Clear selection when filter changes
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Select Fleet dropdown
                    Builder(
                      builder: (context) {
                        final fleetFilter = filterController.text;
                        // Filter fleet with multiple search terms support
                        final filteredFleet = _allPlant.where((plant) {
                          if (fleetFilter.isEmpty) return true;
                          final plantNo = (plant['plant_no']?.toString() ?? '').toLowerCase();
                          final desc = (plant['plant_description']?.toString() ?? 
                                       plant['short_description']?.toString() ?? '').toLowerCase();
                          final filterTerms = fleetFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                          // All filter terms must be found in either plant_no or description
                          return filterTerms.every((term) => plantNo.contains(term) || desc.contains(term));
                        }).toList();
                        
                        // Create dropdown items - show only plant_description
                        final items = filteredFleet.map((plant) {
                          final plantNo = plant['plant_no']?.toString() ?? '';
                          // Use plant_description, fallback to short_description
                          final desc = plant['plant_description']?.toString() ?? 
                                      plant['short_description']?.toString() ?? 
                                      plantNo;
                          return DropdownMenuItem(
                            value: plantNo,
                            child: Text(
                              desc, // Only show description, not "plant_no - desc"
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          );
                        }).toList();
                        
                        return DropdownButtonFormField<String>(
                          key: ValueKey('fleet_dropdown_${fleetFilter}_${selectedFleetNo ?? 'null'}'),
                          value: selectedFleetNo,
                          decoration: const InputDecoration(
                            labelText: 'Select Fleet',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: items,
                          onChanged: (value) {
                            setDialogState(() {
                              selectedFleetNo = value;
                            });
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    filterController.dispose();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedFleetNo != null
                      ? () {
                          final result = selectedFleetNo;
                          filterController.dispose();
                          Navigator.of(dialogContext).pop(result);
                        }
                      : null,
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );
    
    if (result != null && result.isNotEmpty) {
      setState(() {
        if (isMobilised) {
          while (_mobilisedFleet.length <= index) {
            _mobilisedFleet.add('');
          }
          _mobilisedFleet[index] = result.toUpperCase();
          // Validate immediately after selection
          _validateFleetNumber(index, result, true);
        } else {
          while (_usedFleet.length <= index) {
            _usedFleet.add('');
          }
          _usedFleet[index] = result.toUpperCase();
          // Validate immediately after selection
          _validateFleetNumber(index, result, false);
        }
      });
    } else {
      filterController.dispose();
    }
  }

  Future<void> _handleClearFleet() async {
    if (_userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile not found. Cannot clear fleet.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final updateData = <String, dynamic>{};
      for (int i = 1; i <= 6; i++) {
        updateData['fleet_$i'] = '';
      }

      // users_data table uses user_id as primary key, not id
      final userId = _userData!['user_id']?.toString() ?? _currentUser?['id']?.toString();
      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Update the record using the id field (primary key)
      // The record exists (we have _userData), so we can update it
      // Use id instead of user_id as it's the primary key and may have better RLS support
      final recordId = _userData!['id']?.toString();
      if (recordId == null) {
        throw Exception('Record ID not found in user data');
      }
      
      await SupabaseService.client
          .from('users_data')
          .update(updateData)
          .eq('id', recordId);
      
      print('✅ Fleet clear command sent successfully (using id: $recordId)');

      // Reload user data
      await _loadUserData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved fleet information has been cleared.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to clear fleet information: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Optimized confirmation dialog - uses pre-calculated values (no lookups or calculations during build)
  Widget _buildSaveConfirmationDialogOptimized({
    required String formattedDate,
    required String startTimeFormatted,
    required String finishTimeFormatted,
    required String projectDisplayName,
    required String totalBreakText,
    required List<String> breakDetails,
    required String totalWorkText,
    required List<String> usedFleetDescriptions,
    required List<String> mobilisedFleetDescriptions,
    required String travelToSite,
    required String travelFromSite,
    required String miscellaneous,
    required bool onCall,
    required String comments,
    required String ticketNumber,
    required String concreteMix,
    required String quantity,
  }) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title - wrap to two lines when needed
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF0081FB), size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Confirm Time Period Entry',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0081FB),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Content in a Card-like container - scrollable
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date (no "Date:" heading)
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Start & Finish Times
                      const Text(
                        'Start & Finish Times:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$startTimeFormatted - $finishTimeFormatted',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      // Project/Fleet
                      const Text(
                        'Project/Fleet:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        projectDisplayName,
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (breakDetails.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Breaks:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              'Total: $totalBreakText',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      ...breakDetails.asMap().entries.map((entry) {
                        final idx = entry.key;
                        return Padding(
                          padding: const EdgeInsets.only(left: 16, top: 4),
                          child: Text(
                            'Break ${idx + 1}: ${entry.value}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }),
                      ],
                    // Total Hours Worked
                    if (totalWorkText != '0 min') ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      _buildSummaryRow(
                        'Total Hours Worked',
                        totalWorkText,
                        isBold: true,
                        textColor: Colors.green.shade700,
                      ),
                    ],
                    if (usedFleetDescriptions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Used Fleet:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ...usedFleetDescriptions.map((item) => Padding(
                        padding: const EdgeInsets.only(left: 16, top: 4),
                        child: Text(item, style: const TextStyle(fontSize: 14)),
                      )),
                    ],
                    if (mobilisedFleetDescriptions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Mobilised Fleet:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ...mobilisedFleetDescriptions.map((item) => Padding(
                        padding: const EdgeInsets.only(left: 16, top: 4),
                        child: Text(item, style: const TextStyle(fontSize: 14)),
                      )),
                    ],
                    // Only show allowances if they are not empty and not zero
                    if ((_isNotEmptyAndNotZero(travelToSite) || 
                         _isNotEmptyAndNotZero(travelFromSite) || 
                         _isNotEmptyAndNotZero(miscellaneous))) ...[
                      const SizedBox(height: 12),
                      if (_isNotEmptyAndNotZero(miscellaneous)) _buildSummaryRow('Miscellaneous', '${miscellaneous} min'),
                      if (_isNotEmptyAndNotZero(travelToSite)) _buildSummaryRow('Travel To Site', '${travelToSite} min'),
                      if (_isNotEmptyAndNotZero(travelFromSite)) _buildSummaryRow('Travel From Site', '${travelFromSite} min'),
                    ],
                    // Only show Materials section when Concrete Mix or Quantity is not empty
                    if (concreteMix.isNotEmpty || quantity.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const Text(
                        'Materials:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (ticketNumber.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: _buildSummaryRow('Ticket Number', ticketNumber),
                        ),
                      ],
                      if (concreteMix.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: _buildSummaryRow('Concrete Mix', concreteMix),
                        ),
                      ],
                      if (quantity.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: _buildSummaryRow('Quantity', quantity),
                        ),
                      ],
                    ],
                    if (comments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSummaryRow('Comments', comments),
                    ],
                  ],
                ),
              ),
            ),
            ),
            const SizedBox(height: 12),
            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: textColor ?? Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: textColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper method to check if a string is not empty and not zero (or "0 min")
  bool _isNotEmptyAndNotZero(String value) {
    if (value.isEmpty) return false;
    final trimmed = value.trim();
    // Check if it's "0" or "0 min" or similar zero variations
    if (trimmed == '0' || 
        trimmed.toLowerCase() == '0 min' || 
        trimmed.toLowerCase() == '0min' ||
        (int.tryParse(trimmed) == 0)) {
      return false;
    }
    return true;
  }

  void _resetForm({String? finishTime, bool preserveDate = false}) {
    final timeFormat = DateFormat('HH:mm');
    
    setState(() {
      // Only reset date if preserveDate is false
      if (!preserveDate) {
        _date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }
      
      // If finishTime is provided (from previous period), use it as start time
      if (finishTime != null && finishTime.isNotEmpty) {
        _startTime = finishTime;
        // Autofill finish time as start time + 30 minutes
        _finishTime = _addMinutesToTime(finishTime, 30);
      } else {
        // Default behavior: use current time rounded to 15 minutes
        final now = DateTime.now();
        final roundedMinutes = ((now.minute / 15).round() * 15) % 60;
        final roundedTime = DateTime(now.year, now.month, now.day, now.hour, roundedMinutes);
        final defaultFinishTime = roundedTime.add(const Duration(minutes: 30));
        _startTime = timeFormat.format(roundedTime);
        _finishTime = timeFormat.format(defaultFinishTime);
      }
        _breaks = [];
        _selectedProject = '';
        // Keep _usedFleet unchanged (don't clear it)
        _mobilisedFleet = [];
        _travelToSite = '';
        _travelFromSite = '';
        _miscellaneous = '';
        _onCall = false;
        _ticketNumber = '';
        _concreteMix = '';
        _quantity = '';
        _comments = '';
        _commentResetCounter++; // Increment counter to force comment field to rebuild
        _calculatedTravelTime = '';
        _calculatedDistance = '';
        _findNearestButtonText = 'Find Nearest Job';
        _foundNearestProjects = [];
        _projectSelected = false;
        // Keep employee selection (don't reset)
        // _selectedEmployeeUserId = null;
      });
    
    // Scroll to top of form after reset
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
}

// Separate StatefulWidget to maintain controller state
class _FleetInputField extends StatefulWidget {
  final String initialValue;
  final String labelText;
  final bool isDuplicate;
  final bool isInvalid;
  final Function(String) onChanged;
  final Function()? onFocusLost;
  final Function()? onFocusGained;

  const _FleetInputField({
    Key? key,
    required this.initialValue,
    required this.labelText,
    required this.isDuplicate,
    required this.isInvalid,
    required this.onChanged,
    this.onFocusLost,
    this.onFocusGained,
  }) : super(key: key);

  @override
  State<_FleetInputField> createState() => _FleetInputFieldState();
}

class _FleetInputFieldState extends State<_FleetInputField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        widget.onFocusLost?.call();
      } else {
        widget.onFocusGained?.call();
      }
    });
  }

  @override
  void didUpdateWidget(_FleetInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller text if initialValue changed (e.g., from Recall Fleet)
    // Use post-frame callback to avoid setState during build
    if (oldWidget.initialValue != widget.initialValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.text != widget.initialValue) {
          _controller.text = widget.initialValue;
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use custom keyboard on mobile platforms (not web)
    final isMobile = !kIsWeb;
    
    return TextFormField(
      key: ValueKey(widget.labelText), // Stable key based on label only
      controller: _controller,
      focusNode: _focusNode,
      textAlign: TextAlign.center,
      maxLength: 4,
      readOnly: isMobile, // Make read-only on mobile to force custom keyboard
      style: TextStyle(
        color: (widget.isDuplicate || widget.isInvalid) ? Colors.red.shade700 : null,
      ),
      decoration: InputDecoration(
        labelText: widget.labelText,
        border: OutlineInputBorder(
          borderSide: BorderSide(
            color: (widget.isDuplicate || widget.isInvalid) ? Colors.red : Colors.grey,
            width: (widget.isDuplicate || widget.isInvalid) ? 2 : 1,
          ),
        ),
        filled: true,
        fillColor: (widget.isDuplicate || widget.isInvalid) ? Colors.red.shade50 : Colors.white,
        counterText: '',
        errorText: null, // We handle validation via description field
      ),
      onTap: isMobile
          ? () async {
              // Show custom keyboard dialog on mobile
              final dialogController = TextEditingController(text: _controller.text);
              final result = await showDialog<String>(
                context: context,
                builder: (context) => FleetKeyboardDialog(
                  controller: dialogController,
                  maxLength: 4,
                ),
              );
              // Update the value after dialog closes
              final newValue = result ?? dialogController.text;
              if (newValue.toUpperCase() != _controller.text.toUpperCase()) {
                _controller.text = newValue.toUpperCase();
                widget.onChanged(newValue.toUpperCase());
              }
              // Trigger focus lost after dialog closes
              _focusNode.unfocus();
            }
          : null,
      onChanged: isMobile ? null : (value) {
        // Update controller and call onChanged
        final upperValue = value.toUpperCase();
        if (_controller.text != upperValue) {
          _controller.text = upperValue;
        }
        widget.onChanged(upperValue);
      },
    );
  }
}


