/// Submit Employee Review Screen
///
/// Weekly employee review form: select employee, week period, week days (Mon–Fri),
/// and 7 category scores (1–3). Supports Phase A (no timesheet data) and Phase B
/// (filter by project / project_number prefix, day ticks from time_periods).

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:intl/intl.dart';
import '../config/supabase_config.dart';
import '../modules/users/user_service.dart';
import '../modules/errors/error_log_service.dart';

const int _maxCommentLength = 1000;
const List<int> _scoreValues = [1, 2, 3];

/// Header/app blue and yellow bar thickness (px)
const Color _headerBlue = Color(0xFF0081FB);
const double _barHeight = 4.0;

/// Timesheet-style section border and header (match timesheet_screen)
const Color _sectionBorderColor = Color(0xFF005AB0);
const Color _sectionHeaderBg = Color(0xFFBADDFF);

/// Wide layout breakpoint (web / tablet): same as main_menu
bool _isWideScreen(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= 768;
}

/// Default category names (id 1–7) when review_categories table is empty or not loaded.
const List<String> _defaultCategoryNames = [
  'Health & Safety',
  'Organisation Efficiency',
  'Workmanship',
  'Reliability & Dependability',
  'Maintenance of Plant',
  'Cooperation & Attitude',
  'Paperwork',
];

class SubmitEmployeeReviewScreen extends StatefulWidget {
  const SubmitEmployeeReviewScreen({super.key});

  @override
  State<SubmitEmployeeReviewScreen> createState() =>
      _SubmitEmployeeReviewScreenState();
}

class _SubmitEmployeeReviewScreenState extends State<SubmitEmployeeReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employeeSearchController = TextEditingController();
  final _commentControllers = List.generate(7, (_) => TextEditingController());

  String? _managerUserId;
  String? _managerDisplayName;
  int? _security;
  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];

  String? _selectedEmployeeUserId;
  final List<int?> _scores = List.filled(7, null);
  bool _submitting = false;
  String? _duplicateError;

  List<Map<String, dynamic>> _categories = [];

  // Week period (same as Approve Time Periods): Monday-based week
  DateTime _selectedWeekStart = DateTime.now();

  // Mon–Sun (index 0=Mon .. 6=Sun); when Use Timesheet Data + employee selected, locked from time_periods
  final List<bool> _selectedDayTicks = List.filled(7, false);

  bool _meetsExpectationsAll = false;

  // Phase A/B: unchecked = submit without time_periods; checked = filter employees by time_periods, lock day ticks from data
  bool _useTimesheetData = false;
  String? _selectedProjectId;
  final _projectFilterController = TextEditingController();
  final _prefixFilterController = TextEditingController();
  List<Map<String, dynamic>> _allProjects = [];
  List<Map<String, dynamic>> _employeesFromTimesheet = []; // when _useTimesheetData, subset of _employees
  bool _dayTicksLocked = false; // true when _useTimesheetData && employee selected (Phase B)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedWeekStart = now.subtract(Duration(days: now.weekday - 1));
    _loadInitialData();
  }

  @override
  void dispose() {
    _employeeSearchController.dispose();
    _projectFilterController.dispose();
    _prefixFilterController.dispose();
    for (final c in _commentControllers) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  DateTime _getWeekEnd(DateTime weekStart) {
    return weekStart.add(const Duration(days: 6));
  }

  bool _canNavigateNext() {
    return _selectedWeekStart.isBefore(_getWeekStart(DateTime.now()));
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
      _dayTicksLocked = false;
    });
    if (_useTimesheetData) _applyTimesheetEmployeeFilter();
  }

  void _nextWeek() {
    if (!_canNavigateNext()) return;
    final next = _selectedWeekStart.add(const Duration(days: 7));
    final currentStart = _getWeekStart(DateTime.now());
    setState(() {
      _selectedWeekStart = next.isAfter(currentStart) ? currentStart : next;
      _dayTicksLocked = false;
    });
    if (_useTimesheetData) _applyTimesheetEmployeeFilter();
  }

  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
      _dayTicksLocked = false;
    });
    if (_useTimesheetData) _applyTimesheetEmployeeFilter();
  }

  /// Parse prefix filter: comma-separated project number prefixes for employee filter (e.g. "A, B, C").
  List<String> _parseProjectNumberPrefixes() {
    final raw = _prefixFilterController.text.trim();
    if (raw.isEmpty) return [];
    return raw.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
  }

  /// Apply employee's time-period days to _selectedDayTicks and lock when Phase B.
  Future<void> _applyTimesheetDaysToTicks() async {
    if (!_useTimesheetData || _selectedEmployeeUserId == null) return;
    final startStr = DateFormat('yyyy-MM-dd').format(_selectedWeekStart);
    final endStr = DateFormat('yyyy-MM-dd').format(_getWeekEnd(_selectedWeekStart));
    try {
      var query = SupabaseService.client
          .from('time_periods')
          .select('work_date')
          .eq('user_id', _selectedEmployeeUserId!)
          .gte('work_date', startStr)
          .lte('work_date', endStr);
      if (_selectedProjectId != null && _selectedProjectId!.isNotEmpty) {
        query = query.eq('project_id', _selectedProjectId!);
      }
      final prefixes = _parseProjectNumberPrefixes();
      if (prefixes.isNotEmpty) {
        final projRes = await SupabaseService.client
            .from('projects')
            .select('id')
            .or(prefixes.map((p) => 'project_number.ilike.$p%').join(','));
        final projectIds = (projRes as List).map((r) => r['id']?.toString()).whereType<String>().toList();
        if (projectIds.isEmpty) {
          setState(() {
            for (var i = 0; i < 7; i++) _selectedDayTicks[i] = false;
            _dayTicksLocked = true;
          });
          return;
        }
        query = query.inFilter('project_id', projectIds);
      }
      final res = await query;
      final days = <int>{};
      for (final row in res as List) {
        final d = row['work_date']?.toString();
        if (d == null) continue;
        final dt = DateTime.tryParse(d);
        if (dt != null && dt.weekday >= 1 && dt.weekday <= 7) days.add(dt.weekday);
      }
      if (mounted) {
        setState(() {
          for (var i = 0; i < 7; i++) _selectedDayTicks[i] = days.contains(i + 1);
          _dayTicksLocked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _dayTicksLocked = false);
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _loadError = 'Not signed in.';
          _loading = false;
        });
        return;
      }
      _managerUserId = user.id;

      final setup = await UserService.getCurrentUserSetup();
      if (setup == null) {
        setState(() {
          _loadError = 'User profile not found.';
          _loading = false;
        });
        return;
      }
      _security = setup['security'] is int
          ? setup['security'] as int
          : int.tryParse(setup['security']?.toString() ?? '');
      _managerDisplayName =
          setup['display_name']?.toString() ?? user.email ?? 'Manager';

      if (_security == null || _security! < 1 || _security! > 3) {
        setState(() {
          _loadError = 'Access denied. Only managers (security 1–3) can submit reviews.';
          _loading = false;
        });
        return;
      }

      await Future.wait([
        _loadCategories(),
        _loadEmployees(),
        _loadProjects(),
      ]);

      setState(() {
        _loading = false;
        _filteredEmployees = List.from(_employees);
      });
    } catch (e, st) {
      await ErrorLogService.logError(
        location: 'SubmitEmployeeReviewScreen - Load',
        type: 'Database',
        description: e.toString(),
        stackTrace: st,
      );
      setState(() {
        _loadError = 'Unable to load data. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _loadCategories() async {
    final res = await SupabaseService.client
        .from('review_categories')
        .select('id, name')
        .order('id');
    _categories = List<Map<String, dynamic>>.from(res);
  }

  Future<void> _loadProjects() async {
    try {
      final res = await SupabaseService.client
          .from('projects')
          .select('id, project_name, project_number');
      _allProjects = List<Map<String, dynamic>>.from(res);
      _allProjects.sort((a, b) {
        final na = (a['project_name'] ?? a['project_number'])?.toString().toLowerCase() ?? '';
        final nb = (b['project_name'] ?? b['project_number'])?.toString().toLowerCase() ?? '';
        return na.compareTo(nb);
      });
    } catch (_) {
      _allProjects = [];
    }
  }

  /// Filter and sort projects for the dropdown: by _projectFilterController text (space-separated terms), alphabetical.
  List<Map<String, dynamic>> _getFilteredProjects() {
    final filterText = _projectFilterController.text.trim().toLowerCase();
    if (filterText.isEmpty) return List.from(_allProjects);
    final terms = filterText.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();
    final filtered = _allProjects.where((p) {
      final name = (p['project_name']?.toString() ?? '').toLowerCase();
      final number = (p['project_number']?.toString() ?? '').toLowerCase();
      return terms.every((term) => name.contains(term) || number.contains(term));
    }).toList();
    return filtered;
  }

  /// When Use Timesheet Data is on: get distinct user_ids from time_periods in selected week with project/prefix filters.
  Future<List<String>> _getEmployeeUserIdsFromTimesheet() async {
    final startStr = DateFormat('yyyy-MM-dd').format(_selectedWeekStart);
    final endStr = DateFormat('yyyy-MM-dd').format(_getWeekEnd(_selectedWeekStart));
    List<String> projectIds = [];
    if (_selectedProjectId != null && _selectedProjectId!.isNotEmpty) {
      projectIds.add(_selectedProjectId!);
    }
    final prefixes = _parseProjectNumberPrefixes();
    if (prefixes.isNotEmpty) {
      final orClause = prefixes.map((p) => 'project_number.ilike.$p%').join(',');
      final projRes = await SupabaseService.client
          .from('projects')
          .select('id')
          .or(orClause);
      final fromPrefix = (projRes as List).map((r) => r['id']?.toString()).whereType<String>().toList();
      projectIds = projectIds.isEmpty ? fromPrefix : projectIds.where((id) => fromPrefix.contains(id)).toList();
      if (projectIds.isEmpty) return [];
    }
    if (projectIds.isEmpty && !_useTimesheetData) return [];
    if (projectIds.isEmpty) {
      // No project/prefix filter: all time_periods in range (any project)
      final res = await SupabaseService.client
          .from('time_periods')
          .select('user_id')
          .gte('work_date', startStr)
          .lte('work_date', endStr);
      final ids = <String>{};
      for (final row in res as List) {
        final u = row['user_id']?.toString();
        if (u != null) ids.add(u);
      }
      return ids.toList();
    }
    final res = await SupabaseService.client
        .from('time_periods')
        .select('user_id')
        .gte('work_date', startStr)
        .lte('work_date', endStr)
        .inFilter('project_id', projectIds);
    final ids = <String>{};
    for (final row in res as List) {
      final u = row['user_id']?.toString();
      if (u != null) ids.add(u);
    }
    return ids.toList();
  }

  Future<void> _applyTimesheetEmployeeFilter() async {
    if (!_useTimesheetData) return;
    final userIds = await _getEmployeeUserIdsFromTimesheet();
    final idSet = userIds.toSet();
    if (mounted) {
      setState(() {
        _employeesFromTimesheet = _employees
            .where((e) => idSet.contains(e['user_id']?.toString()))
            .toList()
          ..sort((a, b) =>
              (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString()));
        _filteredEmployees = List.from(_employeesFromTimesheet);
        if (_selectedEmployeeUserId != null && !idSet.contains(_selectedEmployeeUserId)) {
          _selectedEmployeeUserId = null;
          _dayTicksLocked = false;
        } else if (_selectedEmployeeUserId != null) {
          _applyTimesheetDaysToTicks();
        }
      });
    }
  }

  /// Load employee list from users_setup (user_id = id, display_name = name). No reference to public.employees.
  Future<void> _loadEmployees() async {
    final res = await SupabaseService.client
        .from('users_setup')
        .select('user_id, display_name')
        .order('display_name');
    final dataList = List<Map<String, dynamic>>.from(res);
    _employees = dataList.map((e) {
      final uid = e['user_id']?.toString();
      final name = e['display_name']?.toString()?.trim() ?? uid ?? 'Unknown';
      return {'user_id': uid, 'display_name': name};
    }).where((e) => e['user_id'] != null).toList();
  }

  void _filterEmployees(String q) {
    final lower = q.trim().toLowerCase();
    final base = _useTimesheetData ? _employeesFromTimesheet : _employees;
    setState(() {
      if (lower.isEmpty) {
        _filteredEmployees = List.from(base)
          ..sort((a, b) =>
              (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString()));
      } else {
        _filteredEmployees = base
            .where((e) =>
                (e['display_name'] ?? '').toString().toLowerCase().contains(lower))
            .toList()
          ..sort((a, b) =>
              (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString()));
      }
    });
  }

  /// Returns true if a review already exists for this employee/manager/date.
  Future<bool> _checkDuplicateForDate(String dateStr) async {
    if (_managerUserId == null || _selectedEmployeeUserId == null) return false;
    final res = await SupabaseService.client
        .from('reviews')
        .select('id')
        .eq('employee_user_id', _selectedEmployeeUserId!)
        .eq('manager_user_id', _managerUserId!)
        .eq('review_date', dateStr)
        .maybeSingle();
    return res != null;
  }

  bool _isFormValid() {
    if (_selectedEmployeeUserId == null) return false;
    final atLeastOneDay = _selectedDayTicks.any((t) => t);
    if (!atLeastOneDay) return false;
    for (var i = 0; i < 7; i++) {
      if (_scores[i] == null) return false;
      final s = _scores[i]!;
      if (s == 1 || s == 3) {
        final c = _commentControllers[i].text.trim();
        if (c.isEmpty) return false;
      } else {
        if (_commentControllers[i].text.trim().isNotEmpty) return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || !_isFormValid()) return;
    if (_managerUserId == null || _selectedEmployeeUserId == null) return;

    final datesToSubmit = <String>[];
    for (var i = 0; i < 7; i++) {
      if (!_selectedDayTicks[i]) continue;
      final d = _selectedWeekStart.add(Duration(days: i));
      datesToSubmit.add(DateFormat('yyyy-MM-dd').format(d));
    }
    if (datesToSubmit.isEmpty) return;

    for (final dateStr in datesToSubmit) {
      final duplicate = await _checkDuplicateForDate(dateStr);
      if (duplicate) {
        setState(() {
          _duplicateError =
              'A review by you for this employee already exists for one or more of the selected dates.';
        });
        _showToast('You\'ve already submitted a review for this employee on $dateStr.',
            isError: true);
        return;
      }
    }

    setState(() {
      _submitting = true;
      _duplicateError = null;
    });

    try {
      int submitted = 0;
      for (final dateStr in datesToSubmit) {
        final insertRes = await SupabaseService.client
            .from('reviews')
            .insert({
              'employee_user_id': _selectedEmployeeUserId!,
              'manager_user_id': _managerUserId!,
              'review_date': dateStr,
            })
            .select('id')
            .single();

        final reviewId = insertRes['id']?.toString();
        if (reviewId == null) throw Exception('No review id returned');

        final scoreRows = <Map<String, dynamic>>[];
        for (var i = 0; i < 7; i++) {
          final catId = i < _categories.length
              ? (_categories[i]['id'] as int?) ?? (i + 1)
              : (i + 1);
          final score = _scores[i]!;
          final rawComment = _commentControllers[i].text.trim();
          final comment = (score == 1 || score == 3) ? rawComment : null;
          scoreRows.add({
            'review_id': reviewId,
            'category_id': catId,
            'score': score,
            if (comment != null && comment.isNotEmpty) 'comment': comment,
          });
        }
        await SupabaseService.client.from('review_scores').insert(scoreRows);
        submitted++;
      }

      _showToast(submitted == 1
          ? 'Review submitted successfully.'
          : '$submitted reviews submitted successfully.');
      _resetForm();
    } catch (e, st) {
      String message = 'Unable to submit review. Please try again.';
      final err = e.toString();
      if (err.contains('403') || err.contains('42501') || err.contains('insufficient_privilege') || err.contains('permission denied')) {
        message = 'Permission denied (403). Check that your account has manager access (security 1–3 in users_setup) and run the latest migration 20260207120000_employee_review_rls_security_type.sql.';
      } else if (err.contains('uq_employee_manager_date') ||
          (err.contains('unique') && err.contains('review'))) {
        message = 'You\'ve already submitted a review for this employee on one of the selected dates.';
      } else if (err.contains('chk_comment_required')) {
        message =
            'Comments are required for scores 1 and 3 and must be empty for score 2.';
      } else if (err.contains('foreign key') || err.contains('violates')) {
        message = 'Selected user is not a valid employee.';
      }
      await ErrorLogService.logError(
        location: 'SubmitEmployeeReviewScreen - Submit',
        type: 'Database',
        description: err,
        stackTrace: st,
      );
      _showToast(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _resetForm() {
    setState(() {
      _selectedEmployeeUserId = null;
      for (var i = 0; i < 7; i++) {
        _scores[i] = null;
        _commentControllers[i].clear();
      }
      _meetsExpectationsAll = false;
      for (var i = 0; i < 7; i++) _selectedDayTicks[i] = false;
      _dayTicksLocked = false;
      _duplicateError = null;
      _employeeSearchController.clear();
      _filteredEmployees = _useTimesheetData ? List.from(_employeesFromTimesheet) : List.from(_employees);
    });
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0081FB),
          title: const Text('Submit Employee Review',
              style: TextStyle(color: Colors.black)),
          foregroundColor: Colors.black,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: Container(
              height: 4,
              color: const Color(0xFFFEFE00),
            ),
          ),
          actions: const [ScreenInfoIcon(screenName: 'submit_employee_review_screen.dart')],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0081FB),
          title: const Text('Submit Employee Review',
              style: TextStyle(color: Colors.black)),
          foregroundColor: Colors.black,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: Container(
              height: 4,
              color: const Color(0xFFFEFE00),
            ),
          ),
          actions: const [ScreenInfoIcon(screenName: 'submit_employee_review_screen.dart')],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _headerBlue,
        centerTitle: true,
        title: const Text('Submit Employee Review',
            style: TextStyle(color: Colors.black)),
        foregroundColor: Colors.black,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Container(
            height: _barHeight,
            color: const Color(0xFFFEFE00),
          ),
        ),
        actions: const [ScreenInfoIcon(screenName: 'submit_employee_review_screen.dart')],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Review Period – timesheet-style section
              _buildSection(
                title: 'Review Period',
                child: Center(
                  child: UnconstrainedBox(
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
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
                          onPressed: _canNavigateNext() ? _nextWeek : null,
                          tooltip: 'Next Week',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Review details – timesheet-style section
              _buildSection(
                title: 'Review details',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade700),
                              children: [
                                const TextSpan(
                                  text: 'Reviewing as: ',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: _managerDisplayName ?? '—',
                                  style: const TextStyle(fontStyle: FontStyle.italic),
                                ),
                                TextSpan(
                                  text: '  •  Review date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            value: _useTimesheetData,
                            onChanged: (v) async {
                              final useTimesheet = v ?? false;
                              setState(() {
                                _useTimesheetData = useTimesheet;
                                _dayTicksLocked = false;
                                if (!useTimesheet) {
                                  _employeesFromTimesheet = [];
                                  _filteredEmployees = List.from(_employees);
                                  _selectedProjectId = null;
                                  _projectFilterController.clear();
                                  _prefixFilterController.clear();
                                }
                              });
                              if (useTimesheet) await _applyTimesheetEmployeeFilter();
                            },
                            title: const Text('Use Timesheet Data', style: TextStyle(fontSize: 14)),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isWideScreen(context))
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildEmployeeSelector()),
                          const SizedBox(width: 16),
                          Expanded(child: _buildWeekDayTickBoxes()),
                        ],
                      )
                    else ...[
                      _buildEmployeeSelector(),
                      const SizedBox(height: 16),
                      _buildWeekDayTickBoxes(),
                    ],
                    if (_useTimesheetData) ...[
                      const SizedBox(height: 16),
                      _buildProjectFilterSection(),
                    ],
                    if (_duplicateError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _duplicateError!,
                        style: TextStyle(
                            color: Colors.red.shade700, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Category scores – timesheet-style section with legend table
              _buildSection(
                title: 'Category scores',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IntrinsicWidth(
                          child: _buildRatingLegendTable(context),
                        ),
                        const SizedBox(width: 24),
                        IntrinsicWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  SizedBox(
                                    width: 140,
                                    child: FilledButton.icon(
                                    onPressed: _submitting || !_isFormValid()
                                        ? null
                                        : _submit,
                                    icon: _submitting
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.send),
                                    label: Text(_submitting ? 'Submitting...' : 'Submit Review'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF0081FB),
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 140,
                                  child: OutlinedButton(
                                    onPressed: _submitting ? null : _resetForm,
                                    child: const Text('Reset'),
                                  ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                value: _meetsExpectationsAll,
                                onChanged: (v) {
                                  setState(() {
                                    _meetsExpectationsAll = v ?? false;
                                    if (_meetsExpectationsAll) {
                                      for (var i = 0; i < 7; i++) {
                                        _scores[i] = 2;
                                        _commentControllers[i].clear();
                                      }
                                    }
                                  });
                                },
                                title: const Text('Meets Expectations for all Categories', style: TextStyle(fontSize: 14)),
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isWideScreen(context))
                      _buildCategoryScoresTable()
                    else
                      ...List.generate(7, (i) => _buildCategoryCard(i)),
                  ],
                ),
              ),
              if (_scores.every((s) => s != null))
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Text(
                    'All 7 categories completed. You can submit the review.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green.shade700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Timesheet-style section: bordered container, header bar, content.
  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _sectionBorderColor, width: 2),
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
                color: _sectionHeaderBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: _sectionBorderColor, width: 2),
                ),
              ),
              child: Center(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  /// Table at top of Category section explaining rating symbols (fit to content width).
  Widget _buildRatingLegendTable(BuildContext context) {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade400, width: 1),
      columnWidths: {
        0: const IntrinsicColumnWidth(),
        1: const IntrinsicColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                'Symbol',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                'Meaning',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.thumb_down, size: 28, color: Colors.red.shade700),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Needs Improvement (requires comment)'),
            ),
          ],
        ),
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.thumb_up, size: 28, color: Colors.green.shade700),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Meets Expectations'),
            ),
          ],
        ),
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.emoji_events, size: 28, color: Colors.amber.shade700),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Exceeds Expectations (requires comment)'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmployeeSelector() {
    final selectedName = _filteredEmployees
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (e) => e?['user_id'] == _selectedEmployeeUserId,
          orElse: () => null,
        )
        ?['display_name']?.toString() ?? '';

    final idx = _filteredEmployees.indexWhere(
        (e) => e['user_id']?.toString() == _selectedEmployeeUserId);
    final canPrev = idx > 0;
    final canNext = idx >= 0 && idx < _filteredEmployees.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Employee *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: canPrev
                  ? () {
                      setState(() {
                        _selectedEmployeeUserId =
                            _filteredEmployees[idx - 1]['user_id']?.toString();
                        _duplicateError = null;
                        if (_useTimesheetData) _applyTimesheetDaysToTicks();
                      });
                    }
                  : null,
              tooltip: 'Previous employee',
            ),
            Expanded(
              child: InkWell(
                onTap: () => _showEmployeePicker(),
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Select employee',
                    errorText: _selectedEmployeeUserId == null &&
                            (_formKey.currentState?.validate() ?? false)
                        ? 'Required'
                        : null,
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(
                    selectedName.isEmpty ? 'Select employee' : selectedName,
                    style: TextStyle(
                      color: selectedName.isEmpty ? Colors.grey : null,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: canNext
                  ? () {
                      setState(() {
                        _selectedEmployeeUserId =
                            _filteredEmployees[idx + 1]['user_id']?.toString();
                        _duplicateError = null;
                        if (_useTimesheetData) _applyTimesheetDaysToTicks();
                      });
                    }
                  : null,
              tooltip: 'Next employee',
            ),
          ],
        ),
      ],
    );
  }

  /// When Use Timesheet Data: Project Filter and Prefix Filter 50:50 on one line, then project dropdown.
  Widget _buildProjectFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _projectFilterController,
                decoration: InputDecoration(
                  labelText: 'Project Filter',
                  hintText: 'Filter by project name or number',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _projectFilterController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _projectFilterController.clear();
                            setState(() {
                              final filtered = _getFilteredProjects();
                              if (_selectedProjectId != null &&
                                  !filtered.any((p) => p['id']?.toString() == _selectedProjectId)) {
                                _selectedProjectId = null;
                                _applyTimesheetEmployeeFilter();
                              }
                            });
                          },
                          tooltip: 'Clear',
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {
                    final filtered = _getFilteredProjects();
                    if (_selectedProjectId != null &&
                        !filtered.any((p) => p['id']?.toString() == _selectedProjectId)) {
                      _selectedProjectId = null;
                      _applyTimesheetEmployeeFilter();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _prefixFilterController,
                decoration: InputDecoration(
                  labelText: 'Prefix Filter',
                  hintText: 'e.g. A, B, C (project number prefixes)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.filter_list, size: 20),
                  suffixIcon: _prefixFilterController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _prefixFilterController.clear();
                            _applyTimesheetEmployeeFilter();
                          },
                          tooltip: 'Clear',
                        )
                      : null,
                ),
                onChanged: (_) {
                  _applyTimesheetEmployeeFilter();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final filtered = _getFilteredProjects();
            final validValue = _selectedProjectId != null &&
                    filtered.any((p) => p['id']?.toString() == _selectedProjectId)
                ? _selectedProjectId
                : null;
            return DropdownButtonFormField<String>(
              value: validValue,
              decoration: const InputDecoration(
                labelText: 'By Project',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All projects')),
                ...filtered.map((p) {
                  final id = p['id']?.toString();
                  final name = p['project_name']?.toString() ?? p['project_number']?.toString() ?? id ?? '';
                  return DropdownMenuItem(value: id, child: Text(name));
                }),
              ],
              onChanged: (v) {
                setState(() => _selectedProjectId = v);
                _applyTimesheetEmployeeFilter();
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildWeekDayTickBoxes() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Week days to submit review for *',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ...List.generate(7, (i) {
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: FilterChip(
                  selected: _selectedDayTicks[i],
                  label: Text(days[i]),
                  onSelected: _dayTicksLocked
                      ? null
                      : (selected) {
                          setState(() {
                            _selectedDayTicks[i] = selected;
                            _duplicateError = null;
                          });
                        },
                ),
              );
            }),
            if (!_dayTicksLocked && !_useTimesheetData) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    for (var i = 0; i < 5; i++) _selectedDayTicks[i] = true;
                    _duplicateError = null;
                  });
                },
                child: const Text('All Week'),
              ),
            ],
          ],
        ),
        if (_dayTicksLocked)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              'Days are set from timesheet data and cannot be changed.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  void _showEmployeePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (ctx, scrollController) {
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _employeeSearchController,
                          decoration: const InputDecoration(
                            labelText: 'Search',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) {
                            _filterEmployees(v);
                            setModalState(() {});
                          },
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: _filteredEmployees.length,
                          itemBuilder: (ctx, i) {
                            final e = _filteredEmployees[i];
                            final uid = e['user_id']?.toString();
                            final name =
                                e['display_name']?.toString() ?? 'Unknown';
                            return ListTile(
                              title: Text(name),
                              onTap: () {
                                setState(() {
                                  _selectedEmployeeUserId = uid;
                                  _duplicateError = null;
                                });
                                Navigator.pop(ctx);
                                if (_useTimesheetData) _applyTimesheetDaysToTicks();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static Widget _scoreIcon(int score, {required bool selected}) {
    final double size = 28;
    switch (score) {
      case 1:
        return Icon(Icons.thumb_down, size: size, color: Colors.red.shade700);
      case 2:
        return Icon(Icons.thumb_up, size: size, color: Colors.green.shade700);
      case 3:
        return Icon(Icons.emoji_events, size: size, color: Colors.amber.shade700);
      default:
        return Icon(Icons.help_outline, size: size);
    }
  }

  /// Comment field for one category (shared by card and table layouts).
  Widget _buildCategoryCommentField(int index) {
    final isWide = _isWideScreen(context);
    final needsComment = _scores[index] == 1 || _scores[index] == 3;
    return TextFormField(
      controller: _commentControllers[index],
      enabled: needsComment,
      decoration: const InputDecoration(
        labelText: 'A comment is required to explain the reason for this rating',
        border: OutlineInputBorder(),
        counterText: '',
      ),
      maxLength: _maxCommentLength,
      maxLines: isWide ? 1 : 2,
      onChanged: (_) => setState(() {}),
      validator: (v) {
        if (_scores[index] == 1 || _scores[index] == 3) {
          if (v == null || v.trim().isEmpty) return null;
        }
        return null;
      },
    );
  }

  /// Wide layout: one table so description/symbols columns use fixed width (longest description, min symbols), comment gets remainder; rows align vertically.
  Widget _buildCategoryScoresTable() {
    final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold) ?? const TextStyle(fontWeight: FontWeight.bold);
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: FlexColumnWidth(1),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: List.generate(7, (i) {
        final name = i < _categories.length
            ? (_categories[i]['name']?.toString() ?? _defaultCategoryNames[i])
            : _defaultCategoryNames[i];
        return TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(name, style: textStyle),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
              child: _buildRatingSymbolsRow(i),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12),
              child: _buildCategoryCommentField(i),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildCategoryCard(int index) {
    final name = index < _categories.length
        ? (_categories[index]['name']?.toString() ?? _defaultCategoryNames[index])
        : _defaultCategoryNames[index];
    final commentField = _buildCategoryCommentField(index);

    // Mobile only: 50/50 row, then full-width comment.
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(child: _buildRatingSymbolsRow(index)),
              ],
            ),
            const SizedBox(height: 8),
            commentField,
          ],
        ),
      ),
    );
  }

  /// Rating radios + icons row (no description) for use in category card layout.
  Widget _buildRatingSymbolsRow(int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _scoreValues.map((s) {
        final isSelected = _scores[index] == s;
        return Padding(
          padding: const EdgeInsets.only(right: 4.0),
          child: InkWell(
            onTap: () {
              setState(() {
                _scores[index] = s;
                if (s == 2) _commentControllers[index].clear();
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<int>(
                  value: s,
                  groupValue: _scores[index],
                  onChanged: (v) {
                    setState(() {
                      _scores[index] = v;
                      if (v == 2) _commentControllers[index].clear();
                    });
                  },
                ),
                _scoreIcon(s, selected: isSelected),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

