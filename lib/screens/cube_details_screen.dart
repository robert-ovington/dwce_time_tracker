/// Cube Details Screen
/// 
/// Allows users to record concrete cube test details with GPS tracking.
/// Features:
/// - Online/offline status display
/// - Employee details
/// - Date & Time selection (restricted like timesheet_screen)
/// - Project selection
/// - Concrete Cube Details (Ticket Number, Cube Reference, Concrete Mix, Cube Size, Slump, Test Age)
/// - Photo capture for ticket (camera or gallery)
/// - Location capture with multiple options
/// - Offline support

import 'dart:async';
import 'dart:io' show File;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/widgets/screen_info_icon.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/offline/offline_storage_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';

class CubeDetailsScreen extends StatefulWidget {
  const CubeDetailsScreen({super.key});

  @override
  State<CubeDetailsScreen> createState() => _CubeDetailsScreenState();
}

class _CubeDetailsScreenState extends State<CubeDetailsScreen> {
  // Connectivity
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // User data
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _userData;
  String _displayName = '';

  // Form fields
  String _date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _timeOfPour = ''; // Time of Pour (rounded to nearest 15 minutes)
  
  // Project fields
  String _selectedProject = '';
  String _selectedProjectDescription = '';
  bool _projectSelected = false;
  List<Map<String, dynamic>> _allProjects = [];
  Map<String, Map<String, dynamic>> _projectMapByName = {};

  // Concrete Cube Details
  String _ticketNumber = '';
  String _concreteMix = ''; // Auto-populated from time_periods based on ticket number
  String _cubeSize = '100mm x 100mm x 100mm';
  String _cubeReference = 'A'; // Auto-increment based on ticket number count
  String _slump = '';
  String _testAge = ''; // Numeric value between 7 and 58

  // Location fields
  String _latitude = '';
  String _longitude = '';

  // GPS
  double? _currentLatitude;
  double? _currentLongitude;
  int? _currentGpsAccuracy;

  // Ticket numbers (filtered by project_id)
  List<Map<String, dynamic>> _ticketNumbers = [];
  
  // Dates with time periods (for enabling date picker)
  Set<String> _datesWithTimePeriods = {};

  // Loading state
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  // Week start from system_settings: 0-6 (PostgreSQL DOW: 0=Sunday .. 6=Saturday)
  int? _weekStartDow;
  
  // Photo upload
  static const String _photoBucketName = 'concrete_cube_truck_docket_link';

  @override
  void initState() {
    super.initState();
    _initialize();
    _setupConnectivityListener();
    // Time of Pour will be populated when Ticket Number is selected
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _initializeTimeOfPour() {
    // Default to current time rounded to nearest 15 minutes
    final now = DateTime.now();
    final minutes = now.minute;
    final roundedMinutes = ((minutes / 15).round() * 15) % 60;
    final hours = roundedMinutes == 0 && minutes > 45 ? now.hour + 1 : now.hour;
    final roundedTime = DateTime(now.year, now.month, now.day, hours % 24, roundedMinutes);
    
    setState(() {
      _timeOfPour = DateFormat('HH:mm').format(roundedTime);
    });
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    
    try {
      await _loadCurrentUser();
      await _loadUserData();
      await _loadWeekStart();
      await _loadDatesWithTimePeriods();
      _checkDateRestrictions();
      // Load projects after date is set (will be filtered by date)
      await _loadProjects();
      await _checkGpsStatus();
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

  void _setupConnectivityListener() {
    Connectivity().checkConnectivity().then((results) {
      final isOnline = results.any((result) => result != ConnectivityResult.none);
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((result) => result != ConnectivityResult.none);
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
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
    if (_currentUser == null || _date.isEmpty) {
      setState(() {
        _allProjects = [];
        _projectMapByName = {};
      });
      return;
    }

    try {
      // Load projects that have time periods for the current user on the selected date
      final response = await SupabaseService.client
          .from('time_periods')
          .select('project_id, projects!inner(id, project_name, client_name, description_of_work, latitude, longitude, is_active)')
          .eq('user_id', _currentUser!['id'] as Object)
          .eq('work_date', _date)
          .eq('is_active', true)
          .not('project_id', 'is', null);

      final projectIds = <String>{};
      final projectsMap = <String, Map<String, dynamic>>{};
      
      for (final period in response) {
        final project = period['projects'] as Map<String, dynamic>?;
        if (project != null) {
          final projectId = project['id']?.toString();
          if (projectId != null && !projectIds.contains(projectId)) {
            projectIds.add(projectId);
            final projectName = project['project_name']?.toString() ?? '';
            if (projectName.isNotEmpty) {
              projectsMap[projectName] = project;
            }
          }
        }
      }

      // Convert to list and sort by project_name
      final projectsList = projectsMap.values.toList();
      projectsList.sort((a, b) {
        final nameA = a['project_name']?.toString() ?? '';
        final nameB = b['project_name']?.toString() ?? '';
        return nameA.compareTo(nameB);
      });
      
      setState(() {
        _allProjects = projectsList;
        _projectMapByName = projectsMap;
        
        // Clear selected project if it's no longer in the filtered list
        if (_selectedProject.isNotEmpty && !projectsMap.containsKey(_selectedProject)) {
          _selectedProject = '';
          _selectedProjectDescription = '';
          _projectSelected = false;
          _ticketNumbers = [];
        }
      });
    } catch (e) {
      print('❌ Error loading projects: $e');
      setState(() {
        _allProjects = [];
        _projectMapByName = {};
      });
    }
  }

  Future<void> _loadWeekStart() async {
    try {
      final response = await SupabaseService.client
          .from('system_settings')
          .select('week_start')
          .limit(1)
          .maybeSingle();
      if (response != null) {
        final v = int.tryParse(response['week_start']?.toString() ?? '');
        if (v != null && v >= 0 && v <= 6) setState(() => _weekStartDow = v);
      }
    } catch (e) {
      print('⚠️ Error loading week start setting: $e');
    }
  }

  void _checkDateRestrictions() {
    // Similar to timesheet_screen - prevent selecting dates outside current week
    final selectedDate = DateTime.tryParse(_date);
    if (selectedDate == null) return;

    final now = DateTime.now();
    final weekStartDay = _getWeekStartDay();
    final currentWeekStart = _getWeekStart(now, weekStartDay);
    final currentWeekEnd = currentWeekStart.add(const Duration(days: 6));

    if (selectedDate.isBefore(currentWeekStart) || selectedDate.isAfter(currentWeekEnd)) {
      setState(() {
        _date = DateFormat('yyyy-MM-dd').format(currentWeekStart);
      });
    }
  }

  /// Dart weekday for week start (1=Mon .. 7=Sun) from DOW 0-6
  int _getWeekStartDay() {
    final dow = _weekStartDow ?? 1;
    return dow == 0 ? 7 : dow;
  }

  DateTime _getWeekStart(DateTime date, int weekStartDay) {
    final daysToSubtract = (date.weekday - weekStartDay + 7) % 7;
    return date.subtract(Duration(days: daysToSubtract));
  }

  /// Load dates with time periods for the current user
  Future<void> _loadDatesWithTimePeriods() async {
    if (_currentUser == null) return;

    try {
      final response = await SupabaseService.client
          .from('time_periods')
          .select('work_date')
          .eq('user_id', _currentUser!['id'] as Object)
          .eq('is_active', true)
          .not('work_date', 'is', null);

      final dates = <String>{};
      for (final period in response) {
        final workDate = period['work_date']?.toString();
        if (workDate != null && workDate.isNotEmpty) {
          dates.add(workDate);
        }
      }

      setState(() {
        _datesWithTimePeriods = dates;
      });
      
      // If current date is not in the set, set to the most recent valid date
      if (dates.isNotEmpty && !dates.contains(_date)) {
        final sortedDates = dates.toList()..sort();
        // Use the most recent date (last in sorted list)
        final mostRecentDate = sortedDates.last;
        setState(() {
          _date = mostRecentDate;
        });
        // Reload projects and ticket numbers for the new date
        _loadProjects();
        _loadTicketNumbers();
      } else if (dates.isNotEmpty) {
        // Reload projects and ticket numbers for the current date
        _loadProjects();
        _loadTicketNumbers();
      }
    } catch (e) {
      print('❌ Error loading dates with time periods: $e');
      _datesWithTimePeriods = {};
    }
  }

  /// Find next date with time periods (forward)
  String? _getNextDateWithTimePeriods(String currentDateStr) {
    final currentDate = DateTime.tryParse(currentDateStr);
    if (currentDate == null || _datesWithTimePeriods.isEmpty) return null;

    final sortedDates = _datesWithTimePeriods.toList()..sort();
    for (final dateStr in sortedDates) {
      final date = DateTime.tryParse(dateStr);
      if (date != null && date.isAfter(currentDate)) {
        return dateStr;
      }
    }
    return null;
  }

  /// Find previous date with time periods (backward)
  String? _getPreviousDateWithTimePeriods(String currentDateStr) {
    final currentDate = DateTime.tryParse(currentDateStr);
    if (currentDate == null || _datesWithTimePeriods.isEmpty) return null;

    final sortedDates = _datesWithTimePeriods.toList()..sort();
    for (int i = sortedDates.length - 1; i >= 0; i--) {
      final dateStr = sortedDates[i];
      final date = DateTime.tryParse(dateStr);
      if (date != null && date.isBefore(currentDate)) {
        return dateStr;
      }
    }
    return null;
  }

  Future<void> _loadTicketNumbers() async {
    if (!_projectSelected || _selectedProject.isEmpty || _currentUser == null || _date.isEmpty) {
      setState(() {
        _ticketNumbers = [];
      });
      return;
    }

    try {
      // Get project_id from selected project
      final project = _projectMapByName[_selectedProject];
      if (project == null || project['id'] == null) {
        setState(() {
          _ticketNumbers = [];
        });
        return;
      }

      final projectId = project['id']?.toString();
      if (projectId == null) {
        setState(() {
          _ticketNumbers = [];
        });
        return;
      }

      // Load ticket numbers from time_periods filtered by date, user_id, and project_id
      final response = await SupabaseService.client
          .from('time_periods')
          .select('concrete_ticket_no, concrete_mix_type')
          .eq('user_id', _currentUser!['id'] as Object)
          .eq('work_date', _date)
          .eq('project_id', projectId as Object)
          .eq('is_active', true)
          .not('concrete_ticket_no', 'is', null)
          .order('concrete_ticket_no', ascending: true); // Sort ascending

      final tickets = List<Map<String, dynamic>>.from(response as List);
      
      // Remove duplicates while preserving order (ascending)
      final uniqueTickets = <int, Map<String, dynamic>>{};
      for (final ticket in tickets) {
        final ticketNo = ticket['concrete_ticket_no'] as int?;
        if (ticketNo != null && !uniqueTickets.containsKey(ticketNo)) {
          uniqueTickets[ticketNo] = ticket;
        }
      }

      // Convert back to list sorted by ticket number (ascending)
      final sortedTickets = uniqueTickets.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      setState(() {
        _ticketNumbers = sortedTickets.map((e) => e.value).toList();
      });
    } catch (e) {
      print('❌ Error loading ticket numbers: $e');
      setState(() {
        _ticketNumbers = [];
      });
    }
  }

  Future<void> _updateConcreteMixFromTicket() async {
    if (_ticketNumber.isEmpty) {
      setState(() {
        _concreteMix = '';
      });
      return;
    }

    try {
      final ticketNo = int.tryParse(_ticketNumber);
      if (ticketNo == null) {
        setState(() {
          _concreteMix = '';
        });
        return;
      }

      // Query time_periods directly using ticket number to get concrete_mix_type
      final response = await SupabaseService.client
          .from('time_periods')
          .select('concrete_mix_type')
          .eq('concrete_ticket_no', ticketNo)
          .eq('is_active', true)
          .not('concrete_mix_type', 'is', null)
          .order('work_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null || response['concrete_mix_type'] == null) {
        setState(() {
          _concreteMix = '';
        });
        return;
      }

      // Get concrete_mix_type (which is the UUID id from concrete_mix table)
      final mixTypeId = response['concrete_mix_type']?.toString();
      if (mixTypeId == null || mixTypeId.isEmpty) {
        setState(() {
          _concreteMix = '';
        });
        return;
      }

      // Look up concrete mix name from concrete_mix table
      try {
        print('🔍 Looking up concrete mix name for id: $mixTypeId');
        final mixResponse = await SupabaseService.client
            .from('concrete_mix')
            .select('id, name')
            .eq('id', mixTypeId)
            .maybeSingle();

        if (mixResponse != null) {
          final mixName = mixResponse['name']?.toString() ?? '';
          print('✅ Found concrete mix name: $mixName');
          setState(() {
            _concreteMix = mixName;
          });
        } else {
          print('⚠️ No concrete mix found for id: $mixTypeId');
          setState(() {
            _concreteMix = '';
          });
        }
      } catch (e) {
        print('⚠️ Error loading concrete mix details: $e');
        setState(() {
          _concreteMix = '';
        });
      }
    } catch (e) {
      print('❌ Error updating concrete mix from ticket: $e');
      setState(() {
        _concreteMix = '';
      });
    }
  }

  Future<void> _updateTimeOfPourFromTicket() async {
    if (_ticketNumber.isEmpty) {
      setState(() {
        _timeOfPour = '';
      });
      return;
    }

    try {
      final ticketNo = int.tryParse(_ticketNumber);
      if (ticketNo == null) {
        setState(() {
          _timeOfPour = '';
        });
        return;
      }

      // Query time_periods directly using ticket number to get finish_time
      final response = await SupabaseService.client
          .from('time_periods')
          .select('finish_time')
          .eq('concrete_ticket_no', ticketNo)
          .eq('is_active', true)
          .not('finish_time', 'is', null)
          .order('work_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null || response['finish_time'] == null) {
        setState(() {
          _timeOfPour = '';
        });
        return;
      }

      // Get finish_time and format as hh:mm
      final finishTime = response['finish_time']?.toString();
      if (finishTime == null || finishTime.isEmpty) {
        setState(() {
          _timeOfPour = '';
        });
        return;
      }

      // Parse finish_time (assumes it's in HH:mm or HH:mm:ss format or ISO 8601)
      try {
        DateTime? timeValue;
        if (finishTime.contains('T')) {
          // ISO 8601 format
          timeValue = DateTime.tryParse(finishTime);
        } else {
          // HH:mm or HH:mm:ss format
          final parts = finishTime.split(':');
          if (parts.length >= 2) {
            final hour = int.tryParse(parts[0]) ?? 0;
            final minute = int.tryParse(parts[1]) ?? 0;
            timeValue = DateTime(2000, 1, 1, hour, minute);
          }
        }

        if (timeValue != null) {
          final timeStr = DateFormat('HH:mm').format(timeValue);
          setState(() {
            _timeOfPour = timeStr;
          });

          // Show popup for 3 seconds
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Time of Pour has been updated to $timeStr'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          setState(() {
            _timeOfPour = '';
          });
        }
      } catch (e) {
        print('⚠️ Error parsing finish_time: $e');
        setState(() {
          _timeOfPour = '';
        });
      }
    } catch (e) {
      print('❌ Error updating time of pour from ticket: $e');
      setState(() {
        _timeOfPour = '';
      });
    }
  }

  Future<void> _updateCubeReference() async {
    if (_ticketNumber.isEmpty) {
      setState(() {
        _cubeReference = 'A';
      });
      return;
    }

    try {
      final ticketNo = int.tryParse(_ticketNumber);
      if (ticketNo == null) return;

      // Count existing cubes for this ticket number (this would need to be from concrete_cubes table)
      // For now, we'll calculate based on ticket number - you may need to adjust this logic
      // The cube reference should increment: a, b, c, ..., z
      // This is a simplified version - you may need to query concrete_cubes table
      
      // For now, start with 'A' and let user adjust if needed
      setState(() {
        _cubeReference = 'A';
      });
    } catch (e) {
      print('❌ Error updating cube reference: $e');
    }
  }

  Future<void> _checkGpsStatus() async {
    try {
      if (kIsWeb) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: WebSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          ),
        );
        setState(() {
          _currentLatitude = position.latitude;
          _currentLongitude = position.longitude;
          _currentGpsAccuracy = position.accuracy.round();
        });
      } else {
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
      }
    } catch (e) {
      print('⚠️ GPS not available: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cube Details', style: TextStyle(color: Colors.black)),
          centerTitle: true,
          backgroundColor: Colors.white,
          actions: const [ScreenInfoIcon(screenName: 'cube_details_screen.dart')],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0081FB),
        title: const Text(
          'Cube Details',
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
        actions: const [ScreenInfoIcon(screenName: 'cube_details_screen.dart')],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Offline indicator (moved from AppBar)
              _buildOfflineIndicator(),
              const SizedBox(height: 16),

              // Employee Details Section
              _buildEmployeeSection(),
              const SizedBox(height: 16),

              // Date & Time Section
              _buildSection(
                'Date & Time',
                [
                  _buildDateDisplay(),
                  const SizedBox(height: 16),
                  _buildLabeledInput(
                    'Time of Pour',
                    _buildTimeDropdown(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Project Section
              _buildSection(
                'Project',
                [
                  // Project Dropdown
                  _buildLabeledInput(
                    'Project',
                    DropdownButtonFormField<String>(
                      value: _selectedProject.isEmpty ? null : _selectedProject,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _allProjects.map((project) {
                        final name = project['project_name']?.toString() ?? '';
                        return DropdownMenuItem(
                          value: name,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedProject = value ?? '';
                          _selectedProjectDescription = '';
                          _projectSelected = value != null && value.isNotEmpty;
                        });
                        
                        if (_projectSelected) {
                          final project = _projectMapByName[_selectedProject];
                          if (project != null) {
                            _selectedProjectDescription = project['description_of_work']?.toString() ?? '';
                          }
                          _loadTicketNumbers(); // Reload ticket numbers when project changes
                        } else {
                          // Clear ticket numbers if project is deselected
                          setState(() {
                            _ticketNumbers = [];
                            _ticketNumber = '';
                            _concreteMix = '';
                          });
                        }
                      },
                    ),
                  ),

                  // Project Details
                  if (_projectSelected) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: _buildProjectDetailsContent(),
                    ),
                  ],

                  // Location Fields
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Location',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildLabeledInput(
                          'Latitude',
                          TextFormField(
                            key: ValueKey('latitude_$_latitude'),
                            initialValue: _latitude,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _latitude = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildLabeledInput(
                          'Longitude',
                          TextFormField(
                            key: ValueKey('longitude_$_longitude'),
                            initialValue: _longitude,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _longitude = value;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Location Buttons
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _handleUseProjectLocation,
                        icon: const Icon(Icons.location_on, size: 16),
                        label: const Text('Use Project Location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _handleUseCurrentLocation,
                        icon: const Icon(Icons.my_location, size: 16),
                        label: const Text('Use Current Location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _handleUseTimePeriodLocation,
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('Use Time Period Location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Concrete Cube Details Section
              _buildSection(
                'Concrete Cube Details',
                [
                  // Ticket Number and Cube Reference on same line
                  Row(
                    children: [
                      Expanded(
                        child: _buildLabeledInput(
                          'Ticket Number',
                          DropdownButtonFormField<String>(
                            value: _ticketNumber.isEmpty ? null : _ticketNumber,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: _ticketNumbers.map((ticket) {
                              final ticketNo = ticket['concrete_ticket_no']?.toString() ?? '';
                              return DropdownMenuItem(
                                value: ticketNo,
                                child: Text(ticketNo),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _ticketNumber = value ?? '';
                              });
                              _updateConcreteMixFromTicket();
                              _updateTimeOfPourFromTicket();
                              _updateCubeReference();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildLabeledInput(
                          'Cube Reference',
                          TextFormField(
                            initialValue: _cubeReference,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'A, B, C, ...',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _cubeReference = value;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Concrete Mix (read-only, auto-populated)
                  const SizedBox(height: 16),
                  _buildLabeledInput(
                    'Concrete Mix',
                    TextFormField(
                      key: ValueKey('concrete_mix_$_concreteMix'),
                      initialValue: _concreteMix,
                      enabled: false,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                  
                  // Cube Size
                  const SizedBox(height: 16),
                  _buildLabeledInput(
                    'Cube Size',
                    DropdownButtonFormField<String>(
                      value: _cubeSize,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '100mm x 100mm x 100mm',
                          child: Text('100mm x 100mm x 100mm'),
                        ),
                        DropdownMenuItem(
                          value: '150mm x 150mm x 150mm',
                          child: Text('150mm x 150mm x 150mm'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _cubeSize = value ?? '100mm x 100mm x 100mm';
                        });
                      },
                    ),
                  ),
                  
                  // Slump and Test Age on same line
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildLabeledInput(
                          'Slump',
                          TextFormField(
                            initialValue: _slump,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Enter slump value',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _slump = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildLabeledInput(
                          'Test Age',
                          TextFormField(
                            initialValue: _testAge,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Enter Number of Days',
                              suffixText: 'days',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                final age = int.tryParse(value);
                                if (age == null || age < 7 || age > 58) {
                                  return 'Test age must be between 7 and 58 days';
                                }
                              }
                              return null;
                            },
                            onChanged: (value) {
                              setState(() {
                                _testAge = value;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Take picture of ticket button
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isUploadingPhoto ? null : _handleTakePicture,
                    icon: _isUploadingPhoto
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Take picture of ticket'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0081FB),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Upload Button
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _handleUploadCubeDetails,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.upload),
                label: Text(_isSaving ? 'Uploading...' : 'Upload Cube Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0081FB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
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
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabeledInput(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        child,
      ],
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
                    ? 'Online - Your data will be saved to the server'
                    : 'Offline - Your data will be saved locally and synced when online',
                style: TextStyle(
                  color: _isOnline ? Colors.green.shade900 : Colors.orange.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeSection() {
    // Get display name similar to timesheet_screen
    String currentUserDisplay = 'Unknown';
    
    if (_userData != null) {
      final forename = _userData!['forename']?.toString() ?? '';
      final surname = _userData!['surname']?.toString() ?? '';
      if (forename.isNotEmpty || surname.isNotEmpty) {
        currentUserDisplay = '$forename $surname'.trim();
      } else if (_userData!['display_name'] != null) {
        final displayName = _userData!['display_name'].toString();
        if (displayName.contains(',')) {
          final parts = displayName.split(',');
          if (parts.length == 2) {
            currentUserDisplay = '${parts[1].trim()} ${parts[0].trim()}';
        } else {
          currentUserDisplay = displayName;
        }
      }
      }
    }
    
    if (currentUserDisplay == 'Unknown' && _currentUser != null) {
      currentUserDisplay = (_currentUser!['email'] as String?) ?? 'Unknown';
    }

    return Container(
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
                  'Employee Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectDetailsContent() {
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

  Widget _buildDateDisplay() {
    final dateFormat = DateFormat('EEE (d MMM)'); // e.g., "Mon (7 Dec)"
    final currentDate = DateTime.now();
    final selectedDate = DateTime.tryParse(_date) ?? currentDate;
    final maxDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
    
    // Find min and max dates from available time periods
    DateTime? minDate;
    if (_datesWithTimePeriods.isNotEmpty) {
      final sortedDates = _datesWithTimePeriods.toList()..sort();
      minDate = DateTime.tryParse(sortedDates.first);
    }
    // Fallback to week start if no time periods found
    if (minDate == null) {
      minDate = _getWeekStart(currentDate, _getWeekStartDay());
    }

    final isCurrentDate = selectedDate.year == maxDate.year &&
                          selectedDate.month == maxDate.month &&
                          selectedDate.day == maxDate.day;
    final isPastDate = selectedDate.isBefore(maxDate);
    final hasNextDate = _getNextDateWithTimePeriods(_date) != null;
    final hasPreviousDate = _getPreviousDateWithTimePeriods(_date) != null;
    final isDateEnabled = _datesWithTimePeriods.contains(_date);

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

    return Builder(
      builder: (context) {
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
                  onPressed: _datesWithTimePeriods.isEmpty
                      ? null
                      : () {
                          final prevDate = _getPreviousDateWithTimePeriods(_date);
                          if (prevDate != null) {
                            setState(() {
                              _date = prevDate;
                            });
                            _loadProjects();
                            _loadTicketNumbers();
                          } else {
                            // If no previous date, wrap to most recent (newest) date
                            if (_datesWithTimePeriods.isNotEmpty) {
                              final sortedDates = _datesWithTimePeriods.toList()..sort();
                              setState(() {
                                _date = sortedDates.last; // Most recent date
                              });
                              _loadProjects();
                              _loadTicketNumbers();
                            }
                          }
                          // Don't call _checkDateRestrictions() - allow any date with time periods
                        },
                ),
                Flexible(
                  child: GestureDetector(
                    onTap: () async {
                      // Find a valid initial date - use current date if valid, otherwise use nearest valid date
                      DateTime validInitialDate = selectedDate;
                      final currentDateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
                      
                      if (!_datesWithTimePeriods.contains(currentDateStr) && _datesWithTimePeriods.isNotEmpty) {
                        // Find the nearest valid date (prefer dates before current, then after)
                        final sortedDates = _datesWithTimePeriods.toList()..sort();
                        
                        // Try to find a date before or equal to current date
                        String? nearestDate;
                        for (int i = sortedDates.length - 1; i >= 0; i--) {
                          final dateStr = sortedDates[i];
                          final date = DateTime.tryParse(dateStr);
                          if (date != null && !date.isAfter(selectedDate)) {
                            nearestDate = dateStr;
                            break;
                          }
                        }
                        
                        // If no date before current, use the first available date
                        if (nearestDate == null && sortedDates.isNotEmpty) {
                          nearestDate = sortedDates.first;
                        }
                        
                        if (nearestDate != null) {
                          final date = DateTime.tryParse(nearestDate);
                          if (date != null) {
                            validInitialDate = date;
                          }
                        }
                      }
                      
                      // Only show date picker if there are dates with time periods
                      if (_datesWithTimePeriods.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No time periods found. Please create a time period first.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: validInitialDate,
                        firstDate: minDate!,
                        lastDate: maxDate,
                        selectableDayPredicate: (DateTime date) {
                          final dateStr = DateFormat('yyyy-MM-dd').format(date);
                          return _datesWithTimePeriods.contains(dateStr);
                        },
                      );
                      if (pickedDate != null) {
                        setState(() {
                          _date = DateFormat('yyyy-MM-dd').format(pickedDate);
                        });
                        _loadProjects();
                        _loadTicketNumbers();
                        // Don't call _checkDateRestrictions() here - allow any date with time periods
                      }
                    },
                    child: Text(
                      dateFormat.format(selectedDate),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDateEnabled ? null : Colors.grey,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _datesWithTimePeriods.isEmpty
                      ? null
                      : () {
                          final nextDate = _getNextDateWithTimePeriods(_date);
                          if (nextDate != null) {
                            setState(() {
                              _date = nextDate;
                            });
                            _loadProjects();
                            _loadTicketNumbers();
                          } else {
                            // If no next date, wrap to oldest date
                            if (_datesWithTimePeriods.isNotEmpty) {
                              final sortedDates = _datesWithTimePeriods.toList()..sort();
                              setState(() {
                                _date = sortedDates.first; // Oldest date
                              });
                              _loadProjects();
                              _loadTicketNumbers();
                            }
                          }
                          // Don't call _checkDateRestrictions() - allow any date with time periods
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeDropdown() {
    return TextFormField(
      key: ValueKey('time_of_pour_$_timeOfPour'),
      initialValue: _timeOfPour,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
        hintText: 'Time will be added when Ticket Number is selected',
      ),
      onChanged: (value) {
        setState(() {
          _timeOfPour = value;
        });
      },
    );
  }


  void _handleUseProjectLocation() {
    if (!_projectSelected || _selectedProject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a project first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final project = _projectMapByName[_selectedProject];
    if (project == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project not found in project list.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final lat = project['latitude'];
    final lng = project['longitude'];

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected project has no GPS data.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _latitude = lat.toString();
      _longitude = lng.toString();
    });
  }

  Future<void> _handleUseCurrentLocation() async {
    // Try to get GPS location if not already available
    if (_currentLatitude == null || _currentLongitude == null) {
      try {
        await _checkGpsStatus();
      } catch (e) {
        print('⚠️ Error getting GPS: $e');
      }
    }

    if (_currentLatitude == null || _currentLongitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Current GPS location not available. Please ensure location services are enabled.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _latitude = _currentLatitude!.toString();
      _longitude = _currentLongitude!.toString();
    });
  }

  Future<void> _handleUseTimePeriodLocation() async {
    if (_ticketNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a ticket number first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final ticketNo = int.tryParse(_ticketNumber);
      if (ticketNo == null) {
        print('⚠️ Invalid ticket number: $_ticketNumber');
        return;
      }

      print('🔍 Looking up time period location for ticket number: $ticketNo');
      
      // Find time_period with matching ticket number
      final response = await SupabaseService.client
          .from('time_periods')
          .select('submission_lat, submission_lng')
          .eq('concrete_ticket_no', ticketNo)
          .eq('is_active', true)
          .not('submission_lat', 'is', null)
          .not('submission_lng', 'is', null)
          .order('work_date', ascending: false)
          .limit(1)
          .maybeSingle();

      print('🔍 Response: $response');

      if (response != null) {
        final lat = response['submission_lat'];
        final lng = response['submission_lng'];

        print('🔍 Found location - lat: $lat, lng: $lng');

        if (lat != null && lng != null) {
          final latStr = lat.toString();
          final lngStr = lng.toString();
          
          print('✅ Setting location - latitude: $latStr, longitude: $lngStr');
          
          setState(() {
            _latitude = latStr;
            _longitude = lngStr;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location updated from time period.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          print('⚠️ Location data is null');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No location data found for this ticket number.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        print('⚠️ No time period found for ticket number: $ticketNo');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No time period found for this ticket number.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error getting time period location: $e');
      print('❌ Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting time period location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleTakePicture() async {
    // Validate required fields
    if (_ticketNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a ticket number first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_cubeReference.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a cube reference first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show dialog to choose camera or gallery
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: const Text('Choose where to get the image from:'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (source == null) return;

    try {
      setState(() {
        _isUploadingPhoto = true;
      });

      // Pick image
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85, // Compress to 85% quality
        maxWidth: 1920, // Max width
        maxHeight: 1920, // Max height,
      );

      if (image == null) {
        setState(() {
          _isUploadingPhoto = false;
        });
        return;
      }

      // Generate filename: ticket_number_cube_reference.jpg
      final fileName = '${_ticketNumber}_${_cubeReference}.jpg';

      // Upload to Supabase Storage
      // For web platform, photo upload is not supported in this implementation
      // Use mobile/desktop platforms for photo upload functionality
      if (kIsWeb) {
        throw Exception('Photo upload is not supported on web. Please use mobile or desktop app.');
      }

      // Use File object directly - Supabase SDK handles this correctly
      final file = File(image.path);
      
      // Check if file exists and has content
      if (!await file.exists()) {
        throw Exception('Image file does not exist');
      }
      
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }
      
      // Upload to Supabase Storage using File object
      // The SDK will handle the file upload correctly
      await SupabaseService.client.storage
          .from(_photoBucketName)
          .upload(fileName, file);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo uploaded successfully: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error uploading photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _handleUploadCubeDetails() async {
    // Validate required fields
    if (!_projectSelected || _selectedProject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a project.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_ticketNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a ticket number.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate test age if provided
    if (_testAge.isNotEmpty) {
      final age = int.tryParse(_testAge);
      if (age == null || age < 7 || age > 58) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test age must be between 7 and 58 days.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Show confirmation dialog
    final shouldSave = await _showUploadConfirmationDialog();
    if (shouldSave != true) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Get project_id
      final project = _projectMapByName[_selectedProject];
      if (project == null || project['id'] == null) {
        throw Exception('Project not found');
      }

      final projectId = project['id']?.toString();
      if (projectId == null) {
        throw Exception('Project ID is null');
      }

      // Combine date and time for date_casted
      final dateTimeStr = '$_date $_timeOfPour:00';
      final dateCasted = DateTime.tryParse(dateTimeStr);

      // Build cube data
      final cubeData = <String, dynamic>{
        'user_id': _currentUser!['id'],
        'project_id': projectId,
        'date_casted': dateCasted?.toIso8601String(),
        'concrete_ticket_no': int.tryParse(_ticketNumber),
        'cube_size': _cubeSize,
        'cube_reference': _cubeReference,
        if (_concreteMix.isNotEmpty) 'mix_name': _concreteMix,
        if (_slump.isNotEmpty) 'slump': _slump,
        if (_testAge.isNotEmpty) 'test_age': int.tryParse(_testAge),
        if (_latitude.isNotEmpty) 'latitude': double.tryParse(_latitude),
        if (_longitude.isNotEmpty) 'longitude': double.tryParse(_longitude),
        'offline_created': !_isOnline,
        'synced': _isOnline,
      };

      if (_isOnline) {
        // Save to Supabase
        await DatabaseService.create('concrete_cubes', cubeData);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cube details uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Save offline
        if (!OfflineStorageService.isSupported) {
          throw Exception('Offline storage not available on this platform. Please ensure you have internet connection.');
        }

        final offlineId = 'cube_${DateTime.now().millisecondsSinceEpoch}_${_currentUser!['id'].toString().substring(0, 8)}';
        cubeData['offline_id'] = offlineId;
        cubeData['_entry_type'] = 'create';
        cubeData['_offline_id'] = offlineId;
        cubeData['_table_name'] = 'concrete_cubes';
        
        await OfflineStorageService.addToQueue(cubeData);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cube details saved offline. They will be uploaded when you go online.'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // Close screen after successful save
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      print('❌ Error uploading cube details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading cube details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<bool?> _showUploadConfirmationDialog() async {
    final project = _projectMapByName[_selectedProject];
    final projectName = project?['project_name']?.toString() ?? _selectedProject;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Upload'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Project: $projectName'),
              Text('Ticket Number: $_ticketNumber'),
              Text('Date: $_date'),
              Text('Time of Pour: $_timeOfPour'),
              if (_concreteMix.isNotEmpty) Text('Concrete Mix: $_concreteMix'),
              Text('Cube Size: $_cubeSize'),
              Text('Cube Reference: $_cubeReference'),
              if (_slump.isNotEmpty) Text('Slump: $_slump'),
              if (_testAge.isNotEmpty) Text('Test Age: $_testAge days'),
              if (_latitude.isNotEmpty && _longitude.isNotEmpty)
                Text('Location: $_latitude, $_longitude'),
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
              backgroundColor: const Color(0xFF0081FB),
              foregroundColor: Colors.white,
            ),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }
}
