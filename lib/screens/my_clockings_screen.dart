/// My Clockings Screen
/// 
/// Allows users to view their clock in/out records (read-only).
/// Features:
/// - Grouped by date with total hours per day
/// - Sorted oldest to newest
/// - Shows project name, clock in/out times, and GPS accuracy
/// - Read-only view

import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:intl/intl.dart';

class MyClockingsScreen extends StatefulWidget {
  const MyClockingsScreen({super.key});

  @override
  State<MyClockingsScreen> createState() => _MyClockingsScreenState();
}

class _MyClockingsScreenState extends State<MyClockingsScreen> {
  DateTime _selectedWeekStart = DateTime.now();
  bool _isLoading = true;
  List<Map<String, dynamic>> _clockings = [];
  Map<String, String> _projectNames = {}; // project_id -> project_name

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = _getWeekStart(DateTime.now());
    _loadClockings();
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

  /// Convert DateTime to 12-hour format
  String _convertDateTimeTo12Hour(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  /// Format hours as h:mm
  String _formatHoursAsHMM(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  /// Load projects to map project_id to project_name
  Future<void> _loadProjects() async {
    try {
      final projects = await SupabaseService.client
          .from('projects')
          .select('id, project_name');
      
      _projectNames = {};
      for (final project in projects) {
        final id = project['id']?.toString();
        final name = project['project_name']?.toString() ?? 
                     id ?? 'Unknown';
        if (id != null) {
          _projectNames[id] = name;
        }
      }
    } catch (e) {
      print('Error loading projects: $e');
    }
  }

  /// Load clockings for the selected week.
  /// Reads from time_attendance where user_id = current user. If users see no entries,
  /// the most likely cause is RLS: there must be a policy allowing SELECT for rows
  /// where user_id = auth.uid() (e.g. "Users can view own time_attendance").
  Future<void> _loadClockings() async {
    setState(() => _isLoading = true);

    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Load projects first
      await _loadProjects();

      final weekEnd = _getWeekEnd(_selectedWeekStart);
      final weekStartStr = DateFormat('yyyy-MM-dd').format(_selectedWeekStart);
      final weekEndStr = DateFormat('yyyy-MM-dd').format(weekEnd);

      // time_attendance: eq user_id + start_time range uses idx_time_attendance_user_id (see supabase_indexes.md)
      final response = await SupabaseService.client
          .from('time_attendance')
          .select()
          .eq('user_id', user.id)
          .not('start_time', 'is', null)
          .not('finish_time', 'is', null)
          .gte('start_time', '${weekStartStr}T00:00:00')
          .lte('start_time', '${weekEndStr}T23:59:59')
          .order('start_time', ascending: true);
      
      final clockings = List<Map<String, dynamic>>.from(response as List);

      setState(() {
        _clockings = clockings;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('Error loading clockings: $e');
      print('Stack: $stackTrace');
      setState(() => _isLoading = false);

      final message = e.toString();
      final isLikelyRls = message.contains('policy') ||
          message.contains('permission') ||
          message.contains('row-level security') ||
          message.contains('RLS');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isLikelyRls
                  ? 'Cannot load clockings (check RLS: allow SELECT where user_id = auth.uid()). $message'
                  : 'Error loading clockings: $message',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
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
    _loadClockings();
  }

  /// Navigate to next week
  void _nextWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
    });
    _loadClockings();
  }

  /// Navigate to current week
  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
    });
    _loadClockings();
  }

  /// Calculate total hours for a clocking
  double _calculateClockingHours(Map<String, dynamic> clocking) {
    if (clocking['start_time'] == null || clocking['finish_time'] == null) {
      return 0.0;
    }
    
    try {
      final startTimeStr = clocking['start_time']?.toString() ?? '';
      final finishTimeStr = clocking['finish_time']?.toString() ?? '';
      final startTime = DateTime.parse(startTimeStr);
      final finishTime = DateTime.parse(finishTimeStr);
      final totalMinutes = finishTime.difference(startTime).inMinutes.toDouble();
      
      return totalMinutes / 60.0;
    } catch (e) {
      print('Error calculating clocking hours: $e');
      return 0.0;
    }
  }

  /// Calculate total hours for a date
  double _calculateDayHours(List<Map<String, dynamic>> clockings) {
    double total = 0.0;
    for (final clocking in clockings) {
      total += _calculateClockingHours(clocking);
    }
    return total;
  }

  /// Calculate earliest clock in and latest clock out for a day
  String _calculateDayTimes(List<Map<String, dynamic>> clockings) {
    DateTime? earliestClockIn;
    DateTime? latestClockOut;
    
    for (final clocking in clockings) {
      if (clocking['start_time'] != null) {
        try {
          final startStr = clocking['start_time']?.toString() ?? '';
          final start = DateTime.parse(startStr);
          if (earliestClockIn == null || start.isBefore(earliestClockIn)) {
            earliestClockIn = start;
          }
        } catch (e) {
          print('Error parsing start time: $e');
        }
      }
      if (clocking['finish_time'] != null) {
        try {
          final finishStr = clocking['finish_time']?.toString() ?? '';
          final finish = DateTime.parse(finishStr);
          if (latestClockOut == null || finish.isAfter(latestClockOut)) {
            latestClockOut = finish;
          }
        } catch (e) {
          print('Error parsing finish time: $e');
        }
      }
    }
    
    final clockInStr = earliestClockIn != null 
        ? _convertDateTimeTo12Hour(earliestClockIn) 
        : '--:--';
    final clockOutStr = latestClockOut != null 
        ? _convertDateTimeTo12Hour(latestClockOut) 
        : '--:--';
    
    return '$clockInStr - $clockOutStr';
  }

  /// Group clockings by date
  Map<String, List<Map<String, dynamic>>> _groupByDate() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final clocking in _clockings) {
      final startTime = clocking['start_time']?.toString();
      if (startTime != null) {
        try {
          final dateTime = DateTime.parse(startTime);
          final date = DateFormat('yyyy-MM-dd').format(dateTime);
          if (!grouped.containsKey(date)) {
            grouped[date] = [];
          }
          grouped[date]!.add(clocking);
        } catch (e) {
          print('Error parsing date: $e');
        }
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
          'My Clockings',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'my_clockings_screen.dart')],
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

          // Clockings List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : sortedDates.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.access_time, 
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No clockings for this week',
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
                          final clockings = groupedByDate[date]!;
                          final dayHours = _calculateDayHours(clockings);
                          final dateObj = DateTime.parse(date);
                          final dayName = DateFormat('EEEE').format(dateObj);
                          final dayTimes = _calculateDayTimes(clockings);
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Date Header: "Monday | Clock In - Clock Out | Total: Total Hours"
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
                              // Clockings for this date
                              ...clockings.map((clocking) => _buildClockingCard(clocking)),
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

  Widget _buildClockingCard(Map<String, dynamic> clocking) {
    final projectId = clocking['project_id']?.toString();
    String projectName = 'No Project';
    if (projectId != null && _projectNames.containsKey(projectId)) {
      projectName = _projectNames[projectId]!;
    } else if (projectId != null) {
      projectName = projectId;
    }
    
    final startTime = clocking['start_time'] != null
        ? _convertDateTimeTo12Hour(DateTime.parse(clocking['start_time']?.toString() ?? ''))
        : '--:--';
    
    final finishTime = clocking['finish_time'] != null
        ? _convertDateTimeTo12Hour(DateTime.parse(clocking['finish_time']?.toString() ?? ''))
        : '--:--';

    final clockingHours = _calculateClockingHours(clocking);
    
    // GPS accuracy info
    final startAccuracy = clocking['start_gps_accuracy'] as int?;
    final finishAccuracy = clocking['finish_gps_accuracy'] as int?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Project Name and Hours
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
                Text(
                  _formatHoursAsHMM(clockingHours),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: Clock In - Clock Out
            Row(
              children: [
                const Text(
                  'Clock In: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  startTime,
                  style: const TextStyle(fontSize: 12),
                ),
                if (startAccuracy != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${startAccuracy}m)',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                const Text(
                  'Clock Out: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  finishTime,
                  style: const TextStyle(fontSize: 12),
                ),
                if (finishAccuracy != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${finishAccuracy}m)',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
