/// Time Clocking Screen
/// 
/// Allows users to clock in and clock out with separate entries.
/// Features:
/// - Adjustable date and time (15 minute intervals)
/// - GPS location capture
/// - Online/offline status display
/// - Project selection with "Find Nearest Job", "Find Next", and "Find Last"
/// - Separate clock in/out entries in time_clocking table
/// - Saves manual_time (adjusted) and automatic_time (current time)

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dwce_time_tracker/widgets/screen_info_icon.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/offline/offline_storage_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';

class TimeClockingScreen extends StatefulWidget {
  const TimeClockingScreen({super.key});

  @override
  State<TimeClockingScreen> createState() => _TimeClockingScreenState();
}

class _TimeClockingScreenState extends State<TimeClockingScreen> {
  // Connectivity
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // User data
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _userData;
  String _displayName = '';

  // Form fields
  String _date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _selectedTime = '';
  DateTime _manualDateTime = DateTime.now();
  DateTime _automaticDateTime = DateTime.now();
  String _selectedProject = '';
  String _selectedProjectDescription = '';
  bool _projectSelected = false;
  
  // Clock status
  bool _hasClockedInToday = false;
  bool _canClockOut = false; // True if user can clock out (has clocked in today or on selected date)

  // Project data
  List<Map<String, dynamic>> _allProjects = [];
  Map<String, Map<String, dynamic>> _projectMapByName = {};
  String _projectFilter = '';
  int _projectFilterResetCounter = 0;
  String _findNearestButtonText = 'Find Nearest Job';
  bool _isFindingNearest = false;
  bool _isFindingLast = false;
  List<String> _foundNearestProjects = [];

  // GPS
  double? _currentLatitude;
  double? _currentLongitude;
  int? _currentGpsAccuracy;
  bool _gpsEnabled = false;
  Timer? _dateTimeUpdateTimer;

  // Loading state
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    _setupConnectivityListener();
    _startDateTimeUpdate();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _dateTimeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    
    try {
      await _loadCurrentUser();
      await _loadUserData();
      await _loadProjects();
      await _checkGpsStatus();
      await _checkClockStatus();
      
      // Initialize date/time
      _updateDateTime();
    } catch (e) {
      print('❌ Error initializing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    final user = AuthService.getCurrentUser();
    if (user != null) {
      setState(() {
        _currentUser = {
          'email': user.email,
          'id': user.id,
        };
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final userData = await UserService.getCurrentUserData();
      if (userData != null) {
        setState(() {
          _userData = userData;
          _displayName = userData['display_name']?.toString() ?? 
                        userData['forename']?.toString() ?? 
                        _currentUser?['email']?.toString() ?? 
                        'Unknown User';
        });
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
    }
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await DatabaseService.read(
        'projects',
        filterColumn: 'is_active',
        filterValue: true,
        orderBy: 'project_name',
        ascending: true,
        limit: 10000,
      );
      
      setState(() {
        _allProjects = projects;
        _projectMapByName = {};
        for (final project in projects) {
          final name = project['project_name']?.toString() ?? '';
          if (name.isNotEmpty) {
            _projectMapByName[name] = project;
          }
        }
      });
    } catch (e) {
      print('❌ Error loading projects: $e');
    }
  }

  Future<void> _checkGpsStatus() async {
    if (kIsWeb) {
      setState(() => _gpsEnabled = false);
      return;
    }

    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      setState(() => _gpsEnabled = isEnabled);
      
      if (isEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission != LocationPermission.denied && 
            permission != LocationPermission.deniedForever) {
          try {
            final position = await Geolocator.getCurrentPosition(
              locationSettings: AndroidSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 5),
              ),
            );
            setState(() {
              _currentLatitude = position.latitude;
              _currentLongitude = position.longitude;
              _currentGpsAccuracy = position.accuracy.round();
            });
          } catch (e) {
            print('⚠️ Error getting GPS position: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error checking GPS status: $e');
    }
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (mounted) {
          final isOnline = results.any((result) => result != ConnectivityResult.none);
          setState(() {
            _isOnline = isOnline;
          });
        }
      },
    );

    Connectivity().checkConnectivity().then((results) {
      if (mounted) {
        final isOnline = results.any((result) => result != ConnectivityResult.none);
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  void _startDateTimeUpdate() {
    _dateTimeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateAutomaticTime();
    });
  }

  void _updateAutomaticTime() {
    setState(() {
      _automaticDateTime = DateTime.now();
    });
  }

  void _updateDateTime() {
    final now = DateTime.now();
    final roundedTime = _roundToNearest15Minutes(now);
    final timeString = DateFormat('HH:mm').format(roundedTime);
    
    setState(() {
      _date = DateFormat('yyyy-MM-dd').format(now);
      _selectedTime = timeString;
      final selectedDate = DateTime.parse(_date);
      _manualDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        roundedTime.hour,
        roundedTime.minute,
      );
      _automaticDateTime = now;
    });
  }

  DateTime _roundToNearest15Minutes(DateTime dateTime) {
    final roundedMinutes = ((dateTime.minute / 15).round() * 15) % 60;
    return DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
      dateTime.hour,
      roundedMinutes,
    );
  }

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

  DateTime _getMinDate(DateTime today) {
    // Get week start from system settings or default to Monday
    // For now, just return 4 weeks ago
    return today.subtract(const Duration(days: 28));
  }

  Future<void> _checkClockStatus() async {
    if (_currentUser == null) return;

    try {
      final userId = _currentUser!['id']?.toString();
      if (userId == null) return;

      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Check if user has clocked in today
      final clockInResponse = await SupabaseService.client
          .from('time_clocking')
          .select()
          .eq('user_id', userId)
          .eq('clock_in', true)
          .gte('manual_time', todayStart.toIso8601String())
          .lt('manual_time', todayEnd.toIso8601String())
          .order('manual_time', ascending: false)
          .limit(1)
          .maybeSingle();

      final hasClockInToday = clockInResponse != null;

      // Check if user has clocked out today
      final clockOutResponse = await SupabaseService.client
          .from('time_clocking')
          .select()
          .eq('user_id', userId)
          .eq('clock_out', true)
          .gte('manual_time', todayStart.toIso8601String())
          .lt('manual_time', todayEnd.toIso8601String())
          .order('manual_time', ascending: false)
          .limit(1)
          .maybeSingle();

      final hasClockOutToday = clockOutResponse != null;

      // Check if user can clock out on selected date (has clocked in on that date but not out)
      final selectedDate = DateTime.parse(_date);
      final selectedDateStart = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
      final selectedDateEnd = selectedDateStart.add(const Duration(days: 1));

      bool canClockOutOnSelectedDate = false;
      if (selectedDate.isBefore(todayStart) || selectedDate.isAtSameMomentAs(todayStart)) {
        // Check if user clocked in on selected date
        final clockInOnDate = await SupabaseService.client
            .from('time_clocking')
            .select()
            .eq('user_id', userId)
            .eq('clock_in', true)
            .gte('manual_time', selectedDateStart.toIso8601String())
            .lt('manual_time', selectedDateEnd.toIso8601String())
            .order('manual_time', ascending: false)
            .limit(1)
            .maybeSingle();

        if (clockInOnDate != null) {
          // Check if user already clocked out on that date
          final clockOutOnDate = await SupabaseService.client
              .from('time_clocking')
              .select()
              .eq('user_id', userId)
              .eq('clock_out', true)
              .gte('manual_time', selectedDateStart.toIso8601String())
              .lt('manual_time', selectedDateEnd.toIso8601String())
              .order('manual_time', ascending: false)
              .limit(1)
              .maybeSingle();

          canClockOutOnSelectedDate = clockOutOnDate == null;
        }
      }

      setState(() {
        _hasClockedInToday = hasClockInToday && !hasClockOutToday;
        _canClockOut = _hasClockedInToday || canClockOutOnSelectedDate;
      });
    } catch (e) {
      print('❌ Error checking clock status: $e');
    }
  }

  Future<void> _handleFindNearestProject() async {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location services are disabled. Please enable them.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are required. Please grant location permissions in app settings.'),
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

    if (_findNearestButtonText == 'Find Nearest Job') {
      setState(() {
        _projectFilter = '';
        _projectFilterResetCounter++;
        _selectedProject = '';
        _projectSelected = false;
        _foundNearestProjects = [];
        _isFindingNearest = true;
      });
    } else {
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

      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
        _currentGpsAccuracy = position.accuracy.round();
      });

      Map<String, dynamic>? nearestProject;
      double? minDistance;

      for (final project in _allProjects) {
        final projectName = project['project_name']?.toString() ?? '';
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
        final projectDescription = nearestProject['description']?.toString() ?? '';
        setState(() {
          _selectedProject = projectName;
          _selectedProjectDescription = projectDescription;
          _projectSelected = true;
          _findNearestButtonText = 'Find Next';
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error finding nearest project: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isFindingNearest = false;
      });
    }
  }

  Future<void> _handleFindLastJob() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User not loaded. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _projectFilter = '';
      _projectFilterResetCounter++;
      _selectedProject = '';
      _projectSelected = false;
      _isFindingLast = true;
    });

    try {
      final userId = _currentUser!['id']?.toString();
      if (userId == null || userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find user ID.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final userDataResponse = await DatabaseService.read(
        'users_data',
        filterColumn: 'user_id',
        filterValue: userId,
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

      lastJobs.sort((a, b) {
        final aDate = a['changed_at']?.toString();
        final bDate = b['changed_at']?.toString();
        
        if (aDate != null && aDate.isNotEmpty && bDate != null && bDate.isNotEmpty) {
          try {
            final aDateTime = DateTime.parse(aDate);
            final bDateTime = DateTime.parse(bDate);
            return bDateTime.compareTo(aDateTime);
          } catch (e) {
            return 0;
          }
        }
        
        if (aDate != null && aDate.isNotEmpty) return -1;
        if (bDate != null && bDate.isNotEmpty) return 1;
        
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
      
      String dateText = 'Date not available';
      if (changedAtStr != null && changedAtStr.isNotEmpty) {
        try {
          final dateTime = DateTime.parse(changedAtStr);
          dateText = DateFormat('EEEE, d MMM yyyy').format(dateTime);
        } catch (e) {
          print('Error parsing date: $e');
        }
      }

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
              const Text(
                'Project:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(projectName, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              const Text(
                'Date Last Used:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(dateText),
              if (projectDetails != null && projectDetails.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Client Name:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(projectDetails['client_name']?.toString() ?? 'Not specified'),
                const SizedBox(height: 8),
                const Text(
                  'Description of Work:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(projectDetails['description_of_work']?.toString() ?? 'Not specified'),
              ],
            ],
          ),
          actions: [
            Builder(
              builder: (context) {
                final buttonWidth = 120.0;
                
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
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
                        const Expanded(flex: 1, child: SizedBox()),
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
                    Row(
                      children: [
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
                        const Expanded(flex: 1, child: SizedBox()),
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
        return;
      } else if (result == projectName) {
        final project = _projectMapByName[projectName];
        if (project != null) {
          setState(() {
            _selectedProject = projectName;
            _selectedProjectDescription = project['description']?.toString() ?? '';
            _projectSelected = true;
          });
          return;
        }
      } else if (result == 'previous') {
        currentIndex--;
      } else if (result == 'skip') {
        currentIndex++;
      }
    }
  }

  void _updateManualDateTime() {
    if (_selectedTime.isEmpty) {
      final now = DateTime.now();
      final roundedTime = _roundToNearest15Minutes(now);
      final timeString = DateFormat('HH:mm').format(roundedTime);
      _selectedTime = timeString;
    }
    
    final selectedDate = DateTime.parse(_date);
    final timeParts = _selectedTime.split(':');
    if (timeParts.length == 2) {
      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;
      _manualDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        hour,
        minute,
      );
    }
  }

  Future<void> _handleClockIn() async {
    // Check if date is current day
    final currentDate = DateTime.now();
    final selectedDate = DateTime.parse(_date);
    final maxDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
    final isCurrentDate = selectedDate.year == maxDate.year &&
                        selectedDate.month == maxDate.month &&
                        selectedDate.day == maxDate.day;
    
    if (!isCurrentDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only clock in on the current day.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (!_projectSelected || _selectedProject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a project first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_currentLatitude == null || _currentLongitude == null) {
      try {
        if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable them.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

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

        setState(() {
          _currentLatitude = position.latitude;
          _currentLongitude = position.longitude;
          _currentGpsAccuracy = position.accuracy.round();
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting GPS location: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final project = _projectMapByName[_selectedProject];
    if (project == null) throw Exception('Project not found');

    double? distanceKm;
    final projectLat = project['latitude'];
    final projectLng = project['longitude'];
    if (_currentLatitude != null && _currentLongitude != null && 
        projectLat != null && projectLng != null) {
      final distanceMeters = Geolocator.distanceBetween(
        _currentLatitude!,
        _currentLongitude!,
        (projectLat as num).toDouble(),
        (projectLng as num).toDouble(),
      );
      distanceKm = distanceMeters / 1000;
    }

    final confirmed = await _showClockInConfirmation(project, distanceKm);
    if (confirmed != true) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = _currentUser!['id']?.toString();
      if (userId == null) throw Exception('User ID not found');

      final projectId = project['id']?.toString();
      _updateManualDateTime();
      final roundedManualTime = _roundToNearest15Minutes(_manualDateTime);
      final automaticTime = DateTime.now();

      final clockingData = {
        'user_id': userId,
        'project_id': projectId,
        'manual_time': roundedManualTime.toIso8601String(),
        'automatic_time': automaticTime.toIso8601String(),
        'clock_in': true,
        'clock_out': false,
        'latitude': _currentLatitude,
        'longitude': _currentLongitude,
        'gps_accuracy': _currentGpsAccuracy,
        'offline_created': !_isOnline,
        'synced': _isOnline,
      };

      if (_isOnline) {
        await DatabaseService.create('time_clocking', clockingData);
      } else {
        if (!OfflineStorageService.isSupported) {
          throw Exception('Offline storage not available on this platform. Please ensure you have internet connection.');
        }

        final offlineId = 'clock_in_${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}';
        clockingData['offline_id'] = offlineId;
        clockingData['_entry_type'] = 'clock_in';
        clockingData['_offline_id'] = offlineId;
        clockingData['_table_name'] = 'time_clocking';

        await OfflineStorageService.addToQueue(clockingData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isOnline 
                ? 'Clocked in successfully!'
                : 'Clocked in offline. Will sync when online.'),
            backgroundColor: _isOnline ? Colors.green : Colors.orange,
          ),
        );
      }
      
      // Refresh clock status
      await _checkClockStatus();
    } catch (e) {
      print('❌ Error clocking in: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clocking in: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleClockOut() async {
    if (!_projectSelected || _selectedProject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a project first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location services are disabled. Please enable them.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

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

      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
        _currentGpsAccuracy = position.accuracy.round();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting GPS location: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final project = _projectMapByName[_selectedProject];
    if (project == null || project.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project information not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    double? distanceKm;
    final projectLat = project['latitude'];
    final projectLng = project['longitude'];
    if (_currentLatitude != null && _currentLongitude != null && 
        projectLat != null && projectLng != null) {
      final distanceMeters = Geolocator.distanceBetween(
        _currentLatitude!,
        _currentLongitude!,
        (projectLat as num).toDouble(),
        (projectLng as num).toDouble(),
      );
      distanceKm = distanceMeters / 1000;
    }

    final confirmed = await _showClockOutConfirmation(project, distanceKm);
    if (confirmed != true) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = _currentUser!['id']?.toString();
      if (userId == null) throw Exception('User ID not found');

      final projectId = project['id']?.toString();
      _updateManualDateTime();
      final roundedManualTime = _roundToNearest15Minutes(_manualDateTime);
      final automaticTime = DateTime.now();

      final clockingData = {
        'user_id': userId,
        'project_id': projectId,
        'manual_time': roundedManualTime.toIso8601String(),
        'automatic_time': automaticTime.toIso8601String(),
        'clock_in': false,
        'clock_out': true,
        'latitude': _currentLatitude,
        'longitude': _currentLongitude,
        'gps_accuracy': _currentGpsAccuracy,
        'offline_created': !_isOnline,
        'synced': _isOnline,
      };

      if (_isOnline) {
        await DatabaseService.create('time_clocking', clockingData);
      } else {
        if (!OfflineStorageService.isSupported) {
          throw Exception('Offline storage not available on this platform. Please ensure you have internet connection.');
        }

        final offlineId = 'clock_out_${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}';
        clockingData['offline_id'] = offlineId;
        clockingData['_entry_type'] = 'clock_out';
        clockingData['_offline_id'] = offlineId;
        clockingData['_table_name'] = 'time_clocking';

        await OfflineStorageService.addToQueue(clockingData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isOnline 
                ? 'Clocked out successfully!'
                : 'Clocked out offline. Will sync when online.'),
            backgroundColor: _isOnline ? Colors.green : Colors.orange,
          ),
        );
      }
      
      // Refresh clock status
      await _checkClockStatus();
    } catch (e) {
      print('❌ Error clocking out: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clocking out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool?> _showClockInConfirmation(Map<String, dynamic> project, double? distanceKm) async {
    final projectName = project['project_name']?.toString() ?? '';
    final clientName = project['client_name']?.toString() ?? 'Not specified';
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(_manualDateTime);
    final timeStr = DateFormat('h:mm a').format(_manualDateTime);
    final distanceStr = distanceKm != null 
        ? '${distanceKm.toStringAsFixed(2)} km'
        : 'Distance unavailable';

    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Clock In'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please confirm the following details:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Project:', projectName),
                const SizedBox(height: 8),
                _buildDetailRow('Client:', clientName),
                const SizedBox(height: 8),
                _buildDetailRow('Date:', dateStr),
                const SizedBox(height: 8),
                _buildDetailRow('Time:', timeStr),
                const SizedBox(height: 8),
                _buildDetailRow('Distance from Job:', distanceStr),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm Clock In'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showClockOutConfirmation(Map<String, dynamic> project, double? distanceKm) async {
    final projectName = project['project_name']?.toString() ?? '';
    final clientName = project['client_name']?.toString() ?? 'Not specified';
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(_manualDateTime);
    final timeStr = DateFormat('h:mm a').format(_manualDateTime);
    final distanceStr = distanceKm != null 
        ? '${distanceKm.toStringAsFixed(2)} km'
        : 'Distance unavailable';

    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Clock Out'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please confirm the following details:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Project:', projectName),
                const SizedBox(height: 8),
                _buildDetailRow('Client:', clientName),
                const SizedBox(height: 8),
                _buildDetailRow('Date:', dateStr),
                const SizedBox(height: 8),
                _buildDetailRow('Time:', timeStr),
                const SizedBox(height: 8),
                _buildDetailRow('Distance from Job:', distanceStr),
              ],
            ),
          ),
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
              child: const Text('Confirm Clock Out'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectDetailsContent() {
    final project = _projectMapByName[_selectedProject];
    
    if (project == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200, width: 1),
        ),
        child: const Text(
          'Project details not available',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      );
    }
    
    final clientName = project['client_name']?.toString() ?? 'Not specified';
    final descriptionOfWork = project['description_of_work']?.toString() ?? _selectedProjectDescription;
    final projectName = project['project_name']?.toString() ?? _selectedProject;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Project Details:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
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
          if (descriptionOfWork.isNotEmpty && descriptionOfWork != 'Not specified') ...[
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Clock In/Out',
            style: TextStyle(color: Colors.black),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0081FB),
          foregroundColor: Colors.black,
          actions: const [ScreenInfoIcon(screenName: 'time_clocking_screen.dart')],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Clock In/Out',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'time_clocking_screen.dart')],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Online/Offline Status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isOnline ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isOnline ? Colors.green : Colors.orange,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isOnline ? Icons.cloud_done : Icons.cloud_off,
                    color: _isOnline ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isOnline ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // User Display Name
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    _displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Date and Time Selection (matching timesheet_screen format)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF005AB0), width: 2),
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFBADDFF),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF005AB0), width: 2),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Date & Time',
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
                          // Centered date with arrows
                          Builder(
                            builder: (context) {
                              final currentDate = DateTime.now();
                              final selectedDate = DateTime.parse(_date);
                              final dateFormat = DateFormat('EEE (d MMM)');
                              final maxDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
                              final minDate = _getMinDate(currentDate);
                              final isCurrentDate = selectedDate.year == maxDate.year &&
                                                  selectedDate.month == maxDate.month &&
                                                  selectedDate.day == maxDate.day;
                              final isPastDate = selectedDate.isBefore(maxDate);
                              final isAtMinDate = selectedDate.year == minDate.year &&
                                                  selectedDate.month == minDate.month &&
                                                  selectedDate.day == minDate.day;
                              
                              Color backgroundColor;
                              if (_isOnline) {
                                backgroundColor = isCurrentDate 
                                    ? Colors.green.withOpacity(0.1)
                                    : isPastDate 
                                        ? Colors.red.withOpacity(0.1)
                                        : Colors.grey.withOpacity(0.1);
                              } else {
                                backgroundColor = Colors.orange.withOpacity(0.1);
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
                                                if (newDate.isAfter(minDate) || 
                                                    (newDate.year == minDate.year &&
                                                     newDate.month == minDate.month &&
                                                     newDate.day == minDate.day)) {
                                                  setState(() {
                                                    _date = DateFormat('yyyy-MM-dd').format(newDate);
                                                    _updateManualDateTime();
                                                  });
                                                  _checkClockStatus();
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
                                                return !date.isBefore(minDate) && !date.isAfter(maxDate);
                                              },
                                            );
                                            if (pickedDate != null) {
                                              setState(() {
                                                _date = DateFormat('yyyy-MM-dd').format(pickedDate);
                                                _updateManualDateTime();
                                              });
                                              _checkClockStatus();
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
                                                    if (newDate.isBefore(maxDate) || 
                                                        (newDate.year == maxDate.year &&
                                                         newDate.month == maxDate.month &&
                                                         newDate.day == maxDate.day)) {
                                                      setState(() {
                                                        _date = DateFormat('yyyy-MM-dd').format(newDate);
                                                        _updateManualDateTime();
                                                      });
                                                      _checkClockStatus();
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
                              final currentDate = DateTime.now();
                              final selectedDate = DateTime.parse(_date);
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
                                        _updateManualDateTime();
                                      });
                                      _checkClockStatus();
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
                          // Time dropdown
                          DropdownButtonFormField<String>(
                            value: _selectedTime.isEmpty ? null : _selectedTime,
                            decoration: const InputDecoration(
                              labelText: 'Time',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                            selectedItemBuilder: (BuildContext context) {
                              return _generateTimeOptions().map((time) {
                                return Text(
                                  _convertTo12Hour(time),
                                  textAlign: TextAlign.center,
                                );
                              }).toList();
                            },
                            items: _generateTimeOptions().map((time) {
                              return DropdownMenuItem(
                                value: time,
                                child: Text(
                                  _convertTo12Hour(time),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedTime = value ?? '';
                                _updateManualDateTime();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Project Section
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF005AB0), width: 2),
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFBADDFF),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFF005AB0), width: 2),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Project',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
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
                                
                                if (_selectedProject.isNotEmpty) {
                                  final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                                  final selectedProjectName = _selectedProject.toLowerCase();
                                  
                                  final isStillInFilter = filterTerms.isEmpty || 
                                      filterTerms.every((term) => selectedProjectName.contains(term));
                                  
                                  final filteredProjects = _allProjects.where((project) {
                                    if (value.isEmpty) return true;
                                    final name = project['project_name']?.toString().toLowerCase() ?? '';
                                    final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                                    return filterTerms.every((term) => name.contains(term));
                                  }).toList();
                                  
                                  final projectExists = filteredProjects.any(
                                    (p) => p['project_name']?.toString() == _selectedProject
                                  );
                                  
                                  if (!isStillInFilter || !projectExists) {
                                    _selectedProject = '';
                                    _selectedProjectDescription = '';
                                    _projectSelected = false;
                                  }
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            key: ValueKey('project_$_projectFilterResetCounter'),
                            value: _selectedProject.isEmpty ? null : _selectedProject,
                            decoration: InputDecoration(
                              labelText: 'PROJECT *',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: _allProjects
                                .where((p) {
                                  if (_projectFilter.isEmpty) return true;
                                  final name = p['project_name']?.toString().toLowerCase() ?? '';
                                  final filterTerms = _projectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
                                  return filterTerms.every((term) => name.contains(term));
                                })
                                .map((project) {
                                  final name = project['project_name']?.toString() ?? '';
                                  return DropdownMenuItem<String>(
                                    value: name,
                                    child: Text(name),
                                  );
                                })
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                final project = _projectMapByName[value];
                                setState(() {
                                  _selectedProject = value;
                                  _selectedProjectDescription = project?['description']?.toString() ?? '';
                                  _projectSelected = true;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // Find Nearest Job / Find Next / Find Last Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isFindingNearest ? null : _handleFindNearestProject,
                                  icon: const Icon(Icons.my_location),
                                  label: Text(_findNearestButtonText),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isFindingLast ? null : _handleFindLastJob,
                                  icon: const Icon(Icons.history),
                                  label: const Text('Find Last'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (_projectSelected && _selectedProject.isNotEmpty) ...[
                            _buildProjectDetailsContent(),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // GPS Status
            if (!kIsWeb) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _gpsEnabled && _currentLatitude != null 
                      ? Colors.green.shade50 
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _gpsEnabled && _currentLatitude != null 
                        ? Colors.green 
                        : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _gpsEnabled && _currentLatitude != null 
                          ? Icons.gps_fixed 
                          : Icons.gps_off,
                      color: _gpsEnabled && _currentLatitude != null 
                          ? Colors.green 
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _gpsEnabled && _currentLatitude != null
                            ? 'GPS: ${_currentLatitude!.toStringAsFixed(6)}, ${_currentLongitude!.toStringAsFixed(6)} (Accuracy: ${_currentGpsAccuracy ?? 0}m)'
                            : 'GPS: Not available. Please enable location services.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _gpsEnabled && _currentLatitude != null 
                              ? Colors.green.shade700 
                              : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Clock In/Out Button (single button based on status)
            Builder(
              builder: (context) {
                final currentDate = DateTime.now();
                final selectedDate = DateTime.parse(_date);
                final maxDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
                final isCurrentDate = selectedDate.year == maxDate.year &&
                                    selectedDate.month == maxDate.month &&
                                    selectedDate.day == maxDate.day;
                
                // Can clock in only on current day and if not already clocked in
                final canClockIn = isCurrentDate && !_hasClockedInToday && !_isSaving && _projectSelected;
                // Can clock out if has clocked in today OR can clock out on selected date
                final canClockOut = _canClockOut && !_isSaving && _projectSelected;
                
                final showClockIn = !_hasClockedInToday && isCurrentDate;
                final showClockOut = _canClockOut;
                
                if (!showClockIn && !showClockOut) {
                  return const SizedBox.shrink();
                }
                
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: showClockIn ? (canClockIn ? _handleClockIn : null) : (canClockOut ? _handleClockOut : null),
                    icon: Icon(showClockIn ? Icons.login : Icons.logout),
                    label: Text(
                      _isSaving 
                          ? 'Saving...' 
                          : (showClockIn ? 'Clock In' : 'Clock Out'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: showClockIn ? Colors.green : Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
