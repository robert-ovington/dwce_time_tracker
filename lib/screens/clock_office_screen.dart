/// Clock Office Screen
/// 
/// Allows users to clock in and clock out for office work with GPS tracking.
/// Features:
/// - GPS location capture
/// - Online/offline status display
/// - Date and time adjustment
/// - Break management
/// - Office-specific time tracking

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/offline/offline_storage_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';
import 'package:dwce_time_tracker/modules/errors/error_log_service.dart';

class ClockOfficeScreen extends StatefulWidget {
  const ClockOfficeScreen({super.key});

  @override
  State<ClockOfficeScreen> createState() => _ClockOfficeScreenState();
}

class _ClockOfficeScreenState extends State<ClockOfficeScreen> {
  // Connectivity
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // User data
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _userData;
  String _displayName = '';

  // Clock status
  bool _isClockedIn = false;
  Map<String, dynamic>? _currentClockInRecord;
  String? _currentTimeOfficeId;
  bool _currentClockInIsOffline = false;
  int? _offlineClockInId;

  // Date and time
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedTime = DateTime.now();
  bool _hasChanges = false;

  // GPS
  double? _currentLatitude;
  double? _currentLongitude;
  int? _currentGpsAccuracy;
  bool _gpsEnabled = false;

  // Project calculations (done in background)
  String? _homeProjectId;
  String? _nearestProjectStartId;
  String? _nearestProjectFinishId;
  bool _isCalculatingProjects = false;

  // Breaks
  List<Map<String, dynamic>> _breaks = [];
  List<Map<String, dynamic>> _allProjects = [];
  Map<String, Map<String, dynamic>> _projectMapById = {};

  // Loading state
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    _setupConnectivityListener();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    
    try {
      await _loadCurrentUser();
      await _loadUserData();
      await _loadProjects();
      await _checkClockStatus();
      await _checkGpsStatus();
      
      // Calculate projects in background
      _calculateProjectsInBackground();
      
      // Round time to nearest 15 minutes
      _roundTimeToNearest15Minutes();
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
        _projectMapById = {};
        for (final project in projects) {
          final id = project['id']?.toString();
          if (id != null && id.isNotEmpty) {
            _projectMapById[id] = project;
          }
        }
      });
    } catch (e) {
      print('❌ Error loading projects: $e');
    }
  }

  Future<void> _checkClockStatus() async {
    try {
      if (_currentUser == null) return;

      final userId = _currentUser!['id']?.toString();
      if (userId == null) return;

      // Check online records for active clock-in
      Map<String, dynamic>? onlineRecord;
      try {
        final response = await SupabaseService.client
            .from('time_office')
            .select()
            .eq('user_id', userId)
            .eq('is_active', true)
            .isFilter('finish_time', null)
            .order('start_time', ascending: false)
            .limit(1)
            .maybeSingle();

        if (response != null) {
          onlineRecord = response as Map<String, dynamic>;
        }
      } catch (e) {
        print('⚠️ Error checking online clock status: $e');
      }

      // Also check offline storage for pending clock-in
      Map<String, dynamic>? offlineRecord;
      int? offlineRecordId;
      if (OfflineStorageService.isSupported) {
        try {
          final pendingEntries = await OfflineStorageService.getPendingEntries();
          for (final entry in pendingEntries) {
            final entryData = entry['entry_data'] as Map<String, dynamic>;
            final entryUserId = entryData['user_id']?.toString();
            final entryType = entryData['_entry_type']?.toString();
            
            if (entryUserId == userId && entryType == 'clock_in_office') {
              bool hasClockOut = false;
              for (final otherEntry in pendingEntries) {
                final otherData = otherEntry['entry_data'] as Map<String, dynamic>;
                final otherType = otherData['_entry_type']?.toString();
                if (otherType == 'clock_out_office') {
                  final refOfflineId = otherData['_clock_in_offline_id']?.toString();
                  final entryOfflineId = entryData['_offline_id']?.toString();
                  if (refOfflineId == entryOfflineId || 
                      refOfflineId == entry['id'].toString()) {
                    hasClockOut = true;
                    break;
                  }
                }
              }
              
              if (!hasClockOut) {
                offlineRecord = entryData;
                offlineRecordId = entry['id'] as int;
                break;
              }
            }
          }
        } catch (e) {
          print('⚠️ Error checking offline clock status: $e');
        }
      }

      final record = onlineRecord ?? offlineRecord;
      if (record != null) {
        // Load date/time from clock-in record
        DateTime? clockInDateTime;
        try {
          final startTime = record['start_time']?.toString();
          if (startTime != null && startTime.isNotEmpty) {
            clockInDateTime = DateTime.parse(startTime);
          }
        } catch (e) {
          print('⚠️ Error parsing start_time: $e');
        }
        
        setState(() {
          _isClockedIn = true;
          _currentClockInRecord = record;
          _currentClockInIsOffline = onlineRecord == null;
          _offlineClockInId = offlineRecordId;
          _currentTimeOfficeId = record['id']?.toString();
          
          // Set date from clock-in record (locked to clock-in date)
          // Set time to current time (for clock-out)
          if (clockInDateTime != null) {
            _selectedDate = DateTime(clockInDateTime.year, clockInDateTime.month, clockInDateTime.day);
            // Time defaults to current time rounded to 15 minutes for clock-out
            _roundTimeToNearest15Minutes();
          }
          
          // Load breaks if clocked in
          if (_currentTimeOfficeId != null && !_currentClockInIsOffline) {
            _loadBreaks();
          }
        });
      } else {
        setState(() {
          _isClockedIn = false;
          _currentClockInRecord = null;
          _currentClockInIsOffline = false;
          _offlineClockInId = null;
          _currentTimeOfficeId = null;
          _breaks = [];
        });
      }
    } catch (e) {
      print('❌ Error checking clock status: $e');
    }
  }

  Future<void> _loadBreaks() async {
    if (_currentTimeOfficeId == null) return;
    
    try {
      final breaks = await DatabaseService.readAdvanced(
        'time_office_breaks',
        filters: {
          'time_office_id': _currentTimeOfficeId,
          'is_active': true,
        },
        orderBy: 'display_order',
        ascending: true,
      );
      
      setState(() {
        _breaks = breaks.map((b) {
          // Parse break_start to time string (HH:mm format)
          String startTime = '';
          try {
            final breakStart = b['break_start']?.toString();
            if (breakStart != null && breakStart.isNotEmpty) {
              final startDateTime = DateTime.parse(breakStart);
              startTime = '${startDateTime.hour.toString().padLeft(2, '0')}:${startDateTime.minute.toString().padLeft(2, '0')}';
            }
          } catch (e) {
            print('⚠️ Error parsing break_start: $e');
          }
          
          // Parse break_finish to time string (HH:mm format)
          String finishTime = '';
          try {
            final breakFinish = b['break_finish']?.toString();
            if (breakFinish != null && breakFinish.isNotEmpty) {
              final finishDateTime = DateTime.parse(breakFinish);
              finishTime = '${finishDateTime.hour.toString().padLeft(2, '0')}:${finishDateTime.minute.toString().padLeft(2, '0')}';
            }
          } catch (e) {
            print('⚠️ Error parsing break_finish: $e');
          }
          
          return {
            'id': b['id']?.toString(),
            'start': startTime,
            'finish': finishTime,
            'display_order': b['display_order'] ?? 0,
          };
        }).toList();
      });
    } catch (e) {
      print('❌ Error loading breaks: $e');
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

  void _roundTimeToNearest15Minutes() {
    final now = DateTime.now();
    final roundedMinutes = ((now.minute / 15).round() * 15) % 60;
    final roundedTime = DateTime(now.year, now.month, now.day, now.hour, roundedMinutes);
    
    setState(() {
      _selectedTime = roundedTime;
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

  void _adjustDate(int days) {
    // If clocked in, date is locked to clock-in date
    if (_isClockedIn && _currentClockInRecord != null) {
      try {
        final startTime = _currentClockInRecord!['start_time']?.toString();
        if (startTime != null && startTime.isNotEmpty) {
          final clockInDateTime = DateTime.parse(startTime);
          final clockInDate = DateTime(clockInDateTime.year, clockInDateTime.month, clockInDateTime.day);
          // Date is locked when clocked in
          return;
        }
      } catch (e) {
        print('⚠️ Error parsing clock-in date: $e');
      }
    }
    
    final newDate = _selectedDate.add(Duration(days: days));
    final today = DateTime.now();
    final maxDate = DateTime(today.year, today.month, today.day);
    final newDateOnly = DateTime(newDate.year, newDate.month, newDate.day);
    
    if (newDateOnly.isAfter(maxDate)) {
      return; // Can't go past today
    }
    
    setState(() {
      _selectedDate = newDateOnly;
      _hasChanges = true;
    });
  }

  void _adjustTime(int minutes) {
    final newTime = _selectedTime.add(Duration(minutes: minutes));
    final rounded = _roundToNearest15Minutes(newTime);
    
    setState(() {
      _selectedTime = rounded;
      _hasChanges = true;
    });
  }

  Future<void> _calculateProjectsInBackground() async {
    if (_isCalculatingProjects) return;
    
    setState(() => _isCalculatingProjects = true);
    
    try {
      // Get home_project_id from users_data.project_1
      if (_userData != null) {
        final project1Name = _userData!['project_1']?.toString();
        if (project1Name != null && project1Name.isNotEmpty) {
          final project = _allProjects.firstWhere(
            (p) => p['project_name']?.toString() == project1Name,
            orElse: () => <String, dynamic>{},
          );
          if (project.isNotEmpty) {
            _homeProjectId = project['id']?.toString();
          }
        }
      }

      // Calculate nearest project if GPS is available
      if (_currentLatitude != null && _currentLongitude != null) {
        Map<String, dynamic>? nearestProject;
        double? minDistance;

        for (final project in _allProjects) {
          final lat = project['latitude'];
          final lng = project['longitude'];
          if (lat != null && lng != null) {
            final distance = Geolocator.distanceBetween(
              _currentLatitude!,
              _currentLongitude!,
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
          if (_isClockedIn) {
            // Calculate nearest project for finish (clock out)
            _nearestProjectFinishId = nearestProject['id']?.toString();
          } else {
            // Calculate nearest project for start (clock in)
            _nearestProjectStartId = nearestProject['id']?.toString();
          }
        }
      }
    } catch (e) {
      print('❌ Error calculating projects: $e');
    } finally {
      setState(() => _isCalculatingProjects = false);
    }
  }

  Future<void> _handleClockIn() async {
    // Get current GPS location if not available
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
        
        // Recalculate projects with new GPS
        await _calculateProjectsInBackground();
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

    setState(() => _isSaving = true);

    try {
      final userId = _currentUser!['id']?.toString();
      if (userId == null) throw Exception('User ID not found');

      // Combine date and time
      final clockInDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final roundedTime = _roundToNearest15Minutes(clockInDateTime);

      final timeOfficeData = {
        'user_id': userId,
        'home_project_id': _homeProjectId,
        'nearest_project_start_id': _nearestProjectStartId,
        'start_time': roundedTime.toIso8601String(), // User-adjusted date/time
        'start_timestamp': DateTime.now().toIso8601String(), // Actual time when clocked in
        'start_lat': _currentLatitude,
        'start_lng': _currentLongitude,
        'start_gps_accuracy': _currentGpsAccuracy,
        'offline_created': !_isOnline,
        'synced': _isOnline,
        'is_active': true,
      };

      if (_isOnline) {
        // Save online
        final result = await DatabaseService.create('time_office', timeOfficeData);
        _currentTimeOfficeId = result['id']?.toString();
      } else {
        // Save to offline queue
        if (!OfflineStorageService.isSupported) {
          throw Exception('Offline storage not available on this platform. Please ensure you have internet connection.');
        }

        final offlineId = 'clock_in_office_${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}';
        timeOfficeData['offline_id'] = offlineId;
        timeOfficeData['_entry_type'] = 'clock_in_office';
        timeOfficeData['_offline_id'] = offlineId;
        timeOfficeData['_table_name'] = 'time_office';

        await OfflineStorageService.addToQueue(timeOfficeData);
        
        setState(() {
          _isClockedIn = true;
          _currentClockInRecord = timeOfficeData;
          _currentClockInIsOffline = true;
        });
      }

      await _checkClockStatus();

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
        setState(() {
          _isSaving = false;
          _hasChanges = false;
        });
      }
    }
  }

  Future<void> _handleClockOut() async {
    if (_currentClockInRecord == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active clock-in record found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get current GPS location
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
      
      // Recalculate nearest project for finish
      await _calculateProjectsInBackground();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting GPS location: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Combine date and time
      final clockOutDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final roundedTime = _roundToNearest15Minutes(clockOutDateTime);

      if (_isOnline && !_currentClockInIsOffline && _currentTimeOfficeId != null) {
        // Clock-in was online, clock-out is online - update online record
        final updateData = {
          'finish_time': roundedTime.toIso8601String(), // User-adjusted date/time
          'finish_timestamp': DateTime.now().toIso8601String(), // Actual time when clocked out
          'finish_lat': _currentLatitude,
          'finish_lng': _currentLongitude,
          'finish_gps_accuracy': _currentGpsAccuracy,
          'nearest_project_finish_id': _nearestProjectFinishId,
          'synced': true,
        };

        await DatabaseService.update('time_office', _currentTimeOfficeId!, updateData);
      } else {
        // Either clock-in was offline, or clock-out is offline - use offline storage
        if (!OfflineStorageService.isSupported) {
          throw Exception('Offline storage not available on this platform. Please ensure you have internet connection.');
        }

        final clockOutData = {
          'finish_time': roundedTime.toIso8601String(), // User-adjusted date/time
          'finish_timestamp': DateTime.now().toIso8601String(), // Actual time when clocked out
          'finish_lat': _currentLatitude,
          'finish_lng': _currentLongitude,
          'finish_gps_accuracy': _currentGpsAccuracy,
          'nearest_project_finish_id': _nearestProjectFinishId,
        };

        clockOutData['_entry_type'] = 'clock_out_office';
        clockOutData['_table_name'] = 'time_office';
        
        if (_currentClockInIsOffline && _offlineClockInId != null) {
          clockOutData['_clock_in_offline_id'] = _offlineClockInId.toString();
          clockOutData['_clock_in_offline_record'] = _currentClockInRecord!['_offline_id']?.toString();
        } else if (_currentTimeOfficeId != null) {
          clockOutData['_clock_in_record_id'] = _currentTimeOfficeId;
        }

        await OfflineStorageService.addToQueue(clockOutData);
      }

      await _checkClockStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isOnline 
                ? 'Clocked out successfully!'
                : 'Clocked out offline. Will sync when online.'),
            backgroundColor: _isOnline ? Colors.green : Colors.orange,
          ),
        );
        Navigator.of(context).pop(true);
      }
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
        setState(() {
          _isSaving = false;
          _hasChanges = false;
        });
      }
    }
  }

  Future<void> _handleClose() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    // Save any changes (breaks only - don't change clock-in time)
    if (_isClockedIn && _currentTimeOfficeId != null && !_currentClockInIsOffline) {
      setState(() => _isSaving = true);
      
      try {
        // Only save breaks (clock-in time should not be changed after clocking in)
        await _saveBreaks();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Changes saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print('❌ Error saving changes: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving changes: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
            _hasChanges = false;
          });
        }
      }
    } else if (_isClockedIn && _currentClockInIsOffline) {
      // For offline records, just close - changes will sync when online
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleAddBreak() async {
    if (!_isClockedIn || _currentClockInRecord == null) return;
    
    // Get clock-in start time
    DateTime? clockInStart;
    try {
      final startTime = _currentClockInRecord!['start_time']?.toString();
      if (startTime != null && startTime.isNotEmpty) {
        clockInStart = DateTime.parse(startTime);
      }
    } catch (e) {
      print('⚠️ Error parsing clock-in start time: $e');
    }
    
    if (clockInStart == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to determine clock-in time.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final timeOptions = _generateTimeOptions();
    final clockInTimeString = '${clockInStart.hour.toString().padLeft(2, '0')}:${clockInStart.minute.toString().padLeft(2, '0')}';
    
    // Find valid start time options (after clock-in start time)
    final startOptions = timeOptions.where((time) {
      final timeMinutes = _timeStringToMinutes(time);
      final startMinutes = _timeStringToMinutes(clockInTimeString);
      return timeMinutes >= startMinutes;
    }).toList();
    
    if (startOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid break times available.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      _breaks.add({
        'id': null,
        'start': startOptions.first,
        'finish': '',
        'display_order': _breaks.length,
      });
      _hasChanges = true;
    });
  }

  Future<void> _saveBreaks() async {
    if (_currentTimeOfficeId == null || _currentClockInIsOffline) return;
    
    try {
      // Get clock-in date from record
      DateTime breakDate = _selectedDate;
      try {
        if (_currentClockInRecord != null) {
          final startTime = _currentClockInRecord!['start_time']?.toString();
          if (startTime != null && startTime.isNotEmpty) {
            final clockInDateTime = DateTime.parse(startTime);
            breakDate = DateTime(clockInDateTime.year, clockInDateTime.month, clockInDateTime.day);
          }
        }
      } catch (e) {
        print('⚠️ Error parsing clock-in date for breaks: $e');
      }
      
      // Get existing breaks
      final existingBreaks = await DatabaseService.readAdvanced(
        'time_office_breaks',
        filters: {
          'time_office_id': _currentTimeOfficeId,
        },
      );
      
      // Delete existing breaks
      for (final breakRecord in existingBreaks) {
        final breakId = breakRecord['id']?.toString();
        if (breakId != null) {
          await DatabaseService.delete('time_office_breaks', breakId);
        }
      }
      
      // Save new breaks
      for (int i = 0; i < _breaks.length; i++) {
        final breakData = _breaks[i];
        final startTime = breakData['start']?.toString();
        final finishTime = breakData['finish']?.toString();
        
        if (startTime != null && startTime.isNotEmpty) {
          // Parse start time using clock-in date
          final startDateTime = _parseTimeString(startTime, breakDate);
          
          final breakRecord = {
            'time_office_id': _currentTimeOfficeId,
            'break_start': startDateTime.toIso8601String(),
            'break_finish': finishTime != null && finishTime.isNotEmpty
                ? _parseTimeString(finishTime, breakDate).toIso8601String()
                : null,
            'display_order': i,
            'is_active': true,
            'offline_created': !_isOnline,
            'synced': _isOnline,
          };
          
          await DatabaseService.create('time_office_breaks', breakRecord);
        }
      }
    } catch (e) {
      print('❌ Error saving breaks: $e');
      rethrow;
    }
  }

  DateTime _parseTimeString(String timeString, DateTime date) {
    final parts = timeString.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
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

  int _timeStringToMinutes(String timeString) {
    if (timeString.isEmpty) return 0;
    final parts = timeString.split(':');
    if (parts.length != 2) return 0;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    return hours * 60 + minutes;
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

  Widget _buildBreakRow(int index) {
    final breakData = _breaks[index];
    final startTime = breakData['start']?.toString() ?? '';
    final finishTime = breakData['finish']?.toString() ?? '';
    
    // Get clock-in start time for limiting break options
    DateTime? clockInStart;
    try {
      if (_currentClockInRecord != null) {
        final startTimeStr = _currentClockInRecord!['start_time']?.toString();
        if (startTimeStr != null && startTimeStr.isNotEmpty) {
          clockInStart = DateTime.parse(startTimeStr);
        }
      }
    } catch (e) {
      print('⚠️ Error parsing clock-in start time for breaks: $e');
    }
    
    String? clockInTimeString;
    if (clockInStart != null) {
      clockInTimeString = '${clockInStart.hour.toString().padLeft(2, '0')}:${clockInStart.minute.toString().padLeft(2, '0')}';
    }
    
    final timeOptions = _generateTimeOptions();
    final startOptions = clockInTimeString != null
        ? _generateLimitedTimeOptions(clockInTimeString, finishTime.isNotEmpty ? finishTime : null)
        : _generateLimitedTimeOptions(null, finishTime.isNotEmpty ? finishTime : null);
    final finishOptions = startTime.isNotEmpty 
        ? _generateLimitedTimeOptions(startTime, null)
        : <String>[];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: startTime.isNotEmpty ? startTime : null,
                decoration: const InputDecoration(
                  labelText: 'Break Start',
                  border: OutlineInputBorder(),
                ),
                items: startOptions.map((time) {
                  return DropdownMenuItem(
                    value: time,
                    child: Text(_convertTo12Hour(time)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _breaks[index]['start'] = value ?? '';
                    if (value != null && finishTime.isNotEmpty) {
                      final finishMinutes = _timeStringToMinutes(finishTime);
                      final startMinutes = _timeStringToMinutes(value);
                      if (finishMinutes <= startMinutes) {
                        _breaks[index]['finish'] = '';
                      }
                    }
                    _hasChanges = true;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: finishTime.isNotEmpty ? finishTime : null,
                decoration: const InputDecoration(
                  labelText: 'Break Finish',
                  border: OutlineInputBorder(),
                ),
                items: finishOptions.map((time) {
                  return DropdownMenuItem(
                    value: time,
                    child: Text(_convertTo12Hour(time)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _breaks[index]['finish'] = value ?? '';
                    _hasChanges = true;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                setState(() {
                  _breaks.removeAt(index);
                  _hasChanges = true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Office Clock In/Out',
            style: TextStyle(color: Colors.black),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0081FB),
          foregroundColor: Colors.black,
          actions: const [ScreenInfoIcon(screenName: 'clock_office_screen.dart')],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Office Clock In/Out',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'clock_office_screen.dart')],
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

            // Date Selection
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: _isClockedIn ? null : () => _adjustDate(-1),
                  ),
                  Text(
                    DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isClockedIn ? Colors.grey : Colors.black,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios),
                    onPressed: _isClockedIn ? null : () {
                      final today = DateTime.now();
                      final todayOnly = DateTime(today.year, today.month, today.day);
                      final selectedOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
                      if (selectedOnly.isAtSameMomentAs(todayOnly)) {
                        return; // Can't go past today
                      }
                      _adjustDate(1);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Time Selection
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => _adjustTime(-15),
                  ),
                  Text(
                    DateFormat('h:mm a').format(_selectedTime),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _adjustTime(15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Breaks Section (only if clocked in)
            if (_isClockedIn) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Breaks',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Break'),
                    onPressed: _handleAddBreak,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...List.generate(_breaks.length, (index) => _buildBreakRow(index)),
              const SizedBox(height: 24),
            ],

            // Action Buttons
            if (!_isClockedIn) ...[
              // Clock In Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _handleClockIn,
                  icon: const Icon(Icons.login),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Clock In',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ] else ...[
              // Close and Clock Out Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _handleClose,
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _handleClockOut,
                      icon: const Icon(Icons.logout),
                      label: Text(
                        _isSaving ? 'Saving...' : 'Clock Out',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
