import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/screens/timesheet_screen.dart';
import 'package:flutter/material.dart';
import 'package:dwce_time_tracker/widgets/screen_info_icon.dart';
import 'package:intl/intl.dart';

/// My Time Periods Screen
/// 
/// Allows users to view their time periods grouped by date
/// Features:
/// - Grouped by date with total hours per day
/// - Sorted oldest to newest
/// - Shows project_name, times, breaks, fleet, allowances, concrete mix, and comments
/// - Click to edit/delete
class MyTimePeriodsScreen extends StatefulWidget {
  const MyTimePeriodsScreen({super.key});

  @override
  State<MyTimePeriodsScreen> createState() => _MyTimePeriodsScreenState();
}

class _MyTimePeriodsScreenState extends State<MyTimePeriodsScreen> {
  DateTime _selectedWeekStart = DateTime.now();
  bool _isLoading = true;
  List<Map<String, dynamic>> _timePeriods = [];
  Map<String, String> _projectNames = {}; // project_id -> project_name
  Map<String, String> _plantDescriptions = {}; // large_plant_id -> plant_description
  Map<String, String> _concreteMixNames = {}; // id (UUID) -> user_description
  final Map<String, List<Map<String, dynamic>>> _usedFleet = {}; // time_period_id -> fleet list
  final Map<String, List<Map<String, dynamic>>> _mobilisedFleet = {}; // time_period_id -> fleet list
  final Map<String, int> _breakDurations = {}; // time_period_id -> break duration in minutes
  final Map<String, List<Map<String, dynamic>>> _breaks = {}; // time_period_id -> breaks list

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = _getWeekStart(DateTime.now());
    _loadTimePeriods();
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

  /// Convert 24-hour time to 12-hour format
  String _convertTo12Hour(String time24) {
    if (time24.isEmpty) return '';
    try {
      final parts = time24.split(':');
      if (parts.length != 2) return time24;
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$hour12:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return time24;
    }
  }

  /// Convert DateTime to 12-hour format
  String _convertDateTimeTo12Hour(DateTime dateTime) {
    return _convertTo12Hour(DateFormat('HH:mm').format(dateTime));
  }

  /// Format hours as h:mm
  String _formatHoursAsHMM(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  /// Load project names only for the given project IDs (e.g. from current week's periods)
  Future<void> _loadProjectNamesForIds(List<String> projectIds) async {
    if (projectIds.isEmpty) {
      _projectNames = {};
      return;
    }
    try {
      final response = await SupabaseService.client
          .from('projects')
          .select('id, project_name')
          .inFilter('id', projectIds);
      _projectNames = {};
      for (final project in response as List) {
        final id = (project as Map<String, dynamic>)['id']?.toString();
        final name = project['project_name']?.toString() ??
            project['name']?.toString() ?? id ?? 'Unknown';
        if (id != null) {
          _projectNames[id] = name;
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error loading project names: $e');
      _projectNames = {};
    }
  }

  /// Load concrete mixes to map id (UUID) to user_description
  /// Loads ALL mixes (not just active) to handle historical time periods with inactive mixes
  Future<void> _loadConcreteMixes() async {
    try {
      // Load all concrete mixes (not just active) to handle historical data
      final mixes = await DatabaseService.read('concrete_mix');
      _concreteMixNames = {};
      for (final mix in mixes) {
        final id = mix['id']?.toString()?.trim();
        if (id == null || id.isEmpty) continue;
        
        // Use only the 'name' field - no fallback
        final name = mix['name']?.toString()?.trim();
        
        if (name != null && name.isNotEmpty) {
          _concreteMixNames[id] = name;
        } else {
          // If name is missing, skip this entry
          print('⚠️ Concrete mix $id has no name field - skipping');
        }
      }
      print('✅ Loaded ${_concreteMixNames.length} concrete mixes for lookup (by UUID)');
      if (_concreteMixNames.isEmpty) {
        print('⚠️ WARNING: No concrete mixes loaded! Check database connection.');
      } else {
        // Debug: show sample entries
        final sampleKeys = _concreteMixNames.keys.take(3).toList();
        for (final key in sampleKeys) {
          print('🔍 Sample: "$key" -> "${_concreteMixNames[key]}"');
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error loading concrete mixes: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Batch-load breaks for many time periods (one query)
  Future<void> _batchLoadBreaks(List<String> timePeriodIds) async {
    if (timePeriodIds.isEmpty) return;
    try {
      final response = await SupabaseService.client
          .from('time_period_breaks')
          .select('time_period_id, break_start, break_finish')
          .inFilter('time_period_id', timePeriodIds)
          .order('break_start', ascending: true);
      for (final id in timePeriodIds) {
        _breaks[id] = [];
        _breakDurations[id] = 0;
      }
      final byPeriod = <String, List<Map<String, dynamic>>>{};
      for (final id in timePeriodIds) {
        byPeriod[id] = [];
      }
      for (final row in (response as List)) {
        final id = row['time_period_id']?.toString();
        if (id == null || !byPeriod.containsKey(id)) continue;
        final breakRow = {
          'break_start': row['break_start'],
          'break_finish': row['break_finish'],
        };
        byPeriod[id]!.add(breakRow);
        int total = _breakDurations[id] ?? 0;
        final start = row['break_start']?.toString();
        final finish = row['break_finish']?.toString();
        if (start != null && finish != null) {
          try {
            total += DateTime.parse(finish).difference(DateTime.parse(start)).inMinutes;
          } catch (_) {}
        }
        _breakDurations[id] = total;
      }
      for (final id in timePeriodIds) {
        _breaks[id] = byPeriod[id] ?? [];
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error batch-loading breaks: $e');
      for (final id in timePeriodIds) {
        _breaks[id] = [];
        _breakDurations[id] = 0;
      }
    }
  }

  /// Batch-load used and mobilised fleet for many time periods (two queries)
  Future<void> _batchLoadFleetData(List<String> timePeriodIds) async {
    if (timePeriodIds.isEmpty) return;
    for (final id in timePeriodIds) {
      _usedFleet[id] = [];
      _mobilisedFleet[id] = [];
    }
    try {
      final usedResponse = await SupabaseService.client
          .from('time_period_used_fleet')
          .select('time_period_id, large_plant_id, large_plant(plant_no)')
          .inFilter('time_period_id', timePeriodIds)
          .order('display_order', ascending: true);
      for (final item in (usedResponse as List)) {
        final id = item['time_period_id']?.toString();
        if (id == null) continue;
        final plant = (item as Map<String, dynamic>)['large_plant'] as Map<String, dynamic>?;
        final no = plant?['plant_no']?.toString();
        if (no != null) _usedFleet[id]!.add({'plant_no': no});
      }
      final mobilisedResponse = await SupabaseService.client
          .from('time_period_mobilised_fleet')
          .select('time_period_id, large_plant_id, large_plant(plant_no)')
          .inFilter('time_period_id', timePeriodIds)
          .order('display_order', ascending: true);
      for (final item in (mobilisedResponse as List)) {
        final id = item['time_period_id']?.toString();
        if (id == null) continue;
        final plant = (item as Map<String, dynamic>)['large_plant'] as Map<String, dynamic>?;
        final no = plant?['plant_no']?.toString();
        if (no != null) _mobilisedFleet[id]!.add({'plant_no': no});
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error batch-loading fleet: $e');
    }
  }

  /// Load time periods for the selected week
  Future<void> _loadTimePeriods() async {
    setState(() => _isLoading = true);

    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not logged in');
      }

      final weekEnd = _getWeekEnd(_selectedWeekStart);
      final weekStartStr = DateFormat('yyyy-MM-dd').format(_selectedWeekStart);
      final weekEndStr = DateFormat('yyyy-MM-dd').format(weekEnd);

      // Fetch time periods (indexed: user_id, work_date, status — see supabase_indexes.md)
      final response = await SupabaseService.client
          .from('time_periods')
          .select()
          .eq('user_id', user.id)
          .eq('is_active', true)
          .gte('work_date', weekStartStr)
          .lte('work_date', weekEndStr)
          .order('work_date', ascending: true)
          .order('start_time', ascending: true);
      
      final periods = List<Map<String, dynamic>>.from(response as List);
      final periodIds = periods.map((p) => p['id']?.toString()).whereType<String>().toList();
      final projectIds = periods
          .map((p) => p['project_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final plantIdsToLoad = periods
          .map((p) => p['large_plant_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      // Load only project names for projects in this week (not full table)
      await _loadProjectNamesForIds(projectIds);
      await _loadConcreteMixes();

      // Load plant descriptions only for plants in this week
      _plantDescriptions = {};
      if (plantIdsToLoad.isNotEmpty) {
        try {
          final plantResponse = await SupabaseService.client
              .from('large_plant')
              .select('id, plant_description, plant_no')
              .inFilter('id', plantIdsToLoad);
          for (final plant in plantResponse) {
            final plantId = plant['id']?.toString();
            if (plantId != null) {
              final plantDesc = plant['plant_description']?.toString() ??
                  plant['plant_no']?.toString() ?? 'Unknown';
              _plantDescriptions[plantId] = plantDesc;
            }
          }
        } catch (e) {
          // ignore: avoid_print
          print('Error loading plant descriptions: $e');
        }
      }

      // Batch-load breaks and fleet (one/two queries instead of N per period)
      if (periodIds.isNotEmpty) {
        await Future.wait([
          _batchLoadBreaks(periodIds),
          _batchLoadFleetData(periodIds),
        ]);
      }

      setState(() {
        _timePeriods = periods;
        _isLoading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('Error loading time periods: $e');
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

  /// Navigate to previous week
  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
    });
    _loadTimePeriods();
  }

  /// Navigate to next week
  void _nextWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
    });
    _loadTimePeriods();
  }

  /// Navigate to current week
  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
    });
    _loadTimePeriods();
  }

  /// Calculate total hours for a time period (minus breaks)
  double _calculatePeriodHours(Map<String, dynamic> period) {
    if (period['start_time'] == null || period['finish_time'] == null) {
      return 0.0;
    }
    
    try {
      final startTimeStr = period['start_time']?.toString() ?? '';
      final finishTimeStr = period['finish_time']?.toString() ?? '';
      final startTime = DateTime.parse(startTimeStr);
      final finishTime = DateTime.parse(finishTimeStr);
      double totalMinutes = finishTime.difference(startTime).inMinutes.toDouble();
      
      // Subtract break time
      final periodId = period['id']?.toString();
      if (periodId != null) {
        final breakMinutes = _breakDurations[periodId] ?? 0;
        totalMinutes -= breakMinutes;
      }
      
      return totalMinutes / 60.0;
    } catch (e) {
      // ignore: avoid_print
      print('Error calculating period hours: $e');
      return 0.0;
    }
  }

  /// Calculate total break duration in minutes for a list of periods
  int _calculateTotalBreakDuration(List<Map<String, dynamic>> periods) {
    int total = 0;
    for (final period in periods) {
      final periodId = period['id']?.toString();
      if (periodId != null) {
        total += _breakDurations[periodId] ?? 0;
      }
    }
    return total;
  }

  /// Calculate earliest start time and latest finish time for a day
  String _calculateDayTimes(List<Map<String, dynamic>> periods) {
    DateTime? earliestStart;
    DateTime? latestFinish;
    
    for (final period in periods) {
      if (period['start_time'] != null) {
        try {
          final startStr = period['start_time']?.toString() ?? '';
          final start = DateTime.parse(startStr);
          if (earliestStart == null || start.isBefore(earliestStart)) {
            earliestStart = start;
          }
        } catch (e) {
          // ignore: avoid_print
          print('Error parsing start time: $e');
        }
      }
      if (period['finish_time'] != null) {
        try {
          final finishStr = period['finish_time']?.toString() ?? '';
          final finish = DateTime.parse(finishStr);
          if (latestFinish == null || finish.isAfter(latestFinish)) {
            latestFinish = finish;
          }
        } catch (e) {
          // ignore: avoid_print
          print('Error parsing finish time: $e');
        }
      }
    }
    
    final startStr = earliestStart != null ? _convertDateTimeTo12Hour(earliestStart) : '--:--';
    final finishStr = latestFinish != null ? _convertDateTimeTo12Hour(latestFinish) : '--:--';
    final totalBreakMinutes = _calculateTotalBreakDuration(periods);
    final breakStr = totalBreakMinutes == 0 ? 'no break' : _formatHoursAsHMM(totalBreakMinutes / 60.0);
    
    return '$startStr - $breakStr - $finishStr';
  }

  /// Calculate total hours for a date (minus breaks)
  double _calculateDayHours(List<Map<String, dynamic>> periods) {
    double total = 0.0;
    for (final period in periods) {
      total += _calculatePeriodHours(period);
    }
    return total;
  }

  /// Format break duration as h:mm
  String _formatBreakDuration(int minutes) {
    return _formatHoursAsHMM(minutes / 60.0);
  }

  /// Get status badge color
  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'submitted':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Get status display text
  String _getStatusText(String status) {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'submitted':
        return 'Submitted';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  /// Show popup with Edit, Delete, Cancel options
  Future<void> _showTimePeriodOptions(Map<String, dynamic> period) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Time Period Options'),
        content: const Text('What would you like to do?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('edit'),
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (result == 'edit') {
      _editTimePeriod(period);
    } else if (result == 'delete') {
      _deleteTimePeriod(period);
    }
  }

  /// Edit a time period
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
    if (status != 'submitted') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This time period has been ${status == 'supervisor_approved' ? 'approved by supervisor' : status == 'admin_approved' ? 'approved by admin' : status} and cannot be edited.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    
    // Navigate to timesheet screen with the time period ID for editing
    if (!mounted) return;
    
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TimeTrackingScreen(timePeriodId: periodId),
      ),
    );
    
    // Reload time periods after returning from edit screen (if data changed)
    if (result == true || mounted) {
      _loadTimePeriods();
    }
  }

  /// Delete a time period
  Future<void> _deleteTimePeriod(Map<String, dynamic> period) async {
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
      final periodId = period['id']?.toString();
      if (periodId == null) throw Exception('Period ID not found');

      final currentUser = await AuthService.getCurrentUser();
      if (currentUser == null) throw Exception('Not logged in');
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

      _loadTimePeriods(); // Reload data
    } catch (e) {
      // ignore: avoid_print
      print('Error deleting time period: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting time period: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Group time periods by date
  Map<String, List<Map<String, dynamic>>> _groupByDate() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final period in _timePeriods) {
      final date = period['work_date']?.toString() ?? '';
      if (date.isNotEmpty) {
        if (!grouped.containsKey(date)) {
          grouped[date] = [];
        }
        grouped[date]!.add(period);
      }
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _getWeekEnd(_selectedWeekStart);
    final isCurrentWeek = _selectedWeekStart == _getWeekStart(DateTime.now());
    final groupedByDate = _groupByDate();
    final sortedDates = groupedByDate.keys.toList()..sort();

    // Format week display: "15 - 21 Dec, 2025"
    final weekStartDay = _selectedWeekStart.day;
    final weekEndDay = weekEnd.day;
    final month = DateFormat('MMM').format(_selectedWeekStart);
    final year = _selectedWeekStart.year;
    final weekDisplay = '$weekStartDay - $weekEndDay $month, $year';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Time Periods',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'my_time_periods_screen.dart')],
      ),
      body: Column(
        children: [
          // Week Navigation
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _previousWeek,
                  tooltip: 'Previous Week',
                ),
                Column(
                  children: [
                    Text(
                      weekDisplay,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!isCurrentWeek)
                      TextButton.icon(
                        icon: const Icon(Icons.today, size: 16),
                        label: const Text('Go to Current Week'),
                        onPressed: _goToCurrentWeek,
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _nextWeek,
                  tooltip: 'Next Week',
                ),
              ],
            ),
          ),

          // Time Periods List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : sortedDates.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today, 
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No time periods for this week',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: sortedDates.map((date) {
                          final periods = groupedByDate[date]!;
                          final dayHours = _calculateDayHours(periods);
                          final dateObj = DateTime.parse(date);
                          final dayName = DateFormat('EEEE').format(dateObj);
                          final dayTimes = _calculateDayTimes(periods);
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Date Header: "Monday | Start Time - Total Break Time - Finish Time | Total: Total Hours"
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      dayName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          dayTimes,
                                          style: const TextStyle(
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Total: ${_formatHoursAsHMM(dayHours)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Time Periods for this date with break sections
                              ..._buildTimePeriodsWithBreaks(periods),
                              const SizedBox(height: 16),
                            ],
                          );
                        }).toList(),
                      ),
          ),
        ],
      ),
    );
  }

  /// Build time periods with break sections inserted between gaps
  List<Widget> _buildTimePeriodsWithBreaks(List<Map<String, dynamic>> periods) {
    if (periods.isEmpty) return [];
    
    // Sort periods by start_time
    final sortedPeriods = List<Map<String, dynamic>>.from(periods);
    sortedPeriods.sort((a, b) {
      final aStart = a['start_time']?.toString();
      final bStart = b['start_time']?.toString();
      if (aStart == null && bStart == null) return 0;
      if (aStart == null) return 1;
      if (bStart == null) return -1;
      try {
        return DateTime.parse(aStart).compareTo(DateTime.parse(bStart));
      } catch (e) {
        return 0;
      }
    });
    
    final widgets = <Widget>[];
    
    for (int i = 0; i < sortedPeriods.length; i++) {
      // Add the time period
      widgets.add(_buildTimePeriodCard(sortedPeriods[i]));
      
      // Check if there's a gap before the next period
      if (i < sortedPeriods.length - 1) {
        final currentPeriod = sortedPeriods[i];
        final nextPeriod = sortedPeriods[i + 1];
        
        final currentFinish = currentPeriod['finish_time']?.toString();
        final nextStart = nextPeriod['start_time']?.toString();
        
        if (currentFinish != null && nextStart != null) {
          try {
            final finishTime = DateTime.parse(currentFinish);
            final startTime = DateTime.parse(nextStart);
            
            // If there's a gap (finish time is before next start time)
            if (finishTime.isBefore(startTime)) {
              final gapDuration = startTime.difference(finishTime);
              final gapMinutes = gapDuration.inMinutes;
              
              // Only show break if gap is significant (more than 0 minutes)
              if (gapMinutes > 0) {
                widgets.add(_buildBreakSection(finishTime, startTime, gapMinutes));
              }
            }
          } catch (e) {
            // ignore: avoid_print
            print('Error parsing times for gap detection: $e');
          }
        }
      }
    }
    
    return widgets;
  }

  /// Build a break section widget
  Widget _buildBreakSection(DateTime finishTime, DateTime startTime, int gapMinutes) {
    final finishStr = _convertDateTimeTo12Hour(finishTime);
    final startStr = _convertDateTimeTo12Hour(startTime);
    final gapHours = gapMinutes ~/ 60;
    final gapMins = gapMinutes % 60;
    final gapStr = gapHours > 0 ? '$gapHours:${gapMins.toString().padLeft(2, '0')}' : '0:${gapMins.toString().padLeft(2, '0')}';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.red[50],
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline, color: Colors.red[700], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Break: $finishStr - $startStr ($gapStr)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePeriodCard(Map<String, dynamic> period) {
    final periodId = period['id']?.toString() ?? '';
    final projectId = period['project_id']?.toString();
    final largePlantId = period['large_plant_id']?.toString();
    
    // For mechanics, check large_plant_id first
    String projectName = 'No Project';
    if (largePlantId != null && largePlantId.isNotEmpty) {
      projectName = _plantDescriptions[largePlantId] ?? 'No Project';
    } else if (projectId != null && _projectNames.containsKey(projectId)) {
      projectName = _projectNames[projectId]!;
    } else if (projectId != null) {
      projectName = projectId;
    }
    
    final startTime = period['start_time'] != null
        ? _convertDateTimeTo12Hour(DateTime.parse(period['start_time']?.toString() ?? ''))
        : '--:--';
    
    final finishTime = period['finish_time'] != null
        ? _convertDateTimeTo12Hour(DateTime.parse(period['finish_time']?.toString() ?? ''))
        : '--:--';

    final status = period['status']?.toString() ?? 'draft';
    
    final usedFleetList = _usedFleet[periodId] ?? [];
    final mobilisedFleetList = _mobilisedFleet[periodId] ?? [];
    final breakDuration = _breakDurations[periodId] ?? 0;
    final periodHours = _calculatePeriodHours(period);

    // Get allowances - explicitly cast to ensure proper types
    final travelToSiteValue = period['travel_to_site_min'];
    final travelToSite = travelToSiteValue is int ? travelToSiteValue : (travelToSiteValue is num ? travelToSiteValue.toInt() : 0);
    final travelFromSiteValue = period['travel_from_site_min'];
    final travelFromSite = travelFromSiteValue is int ? travelFromSiteValue : (travelFromSiteValue is num ? travelFromSiteValue.toInt() : 0);
    final miscAllowanceValue = period['misc_allowance_min'];
    final miscAllowance = miscAllowanceValue is int ? miscAllowanceValue : (miscAllowanceValue is num ? miscAllowanceValue.toInt() : 0);
    final onCallValue = period['on_call'];
    final onCall = onCallValue == true;

    // Get concrete mix details - look up name from id (UUID)
    // concrete_mix_type stores the UUID id from concrete_mix table
    final concreteMixId = period['concrete_mix_type']?.toString()?.trim() ?? '';
    String concreteMix = '';
    if (concreteMixId.isNotEmpty) {
      // Look up by UUID (exact match)
      if (_concreteMixNames.containsKey(concreteMixId)) {
        concreteMix = _concreteMixNames[concreteMixId]!;
      } else {
        // Fallback: if lookup fails, show the UUID (shouldn't happen if data is correct)
        print('⚠️ Concrete mix not found in lookup: "$concreteMixId" (map has ${_concreteMixNames.length} entries)');
        concreteMix = 'Unknown Mix ($concreteMixId)';
      }
    }
    final concreteQty = period['concrete_qty'];
    final ticketNumber = period['concrete_ticket_no']?.toString() ?? '';

    // Get comments
    final comments = period['comments']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showTimePeriodOptions(period),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Project Name and Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      projectName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getStatusText(status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(status),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Row 2: Times | Used Fleet | Mobilised Fleet | Hours
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Times
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Times: ',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              breakDuration == 0
                                  ? '$startTime - $finishTime'
                                  : '$startTime - ${_formatBreakDuration(breakDuration)} - $finishTime',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        // Used Fleet
                        if (usedFleetList.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Used: ',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                usedFleetList.map((f) => f['plant_no']?.toString() ?? '').join(', '),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        // Mobilised Fleet
                        if (mobilisedFleetList.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Mobilised: ',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                mobilisedFleetList.map((f) => f['plant_no']?.toString() ?? '').join(', '),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Hours display
                  Text(
                    _formatHoursAsHMM(periodHours),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
              // Row 3: Allowances
              if (travelToSite > 0 || travelFromSite > 0 || miscAllowance > 0 || onCall) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Allowances: ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (travelToSite > 0)
                      Text(
                        'To Site: ${travelToSite}m',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (travelToSite > 0 && travelFromSite > 0) const Text(', ', style: TextStyle(fontSize: 12)),
                    if (travelFromSite > 0)
                      Text(
                        'From Site: ${travelFromSite}m',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if ((travelToSite > 0 || travelFromSite > 0) && miscAllowance > 0) const Text(', ', style: TextStyle(fontSize: 12)),
                    if (miscAllowance > 0)
                      Text(
                        'Misc: ${miscAllowance}m',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if ((travelToSite > 0 || travelFromSite > 0 || miscAllowance > 0) && onCall) const Text(', ', style: TextStyle(fontSize: 12)),
                    if (onCall)
                      const Text(
                        'On Call',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ],
              // Row 4: Materials (Ticket, Concrete Mix, Qty)
              if (ticketNumber.isNotEmpty || concreteMix.isNotEmpty || concreteQty != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Materials: ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (ticketNumber.isNotEmpty)
                      Text(
                        'Ticket: $ticketNumber',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (ticketNumber.isNotEmpty && concreteMix.isNotEmpty) const Text(', ', style: TextStyle(fontSize: 12)),
                    if (concreteMix.isNotEmpty)
                      Text(
                        'Concrete Mix: $concreteMix',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if ((ticketNumber.isNotEmpty || concreteMix.isNotEmpty) && concreteQty != null) const Text(', ', style: TextStyle(fontSize: 12)),
                    if (concreteQty != null)
                      Text(
                        'Qty: $concreteQty',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ],
              // Row 5: Comments
              if (comments.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Comments: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  comments,
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
