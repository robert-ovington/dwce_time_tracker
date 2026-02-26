/// Clock In/Out Screen
/// 
/// Allows users to clock in and clock out with GPS tracking.
/// Features:
/// - GPS location capture
/// - Online/offline status display
/// - Project selection with "Find Nearest Job" and "Find Next"
/// - Clock In/Out functionality

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

class ClockInOutScreen extends StatefulWidget {
  const ClockInOutScreen({super.key});

  @override
  State<ClockInOutScreen> createState() => _ClockInOutScreenState();
}

class _ClockInOutScreenState extends State<ClockInOutScreen> {
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
  String? _currentProjectId;
  String _currentProjectName = '';
  bool _currentClockInIsOffline = false; // True if current clock-in is stored offline
  int? _offlineClockInId; // ID of offline clock-in record if applicable

  // Form fields
  DateTime _currentDateTime = DateTime.now();
  String _selectedProject = '';
  String _selectedProjectDescription = '';
  bool _projectSelected = false;

  // Project data
  List<Map<String, dynamic>> _allProjects = [];
  Map<String, Map<String, dynamic>> _projectMapByName = {};
  String _projectFilter = '';
  int _projectFilterResetCounter = 0;
  String _findNearestButtonText = 'Find Nearest Job';
  bool _isFindingNearest = false;
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
      await _checkClockStatus();
      await _checkGpsStatus();
      
      // Update date/time every minute
      _updateCurrentDateTime();
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
      // Set limit to 10000 to handle growth (currently ~7000 active projects, allowing for future growth)
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

  Future<void> _checkClockStatus() async {
    try {
      if (_currentUser == null) return;

      final userId = _currentUser!['id']?.toString();
      if (userId == null) return;

      // First check online records for active clock-in
      Map<String, dynamic>? onlineRecord;
      try {
        final response = await SupabaseService.client
            .from('time_attendance')
            .select()
            .eq('user_id', userId)
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
          // Find clock-in records (not clock-out)
          for (final entry in pendingEntries) {
            final entryData = entry['entry_data'] as Map<String, dynamic>;
            final entryUserId = entryData['user_id']?.toString();
            final entryType = entryData['_entry_type']?.toString();
            
            // Check if this is a clock-in for current user
            if (entryUserId == userId && entryType == 'clock_in') {
              // Check if this clock-in hasn't been clocked out yet
              // Look for clock-out record that references this clock-in
              bool hasClockOut = false;
              for (final otherEntry in pendingEntries) {
                final otherData = otherEntry['entry_data'] as Map<String, dynamic>;
                final otherType = otherData['_entry_type']?.toString();
                if (otherType == 'clock_out') {
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
                // Found an unclocked clock-in
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

      // Use online record if available, otherwise use offline record
      final record = onlineRecord ?? offlineRecord;
      if (record != null) {
        setState(() {
          _isClockedIn = true;
          _currentClockInRecord = record;
          _currentClockInIsOffline = onlineRecord == null;
          _offlineClockInId = offlineRecordId;
          _currentProjectId = record['project_id']?.toString();
          
          // Load project name if project_id exists
          if (_currentProjectId != null && _currentProjectId!.isNotEmpty) {
            final project = _projectMapByName.values.firstWhere(
              (p) => p['id']?.toString() == _currentProjectId,
              orElse: () => <String, dynamic>{},
            );
            if (project.isNotEmpty) {
              _currentProjectName = project['project_name']?.toString() ?? '';
              _selectedProject = _currentProjectName;
              _projectSelected = true;
            }
          }
        });
      } else {
        setState(() {
          _isClockedIn = false;
          _currentClockInRecord = null;
          _currentClockInIsOffline = false;
          _offlineClockInId = null;
          _currentProjectId = null;
          _currentProjectName = '';
        });
      }
    } catch (e) {
      print('❌ Error checking clock status: $e');
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
        // Request permission and get current location
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

    // Check initial connectivity
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
    // Update date/time every minute
    _dateTimeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateCurrentDateTime();
    });
  }

  void _updateCurrentDateTime() {
    final now = DateTime.now();
    // Round to nearest 15 minutes
    final roundedMinutes = ((now.minute / 15).round() * 15) % 60;
    final roundedTime = DateTime(now.year, now.month, now.day, now.hour, roundedMinutes);
    
    setState(() {
      _currentDateTime = roundedTime;
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

  /// Show confirmation dialog for clock in
  Future<bool?> _showClockInConfirmation(Map<String, dynamic> project, double? distanceKm) async {
    final projectName = project['project_name']?.toString() ?? '';
    final clientName = project['client_name']?.toString() ?? 'Not specified';
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(_currentDateTime);
    final timeStr = DateFormat('h:mm a').format(_currentDateTime);
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

  /// Show confirmation dialog for clock out
  Future<bool?> _showClockOutConfirmation(Map<String, dynamic> project, double? distanceKm) async {
    final projectName = project['project_name']?.toString() ?? '';
    final clientName = project['client_name']?.toString() ?? 'Not specified';
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(_currentDateTime);
    final timeStr = DateFormat('h:mm a').format(_currentDateTime);
    final distanceStr = distanceKm != null 
        ? '${distanceKm.toStringAsFixed(2)} km'
        : 'Distance unavailable';

    // Calculate time on site
    String timeOnSiteStr = 'Not available';
    if (_currentClockInRecord != null && _currentClockInRecord!['start_time'] != null) {
      try {
        final startTime = DateTime.parse(_currentClockInRecord!['start_time']?.toString() ?? '');
        final roundedFinishTime = _roundToNearest15Minutes(_currentDateTime);
        final duration = roundedFinishTime.difference(startTime);
        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;
        timeOnSiteStr = '$hours:${minutes.toString().padLeft(2, '0')}';
      } catch (e) {
        print('Error calculating time on site: $e');
      }
    }

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
                const SizedBox(height: 8),
                _buildDetailRow('Time on Site:', timeOnSiteStr),
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

  /// Helper widget to build a detail row in confirmation dialog
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

      // Update cached GPS
      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
        _currentGpsAccuracy = position.accuracy.round();
      });

      // Find nearest project
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

  Future<void> _handleClockIn() async {
    if (!_projectSelected || _selectedProject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a project first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get current GPS location if not available (works on both web and mobile)
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

    // Get project data for confirmation dialog
    final project = _projectMapByName[_selectedProject];
    if (project == null) throw Exception('Project not found');
    
    // Calculate distance from current location to project
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

    // Show confirmation dialog
    final confirmed = await _showClockInConfirmation(project, distanceKm);
    if (confirmed != true) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = _currentUser!['id']?.toString();
      if (userId == null) throw Exception('User ID not found');

      final projectId = project['id']?.toString();

      final roundedTime = _roundToNearest15Minutes(_currentDateTime);

      final attendanceData = {
        'user_id': userId,
        'project_id': projectId,
        'start_time': roundedTime.toIso8601String(),
        'start_lat': _currentLatitude,
        'start_lng': _currentLongitude,
        'start_gps_accuracy': _currentGpsAccuracy,
        'offline_created': !_isOnline,
        'synced': _isOnline,
      };

      if (_isOnline) {
        // Save online
        await DatabaseService.create('time_attendance', attendanceData);
      } else {
        // Save to offline queue
        if (!OfflineStorageService.isSupported) {
          throw Exception('Offline storage not available on this platform. Please ensure you have internet connection.');
        }

        // Generate offline_id for tracking
        final offlineId = 'clock_in_${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}';
        attendanceData['offline_id'] = offlineId;
        
        // Add marker to identify this as a clock_in entry
        attendanceData['_entry_type'] = 'clock_in';
        attendanceData['_offline_id'] = offlineId;
        attendanceData['_table_name'] = 'time_attendance';

        await OfflineStorageService.addToQueue(attendanceData);
        
        // Update local state to reflect clock-in
        setState(() {
          _isClockedIn = true;
          _currentClockInRecord = attendanceData;
          _currentClockInIsOffline = true;
          _currentProjectId = projectId;
          _currentProjectName = _selectedProject;
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
        Navigator.of(context).pop(true); // Return true to indicate successful clock-in
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
        setState(() => _isSaving = false);
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

    // Get current GPS location (works on both web and mobile)
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

    // Get project data for confirmation dialog
    Map<String, dynamic>? project;
    if (_currentProjectId != null && _currentProjectId!.isNotEmpty) {
      project = _projectMapByName.values.firstWhere(
        (p) => p['id']?.toString() == _currentProjectId,
        orElse: () => <String, dynamic>{},
      );
      if (project?.isEmpty ?? true) {
        // Fallback to selected project if project ID lookup fails
        project = _projectMapByName[_selectedProject];
      }
    } else {
      project = _projectMapByName[_selectedProject];
    }

    if (project == null || project.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project information not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Calculate distance from current location to project
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

    // Show confirmation dialog
    final confirmed = await _showClockOutConfirmation(project, distanceKm);
    if (confirmed != true) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final roundedTime = _roundToNearest15Minutes(_currentDateTime);

      if (_isOnline && !_currentClockInIsOffline) {
        // Clock-in was online, clock-out is online - update online record
        final recordId = _currentClockInRecord!['id']?.toString();
        if (recordId == null) throw Exception('Record ID not found');

        final updateData = {
          'finish_time': roundedTime.toIso8601String(),
          'finish_lat': _currentLatitude,
          'finish_lng': _currentLongitude,
          'finish_gps_accuracy': _currentGpsAccuracy,
          'synced': true,
        };

        await DatabaseService.update('time_attendance', recordId, updateData);
      } else {
        // Either clock-in was offline, or clock-out is offline - use offline storage
        if (!OfflineStorageService.isSupported) {
          throw Exception('Offline storage not available on this platform. Please ensure you have internet connection.');
        }

        // Prepare clock-out data
        final clockOutData = {
          'finish_time': roundedTime.toIso8601String(),
          'finish_lat': _currentLatitude,
          'finish_lng': _currentLongitude,
          'finish_gps_accuracy': _currentGpsAccuracy,
        };

        // Add metadata to identify this as a clock-out entry
        clockOutData['_entry_type'] = 'clock_out';
        clockOutData['_table_name'] = 'time_attendance';
        
        // Reference the clock-in record (either online ID or offline ID)
        if (_currentClockInIsOffline && _offlineClockInId != null) {
          // Clock-in was offline - reference offline record ID
          clockOutData['_clock_in_offline_id'] = _offlineClockInId.toString();
          clockOutData['_clock_in_offline_record'] = _currentClockInRecord!['_offline_id']?.toString();
        } else if (_currentClockInRecord!['id'] != null) {
          // Clock-in was online - reference online record ID
          clockOutData['_clock_in_record_id'] = _currentClockInRecord!['id']?.toString();
        }

        // Store clock-out in offline queue
        await OfflineStorageService.addToQueue(clockOutData);
        
        // Update local state to reflect clock-out
        setState(() {
          _isClockedIn = false;
          _currentClockInRecord = null;
          _currentClockInIsOffline = false;
          _offlineClockInId = null;
        });
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
        Navigator.of(context).pop(true); // Return true to indicate successful clock-in
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
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildProjectDetailsContent() {
    // Find the selected project data using fast O(1) map lookup
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
          actions: const [ScreenInfoIcon(screenName: 'clock_in_out_screen.dart')],
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
        actions: const [ScreenInfoIcon(screenName: 'clock_in_out_screen.dart')],
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

            // Current Date and Time (rounded to 15 minutes)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.grey),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, MMMM d, yyyy').format(_currentDateTime),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        DateFormat('h:mm a').format(_currentDateTime),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
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
                    // Header
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
                          // Project Filter Text Box
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
                                    final filterTerms = value.toLowerCase().split(' ').where((t) => t.isNotEmpty).toList();
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
                          const SizedBox(height: 16),
                          // Project Dropdown
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

                          // Find Nearest Job / Find Next Button
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
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Project Details
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

            // Clock In/Out Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isSaving || (_isClockedIn && !_projectSelected)) 
                    ? null 
                    : (_isClockedIn ? _handleClockOut : _handleClockIn),
                icon: Icon(_isClockedIn ? Icons.logout : Icons.login),
                label: Text(
                  _isSaving 
                      ? 'Saving...' 
                      : (_isClockedIn ? 'Clock Out' : 'Clock In'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isClockedIn ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
