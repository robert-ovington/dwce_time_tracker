/// Concrete Mix Bookings Screen
///
/// Book concrete deliveries per project. Style aligned with timesheet_screen and time_clocking_screen.
/// Saves to public.concrete_mix_bookings; uses users_setup for display name and site contact.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/supabase_config.dart';
import '../modules/auth/auth_service.dart';
import '../modules/users/user_service.dart';
import '../modules/errors/error_log_service.dart';
import '../widgets/screen_info_icon.dart';
import '../utils/google_maps_loader.dart';

class ConcreteMixBookingsScreen extends StatefulWidget {
  /// When set, load this booking for editing (e.g. from Calendar screen).
  final String? editBookingId;

  const ConcreteMixBookingsScreen({super.key, this.editBookingId});

  @override
  State<ConcreteMixBookingsScreen> createState() => _ConcreteMixBookingsScreenState();
}

class _ConcreteMixBookingsScreenState extends State<ConcreteMixBookingsScreen> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  String _displayName = '';
  String? _bookingUserId; // auth.uid() -> saved to concrete_mix_bookings.booking_user_id

  List<Map<String, dynamic>> _allProjects = [];
  Map<String, Map<String, dynamic>> _projectMapByName = {};
  String _projectFilter = '';
  int _projectFilterResetCounter = 0;
  String? _selectedProjectId;
  String _selectedProjectName = '';

  List<Map<String, dynamic>> _siteContacts = []; // users_setup: user_id, display_name
  String? _selectedSiteContactUserId;
  String _siteContactFilter = '';
  int _siteContactFilterResetCounter = 0;

  double? _customLat;
  double? _customLng;
  bool _delivered = true; // default Delivered -> delivered = true
  /// Default 7:30am on next weekday: tomorrow if Mon–Fri, else next Monday.
  DateTime get _defaultDueDateTime {
    final now = DateTime.now();
    final today730 = DateTime(now.year, now.month, now.day, 7, 30);
    DateTime date = today730.isBefore(now) ? today730.add(const Duration(days: 1)) : today730;
    // Skip weekend: if Saturday (6) add 2 days, if Sunday (7) add 1 day to get Monday.
    final w = date.weekday;
    if (w == DateTime.saturday) date = date.add(const Duration(days: 2));
    if (w == DateTime.sunday) date = date.add(const Duration(days: 1));
    return date;
  }
  late DateTime _dueDateTime;
  int _durationOnSite = 60; // default 60 minutes, adjusted in 15-min steps

  /// Bookings on the selected date (for availability summary). Loaded when _dueDateTime changes.
  List<Map<String, dynamic>> _bookingsOnSelectedDate = [];

  /// Warnings from the last "Check" run; shown in summary dialog when uploading.
  List<String> _checkWarnings = [];

  String _findNearestButtonText = 'Find Nearest';
  bool _isFindingNearest = false;
  bool _isFindingLast = false;
  List<String> _foundNearestProjectIds = [];

  /// Default travel time (minutes) between two different project locations when coords unknown.
  static const int _defaultTravelMinutes = 30;
  /// Average speed (km/h) for travel time estimate between sites.
  static const double _travelSpeedKmh = 50.0;
  /// Quarry reload time (minutes) to consider between runs.
  static const int _quarryReloadMinutes = 45;
  /// Truck capacity (m³) – more deliveries per day may require reload at quarry.
  static const double _truckCapacityM3 = 6.0;

  void _setDueDate(DateTime date) {
    setState(() {
      _dueDateTime = DateTime(date.year, date.month, date.day, _dueDateTime.hour, _dueDateTime.minute);
      _checkWarnings = [];
    });
    _loadBookingsOnDate(_dueDateTime);
  }

  void _adjustDueHour(int delta) {
    var h = _dueDateTime.hour + delta;
    if (h < 0) h = 0;
    if (h > 23) h = 23;
    setState(() {
      _dueDateTime = DateTime(_dueDateTime.year, _dueDateTime.month, _dueDateTime.day, h, _dueDateTime.minute);
      _checkWarnings = [];
    });
  }

  void _adjustDueMinute(int delta) {
    final m = _dueDateTime.minute;
    final snapped = (m ~/ 15) * 15;
    var newM = snapped + delta;
    var h = _dueDateTime.hour;
    if (newM >= 60) {
      newM = 0;
      h = h + 1;
      if (h > 23) h = 23;
    } else if (newM < 0) {
      newM = 45;
      h = h - 1;
      if (h < 0) h = 0;
    }
    setState(() {
      _dueDateTime = DateTime(_dueDateTime.year, _dueDateTime.month, _dueDateTime.day, h, newM);
      _checkWarnings = [];
    });
  }

  DateTime get _dueDateOnly => DateTime(_dueDateTime.year, _dueDateTime.month, _dueDateTime.day);
  DateTime get _todayOnly => DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  /// Format duration minutes as h:mm (e.g. 60 -> "1:00", 90 -> "1:30").
  String _durationHmm(int minutes) =>
      '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

  void _adjustDuration(int deltaMinutes) {
    setState(() {
      _durationOnSite = _durationOnSite + deltaMinutes;
      if (_durationOnSite < 0) _durationOnSite = 0;
      _checkWarnings = [];
    });
  }

  /// Set duration on site from quantity: 15 min per 2 quantity (0–2 → 15, 2–4 → 30, etc.).
  void _updateDurationFromQuantity() {
    final qty = double.tryParse(_quantityController.text.trim());
    if (qty == null || qty.isNaN || qty < 0) return;
    final blocks = (qty / 2).ceil();
    final suggested = (blocks < 1 ? 1 : blocks) * 15;
    if (_durationOnSite != suggested) {
      setState(() {
        _durationOnSite = suggested;
        _checkWarnings = [];
      });
    }
  }

  static const double _timeWheelItemExtent = 48.0;
  static const int _timeWheelViewportItemCount = 4;
  static const List<int> _minuteOptions = [0, 15, 30, 45];

  Future<void> _showDueTimeScrollPicker() async {
    final hourIndex = _dueDateTime.hour.clamp(0, 23);
    final minuteIndex = _minuteOptions.indexOf((_dueDateTime.minute ~/ 15) * 15);
    final minIdx = minuteIndex >= 0 ? minuteIndex : 0;

    int selectedHour = hourIndex;
    int selectedMin = minIdx;

    // FixedExtentScrollController is required when using FixedExtentScrollPhysics.
    final hourController = FixedExtentScrollController(initialItem: hourIndex);
    final minuteController = FixedExtentScrollController(initialItem: minIdx);
    final viewportHeight = _timeWheelItemExtent * _timeWheelViewportItemCount;

    if (!mounted) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxDialogHeight = screenHeight * 0.6;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxDialogHeight),
              child: Material(
                borderRadius: BorderRadius.circular(12),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Select time (24h)', style: Theme.of(ctx2).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: viewportHeight,
                            width: 72,
                            child: ListWheelScrollView.useDelegate(
                              controller: hourController,
                              itemExtent: _timeWheelItemExtent,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (i) => setModalState(() => selectedHour = i.clamp(0, 23)),
                              childDelegate: ListWheelChildListDelegate(
                                children: List.generate(24, (i) => Center(child: Text(i.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)))),
                              ),
                            ),
                          ),
                          const Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: viewportHeight,
                            width: 72,
                            child: ListWheelScrollView.useDelegate(
                              controller: minuteController,
                              itemExtent: _timeWheelItemExtent,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (i) => setModalState(() => selectedMin = i.clamp(0, _minuteOptions.length - 1)),
                              childDelegate: ListWheelChildListDelegate(
                                children: _minuteOptions.map((m) => Center(child: Text(m.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)))).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              final h = selectedHour.clamp(0, 23);
                              final m = _minuteOptions[selectedMin.clamp(0, _minuteOptions.length - 1)];
                              setState(() {
                                _dueDateTime = DateTime(_dueDateTime.year, _dueDateTime.month, _dueDateTime.day, h, m);
                                _checkWarnings = [];
                              });
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      hourController.dispose();
      minuteController.dispose();
    });
  }

  Widget _buildTimeSpinnerPart({
    required String value,
    required VoidCallback onTap,
    required VoidCallback onUp,
    required VoidCallback onDown,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_drop_up, size: 32),
          onPressed: onUp,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
          tooltip: 'Increase',
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_drop_down, size: 32),
          onPressed: onDown,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
          tooltip: 'Decrease',
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _concreteMixTypes = []; // concrete_mix: id, name
  String? _selectedConcreteMixTypeId;
  String _concreteMixFilter = '';
  final TextEditingController _quantityController = TextEditingController();
  bool _wet = true;
  final TextEditingController _commentsController = TextEditingController();

  List<Map<String, dynamic>> _bookings = [];
  Map<String, dynamic>? _editingBooking; // when open for edit
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _dueDateTime = _defaultDueDateTime;
    _setupConnectivityListener();
    _load();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _quantityController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (mounted) {
        final online = results.any((r) => r != ConnectivityResult.none);
        setState(() => _isOnline = online);
      }
    });
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final uid = AuthService.getCurrentUser()?.id;
      if (uid != null) {
        _bookingUserId = uid;
        final setup = await SupabaseService.client
            .from('users_setup')
            .select('display_name')
            .eq('user_id', uid)
            .maybeSingle();
        if (setup != null && mounted) {
          setState(() => _displayName = setup['display_name']?.toString() ?? '');
        }
      }
      await _loadProjects();
      await _loadSiteContacts();
      await _loadConcreteMixTypes();
      await _loadBookings();
      await _loadBookingsOnDate(_dueDateTime);
      if (widget.editBookingId != null && mounted) {
        final b = await SupabaseService.client
            .from('concrete_mix_bookings')
            .select()
            .eq('id', widget.editBookingId!)
            .maybeSingle();
        if (b != null && mounted) _openBookingForEdit(Map<String, dynamic>.from(b as Map));
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading: $e'), backgroundColor: Colors.red));
        ErrorLogService.logError(location: 'ConcreteMixBookingsScreen._load', type: 'Load', description: '$e', stackTrace: st);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProjects() async {
    final list = await SupabaseService.client
        .from('projects')
        .select('id, project_name, project_number, county, town, latitude, longitude')
        .order('project_name');
    setState(() {
      _allProjects = List<Map<String, dynamic>>.from(list as List);
      _projectMapByName = {};
      for (final p in _allProjects) {
        final name = p['project_name']?.toString() ?? '';
        if (name.isNotEmpty) _projectMapByName[name] = p;
      }
    });
  }

  Future<void> _loadSiteContacts() async {
    final list = await SupabaseService.client
        .from('users_setup')
        .select('user_id, display_name')
        .order('display_name');
    final contacts = List<Map<String, dynamic>>.from(list as List);
    contacts.sort((a, b) => (a['display_name']?.toString() ?? '').toLowerCase().compareTo((b['display_name']?.toString() ?? '').toLowerCase()));
    setState(() => _siteContacts = contacts);
  }

  /// Initials: First name first then surname (e.g. "Doe, John" or "Doe John" -> "JD").
  static String _initialsFrom(String name) {
    final letters = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .toList();
    return letters.reversed.join();
  }

  Future<void> _loadConcreteMixTypes() async {
    final list = await SupabaseService.client
        .from('concrete_mix')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    setState(() => _concreteMixTypes = List<Map<String, dynamic>>.from(list as List));
  }

  Future<void> _loadBookings() async {
    if (_bookingUserId == null) return;
    final list = await SupabaseService.client
        .from('concrete_mix_bookings')
        .select('*')
        .eq('booking_user_id', _bookingUserId!)
        .eq('is_active', true)
        .order('due_date_time', ascending: false);
    setState(() => _bookings = List<Map<String, dynamic>>.from(list as List));
  }

  /// Load all active bookings on the given date (for availability summary). Uses UTC day bounds.
  Future<void> _loadBookingsOnDate(DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59);
    try {
      // Filters: is_active and due_date_time only. inserted_at is for display only (Booked column); never used in filters.
      final list = await SupabaseService.client
          .from('concrete_mix_bookings')
          .select('*')
          .eq('is_active', true)
          .gte('due_date_time', dayStart.toUtc().toIso8601String())
          .lte('due_date_time', dayEnd.toUtc().toIso8601String())
          .order('due_date_time');
      if (mounted) setState(() => _bookingsOnSelectedDate = List<Map<String, dynamic>>.from(list as List));
    } catch (_) {
      if (mounted) setState(() => _bookingsOnSelectedDate = []);
    }
  }

  /// Travel minutes between two projects (from project IDs). Returns 0 if same or missing.
  int _travelMinutesBetween(String? projectIdA, String? projectIdB) {
    if (projectIdA == null || projectIdB == null || projectIdA == projectIdB) return 0;
    final projA = _allProjects.cast<Map<String, dynamic>?>().firstWhere(
      (p) => p!['id']?.toString() == projectIdA,
      orElse: () => null,
    );
    final projB = _allProjects.cast<Map<String, dynamic>?>().firstWhere(
      (p) => p!['id']?.toString() == projectIdB,
      orElse: () => null,
    );
    if (projA == null || projB == null) return _defaultTravelMinutes;
    final latA = (projA['latitude'] as num?)?.toDouble();
    final lngA = (projA['longitude'] as num?)?.toDouble();
    final latB = (projB['latitude'] as num?)?.toDouble();
    final lngB = (projB['longitude'] as num?)?.toDouble();
    if (latA == null || lngA == null || latB == null || lngB == null) return _defaultTravelMinutes;
    final distanceM = Geolocator.distanceBetween(latA, lngA, latB, lngB);
    final distanceKm = distanceM / 1000;
    final minutes = (distanceKm / _travelSpeedKmh) * 60;
    return minutes.round().clamp(5, 120);
  }

  /// Run schedule check for the selected date/time; returns list of warning/suggestion strings.
  List<String> _runScheduleCheck() {
    final warnings = <String>[];
    final qty = double.tryParse(_quantityController.text.trim());
    if (_selectedProjectId == null) return warnings;

    final proposedStart = _dueDateTime;
    final proposedEnd = _dueDateTime.add(Duration(minutes: _durationOnSite));
    final proposedQty = qty ?? 0.0;
    final editId = _editingBooking?['id']?.toString();

    // Build day events: existing (excluding edited) + proposed
    final events = <({DateTime start, DateTime end, String? projectId, double qty, bool isProposed})>[];
    for (final b in _bookingsOnSelectedDate) {
      if (editId != null && b['id']?.toString() == editId) continue;
      final dueStr = b['due_date_time']?.toString();
      if (dueStr == null) continue;
      final start = DateTime.parse(dueStr).toLocal();
      final duration = (b['duration_on_site'] as int?) ?? 60;
      final end = start.add(Duration(minutes: duration));
      final projectId = b['project_id']?.toString();
      final q = (b['concrete_qty'] as num?)?.toDouble() ?? 0.0;
      events.add((start: start, end: end, projectId: projectId, qty: q, isProposed: false));
    }
    events.add((start: proposedStart, end: proposedEnd, projectId: _selectedProjectId, qty: proposedQty, isProposed: true));
    events.sort((a, b) => a.start.compareTo(b.start));

    final proposedIndex = events.indexWhere((e) => e.isProposed);
    if (proposedIndex < 0) return warnings;

    // Overlap check
    for (var i = 0; i < events.length; i++) {
      if (i == proposedIndex) continue;
      final other = events[i];
      if (proposedStart.isBefore(other.end) && proposedEnd.isAfter(other.start)) {
        warnings.add('Overlap with another booking (${DateFormat('HH:mm').format(other.start)}–${DateFormat('HH:mm').format(other.end)}). Consider changing time or duration.');
      }
    }

    // Travel time: gap before proposed (previous finish → proposed start)
    if (proposedIndex > 0) {
      final prev = events[proposedIndex - 1];
      final gapMinutes = proposedStart.difference(prev.end).inMinutes;
      final required = _travelMinutesBetween(prev.projectId, _selectedProjectId) + (prev.projectId != _selectedProjectId ? _quarryReloadMinutes : 0);
      if (gapMinutes < required && gapMinutes >= 0) {
        warnings.add('Insufficient time before this booking: ${required - gapMinutes} min short for travel${prev.projectId != _selectedProjectId ? ' and quarry reload' : ''}. Suggest moving this booking to ${DateFormat('HH:mm').format(prev.end.add(Duration(minutes: required)))} or later.');
      } else if (gapMinutes < 0) {
        warnings.add('This time overlaps the previous booking. Suggest moving to ${DateFormat('HH:mm').format(prev.end.add(Duration(minutes: required)))} or later.');
      }
    }

    // Travel time: gap after proposed (proposed end → next start)
    if (proposedIndex < events.length - 1) {
      final next = events[proposedIndex + 1];
      final gapMinutes = next.start.difference(proposedEnd).inMinutes;
      final required = _travelMinutesBetween(_selectedProjectId, next.projectId) + (_selectedProjectId != next.projectId ? _quarryReloadMinutes : 0);
      if (gapMinutes < required && gapMinutes >= 0) {
        warnings.add('Insufficient time after this booking: ${required - gapMinutes} min short for travel${_selectedProjectId != next.projectId ? ' and quarry reload' : ''}. Suggest moving this booking to ${DateFormat('HH:mm').format(next.start.subtract(Duration(minutes: required + _durationOnSite)))} or earlier.');
      } else if (gapMinutes < 0) {
        warnings.add('This time overlaps the next booking. Suggest moving to ${DateFormat('HH:mm').format(next.start.subtract(Duration(minutes: required + _durationOnSite)))} or earlier.');
      }
    }

    // Minor adjustment suggestions (when gap is close)
    if (proposedIndex > 0) {
      final prev = events[proposedIndex - 1];
      final gapMinutes = proposedStart.difference(prev.end).inMinutes;
      final required = _travelMinutesBetween(prev.projectId, _selectedProjectId) + (prev.projectId != _selectedProjectId ? _quarryReloadMinutes : 0);
      if (gapMinutes >= 0 && gapMinutes < required && required - gapMinutes <= 30) {
        warnings.add('Small adjustment: move previous booking end earlier by ${required - gapMinutes} min, or move this booking later by ${required - gapMinutes} min.');
      }
    }
    if (proposedIndex < events.length - 1) {
      final next = events[proposedIndex + 1];
      final gapMinutes = next.start.difference(proposedEnd).inMinutes;
      final required = _travelMinutesBetween(_selectedProjectId, next.projectId) + (_selectedProjectId != next.projectId ? _quarryReloadMinutes : 0);
      if (gapMinutes >= 0 && gapMinutes < required && required - gapMinutes <= 30) {
        warnings.add('Small adjustment: move next booking start later by ${required - gapMinutes} min, or move this booking earlier by ${required - gapMinutes} min.');
      }
    }

    // Truck capacity / quarry reload: multiple deliveries on same day
    final totalDeliveries = events.length;
    final totalQty = events.fold<double>(0, (s, e) => s + e.qty);
    if (totalDeliveries >= 3 || totalQty > _truckCapacityM3 * 2) {
      warnings.add('Several deliveries on this day; consider truck reload at quarry between runs (allow $_quarryReloadMinutes min).');
    }

    return warnings;
  }

  Future<void> _onCheckPressed() async {
    final warnings = _runScheduleCheck();
    setState(() => _checkWarnings = warnings);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.schedule, color: Color(0xFF0081FB)), SizedBox(width: 8), Text('Schedule Check')]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (warnings.isEmpty)
                const Text('No overlap or travel issues found for the selected time. You can proceed with the booking.')
              else
                ...warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Text(w, style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                )),
              const SizedBox(height: 8),
              Text('This check does not prevent making the booking.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _handleFindNearestProject() async {
    if (_bookingUserId == null) return;
    if (_findNearestButtonText == 'Find Nearest') {
      setState(() {
        _projectFilter = '';
        _projectFilterResetCounter++;
        _selectedProjectId = null;
        _selectedProjectName = '';
        _foundNearestProjectIds = [];
        _isFindingNearest = true;
        _checkWarnings = [];
      });
    } else {
      if (_selectedProjectId != null && !_foundNearestProjectIds.contains(_selectedProjectId)) {
        setState(() {
          _foundNearestProjectIds.add(_selectedProjectId!);
          _isFindingNearest = true;
        });
      } else {
        setState(() => _isFindingNearest = true);
      }
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)),
      );
      Map<String, dynamic>? nearestProject;
      double? minDistance;
      for (final project in _allProjects) {
        final projectId = project['id']?.toString();
        if (projectId != null && _foundNearestProjectIds.contains(projectId)) continue;
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
      if (nearestProject != null && mounted) {
        final projectId = nearestProject['id']?.toString();
        final projectName = nearestProject['project_name']?.toString() ?? '';
        setState(() {
          _selectedProjectId = projectId;
          _selectedProjectName = projectName;
          _findNearestButtonText = 'Find Next';
          if (projectId != null && !_foundNearestProjectIds.contains(projectId)) {
            _foundNearestProjectIds.add(projectId);
          }
        });
        final distanceKm = (minDistance! / 1000).toStringAsFixed(1);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nearest project: $projectName ($distanceKm km)'), backgroundColor: Colors.green),
          );
        }
      } else if (mounted) {
        setState(() {
          _findNearestButtonText = 'Find Nearest';
          _foundNearestProjectIds = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No more projects with location data found.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error finding nearest project: $e'), backgroundColor: Colors.red),
        );
        ErrorLogService.logError(location: 'ConcreteMixBookingsScreen._handleFindNearestProject', type: 'GPS', description: '$e', stackTrace: st);
      }
    } finally {
      if (mounted) setState(() => _isFindingNearest = false);
    }
  }

  Future<void> _handleFindLastJob() async {
    if (_bookingUserId == null) return;
    setState(() {
      _projectFilter = '';
      _projectFilterResetCounter++;
      _selectedProjectId = null;
      _selectedProjectName = '';
      _isFindingLast = true;
      _checkWarnings = [];
    });
    try {
      final list = await SupabaseService.client
          .from('concrete_mix_bookings')
          .select('id, project_id, due_date_time')
          .eq('booking_user_id', _bookingUserId!)
          .eq('is_active', true)
          .order('due_date_time', ascending: false)
          .limit(100);
      final rows = List<Map<String, dynamic>>.from(list as List);
      final seen = <String>{};
      final lastJobs = <Map<String, dynamic>>[];
      for (final b in rows) {
        final projectId = b['project_id']?.toString();
        if (projectId == null || projectId.isEmpty || seen.contains(projectId)) continue;
        seen.add(projectId);
        final project = _allProjects.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p!['id']?.toString() == projectId,
          orElse: () => null,
        );
        final projectName = project?['project_name']?.toString() ?? '—';
        lastJobs.add({
          'project_id': projectId,
          'project_name': projectName,
          'due_date_time': b['due_date_time'],
        });
      }
      if (lastJobs.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No previous bookings found.'), backgroundColor: Colors.orange),
        );
        return;
      }
      if (mounted) await _showLastJobsDialog(lastJobs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error finding last job: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isFindingLast = false);
    }
  }

  Future<void> _showLastJobsDialog(List<Map<String, dynamic>> lastJobs) async {
    int currentIndex = 0;
    while (currentIndex < lastJobs.length) {
      final job = lastJobs[currentIndex];
      final projectId = job['project_id'] as String?;
      final projectName = job['project_name'] as String? ?? '—';
      final dueStr = job['due_date_time']?.toString();
      String dateText = 'Date not available';
      if (dueStr != null && dueStr.isNotEmpty) {
        try {
          final dt = DateTime.parse(dueStr);
          dateText = DateFormat('EEEE, d MMM yyyy HH:mm').format(dt.toLocal());
        } catch (_) {}
      }
      final project = projectId != null
          ? _allProjects.cast<Map<String, dynamic>?>().firstWhere(
              (p) => p!['id']?.toString() == projectId,
              orElse: () => null,
            )
          : null;
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('Last Job ${currentIndex + 1} of ${lastJobs.length}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Project:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(projectName, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              const Text('Date Last Used:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(dateText),
              if (project != null && project.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('County: ${project['county']?.toString() ?? '—'}'),
              ],
            ],
          ),
          actions: [
            Builder(
              builder: (ctx2) {
                const buttonWidth = 120.0;
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
                                    onPressed: () => Navigator.of(ctx2).pop('previous'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.yellow,
                                      fixedSize: const Size(120, 40),
                                    ),
                                    child: const Text('Previous'),
                                  )
                                : const SizedBox(width: buttonWidth),
                          ),
                        ),
                        const Expanded(flex: 1, child: SizedBox()),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(ctx2).pop('skip'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.yellow,
                                fixedSize: const Size(120, 40),
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
                              onPressed: () => Navigator.of(ctx2).pop('cancel'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.black,
                                fixedSize: const Size(120, 40),
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
                              onPressed: () => Navigator.of(ctx2).pop(projectId ?? ''),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.black,
                                fixedSize: const Size(120, 40),
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
      if (result == 'cancel') return;
      if (result == projectId && result != null && result.isNotEmpty) {
        final name = _allProjects.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p!['id']?.toString() == result,
          orElse: () => null,
        )?['project_name']?.toString() ?? '';
        setState(() {
          _selectedProjectId = result;
          _selectedProjectName = name;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Project selected.'), backgroundColor: Colors.green),
          );
        }
        return;
      }
      if (result == 'skip') {
        currentIndex++;
      } else if (result == 'previous' && currentIndex > 0) {
        currentIndex--;
      }
    }
  }

  Future<void> _showCustomGpsMap() async {
    if (kIsWeb) {
      try { await loadGoogleMapsApi(); } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Maps not available: $e'), backgroundColor: Colors.red));
        return;
      }
    }
    double? currentLat = _customLat;
    double? currentLng = _customLng;
    if (currentLat == null || currentLng == null) {
      try {
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)));
        currentLat = pos.latitude;
        currentLng = pos.longitude;
      } catch (_) {}
    }
    final project = _selectedProjectId != null ? _projectMapByName.values.cast<Map<String, dynamic>?>().firstWhere((p) => p!['id'] == _selectedProjectId, orElse: () => null) : null;
    final projectLat = project != null ? (project['latitude'] as num?)?.toDouble() : null;
    final projectLng = project != null ? (project['longitude'] as num?)?.toDouble() : null;
    final hasCustom = _customLat != null && _customLng != null;
    final hasProject = projectLat != null && projectLng != null;
    if (!hasCustom && (currentLat == null || currentLng == null)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not get current location. Select a project with GPS or add a custom point first.'), backgroundColor: Colors.orange));
      return;
    }
    double? markerLat = _customLat ?? currentLat;
    double? markerLng = _customLng ?? currentLng;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final markers = <Marker>{
            Marker(
              markerId: const MarkerId('custom'),
              position: LatLng(markerLat!, markerLng!),
              infoWindow: const InfoWindow(title: 'Custom GPS', snippet: 'Delivery point'),
              draggable: true,
              onDragEnd: (LatLng pos) {
                setDialogState(() {
                  markerLat = pos.latitude;
                  markerLng = pos.longitude;
                });
              },
            ),
          };
          if (projectLat != null && projectLng != null) {
            markers.add(Marker(
              markerId: const MarkerId('project'),
              position: LatLng(projectLat, projectLng),
              infoWindow: const InfoWindow(title: 'Project GPS', snippet: 'Project location'),
              draggable: false,
            ));
          }
          double? distanceM;
          if (projectLat != null && projectLng != null && markerLat != null && markerLng != null) {
            distanceM = Geolocator.distanceBetween(projectLat, projectLng, markerLat!, markerLng!);
          }
          String distanceText = '';
          if (distanceM != null && distanceM >= 0) {
            if (distanceM >= 1000) {
              distanceText = 'Distance: ${(distanceM / 1000).toStringAsFixed(1)} km';
            } else {
              distanceText = 'Distance: ${distanceM.toStringAsFixed(0)} m';
            }
          }
          LatLng cameraTarget = LatLng(markerLat!, markerLng!);
          if (projectLat != null && projectLng != null) {
            final minLat = (markerLat! < projectLat ? markerLat! : projectLat) - 0.002;
            final maxLat = (markerLat! > projectLat ? markerLat! : projectLat) + 0.002;
            final minLng = (markerLng! < projectLng! ? markerLng! : projectLng!) - 0.002;
            final maxLng = (markerLng! > projectLng! ? markerLng! : projectLng!) + 0.002;
            cameraTarget = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
          }
          return AlertDialog(
            title: const Text('Custom GPS Position'),
            content: SizedBox(
              width: MediaQuery.of(ctx2).size.width * 0.9,
              height: MediaQuery.of(ctx2).size.height * 0.5,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (distanceText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(distanceText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  Row(
                    children: [
                      if (currentLat != null && currentLng != null)
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              markerLat = currentLat;
                              markerLng = currentLng;
                            });
                          },
                          icon: const Icon(Icons.my_location),
                          label: const Text('Use current location'),
                        ),
                      if (projectLat != null && projectLng != null) ...[
                        if (currentLat != null && currentLng != null) const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              markerLat = projectLat;
                              markerLng = projectLng;
                            });
                          },
                          icon: const Icon(Icons.place),
                          label: const Text('Jump to project'),
                        ),
                      ],
                    ],
                  ),
                  Expanded(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: cameraTarget,
                        zoom: 14,
                      ),
                      markers: markers,
                      onTap: (LatLng pos) {
                        setDialogState(() {
                          markerLat = pos.latitude;
                          markerLng = pos.longitude;
                        });
                      },
                      onMapCreated: (GoogleMapController controller) {
                        if (projectLat != null && projectLng != null && markerLat != null && markerLng != null) {
                          final minLat = (markerLat! < projectLat ? markerLat! : projectLat) - 0.005;
                          final maxLat = (markerLat! > projectLat ? markerLat! : projectLat) + 0.005;
                          final minLng = (markerLng! < projectLng! ? markerLng! : projectLng!) - 0.005;
                          final maxLng = (markerLng! > projectLng! ? markerLng! : projectLng!) + 0.005;
                          controller.animateCamera(CameraUpdate.newLatLngBounds(
                            LatLngBounds(
                              southwest: LatLng(minLat, minLng),
                              northeast: LatLng(maxLat, maxLng),
                            ),
                            50,
                          ));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _customLat = markerLat;
                    _customLng = markerLng;
                  });
                  Navigator.of(ctx2).pop();
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitBooking() async {
    if (_bookingUserId == null || _selectedProjectId == null || _selectedSiteContactUserId == null || _selectedConcreteMixTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill Project, On Site Contact, and Concrete Mix Type'), backgroundColor: Colors.orange));
      return;
    }
    final qty = double.tryParse(_quantityController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid quantity'), backgroundColor: Colors.orange));
      return;
    }
    if (qty > 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max quantity is 8'), backgroundColor: Colors.orange));
      return;
    }
    // Always run schedule check before showing confirmation so conflicts are included even if user didn't click the button
    final warnings = _runScheduleCheck();
    setState(() => _checkWarnings = warnings);
    final confirmed = await _showSummaryDialog();
    if (confirmed != true) return;
    setState(() => _isSaving = true);
    try {
      await SupabaseService.client.from('concrete_mix_bookings').insert({
        'booking_user_id': _bookingUserId,
        'site_contact_id': _selectedSiteContactUserId,
        'project_id': _selectedProjectId,
        'custom_lat': _customLat,
        'custom_lng': _customLng,
        'delivered': _delivered,
        'concrete_mix_type': _selectedConcreteMixTypeId,
        'concrete_qty': qty,
        'wet': _wet,
        'due_date_time': _dueDateTime.toUtc().toIso8601String(),
        'duration_on_site': _durationOnSite,
        'comments': _commentsController.text.trim().isEmpty ? null : _commentsController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking saved'), backgroundColor: Colors.green));
        _checkWarnings = [];
        _clearForm();
        await _loadBookings();
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red));
        ErrorLogService.logError(location: 'ConcreteMixBookingsScreen._submitBooking', type: 'Save', description: '$e', stackTrace: st);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool?> _showSummaryDialog() async {
    final projectName = _selectedProjectName.isEmpty ? '—' : _selectedProjectName;
    final siteContact = _siteContacts.cast<Map<String, dynamic>?>().firstWhere(
      (u) => u!['user_id'] == _selectedSiteContactUserId,
      orElse: () => null,
    );
    final siteContactName = siteContact?['display_name']?.toString() ?? '—';
    final mixName = _concreteMixTypes.cast<Map<String, dynamic>?>().firstWhere(
      (m) => m!['id'] == _selectedConcreteMixTypeId,
      orElse: () => null,
    )?['name']?.toString() ?? '—';
    final qtyStr = _quantityController.text.trim();
    final qtyVal = double.tryParse(qtyStr);
    final quantityDisplay = qtyVal != null ? qtyVal.toStringAsFixed(2) : qtyStr;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF0081FB), size: 24),
                    SizedBox(width: 8),
                    Text('Confirm Booking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0081FB))),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryRow('Project', projectName),
                        _summaryRow('Contact', siteContactName),
                        _summaryRow('Type', _delivered ? 'Deliver' : 'Collect'),
                        _summaryRow('Date', DateFormat('dd/MM/yyyy HH:mm').format(_dueDateTime)),
                        _summaryRow('On Site', _durationHmm(_durationOnSite)),
                        if (_checkWarnings.isNotEmpty) ...[
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Schedule check warnings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                                      const SizedBox(height: 4),
                                      ..._checkWarnings.map((w) => Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(w, style: const TextStyle(fontSize: 13)),
                                      )),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(),
                        _summaryRow('Mix', mixName),
                        _summaryRow('Quantity', quantityDisplay),
                        _summaryRow('Wet/Dry', _wet ? 'Wet' : 'Dry'),
                        if (_commentsController.text.trim().isNotEmpty) _summaryRow('Comments', _commentsController.text.trim()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text('Upload'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  void _clearForm() {
    setState(() {
      _selectedProjectId = null;
      _selectedProjectName = '';
      _selectedSiteContactUserId = null;
      _customLat = null;
      _customLng = null;
      _delivered = true;
      _dueDateTime = _defaultDueDateTime;
      _loadBookingsOnDate(_dueDateTime);
      _durationOnSite = 60;
      _selectedConcreteMixTypeId = null;
      _quantityController.clear();
      _wet = true;
      _commentsController.clear();
      _editingBooking = null;
      _checkWarnings = [];
    });
  }

  void _openBookingForEdit(Map<String, dynamic> b) {
    setState(() {
      _editingBooking = b;
      _selectedProjectId = b['project_id']?.toString();
      _selectedProjectName = _projectMapByName.values.cast<Map<String, dynamic>?>().firstWhere(
        (p) => p!['id'] == _selectedProjectId,
        orElse: () => null,
      )?['project_name']?.toString() ?? '';
      _selectedSiteContactUserId = b['site_contact_id']?.toString();
      _customLat = (b['custom_lat'] as num?)?.toDouble();
      _customLng = (b['custom_lng'] as num?)?.toDouble();
      _delivered = (b['delivered'] as bool?) ?? true;
      final due = b['due_date_time'];
      _dueDateTime = due != null ? DateTime.parse(due.toString()) : _defaultDueDateTime;
      _durationOnSite = (b['duration_on_site'] as int?) ?? 60;
      _selectedConcreteMixTypeId = b['concrete_mix_type']?.toString();
      _quantityController.text = (b['concrete_qty'] as num?)?.toString() ?? '';
      _wet = (b['wet'] as bool?) ?? true;
      _commentsController.text = b['comments']?.toString() ?? '';
    });
    if (b['due_date_time'] != null) _loadBookingsOnDate(_dueDateTime);
  }

  Future<void> _updateBooking() async {
    final b = _editingBooking;
    if (b == null) return;
    if (_selectedProjectId == null || _selectedSiteContactUserId == null || _selectedConcreteMixTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill required fields'), backgroundColor: Colors.orange));
      return;
    }
    final qty = double.tryParse(_quantityController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid quantity'), backgroundColor: Colors.orange));
      return;
    }
    if (qty > 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max quantity is 8'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await SupabaseService.client.from('concrete_mix_bookings').update({
        'site_contact_id': _selectedSiteContactUserId,
        'project_id': _selectedProjectId,
        'custom_lat': _customLat,
        'custom_lng': _customLng,
        'delivered': _delivered,
        'concrete_mix_type': _selectedConcreteMixTypeId,
        'concrete_qty': qty,
        'wet': _wet,
        'due_date_time': _dueDateTime.toUtc().toIso8601String(),
        'duration_on_site': _durationOnSite,
        'comments': _commentsController.text.trim().isEmpty ? null : _commentsController.text.trim(),
      }).eq('id', b['id'] as Object);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking updated'), backgroundColor: Colors.green));
        _checkWarnings = [];
        _clearForm();
        await _loadBookings();
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating: $e'), backgroundColor: Colors.red));
        ErrorLogService.logError(location: 'ConcreteMixBookingsScreen._updateBooking', type: 'Update', description: '$e', stackTrace: st);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _softDeleteBooking(Map<String, dynamic> b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete booking?'),
        content: const Text('This will soft-delete the booking. You can restore it later if needed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isSaving = true);
    try {
      await SupabaseService.client.from('concrete_mix_bookings').update({'is_active': false}).eq('id', b['id'] as Object);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking deleted'), backgroundColor: Colors.orange));
        _clearForm();
        await _loadBookings();
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red));
        ErrorLogService.logError(location: 'ConcreteMixBookingsScreen._softDeleteBooking', type: 'Delete', description: '$e', stackTrace: st);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildBookingsOnDateSummary() {
    final dateStr = DateFormat('dd/MM/yyyy').format(_dueDateTime);
    const headerStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
    const cellStyle = TextStyle(fontSize: 12);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bookings on $dateStr', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_bookingsOnSelectedDate.isEmpty)
            const Text('No bookings on this date.', style: TextStyle(fontSize: 14, color: Colors.grey))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: IntrinsicColumnWidth(),
                  2: IntrinsicColumnWidth(),
                  3: IntrinsicColumnWidth(),
                  4: IntrinsicColumnWidth(),
                  5: IntrinsicColumnWidth(),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.blue.shade200))),
                    children: [
                      Center(child: Padding(padding: const EdgeInsets.only(right: 12, bottom: 4), child: Text('On Site', style: headerStyle))),
                      Center(child: Padding(padding: const EdgeInsets.only(right: 12, bottom: 4), child: Text('Quantity', style: headerStyle))),
                      Center(child: Padding(padding: const EdgeInsets.only(right: 12, bottom: 4), child: Text('Job No.', style: headerStyle))),
                      Padding(padding: const EdgeInsets.only(right: 12, bottom: 4), child: Text('Location', style: headerStyle)),
                      Center(child: Padding(padding: const EdgeInsets.only(right: 12, bottom: 4), child: Text('Ordered By', style: headerStyle))),
                      Center(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Booked', style: headerStyle))),
                    ],
                  ),
                  ..._bookingsOnSelectedDate.map((b) {
                    final dueStr = b['due_date_time']?.toString();
                    final start = dueStr != null ? DateTime.parse(dueStr).toLocal() : null;
                    final duration = (b['duration_on_site'] as int?) ?? 60;
                    final end = start != null ? start.add(Duration(minutes: duration)) : null;
                    final onSiteStr = (start != null && end != null)
                        ? '${DateFormat('HH:mm').format(start)}–${DateFormat('HH:mm').format(end)}'
                        : '—';
                    final projectId = b['project_id']?.toString();
                    final project = _allProjects.cast<Map<String, dynamic>?>().firstWhere(
                      (p) => p!['id'] == projectId,
                      orElse: () => null,
                    );
                    final jobNoFull = project?['project_number']?.toString() ?? '';
                    final jobNo = jobNoFull.length > 7 ? jobNoFull.substring(0, 7) : jobNoFull;
                    final isCollection = b['delivered'] == false;
                    final townRaw = project?['town']?.toString()?.trim() ?? '';
                    final town = townRaw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2).join(' ');
                    final county = project?['county']?.toString()?.trim() ?? '';
                    final location = isCollection
                        ? 'Ardristan Quarry'
                        : (town.isNotEmpty && county.isNotEmpty
                            ? '$town, Co. $county'
                            : county.isNotEmpty
                                ? 'Co. $county'
                                : town.isNotEmpty
                                    ? town
                                    : '—');
                    final orderedById = b['booking_user_id']?.toString();
                    final orderedBy = _siteContacts.cast<Map<String, dynamic>?>().firstWhere(
                      (u) => u!['user_id']?.toString() == orderedById,
                      orElse: () => null,
                    )?['display_name']?.toString() ?? '—';
                    final qty = b['concrete_qty'];
                    final qtyNum = qty is num ? qty.toDouble() : double.tryParse(qty?.toString() ?? '');
                    final qtyStr = qtyNum != null ? qtyNum.toStringAsFixed(2) : '—';
                    final insertedAt = b['inserted_at']?.toString();
                    final bookedStr = insertedAt != null && insertedAt.isNotEmpty
                        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(insertedAt).toLocal())
                        : '—';
                    return TableRow(
                      children: [
                        Center(child: Padding(padding: const EdgeInsets.only(right: 12, top: 4), child: Text(onSiteStr, style: cellStyle))),
                        Center(child: Padding(padding: const EdgeInsets.only(right: 12, top: 4), child: Text(qtyStr, style: cellStyle))),
                        Center(child: Padding(padding: const EdgeInsets.only(right: 12, top: 4), child: Text(jobNo.isEmpty ? '—' : jobNo, style: cellStyle))),
                        Padding(padding: const EdgeInsets.only(right: 12, top: 4), child: Text(location, style: cellStyle, overflow: TextOverflow.ellipsis)),
                        Center(child: Padding(padding: const EdgeInsets.only(right: 12, top: 4), child: Text(orderedBy, style: cellStyle, overflow: TextOverflow.ellipsis))),
                        Center(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(bookedStr, style: cellStyle))),
                      ],
                    );
                  }),
                ],
              ),
            ),
        ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                border: Border(bottom: BorderSide(color: Color(0xFF005AB0), width: 2)),
              ),
              child: Center(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
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
          title: const Text('Concrete Mix Bookings', style: TextStyle(color: Colors.black)),
          centerTitle: true,
          backgroundColor: const Color(0xFF0081FB),
          foregroundColor: Colors.black,
          actions: const [ScreenInfoIcon(screenName: 'concrete_mix_bookings_screen.dart')],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Concrete Mix Bookings', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'concrete_mix_bookings_screen.dart')],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Online status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isOnline ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isOnline ? Colors.green : Colors.orange, width: 1),
              ),
              child: Row(
                children: [
                  Icon(_isOnline ? Icons.cloud_done : Icons.cloud_off, color: _isOnline ? Colors.green : Colors.orange),
                  const SizedBox(width: 8),
                  Text(_isOnline ? 'Online' : 'Offline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _isOnline ? Colors.green.shade700 : Colors.orange.shade700)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Current user
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
                  Text(_displayName.isEmpty ? '—' : _displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Bookings on selected date (availability summary)
            _buildBookingsOnDateSummary(),
            const SizedBox(height: 24),

            // Date & Time section (above Project) — narrow label column so date row fits on phone
            _buildSection('Date & Time of Booking', [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_delivered ? 'Deliver' : 'Collect', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Switch(
                        value: _delivered,
                        onChanged: (v) => setState(() => _delivered = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios, size: 20),
                                onPressed: _dueDateOnly.isAfter(_todayOnly)
                                    ? () => _setDueDate(_dueDateOnly.subtract(const Duration(days: 1)))
                                    : null,
                                tooltip: 'Previous day',
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('EEE d MMM yyyy').format(_dueDateTime),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.arrow_forward_ios, size: 20),
                                onPressed: () => _setDueDate(_dueDateOnly.add(const Duration(days: 1))),
                                tooltip: 'Next day',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('Time', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTimeSpinnerPart(
                            value: _dueDateTime.hour.toString().padLeft(2, '0'),
                            onTap: _showDueTimeScrollPicker,
                            onUp: () => _adjustDueHour(1),
                            onDown: () => _adjustDueHour(-1),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          ),
                          _buildTimeSpinnerPart(
                            value: ((_dueDateTime.minute ~/ 15) * 15).toString().padLeft(2, '0'),
                            onTap: _showDueTimeScrollPicker,
                            onUp: () => _adjustDueMinute(15),
                            onDown: () => _adjustDueMinute(-15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 24),

            // Project section
            _buildSection('Project Details', [
              TextFormField(
                key: ValueKey('project_filter_$_projectFilterResetCounter'),
                initialValue: _projectFilter,
                decoration: InputDecoration(
                  labelText: 'Filter Projects',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _projectFilter.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () => setState(() { _projectFilter = ''; _projectFilterResetCounter++; })) : null,
                ),
                onChanged: (v) => setState(() => _projectFilter = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedProjectId,
                decoration: const InputDecoration(labelText: 'Project *', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                items: () {
                  // Projects with project_name starting with "W" are excluded, except W0-4010..W9-4010 and W0-4012..W9-4012 (x = 0-9)
                  final w4010Or4012 = RegExp(r'^W[0-9]-4010$|^W[0-9]-4012$', caseSensitive: false);
                  final filtered = _allProjects.where((p) {
                    final name = p['project_name']?.toString() ?? '';
                    final projectNumber = (p['project_number']?.toString() ?? '').trim();
                    final isExceptionProject = w4010Or4012.hasMatch(projectNumber);
                    if (!isExceptionProject && name.toUpperCase().startsWith('W')) return false;
                    if (_projectFilter.isEmpty) return true;
                    final nameLower = name.toLowerCase();
                    final terms = _projectFilter.toLowerCase().split(' ').where((t) => t.isNotEmpty);
                    return terms.every((t) => nameLower.contains(t));
                  }).toList();
                  // When editing a booking, selected project must appear in the list or dropdown throws
                  if (_selectedProjectId != null && _selectedProjectId!.isNotEmpty) {
                    final alreadyInList = filtered.any((p) => p['id']?.toString() == _selectedProjectId);
                    if (!alreadyInList) {
                      final selectedProject = _allProjects.cast<Map<String, dynamic>?>().firstWhere(
                        (p) => p!['id']?.toString() == _selectedProjectId,
                        orElse: () => null,
                      );
                      if (selectedProject != null && selectedProject.isNotEmpty) {
                        filtered.add(selectedProject);
                      }
                    }
                  }
                  filtered.sort((a, b) => (a['project_name']?.toString() ?? '').compareTo(b['project_name']?.toString() ?? ''));
                  return filtered.map((p) => DropdownMenuItem(value: p['id']?.toString(), child: Text(p['project_name']?.toString() ?? '', overflow: TextOverflow.ellipsis))).toList();
                }(),
                onChanged: (v) {
                  if (v != null) {
                    final p = _projectMapByName.values.cast<Map<String, dynamic>?>().firstWhere((x) => x!['id'] == v, orElse: () => null);
                    setState(() {
                      _selectedProjectId = v;
                      _selectedProjectName = p?['project_name']?.toString() ?? '';
                      _checkWarnings = [];
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.2,
                    child: TextFormField(
                      key: ValueKey('site_contact_filter_$_siteContactFilterResetCounter'),
                      initialValue: _siteContactFilter,
                      decoration: InputDecoration(
                        labelText: 'Initials',
                        hintText: 'e.g. JD',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                        // On Android omit clear (X) button so it doesn't mask entered text; match dropdown height
                        suffixIcon: (defaultTargetPlatform != TargetPlatform.android && _siteContactFilter.isNotEmpty)
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () => setState(() {
                                  _siteContactFilter = '';
                                  _siteContactFilterResetCounter++;
                                }),
                              )
                            : null,
                      ),
                      onChanged: (v) => setState(() => _siteContactFilter = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'On Site Contact *',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                      ),
                      items: () {
                        final filter = _siteContactFilter.trim().toUpperCase();
                        final filtered = filter.isEmpty
                            ? _siteContacts
                            : _siteContacts.where((u) {
                                final name = u['display_name']?.toString() ?? '';
                                return _initialsFrom(name).startsWith(filter);
                              }).toList();
                        return filtered
                            .map((u) => DropdownMenuItem(
                                  value: u['user_id']?.toString(),
                                  child: Text(u['display_name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                                ))
                            .toList();
                      }(),
                      value: () {
                        final filter = _siteContactFilter.trim().toUpperCase();
                        final filtered = filter.isEmpty
                            ? _siteContacts
                            : _siteContacts.where((u) {
                                final name = u['display_name']?.toString() ?? '';
                                return _initialsFrom(name).startsWith(filter);
                              }).toList();
                        final selectedInList = filtered.any((u) => u['user_id']?.toString() == _selectedSiteContactUserId);
                        return selectedInList ? _selectedSiteContactUserId : null;
                      }(),
                      onChanged: (v) => setState(() => _selectedSiteContactUserId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _showCustomGpsMap,
                    icon: const Icon(Icons.gps_fixed, size: 20),
                    label: const Text('Custom GPS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0081FB),
                      foregroundColor: Colors.yellow,
                    ),
                  ),
                  if (_customLat != null && _customLng != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 6),
                    Text('Custom GPS Point added', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _selectedProjectId == null ? null : _onCheckPressed,
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text('Check Scheduling for Conflicts'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0081FB),
                  foregroundColor: Colors.yellow,
                ),
              ),
              if (_selectedProjectId == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Select a project to run schedule check.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: (_isFindingNearest || _isFindingLast) ? null : _handleFindNearestProject,
                    icon: _isFindingNearest ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.near_me, size: 20),
                    label: Text(_findNearestButtonText),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0081FB),
                      foregroundColor: Colors.yellow,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: (_isFindingNearest || _isFindingLast) ? null : _handleFindLastJob,
                    icon: _isFindingLast ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.history, size: 20),
                    label: const Text('Find Last'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0081FB),
                      foregroundColor: Colors.yellow,
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 24),

            // Concrete Mix Details
            _buildSection('Concrete Mix Details', [
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedConcreteMixTypeId,
                decoration: const InputDecoration(labelText: 'Concrete Mix Type *', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                items: _concreteMixTypes.map((m) => DropdownMenuItem(value: m['id']?.toString(), child: Center(child: Text(m['name']?.toString() ?? '', overflow: TextOverflow.ellipsis)))).toList(),
                onChanged: (v) => setState(() => _selectedConcreteMixTypeId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityController,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantity (2 decimal places, max 8)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                onChanged: (_) {
                  _updateDurationFromQuantity();
                  setState(() {});
                },
                validator: (v) {
                  final qty = double.tryParse(v?.trim() ?? '');
                  if (qty == null || qty.isNaN || qty < 0) return null;
                  if (qty > 8) return 'Max quantity is 8';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Duration on site', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios),
                            onPressed: () => _adjustDuration(-15),
                            tooltip: '15 min less',
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _durationHmm(_durationOnSite),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios),
                            onPressed: () => _adjustDuration(15),
                            tooltip: '15 min more',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(_wet ? 'Wet' : 'Dry', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const Expanded(child: SizedBox()),
                  Switch(
                    value: _wet,
                    onChanged: (v) => setState(() => _wet = v),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _commentsController,
                textAlign: TextAlign.center,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Enter note for Driver here',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ]),
            const SizedBox(height: 24),

            if (_editingBooking != null) ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _updateBooking,
                      icon: const Icon(Icons.save),
                      label: const Text('Update'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => _clearForm(),
                      child: const Text('Cancel edit'),
                    ),
                  ),
                ],
              ),
            ] else
              FilledButton.icon(
                onPressed: _isSaving ? null : _submitBooking,
                icon: const Icon(Icons.upload),
                label: const Text('Upload'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0081FB), minimumSize: const Size(double.infinity, 48)),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
