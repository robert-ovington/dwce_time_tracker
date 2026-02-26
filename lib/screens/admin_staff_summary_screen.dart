import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/errors/error_log_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';
import 'package:dwce_time_tracker/utils/export_file.dart';
import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:intl/intl.dart';

/// Admin Staff Summary Screen
///
/// Summary-only view of office attendance for a week.
/// Columns: Day, Employee, Mon..Sun, Total
/// Filters: Day + Employee (same overlay style as AdminStaffAttendanceScreen)
/// Export: CSV (Excel can open the CSV)
class AdminStaffSummaryScreen extends StatefulWidget {
  const AdminStaffSummaryScreen({super.key});

  @override
  State<AdminStaffSummaryScreen> createState() => _AdminStaffSummaryScreenState();
}

class _AdminStaffSummaryScreenState extends State<AdminStaffSummaryScreen> {
  bool _isLoading = true;
  bool _isAdmin = false;

  // Week navigation
  DateTime _selectedWeekStart = DateTime.now();
  // Week start from system_settings: 0-6 (PostgreSQL DOW: 0=Sunday .. 6=Saturday)
  int _weekStartDow = 1;

  // Filters
  Set<String> _selectedUserIds = {};
  Set<String> _selectedDays = {}; // Mon..Sun (affects which day-columns contribute to totals)

  // Header filter UI
  String? _openFilterDropdown; // 'day' | 'employee'
  final GlobalKey _headerKey = GlobalKey();
  OverlayEntry? _filterOverlayEntry;

  // Users (for display + export)
  List<Map<String, dynamic>> _allUsers = [];

  // Summary rows (already filtered)
  List<_SummaryRow> _rows = [];

  // Column widths (match attendance screen sizing)
  double _employeeColumnWidth = 180.0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _hideFilterDropdown();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      await _loadWeekStart();
      _selectedWeekStart = _getWeekStart(DateTime.now());

      final userSetup = await UserService.getCurrentUserSetup();
      final security = userSetup?['security'];
      final securityLevel = security is int ? security : int.tryParse(security?.toString() ?? '');
      _isAdmin = securityLevel == 1;

      if (!_isAdmin) {
        setState(() => _isLoading = false);
        return;
      }

      await Future.wait([
        _loadUsers(),
        _loadSummary(),
      ]);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Admin Staff Summary Screen - Initialize',
        type: 'Database',
        description: 'Failed to initialize: $e',
        stackTrace: stackTrace,
      );
      setState(() => _isLoading = false);
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
        if (v != null && v >= 0 && v <= 6) _weekStartDow = v;
      }
    } catch (_) {}
  }

  int _weekStartDartWeekday() => _weekStartDow == 0 ? 7 : _weekStartDow;

  DateTime _getWeekStart(DateTime date) {
    final w = _weekStartDartWeekday();
    final daysToSubtract = (date.weekday - w + 7) % 7;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysToSubtract));
  }

  DateTime _getWeekEnd(DateTime weekStart) => weekStart.add(const Duration(days: 6));

  bool _canNavigateNext() {
    final currentWeekStart = _getWeekStart(DateTime.now());
    return _selectedWeekStart.isBefore(currentWeekStart);
  }

  void _previousWeek() {
    setState(() => _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7)));
    _loadSummary();
  }

  void _nextWeek() {
    if (!_canNavigateNext()) return;
    setState(() => _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7)));
    _loadSummary();
  }

  void _goToCurrentWeek() {
    setState(() => _selectedWeekStart = _getWeekStart(DateTime.now()));
    _loadSummary();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await DatabaseService.read('users_data');
      _allUsers = users;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Admin Staff Summary Screen - Load Users',
        type: 'Database',
        description: 'Error loading users: $e',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    try {
      final weekEnd = _getWeekEnd(_selectedWeekStart);

      // time_office: start_time range + user_id filter use idx_time_office_* (see supabase_indexes.md)
      dynamic query = SupabaseService.client
          .from('time_office')
          .select('id, user_id, start_time, finish_time, users_data!user_id(display_name)')
          .gte('start_time', '${DateFormat('yyyy-MM-dd').format(_selectedWeekStart)}T00:00:00Z')
          .lte('start_time', '${DateFormat('yyyy-MM-dd').format(weekEnd)}T23:59:59Z')
          .eq('is_active', true);

      if (_selectedUserIds.isNotEmpty) {
        query = query.inFilter('user_id', _selectedUserIds.toList());
      }

      query = query.order('start_time', ascending: true);
      final response = await query;

      // Flatten + compute per-record break minutes (batched per record)
      final records = <Map<String, dynamic>>[];
      for (final raw in (response as List)) {
        final r = Map<String, dynamic>.from(raw as Map);
        final userData = r['users_data'];
        r['user_name'] = userData is Map ? userData['display_name'] : null;
        r.remove('users_data');
        records.add(r);
      }

      final breakMinutesByOfficeId = <String, int>{};
      for (final r in records) {
        final id = r['id']?.toString();
        if (id == null || id.isEmpty) continue;
        breakMinutesByOfficeId[id] = await _loadBreakMinutes(id);
      }

      // Build summary: per-employee minutes per weekday (Mon..Sun)
      final byUser = <String, _SummaryRow>{};
      for (final r in records) {
        final userId = r['user_id']?.toString() ?? '';
        if (userId.isEmpty) continue;

        final startStr = r['start_time']?.toString();
        final finishStr = r['finish_time']?.toString();
        if (startStr == null || finishStr == null) continue;

        DateTime start;
        DateTime finish;
        try {
          start = DateTime.parse(startStr);
          finish = DateTime.parse(finishStr);
        } catch (_) {
          continue;
        }

        final mins = finish.difference(start).inMinutes - (breakMinutesByOfficeId[r['id']?.toString() ?? ''] ?? 0);
        if (mins <= 0) continue;

        final dayKey = DateFormat('EEE').format(start); // Mon..Sun
        if (!const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].contains(dayKey)) continue;

        // If day filter is active, only count selected days
        if (_selectedDays.isNotEmpty && !_selectedDays.contains(dayKey)) continue;

        byUser.putIfAbsent(
          userId,
          () {
            final dayLabel = _selectedDays.isEmpty 
                ? 'All' 
                : (List<String>.from(_selectedDays)..sort((a, b) => a.compareTo(b))).join(',');
            return _SummaryRow(
              dayLabel: dayLabel,
              userId: userId,
              userName: (r['user_name']?.toString() ?? 'Unknown'),
            );
          },
        );
        byUser[userId]!.addMinutes(dayKey, mins);
      }

      // Sort by employee name
      final rows = byUser.values.toList()
        ..sort((a, b) => a.userName.toLowerCase().compareTo(b.userName.toLowerCase()));

      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Admin Staff Summary Screen - Load Summary',
        type: 'Database',
        description: 'Failed to load summary: $e',
        stackTrace: stackTrace,
      );
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading summary: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<int> _loadBreakMinutes(String timeOfficeId) async {
    try {
      final breaksResponse = await SupabaseService.client
          .from('time_office_breaks')
          .select('break_start, break_finish')
          .eq('time_office_id', timeOfficeId)
          .eq('is_active', true)
          .order('break_start', ascending: true);

      var total = 0;
      for (final b in (breaksResponse as List)) {
        final start = (b as Map)['break_start']?.toString();
        final finish = (b as Map)['break_finish']?.toString();
        if (start == null || finish == null) continue;
        try {
          total += DateTime.parse(finish).difference(DateTime.parse(start)).inMinutes;
        } catch (_) {}
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  String _fmtMinutes(int minutes) {
    if (minutes <= 0) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  // ---------- Filter header UI (copied pattern) ----------
  void _hideFilterDropdown() {
    _filterOverlayEntry?.remove();
    _filterOverlayEntry = null;
  }

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
                          _hideFilterDropdown();
                          _openFilterDropdown = filterKey;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _showFilterDropdown(filterKey, builderContext);
                          });
                        }
                      });
                    },
                    child: Icon(
                      Icons.filter_list,
                      size: 18,
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
                    child: Container(width: 4, color: Colors.transparent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFilterDropdown(String filterKey, BuildContext context) {
    _hideFilterDropdown();

    final RenderBox? headerBox = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (headerBox == null) return;
    final headerPosition = headerBox.localToGlobal(Offset.zero);
    final headerSize = headerBox.size;

    double left = headerPosition.dx + 8.0;
    double width = 200.0;

    if (filterKey == 'day') {
      left = headerPosition.dx + 8.0;
      width = 220.0;
    } else if (filterKey == 'employee') {
      left = headerPosition.dx + 8.0;
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

  Widget _buildFilterDropdown(String filterKey, double width) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey, width: 2),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2),
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

  Widget _buildDayFilter() {
    const allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Filter by Day', style: TextStyle(fontWeight: FontWeight.bold)),
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
          Column(
            mainAxisSize: MainAxisSize.min,
            children: allDays.map((day) {
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
                  _loadSummary();
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
                  _loadSummary();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeFilter() {
    // Only list employees who have summary data for the selected week
    final employees = _rows
        .map((r) => {
              'user_id': r.userId,
              'display_name': r.userName,
            })
        .toList()
      ..sort((a, b) => (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString()));

    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filter by Employee (${employees.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
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
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: employees.length,
              itemBuilder: (context, index) {
                final user = employees[index];
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
                    _loadSummary();
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
                  _loadSummary();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- Export ----------
  String _toCsv(List<_SummaryRow> rows) {
    const headers = ['Employee', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Total'];
    final lines = <String>[];
    lines.add(headers.join(','));
    for (final r in rows) {
      final cells = <String>[
        _csvEscape(r.userName),
        _csvEscape(_fmtMinutes(r.mon)),
        _csvEscape(_fmtMinutes(r.tue)),
        _csvEscape(_fmtMinutes(r.wed)),
        _csvEscape(_fmtMinutes(r.thu)),
        _csvEscape(_fmtMinutes(r.fri)),
        _csvEscape(_fmtMinutes(r.sat)),
        _csvEscape(_fmtMinutes(r.sun)),
        _csvEscape(_fmtMinutes(r.total)),
      ];
      lines.add(cells.join(','));
    }
    return lines.join('\n');
  }

  String _csvEscape(String v) {
    final needs = v.contains(',') || v.contains('"') || v.contains('\n');
    final escaped = v.replaceAll('"', '""');
    return needs ? '"$escaped"' : escaped;
  }

  Future<void> _exportCsv() async {
    try {
      final csv = _toCsv(_rows);
      final filename = 'admin_staff_summary_${DateFormat('yyyyMMdd').format(_selectedWeekStart)}.csv';
      final result = await saveTextFile(filename: filename, contents: csv, mimeType: 'text/csv');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result == null ? 'Export not supported on this platform' : 'Exported: $result'),
          backgroundColor: result == null ? Colors.orange : Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildHeaderRow() {
    return Container(
      key: _headerKey,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      color: Colors.grey[200],
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
                _buildFilterableHeader(
                  width: _employeeColumnWidth,
                  label: 'Employee',
                  filterKey: 'employee',
                  hasActiveFilter: _selectedUserIds.isNotEmpty,
                  isResizable: true,
                  onResize: (delta) => setState(() {
                    _employeeColumnWidth = (_employeeColumnWidth + delta).clamp(120.0, 450.0);
                  }),
                ),
                const _HeaderCell(width: 100, label: 'Mon'),
                const _HeaderCell(width: 100, label: 'Tue'),
                const _HeaderCell(width: 100, label: 'Wed'),
                const _HeaderCell(width: 100, label: 'Thu'),
                const _HeaderCell(width: 100, label: 'Fri'),
                const _HeaderCell(width: 100, label: 'Sat'),
                const _HeaderCell(width: 100, label: 'Sun'),
                const _HeaderCell(width: 100, label: 'Total'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(_SummaryRow r) {
    Widget cell(double width, String value, {bool bold = false}) {
      return SizedBox(
        width: width,
        child: Center(
          child: Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: _employeeColumnWidth,
                  child: Center(
                    child: Text(
                      r.userName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                cell(100, _fmtMinutes(r.mon)),
                cell(100, _fmtMinutes(r.tue)),
                cell(100, _fmtMinutes(r.wed)),
                cell(100, _fmtMinutes(r.thu)),
                cell(100, _fmtMinutes(r.fri)),
                cell(100, _fmtMinutes(r.sat)),
                cell(100, _fmtMinutes(r.sun)),
                cell(100, _fmtMinutes(r.total), bold: true),
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
          title: const Text('Admin Staff Summary', style: TextStyle(color: Colors.black)),
          centerTitle: true,
          backgroundColor: const Color(0xFF0081FB),
          foregroundColor: Colors.black,
          actions: const [ScreenInfoIcon(screenName: 'admin_staff_summary_screen.dart')],
        ),
        body: const Center(child: Text('You need Admin privileges (Security Level 1)')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Staff Summary', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [
          const ScreenInfoIcon(screenName: 'admin_staff_summary_screen.dart'),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _loadSummary),
          IconButton(icon: const Icon(Icons.file_download), tooltip: 'Export (CSV)', onPressed: _exportCsv),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          if (_openFilterDropdown != null) {
            _hideFilterDropdown();
            setState(() => _openFilterDropdown = null);
          }
        },
        child: Column(
          children: [
            // Week Navigation (same layout as attendance screen)
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: _previousWeek, tooltip: 'Previous Week'),
                  Column(
                    children: [
                      Text(
                        '${DateFormat('MMM dd').format(_selectedWeekStart)} - ${DateFormat('MMM dd, yyyy').format(_getWeekEnd(_selectedWeekStart))}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (!_selectedWeekStart.isAtSameMomentAs(_getWeekStart(DateTime.now())))
                        TextButton(onPressed: _goToCurrentWeek, child: const Text('Go to Current Week')),
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

            _buildHeaderRow(),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? const Center(child: Text('No summary data for this week'))
                      : ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (context, index) => _buildRow(_rows[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.width, required this.label});
  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow {
  _SummaryRow({
    required this.dayLabel,
    required this.userId,
    required this.userName,
  });

  final String dayLabel;
  final String userId;
  final String userName;

  int mon = 0;
  int tue = 0;
  int wed = 0;
  int thu = 0;
  int fri = 0;
  int sat = 0;
  int sun = 0;

  int get total => mon + tue + wed + thu + fri + sat + sun;

  void addMinutes(String dayKey, int minutes) {
    switch (dayKey) {
      case 'Mon':
        mon += minutes;
        break;
      case 'Tue':
        tue += minutes;
        break;
      case 'Wed':
        wed += minutes;
        break;
      case 'Thu':
        thu += minutes;
        break;
      case 'Fri':
        fri += minutes;
        break;
      case 'Sat':
        sat += minutes;
        break;
      case 'Sun':
        sun += minutes;
        break;
    }
  }
}

