import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/errors/error_log_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';
import 'package:dwce_time_tracker/utils/google_maps_loader.dart';
import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

/// Admin Staff Attendance Screen
/// 
/// Allows admins to review office staff attendance (clock in/out)
/// Features:
/// - Filters by date range, employee
/// - Display of start/finish times, breaks, and GPS data
/// - GPS map popups for start and finish locations
class AdminStaffAttendanceScreen extends StatefulWidget {
  const AdminStaffAttendanceScreen({super.key});

  @override
  State<AdminStaffAttendanceScreen> createState() => _AdminStaffAttendanceScreenState();
}

class _AdminStaffAttendanceScreenState extends State<AdminStaffAttendanceScreen> {
  bool _isLoading = true;
  bool _isAdmin = false;
  List<Map<String, dynamic>> _timeOfficeRecords = [];
  List<Map<String, dynamic>> _allUsers = [];
  
  // Week navigation
  DateTime _selectedWeekStart = DateTime.now();
  
  // Filters
  Set<String> _selectedUserIds = {}; // Multi-select for employees
  Set<String> _selectedDays = {}; // Multi-select for days (Mon, Tue, etc.)
  
  // Column widths (for resizable columns) - increased by 50%
  double _employeeColumnWidth = 180.0;
  
  // Filter dropdown visibility
  String? _openFilterDropdown; // 'day', 'employee', or null
  final GlobalKey _headerKey = GlobalKey();
  
  // Break durations cache: time_office_id -> minutes
  final Map<String, int> _breakDurationsCache = {};
  
  // Week start from system_settings: integer 0-6 (PostgreSQL DOW: 0=Sunday .. 6=Saturday)
  int _weekStartDow = 1;

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = _getWeekStart(DateTime.now());
    _checkAdminStatus();
  }
  
  @override
  void dispose() {
    _hideFilterDropdown();
    super.dispose();
  }

  /// Dart weekday for week start (1=Mon .. 7=Sun)
  int _dowToDartWeekday(int dow) => dow == 0 ? 7 : dow;

  /// Get the start of the week for a given date based on week_start setting
  DateTime _getWeekStart(DateTime date) {
    final w = _dowToDartWeekday(_weekStartDow);
    final daysToSubtract = (date.weekday - w + 7) % 7;
    return date.subtract(Duration(days: daysToSubtract));
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
    });
    _loadTimeOfficeRecords();
  }

  /// Navigate to next week (limited to current week)
  void _nextWeek() {
    if (!_canNavigateNext()) return;
    
    final nextWeek = _selectedWeekStart.add(const Duration(days: 7));
    final currentWeekStart = _getWeekStart(DateTime.now());
    
    // Prevent going past current week
    if (nextWeek.isAfter(currentWeekStart)) {
      setState(() {
        _selectedWeekStart = currentWeekStart;
      });
    } else {
      setState(() {
        _selectedWeekStart = nextWeek;
      });
    }
    _loadTimeOfficeRecords();
  }

  /// Navigate to current week
  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
    });
    _loadTimeOfficeRecords();
  }

  Future<void> _checkAdminStatus() async {
    setState(() => _isLoading = true);

    try {
      // Check if user has admin privileges (security level 1)
      final userSetup = await UserService.getCurrentUserSetup();
      if (userSetup != null && userSetup['security'] != null) {
        final security = userSetup['security'];
        final securityLevel = security is int ? security : int.tryParse(security.toString());
        
        if (securityLevel == 1) {
      setState(() => _isAdmin = true);
      
      // Load initial data
      await Future.wait([
        _loadWeekStart(),
        _loadUsers(),
        _loadTimeOfficeRecords(),
      ]);
        } else {
          setState(() {
            _isAdmin = false;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isAdmin = false;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Admin Staff Attendance Screen - Check Admin Status',
        type: 'Database',
        description: 'Error checking admin status: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _isLoading = false;
        _isAdmin = false;
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
        if (v != null && v >= 0 && v <= 6) {
          setState(() => _weekStartDow = v);
        }
      }
    } catch (e) {
      print('⚠️ Error loading week_start: $e');
    }
  }

  static const List<String> _dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Get ordered list of day abbreviations based on week_start (DOW 0-6)
  List<String> _getOrderedDays() {
    final order = <String>[];
    for (var i = 0; i < 7; i++) {
      final dow = (_weekStartDow + i) % 7;
      final dartWeekday = dow == 0 ? 7 : dow;
      order.add(_dayAbbr[dartWeekday - 1]);
    }
    return order;
  }

  Future<void> _loadUsers() async {
    try {
      final users = await DatabaseService.read('users_data');
      setState(() => _allUsers = users);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Admin Staff Attendance Screen - Load Users',
        type: 'Database',
        description: 'Error loading users: $e',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadTimeOfficeRecords() async {
    setState(() => _isLoading = true);

    try {
      final weekEnd = _getWeekEnd(_selectedWeekStart);
      final startDateStr = DateFormat('yyyy-MM-dd').format(_selectedWeekStart);
      final endDateStr = DateFormat('yyyy-MM-dd').format(weekEnd);
      
      // time_office: filter by user_id and start_time range to use idx_time_office_* (see supabase_indexes.md)
      dynamic query = SupabaseService.client
          .from('time_office')
          .select('*, users_data!user_id(display_name), projects!home_project_id(project_name, latitude, longitude)')
          .gte('start_time', '${startDateStr}T00:00:00Z')
          .lte('start_time', '${endDateStr}T23:59:59Z')
          .eq('is_active', true);

      if (_selectedUserIds.isNotEmpty) {
        query = query.inFilter('user_id', _selectedUserIds.toList());
      }
      query = query.order('start_time', ascending: true);

      final response = await query;
      
      // Flatten the nested structure
      var records = (response as List).map((record) {
        final Map<String, dynamic> flatRecord = Map<String, dynamic>.from(record as Map);
        
        // Extract user data
        if (flatRecord['users_data'] != null) {
          final userData = flatRecord['users_data'];
          flatRecord['user_name'] = userData['display_name'];
          flatRecord.remove('users_data');
        }
        
        // Extract project data
        if (flatRecord['projects'] != null) {
          final projectData = flatRecord['projects'];
          flatRecord['project_name'] = projectData['project_name'];
          flatRecord['project_lat'] = projectData['latitude'];
          flatRecord['project_lng'] = projectData['longitude'];
          flatRecord.remove('projects');
        }
        
        return flatRecord;
      }).toList();
      
      // Apply day filter in memory (if selected)
      if (_selectedDays.isNotEmpty) {
        records = records.where((record) {
          final startTime = record['start_time']?.toString();
          if (startTime == null) return false;
          try {
            final date = DateTime.parse(startTime);
            final dayName = DateFormat('EEE').format(date); // Mon, Tue, etc.
            return _selectedDays.contains(dayName);
          } catch (e) {
            return false;
          }
        }).toList();
      }
      
      // Load breaks for all records
      _breakDurationsCache.clear();
      
      for (final record in records) {
        final recordId = record['id']?.toString();
        if (recordId != null) {
          await _loadBreaks(recordId);
        }
      }
      
      setState(() {
        _timeOfficeRecords = records;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Admin Staff Attendance Screen - Load Time Office Records',
        type: 'Database',
        description: 'Error loading time office records: $e',
        stackTrace: stackTrace,
      );
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading attendance records: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Load breaks for a time office record
  Future<void> _loadBreaks(String timeOfficeId) async {
    try {
      final breaksResponse = await SupabaseService.client
          .from('time_office_breaks')
          .select('break_start, break_finish')
          .eq('time_office_id', timeOfficeId)
          .eq('is_active', true)
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
      _breakDurationsCache[timeOfficeId] = totalMinutes;
    } catch (e) {
      print('Error loading breaks for $timeOfficeId: $e');
      _breakDurationsCache[timeOfficeId] = 0;
    }
  }

  /// Format day as Mon, Tue, etc.
  String _formatDay(DateTime? date) {
    if (date == null) return '--';
    return DateFormat('EEE').format(date);
  }

  /// Format time as HH:mm
  String _formatTimeAsHHMM(DateTime? time) {
    if (time == null) return '--';
    return DateFormat('HH:mm').format(time);
  }

  /// Format actual timestamp as "HH:mm" or "HH:mm ±N" when its date differs from scheduled date.
  /// scheduledTime = start_time or finish_time (the expected day); actualTimestamp = start_timestamp or finish_timestamp.
  String _formatTimestampWithDayDiff(DateTime? scheduledTime, DateTime? actualTimestamp) {
    if (actualTimestamp == null) return '--';
    final hhmm = DateFormat('HH:mm').format(actualTimestamp);
    if (scheduledTime == null) return hhmm;
    final scheduledDate = DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day);
    final actualDate = DateTime(actualTimestamp.year, actualTimestamp.month, actualTimestamp.day);
    final dayDiff = actualDate.difference(scheduledDate).inDays;
    if (dayDiff == 0) return hhmm;
    if (dayDiff > 0) return '$hhmm +$dayDiff';
    return '$hhmm $dayDiff';
  }

  /// Format break duration as HH:mm
  String _formatBreakDuration(int minutes) {
    if (minutes <= 0) return '--';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  /// Calculate total time (finish - start - breaks) in minutes
  String _calculateTotalTime(DateTime? startTime, DateTime? finishTime, int breakMinutes) {
    if (startTime == null || finishTime == null) return '--';
    
    final totalMinutes = finishTime.difference(startTime).inMinutes - breakMinutes;
    if (totalMinutes < 0) return '--';
    
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  /// Show GPS map popup for start location
  void _showGPSStartMapPopup(Map<String, dynamic> record) async {
    final startLat = record['start_lat'] as double?;
    final startLng = record['start_lng'] as double?;
    final projectLat = record['project_lat'] as double?;
    final projectLng = record['project_lng'] as double?;
    final startDistance = record['start_distance']?.toString() ?? '--';
    
    // Check if we have valid coordinates
    if (startLat == null || startLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No GPS coordinates available for start location'),
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
    
    // Start location marker (User's location - Green for "You are here")
    markers.add(
      Marker(
        markerId: const MarkerId('start'),
        position: LatLng(startLat, startLng),
        infoWindow: const InfoWindow(
          title: '👤 Start Location',
          snippet: 'Where the employee clocked in',
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
            snippet: 'Distance from start: $startDistance km',
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
            LatLng(startLat, startLng),
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
          startLat < projectLat ? startLat : projectLat,
          startLng < projectLng ? startLng : projectLng,
        ),
        northeast: LatLng(
          startLat > projectLat ? startLat : projectLat,
          startLng > projectLng ? startLng : projectLng,
        ),
      );
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS Start Location Map'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.6,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(startLat, startLng),
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

  /// Show GPS map popup for finish location
  void _showGPSFinishMapPopup(Map<String, dynamic> record) async {
    final finishLat = record['finish_lat'] as double?;
    final finishLng = record['finish_lng'] as double?;
    final projectLat = record['project_lat'] as double?;
    final projectLng = record['project_lng'] as double?;
    final finishDistance = record['finish_distance']?.toString() ?? '--';
    
    // Check if we have valid coordinates
    if (finishLat == null || finishLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No GPS coordinates available for finish location'),
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
    
    // Finish location marker (User's location - Green for "You are here")
    markers.add(
      Marker(
        markerId: const MarkerId('finish'),
        position: LatLng(finishLat, finishLng),
        infoWindow: const InfoWindow(
          title: '👤 Finish Location',
          snippet: 'Where the employee clocked out',
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
            snippet: 'Distance from finish: $finishDistance km',
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
            LatLng(finishLat, finishLng),
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
          finishLat < projectLat ? finishLat : projectLat,
          finishLng < projectLng ? finishLng : projectLng,
        ),
        northeast: LatLng(
          finishLat > projectLat ? finishLat : projectLat,
          finishLng > projectLng ? finishLng : projectLng,
        ),
      );
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS Finish Location Map'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.6,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(finishLat, finishLng),
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

  void _hideFilterDropdown() {
    _filterOverlayEntry?.remove();
    _filterOverlayEntry = null;
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
                      fontSize: 18,
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
      width = _employeeColumnWidth.clamp(300.0, 600.0);
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

  /// Build filter dropdown for a column
  Widget _buildFilterDropdown(String filterKey, double width) {
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
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filterKey == 'day') _buildDayFilter(),
            if (filterKey == 'employee') _buildEmployeeFilter(),
          ],
        ),
      ),
    );
  }

  /// Build day filter dropdown
  Widget _buildDayFilter() {
    // Get unique days from current data
    final uniqueDays = <String>{};
    for (final record in _timeOfficeRecords) {
      final startTime = record['start_time']?.toString();
      if (startTime != null) {
        try {
          final date = DateTime.parse(startTime);
          final dayName = DateFormat('EEE').format(date); // Mon, Tue, etc.
          uniqueDays.add(dayName);
        } catch (e) {
          // Skip invalid dates
        }
      }
    }
    final dayList = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        .where((day) => uniqueDays.contains(day))
        .toList();
    
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filter by Day (${dayList.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _hideFilterDropdown();
                  setState(() => _openFilterDropdown = null);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(),
          dayList.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No days in current data'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: dayList.map((day) {
                    final isSelected = _selectedDays.contains(day);
                    return CheckboxListTile(
                      title: Text(day),
                      value: isSelected,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedDays.add(day);
                          } else {
                            _selectedDays.remove(day);
                          }
                        });
                        // Rebuild the overlay to show updated checkbox state
                        if (_openFilterDropdown == 'day') {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final context = _headerKey.currentContext;
                            if (context != null) {
                              _showFilterDropdown('day', context);
                            }
                          });
                        }
                        _loadTimeOfficeRecords();
                      },
                    );
                  }).toList(),
                ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _hideFilterDropdown();
                  setState(() {
                    _selectedDays.clear();
                    _openFilterDropdown = null;
                  });
                  _loadTimeOfficeRecords();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build employee filter dropdown
  Widget _buildEmployeeFilter() {
    // Get unique employees from current data
    final uniqueEmployees = <String, Map<String, dynamic>>{};
    for (final record in _timeOfficeRecords) {
      final userId = record['user_id']?.toString() ?? '';
      if (userId.isNotEmpty && !uniqueEmployees.containsKey(userId)) {
        final userName = record['user_name']?.toString() ?? 'Unknown';
        uniqueEmployees[userId] = {
          'user_id': userId,
          'display_name': userName,
        };
      }
    }
    final employeeList = uniqueEmployees.values.toList()
      ..sort((a, b) => (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString()));
    
    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filter by Employee (${employeeList.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _hideFilterDropdown();
                  setState(() => _openFilterDropdown = null);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(),
          Flexible(
            child: employeeList.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No employees in current data'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: employeeList.length,
                    itemBuilder: (context, index) {
                      final user = employeeList[index];
                      final userId = user['user_id']?.toString() ?? '';
                      final userName = user['display_name']?.toString() ?? 'Unknown';
                      final isSelected = _selectedUserIds.contains(userId);
                      return CheckboxListTile(
                        title: Text(userName, overflow: TextOverflow.ellipsis),
                        value: isSelected,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedUserIds.add(userId);
                            } else {
                              _selectedUserIds.remove(userId);
                            }
                          });
                          // Rebuild the overlay to show updated checkbox state
                          if (_openFilterDropdown == 'employee') {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final context = _headerKey.currentContext;
                              if (context != null) {
                                _showFilterDropdown('employee', context);
                              }
                            });
                          }
                          _loadTimeOfficeRecords();
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _hideFilterDropdown();
                  setState(() {
                    _selectedUserIds.clear();
                    _openFilterDropdown = null;
                  });
                  _loadTimeOfficeRecords();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Get sorted list of employee IDs from current data
  List<String> _getSortedEmployeeIds() {
    final uniqueEmployees = <String, String>{}; // userId -> display_name
    for (final record in _timeOfficeRecords) {
      final userId = record['user_id']?.toString() ?? '';
      if (userId.isNotEmpty && !uniqueEmployees.containsKey(userId)) {
        final userName = record['user_name']?.toString() ?? 'Unknown';
        uniqueEmployees[userId] = userName;
      }
    }
    final sortedList = uniqueEmployees.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return sortedList.map((e) => e.key).toList();
  }

  /// Navigate to next employee (alphabetically)
  void _nextEmployee() {
    final sortedIds = _getSortedEmployeeIds();
    if (sortedIds.isEmpty || _selectedUserIds.isEmpty) return;
    
    final currentId = _selectedUserIds.first;
    final currentIndex = sortedIds.indexOf(currentId);
    
    if (currentIndex >= 0 && currentIndex < sortedIds.length - 1) {
      setState(() {
        _selectedUserIds = {sortedIds[currentIndex + 1]};
      });
      _loadTimeOfficeRecords();
    }
  }

  /// Navigate to previous employee (alphabetically)
  void _previousEmployee() {
    final sortedIds = _getSortedEmployeeIds();
    if (sortedIds.isEmpty || _selectedUserIds.isEmpty) return;
    
    final currentId = _selectedUserIds.first;
    final currentIndex = sortedIds.indexOf(currentId);
    
    if (currentIndex > 0) {
      setState(() {
        _selectedUserIds = {sortedIds[currentIndex - 1]};
      });
      _loadTimeOfficeRecords();
    }
  }

  /// Calculate daily totals for selected employee
  Map<String, int> _calculateDailyTotals() {
    final dailyTotals = <String, int>{}; // day -> total minutes
    
    for (final record in _timeOfficeRecords) {
      final startTime = record['start_time']?.toString();
      final finishTime = record['finish_time']?.toString();
      final recordId = record['id']?.toString() ?? '';
      final breakMinutes = _breakDurationsCache[recordId] ?? 0;
      
      if (startTime != null && finishTime != null) {
        try {
          final start = DateTime.parse(startTime);
          final finish = DateTime.parse(finishTime);
          final dayName = DateFormat('EEE').format(start);
          
          final totalMinutes = finish.difference(start).inMinutes - breakMinutes;
          if (totalMinutes > 0) {
            dailyTotals[dayName] = (dailyTotals[dayName] ?? 0) + totalMinutes;
          }
        } catch (e) {
          // Skip invalid dates
        }
      }
    }
    
    return dailyTotals;
  }

  /// Calculate weekly total for selected employee
  int _calculateWeeklyTotal() {
    final dailyTotals = _calculateDailyTotals();
    return dailyTotals.values.fold(0, (sum, minutes) => sum + minutes);
  }

  /// Format minutes as hours and minutes
  String _formatHoursMinutes(int minutes) {
    if (minutes <= 0) return '0h 0m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  Widget _buildTimeOfficeRow(Map<String, dynamic> record, int index) {
    final recordId = record['id']?.toString() ?? '';
    
    final userName = record['user_name']?.toString() ?? 'Unknown';
    final startTime = record['start_time'] != null
        ? DateTime.parse(record['start_time']?.toString() ?? '')
        : null;
    final finishTime = record['finish_time'] != null
        ? DateTime.parse(record['finish_time']?.toString() ?? '')
        : null;
    final day = _formatDay(startTime);
    
    final breakMinutes = _breakDurationsCache[recordId] ?? 0;
    final breakTime = _formatBreakDuration(breakMinutes);
    final totalTime = _calculateTotalTime(startTime, finishTime, breakMinutes);
    
    // GPS distances
    final startDistance = record['start_distance']?.toString() ?? '--';
    final finishDistance = record['finish_distance']?.toString() ?? '--';
    
    // Timestamps (actual times)
    final startTimestamp = record['start_timestamp'] != null
        ? DateTime.parse(record['start_timestamp']?.toString() ?? '')
        : null;
    final finishTimestamp = record['finish_timestamp'] != null
        ? DateTime.parse(record['finish_timestamp']?.toString() ?? '')
        : null;
    
    return Container(
      padding: const EdgeInsets.only(left: 0, right: 0, top: 0, bottom: 0),
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            // Day (with border, center justified)
            Container(
              width: 90,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey, width: 1)),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    day,
                    style: const TextStyle(fontSize: 18),
                  ),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    userName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            
            // Start (center justified)
            SizedBox(
              width: 90,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    _formatTimeAsHHMM(startTime),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
            
            // Break (center justified)
            SizedBox(
              width: 90,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    breakTime,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
            
            // Finish (center justified)
            SizedBox(
              width: 90,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    _formatTimeAsHHMM(finishTime),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
            
            // Total (with border, center justified)
            Container(
              width: 90,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey, width: 1)),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    totalTime,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            
            // GPS (Start) (center justified, clickable)
            GestureDetector(
              onTap: () => _showGPSStartMapPopup(record),
              child: SizedBox(
                width: 120,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      startDistance != '--' ? '$startDistance km' : '--',
                      style: TextStyle(
                        fontSize: 16.5,
                        color: startDistance != '--' ? Colors.blue : Colors.black,
                        decoration: startDistance != '--' ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // GPS (Finish) (center justified, clickable)
            GestureDetector(
              onTap: () => _showGPSFinishMapPopup(record),
              child: SizedBox(
                width: 120,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      finishDistance != '--' ? '$finishDistance km' : '--',
                      style: TextStyle(
                        fontSize: 16.5,
                        color: finishDistance != '--' ? Colors.blue : Colors.black,
                        decoration: finishDistance != '--' ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Start (T) (center justified) - actual timestamp; show day diff if different from start_time date
            SizedBox(
              width: 120,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    _formatTimestampWithDayDiff(startTime, startTimestamp),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
            
            // Finish (T) (center justified) - actual timestamp; show day diff if different from finish_time date
            SizedBox(
              width: 120,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    _formatTimestampWithDayDiff(finishTime, finishTimestamp),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Admin Staff Attendance',
            style: TextStyle(color: Colors.black),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0081FB),
          foregroundColor: Colors.black,
          actions: const [ScreenInfoIcon(screenName: 'admin_staff_attendance_screen.dart')],
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
                'You need Admin privileges (Security Level 1)',
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
          'Admin Staff Attendance',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [
          const ScreenInfoIcon(screenName: 'admin_staff_attendance_screen.dart'),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadTimeOfficeRecords,
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
          // Week Navigation with arrows beside date range
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _previousWeek,
                  tooltip: 'Previous Week',
                ),
                Column(
                  children: [
                    Text(
                      '${DateFormat('MMM dd').format(_selectedWeekStart)} - ${DateFormat('MMM dd, yyyy').format(_getWeekEnd(_selectedWeekStart))}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
          
          // Day filter buttons (center justified)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Day:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 8),
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
                        _loadTimeOfficeRecords();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.green : null,
                        foregroundColor: isSelected ? Colors.white : null,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: const Size(50, 32),
                      ),
                      child: Text(day),
                    ),
                  );
                }),
              ],
            ),
          ),
          
          // Employee navigation (only show when single employee is selected, below status line)
          if (_selectedUserIds.length == 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.grey[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Builder(
                    builder: (context) {
                      final sortedIds = _getSortedEmployeeIds();
                      final currentId = _selectedUserIds.first;
                      final currentIndex = sortedIds.indexOf(currentId);
                      final canGoPrevious = currentIndex > 0;
                      final canGoNext = currentIndex >= 0 && currentIndex < sortedIds.length - 1;
                      
                      final selectedUserId = _selectedUserIds.first;
                      final employeeName = _allUsers.firstWhere(
                        (user) => user['user_id']?.toString() == selectedUserId,
                        orElse: () => {'display_name': 'Unknown'},
                      )['display_name']?.toString() ?? 'Unknown';
                      
                      return Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: canGoPrevious ? _previousEmployee : null,
                            tooltip: 'Previous Employee',
                          ),
                          const SizedBox(width: 8),
                          Text(
                            employeeName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 21),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: canGoNext ? _nextEmployee : null,
                            tooltip: 'Next Employee',
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          
          // Header row
          Container(
            key: _headerKey,
            padding: const EdgeInsets.only(left: 0, right: 0, top: 0, bottom: 0),
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border(
                bottom: BorderSide(color: Colors.grey[400]!),
              ),
            ),
            alignment: Alignment.center,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  // Day (with filter)
                  _buildFilterableHeader(
                    width: 90,
                    label: 'Day',
                    filterKey: 'day',
                    hasActiveFilter: _selectedDays.isNotEmpty,
                  ),
                  
                  // Employee (resizable, with filter)
                  _buildFilterableHeader(
                    width: _employeeColumnWidth,
                    label: 'Employee',
                    filterKey: 'employee',
                    hasActiveFilter: _selectedUserIds.isNotEmpty,
                    isResizable: true,
                    onResize: (delta) {
                      setState(() {
                        _employeeColumnWidth = (_employeeColumnWidth + delta).clamp(120.0, 450.0);
                      });
                    },
                  ),
                  
                  // Start header
                  const SizedBox(
                    width: 90,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'Start',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  
                  // Break header
                  const SizedBox(
                    width: 90,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'Break',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  
                  // Finish header
                  const SizedBox(
                    width: 90,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'Finish',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  
                  // Total header
                  Container(
                    width: 90,
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.grey, width: 1)),
                    ),
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'Total',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  
                  // GPS (Start) header
                  const SizedBox(
                    width: 120,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'GPS (Start)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  
                  // GPS (Finish) header
                  const SizedBox(
                    width: 120,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'GPS (Finish)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  
                  // Start (T) header
                  const SizedBox(
                    width: 120,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'Start (T)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  
                  // Finish (T) header
                  const SizedBox(
                    width: 120,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'Finish (T)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Data rows
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _timeOfficeRecords.isEmpty
                    ? const Center(
                        child: Text(
                          'No attendance records found for this week',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              itemCount: _timeOfficeRecords.length,
                              itemBuilder: (context, index) {
                                return Center(
                                  child: _buildTimeOfficeRow(_timeOfficeRecords[index], index),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
          
          // Summary section (only show when single employee is selected, placed below data rows)
          if (_selectedUserIds.length == 1 && !_isLoading && _timeOfficeRecords.isNotEmpty)
            _buildSummarySection(),
        ],
        ),
      ),
    );
  }
  
  /// Build summary section showing daily totals and weekly total
  Widget _buildSummarySection() {
    final dailyTotals = _calculateDailyTotals();
    final weeklyTotal = _calculateWeeklyTotal();
    final orderedDays = _getOrderedDays();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(
          top: BorderSide(color: Colors.grey[400]!, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Summary',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Table layout with days as column headers
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Day columns
                ...orderedDays.map((day) {
                  final minutes = dailyTotals[day] ?? 0;
                  return Container(
                    width: 100,
                    margin: const EdgeInsets.only(right: 8),
                    child: Column(
                      children: [
                        // Day header
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              day,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        // Worked hours value
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              left: BorderSide(color: Colors.grey[300]!),
                              right: BorderSide(color: Colors.grey[300]!),
                              bottom: BorderSide(color: Colors.grey[300]!),
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              minutes > 0 ? _formatHoursMinutes(minutes) : '',
                              style: const TextStyle(
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                // Weekly Total column
                Container(
                  width: 125,
                  margin: const EdgeInsets.only(left: 16),
                  child: Column(
                    children: [
                      // Weekly Total header
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                        decoration: BoxDecoration(
                          color: Colors.blue[200],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'Weekly Total',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      // Weekly Total value
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            left: BorderSide(color: Colors.grey[300]!),
                            right: BorderSide(color: Colors.grey[300]!),
                            bottom: BorderSide(color: Colors.grey[300]!),
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            weeklyTotal > 0 ? _formatHoursMinutes(weeklyTotal) : '',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  OverlayEntry? _filterOverlayEntry;
}
