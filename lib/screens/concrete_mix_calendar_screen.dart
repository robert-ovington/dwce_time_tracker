/// Concrete Mix Calendar Screen
///
/// Week view of concrete_mix_bookings with Submitted/Scheduled filters and weekday filters.
/// Style and week period / status row aligned with supervisor_approval_screen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/errors/error_log_service.dart';
import 'package:dwce_time_tracker/screens/concrete_mix_bookings_screen.dart';
import 'package:dwce_time_tracker/widgets/screen_info_icon.dart';

class ConcreteMixCalendarScreen extends StatefulWidget {
  const ConcreteMixCalendarScreen({super.key});

  @override
  State<ConcreteMixCalendarScreen> createState() => _ConcreteMixCalendarScreenState();
}

class _ConcreteMixCalendarScreenState extends State<ConcreteMixCalendarScreen> {
  static const List<String> _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Table colours (match timesheet_screen section style: 0xFF005AB0 border, 0xFFBADDFF header)
  static const Color _tableBorderColor = Color(0xFF005AB0);
  static const Color _tableHeaderColor = Color(0xFFBADDFF);
  static const Color _tableTotalRowColor = Color(0xFFB3D9FF);
  static const Color _rowColorCol = Color(0xFFFFE4CC);  // light orange for Collection
  static const Color _rowColorDel = Color(0xFFCCE5CC); // light green for Delivery

  // Week navigation
  DateTime _selectedWeekStart = DateTime.now();

  // Filters: status and weekday selection
  String _statusFilter = 'submitted'; // 'submitted' | 'scheduled' | 'all' | 'deleted'
  Set<String> _selectedDays = {};

  // Data
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _deletedBookings = [];

  // Lookup maps (user, project, concrete mix names)
  Map<String, String> _userDisplayNames = {};
  Map<String, String> _projectNames = {};
  Map<String, String> _concreteMixNames = {};

  // Loading state
  bool _isLoading = true;

  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
  }

  DateTime _getWeekEnd(DateTime weekStart) {
    return weekStart.add(const Duration(days: 6));
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
      _load();
    });
  }

  void _nextWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
      _load();
    });
  }

  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
      _load();
    });
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final weekEnd = _getWeekEnd(_selectedWeekStart);
    final startStr = _selectedWeekStart.toUtc().toIso8601String();
    final endStr = DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59).toUtc().toIso8601String();

    try {
      // Filter by due_date_time range to use idx_cmb_due_date_time (see supabase_indexes.md)
      final list = await SupabaseService.client
          .from('concrete_mix_bookings')
          .select('*')
          .eq('is_active', true)
          .gte('due_date_time', startStr)
          .lte('due_date_time', endStr)
          .order('due_date_time');

      final deletedList = await SupabaseService.client
          .from('concrete_mix_bookings')
          .select('*')
          .eq('is_active', false)
          .gte('due_date_time', startStr)
          .lte('due_date_time', endStr)
          .order('due_date_time');

      final bookings = List<Map<String, dynamic>>.from(list as List);
      final deletedBookings = List<Map<String, dynamic>>.from(deletedList as List);

      final userIds = <String>{};
      final projectIds = <String>{};
      final mixIds = <String>{};
      for (final b in bookings) {
        final u = b['booking_user_id']?.toString();
        if (u != null) userIds.add(u);
        final s = b['site_contact_id']?.toString();
        if (s != null) userIds.add(s);
        final p = b['project_id']?.toString();
        if (p != null) projectIds.add(p);
        final m = b['concrete_mix_type']?.toString();
        if (m != null) mixIds.add(m);
      }
      for (final b in deletedBookings) {
        final u = b['booking_user_id']?.toString();
        if (u != null) userIds.add(u);
        final s = b['site_contact_id']?.toString();
        if (s != null) userIds.add(s);
        final p = b['project_id']?.toString();
        if (p != null) projectIds.add(p);
        final m = b['concrete_mix_type']?.toString();
        if (m != null) mixIds.add(m);
      }

      final userDisplayNames = <String, String>{};
      if (userIds.isNotEmpty) {
        final users = await SupabaseService.client
            .from('users_setup')
            .select('user_id, display_name')
            .inFilter('user_id', userIds.toList());
        for (final u in users as List) {
          final map = Map<String, dynamic>.from(u as Map);
          userDisplayNames[map['user_id']?.toString() ?? ''] = map['display_name']?.toString() ?? '—';
        }
      }

      final projectNames = <String, String>{};
      if (projectIds.isNotEmpty) {
        final projects = await SupabaseService.client
            .from('projects')
            .select('id, project_name')
            .inFilter('id', projectIds.toList());
        for (final p in projects as List) {
          final map = Map<String, dynamic>.from(p as Map);
          projectNames[map['id']?.toString() ?? ''] = map['project_name']?.toString() ?? '—';
        }
      }

      final concreteMixNames = <String, String>{};
      if (mixIds.isNotEmpty) {
        final mixes = await SupabaseService.client
            .from('concrete_mix')
            .select('id, name')
            .inFilter('id', mixIds.toList());
        for (final m in mixes as List) {
          final map = Map<String, dynamic>.from(m as Map);
          concreteMixNames[map['id']?.toString() ?? ''] = map['name']?.toString() ?? '—';
        }
      }

      if (mounted) {
        setState(() {
          _bookings = bookings;
          _deletedBookings = deletedBookings;
          _userDisplayNames = userDisplayNames;
          _projectNames = projectNames;
          _concreteMixNames = concreteMixNames;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'ConcreteMixCalendarScreen._load', type: 'Load', description: '$e', stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading: $e'), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  /// Soft-delete a booking (set is_active = false). Reloads list after.
  Future<void> _deleteBooking(Map<String, dynamic> b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete booking?'),
        content: const Text(
          'This will remove the booking from the list. You can restore it from the Bookings screen if needed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await SupabaseService.client
          .from('concrete_mix_bookings')
          .update({'is_active': false})
          .eq('id', b['id'] as Object);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking deleted'), backgroundColor: Colors.orange),
        );
        _load();
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'ConcreteMixCalendarScreen._deleteBooking', type: 'Delete', description: '$e', stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Restore a soft-deleted booking (set is_active = true). Reloads list after.
  Future<void> _restoreBooking(Map<String, dynamic> b) async {
    try {
      await SupabaseService.client
          .from('concrete_mix_bookings')
          .update({'is_active': true})
          .eq('id', b['id'] as Object);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking restored'), backgroundColor: Colors.green),
        );
        _load();
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'ConcreteMixCalendarScreen._restoreBooking', type: 'Restore', description: '$e', stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  List<Map<String, dynamic>> get _filteredBookings {
    if (_statusFilter == 'deleted') return [];
    return _bookings.where((b) {
      final scheduled = b['is_scheduled'] == true;
      if (_statusFilter == 'submitted' && scheduled) return false;
      if (_statusFilter == 'scheduled' && !scheduled) return false;

      final due = b['due_date_time'];
      if (due == null) return true;
      final dt = DateTime.parse(due.toString());
      final dayName = DateFormat('EEE').format(dt);
      if (_selectedDays.isEmpty) return true;
      return _selectedDays.contains(dayName);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredDeletedBookings {
    if (_statusFilter != 'deleted') return [];
    return _deletedBookings.where((b) {
      final due = b['due_date_time'];
      if (due == null) return true;
      final dt = DateTime.parse(due.toString());
      final dayName = DateFormat('EEE').format(dt);
      if (_selectedDays.isEmpty) return true;
      return _selectedDays.contains(dayName);
    }).toList();
  }

  /// Day name (Mon..Sun) to weekday 1..7
  int _dayNameToWeekday(String name) {
    final i = _dayNames.indexOf(name);
    return i >= 0 ? i + 1 : 1;
  }

  /// Sum of concrete_qty for a given day (1=Mon..7=Sun) and scheduled flag
  double _quantityForDay(int weekday, bool scheduled) {
    double sum = 0;
    for (final b in _bookings) {
      final due = b['due_date_time'];
      if (due == null) continue;
      final dt = DateTime.parse(due.toString());
      if (dt.weekday != weekday) continue;
      if ((b['is_scheduled'] == true) != scheduled) continue;
      final q = b['concrete_qty'];
      if (q != null) {
        if (q is num) {
          sum += (q as num).toDouble();
        } else {
          sum += double.tryParse(q.toString()) ?? 0;
        }
      }
    }
    return sum;
  }

  /// Sum of concrete_qty for deleted bookings on a given day (1=Mon..7=Sun)
  double _quantityForDayDeleted(int weekday) {
    double sum = 0;
    for (final b in _deletedBookings) {
      final due = b['due_date_time'];
      if (due == null) continue;
      final dt = DateTime.parse(due.toString());
      if (dt.weekday != weekday) continue;
      final q = b['concrete_qty'];
      if (q != null) {
        if (q is num) {
          sum += (q as num).toDouble();
        } else {
          sum += double.tryParse(q.toString()) ?? 0;
        }
      }
    }
    return sum;
  }

  String _formatQuantity(double q) {
    if (q == q.roundToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Format duration minutes as "h:mm"
  String _durationHmm(int minutes) {
    if (minutes <= 0) return '0:00';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = _getWeekStart(DateTime.now());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Concrete Mix Calendar', style: TextStyle(color: Colors.black)),
          centerTitle: true,
          backgroundColor: const Color(0xFF0081FB),
          foregroundColor: Colors.black,
          actions: const [ScreenInfoIcon(screenName: 'concrete_mix_calendar_screen.dart')],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final filtered = _statusFilter == 'deleted' ? _filteredDeletedBookings : _filteredBookings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Concrete Mix Calendar', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'concrete_mix_calendar_screen.dart')],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Week period (same as supervisor_approval_screen)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF005AB0), width: 2),
                borderRadius: BorderRadius.circular(8),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${DateFormat('MMM dd').format(_selectedWeekStart)} - ${DateFormat('MMM dd, yyyy').format(_getWeekEnd(_selectedWeekStart))}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    onPressed: _nextWeek,
                    tooltip: 'Next Week',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Status row (Submitted, Scheduled, Mon-Sun, All Week)
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
                        setState(() => _statusFilter = 'scheduled');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _statusFilter == 'scheduled' ? Colors.green : null,
                        foregroundColor: _statusFilter == 'scheduled' ? Colors.white : null,
                      ),
                      child: const Text('Scheduled'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _statusFilter = 'all');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _statusFilter == 'all' ? Colors.green : null,
                        foregroundColor: _statusFilter == 'all' ? Colors.white : null,
                      ),
                      child: const Text('All'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _statusFilter = 'deleted');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _statusFilter == 'deleted' ? Colors.orange : null,
                        foregroundColor: _statusFilter == 'deleted' ? Colors.white : null,
                      ),
                      child: const Text('Deleted'),
                    ),
                    const SizedBox(width: 24),
                    ..._dayNames.map((day) {
                      final isSelected = _selectedDays.contains(day);
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedDays = isSelected ? {} : {day};
                            });
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
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedDays.isEmpty ? Colors.green : null,
                        foregroundColor: _selectedDays.isEmpty ? Colors.white : null,
                      ),
                      child: const Text('All Week'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Table: Week Day | Submitted | Scheduled | Deleted
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: _tableBorderColor, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Table(
                border: TableBorder.all(color: _tableBorderColor),
                columnWidths: const {
                  0: FixedColumnWidth(108),
                  1: FixedColumnWidth(108),
                  2: FixedColumnWidth(108),
                  3: FixedColumnWidth(108),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: _tableHeaderColor),
                    children: [
                      const Padding(padding: EdgeInsets.all(8), child: Text('Week Day', style: TextStyle(fontWeight: FontWeight.bold))),
                      const Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Submitted', style: TextStyle(fontWeight: FontWeight.bold)))),
                      const Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Scheduled', style: TextStyle(fontWeight: FontWeight.bold)))),
                      const Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Deleted', style: TextStyle(fontWeight: FontWeight.bold)))),
                    ],
                  ),
                ..._dayNames.where((day) {
                  final wd = _dayNameToWeekday(day);
                  final submitted = _quantityForDay(wd, false);
                  final scheduled = _quantityForDay(wd, true);
                  final deleted = _quantityForDayDeleted(wd);
                  return submitted > 0 || scheduled > 0 || deleted > 0;
                }).map((day) {
                  final wd = _dayNameToWeekday(day);
                  final dateForDay = _selectedWeekStart.add(Duration(days: wd - 1));
                  final submitted = _quantityForDay(wd, false);
                  final scheduled = _quantityForDay(wd, true);
                  final deleted = _quantityForDayDeleted(wd);
                  return TableRow(
                    children: [
                      Padding(padding: const EdgeInsets.all(8), child: Text(DateFormat('EEE, d MMM').format(dateForDay))),
                      Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(_formatQuantity(submitted)))),
                      Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(_formatQuantity(scheduled)))),
                      Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(_formatQuantity(deleted)))),
                    ],
                  );
                }),
                TableRow(
                  decoration: const BoxDecoration(color: _tableTotalRowColor),
                  children: [
                    const Padding(padding: EdgeInsets.all(8), child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(child: Text(_formatQuantity(_bookings.where((b) => b['is_scheduled'] != true).fold<double>(0, (s, b) {
                        final q = b['concrete_qty'];
                        if (q == null) return s;
                        if (q is num) return s + (q as num).toDouble();
                        return s + (double.tryParse(q.toString()) ?? 0);
                      })))),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(child: Text(_formatQuantity(_bookings.where((b) => b['is_scheduled'] == true).fold<double>(0, (s, b) {
                        final q = b['concrete_qty'];
                        if (q == null) return s;
                        if (q is num) return s + (q as num).toDouble();
                        return s + (double.tryParse(q.toString()) ?? 0);
                      })))),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(child: Text(_formatQuantity(_deletedBookings.fold<double>(0, (s, b) {
                        final q = b['concrete_qty'];
                        if (q == null) return s;
                        if (q is num) return s + (q as num).toDouble();
                        return s + (double.tryParse(q.toString()) ?? 0);
                      })))),
                    ),
                  ],
                ),
              ],
            ),
            ),
            const SizedBox(height: 24),

            // Bookings list (full width)
            SizedBox(
              width: constraints.maxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            const Text('Bookings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: _tableBorderColor, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DataTable(
                columnSpacing: 8,
                headingRowHeight: 48,
                dataRowMinHeight: 40,
                columns: [
                  DataColumn(columnWidth: const FlexColumnWidth(0.45), label: const Text('Day', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(0.45), label: const Text('Time', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(0.55), label: const Text('On Site', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(0.5), label: const Text('Quantity', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(0.35), label: const Text('Type', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(1.5), label: const Text('Booked by', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(2.6), label: const Text('Project', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(1.5), label: const Text('Site Contact', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(1.5), label: const Text('Concrete Mix', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(0.6), label: const Text('Wet/Dry', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(2.0), label: const Text('Comment', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(columnWidth: const FlexColumnWidth(0.8), label: const Text('', style: TextStyle(fontWeight: FontWeight.bold)), headingRowAlignment: MainAxisAlignment.center),
                ],
                headingRowColor: WidgetStateProperty.all(_tableHeaderColor),
                rows: filtered.map((b) {
                  final due = b['due_date_time'];
                  final dt = due != null ? DateTime.parse(due.toString()) : DateTime.now();
                  final day = DateFormat('EEE').format(dt);
                  final time = DateFormat('H:mm').format(dt);
                  final duration = (b['duration_on_site'] as int?) ?? 0;
                  final onSite = _durationHmm(duration);
                  final bookedBy = _userDisplayNames[b['booking_user_id']?.toString() ?? ''] ?? '—';
                  final project = _projectNames[b['project_id']?.toString() ?? ''] ?? '—';
                  final siteContact = _userDisplayNames[b['site_contact_id']?.toString() ?? ''] ?? '—';
                  final mix = _concreteMixNames[b['concrete_mix_type']?.toString() ?? ''] ?? '—';
                  final qty = b['concrete_qty'] != null ? (b['concrete_qty'] is num ? (b['concrete_qty'] as num).toString() : b['concrete_qty'].toString()) : '—';
                  final type = (b['delivered'] == true) ? 'Del' : 'Col';
                  final wetDry = (b['wet'] == true) ? 'Wet' : 'Dry';
                  final comment = b['comments']?.toString() ?? '';

                  return DataRow(
                    color: WidgetStateProperty.all(type == 'Del' ? _rowColorDel : _rowColorCol),
                    cells: [
                      DataCell(Center(child: Text(day, overflow: TextOverflow.ellipsis))),
                      DataCell(Center(child: Text(time, overflow: TextOverflow.ellipsis))),
                      DataCell(Center(child: Text(onSite, overflow: TextOverflow.ellipsis))),
                      DataCell(Center(child: Text(qty, overflow: TextOverflow.ellipsis))),
                      DataCell(Center(child: Text(type, overflow: TextOverflow.ellipsis))),
                      DataCell(Center(child: Text(bookedBy, overflow: TextOverflow.ellipsis))),
                      DataCell(Text(project, overflow: TextOverflow.ellipsis)),
                      DataCell(Center(child: Text(siteContact, overflow: TextOverflow.ellipsis))),
                      DataCell(Center(child: Text(mix, overflow: TextOverflow.ellipsis))),
                      DataCell(Center(child: Text(wetDry, overflow: TextOverflow.ellipsis))),
                      DataCell(Text(comment, overflow: TextOverflow.ellipsis)),
                      DataCell(
                        Center(
                          child: _statusFilter == 'deleted'
                              ? IconButton(
                                  icon: const Icon(Icons.restore, size: 20),
                                  onPressed: () => _restoreBooking(b),
                                  tooltip: 'Restore',
                                  style: IconButton.styleFrom(foregroundColor: Colors.green, padding: EdgeInsets.zero, minimumSize: const Size(40, 40)),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (context) => ConcreteMixBookingsScreen(editBookingId: b['id']?.toString()),
                                          ),
                                        ).then((_) => _load());
                                      },
                                      tooltip: 'Edit',
                                      style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 40)),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20),
                                      onPressed: () => _deleteBooking(b),
                                      tooltip: 'Delete',
                                      style: IconButton.styleFrom(foregroundColor: Colors.red, padding: EdgeInsets.zero, minimumSize: const Size(40, 40)),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _statusFilter == 'deleted' ? 'No deleted bookings in this week.' : 'No bookings match the current filters.',
                ),
              ),
                ],
              ),
            ),
                ],
              ),
          );
        },
      ),
    );
  }
}
