/// Concrete Mix Scheduler Screen
///
/// Week view: select a day, order bookings with sequence, build schedule (Loading / Travelling / On Site)
/// and save to public.concrete_mix_calendar. Calendar ID and quarry GPS from system_settings.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';
import '../widgets/screen_info_icon.dart';

class ConcreteMixSchedulerScreen extends StatefulWidget {
  const ConcreteMixSchedulerScreen({super.key});

  @override
  State<ConcreteMixSchedulerScreen> createState() => _ConcreteMixSchedulerScreenState();
}

class _ConcreteMixSchedulerScreenState extends State<ConcreteMixSchedulerScreen> {
  static const List<String> _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const double _maxLoadCapacity = 8.0;
  static const Color _headerBlue = Color(0xFF005AB0);
  static const Color _totalRowBlue = Color(0xFFB3D9FF);
  static const Color _calendarLoading = Colors.blue;
  static const Color _calendarTravelling = Colors.orange;
  static const Color _calendarOnSite = Colors.green;
  static const Color _calendarWaiting = Colors.grey;
  static const Color _calendarWash = Color(0xFF6B8E9E); // slate for wash
  static const Color _calendarOverCapacity = Colors.red;

  /// Total width of Load quantities table (5 × 108) for matching Bookings table width.
  static const double _loadQuantitiesTableWidth = 540.0;
  /// Comment column width; column widths set so Bookings table total matches.
  static const double _bookingsCommentColumnWidth = 171.0;
  /// Bookings DataTable width: sum of column widths (35+36*4+34+38+36+171+38) + columnSpacing*9 + horizontalMargin*2.
  static const double _bookingsTableWidth = 536.0 + (4 * 9) + (4 * 2); // 580

  DateTime _selectedWeekStart = DateTime.now();
  String? _selectedDay; // exactly one: Mon, Tue, ... or null

  List<Map<String, dynamic>> _bookings = [];
  Map<String, String> _projectNumbers = {}; // project_id -> project_number
  Map<String, String> _projectNames = {};   // project_id -> project_name
  Map<String, String> _projectCounties = {}; // project_id -> county
  Map<String, Map<String, dynamic>> _projectCoords = {}; // project_id -> { lat, lng }
  Map<String, String> _bookingUserNames = {}; // user_id -> display_name from users_setup
  Map<String, String> _concreteMixNames = {}; // concrete_mix id -> name
  Map<String, String> _siteContactNames = {}; // site_contact user_id -> display_name
  List<Map<String, dynamic>> _calendarEvents = []; // for selected day from concrete_mix_calendar
  List<Map<String, dynamic>> _previewCalendarEvents = []; // schedule preview when Update is clicked, or loaded saved/synced route
  /// Selected day schedule status: preview (not saved), saved, or synced (with Google Calendar).
  String _scheduleDayStatus = 'preview'; // 'preview' | 'saved' | 'synced'
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSyncing = false;
  bool _isUpdating = false; // building preview for Update

  // system_settings
  String? _calendarId;
  double? _quarryLat;
  double? _quarryLng;
  int _quarryTravelBufferMinutes = 0; // buffer added to each travel, round to 15 min
  /// Max average speed (km/h) for travel; if set, duration is at least distance/max_speed (helps account for traffic). Null = use API only.
  int? _travelMaxSpeedKmh;
  /// Wash time (minutes) after each on-site or quarry delivery; shown in schedule, not uploaded to calendar.
  int _washTimeMinutes = 0;
  /// Loading at quarry duration (minutes); used for all loading blocks regardless of quantity.
  int _loadingTimeMinutes = 15;

  // For selected day: booking id (or null for "return to quarry" row) -> sequence number
  final Map<String, int> _sequenceByBookingId = {};
  // booking id -> include in schedule (default true); toggled off = red, excluded from Update Schedule
  final Map<String, bool> _includedInSchedule = {};
  // Sentinel key for "return to quarry" placeholder rows
  static const String _returnToQuarryKey = '__return_to_quarry__';
  final List<String> _returnToQuarryInsertedAt = []; // list of keys like "__return_1" to maintain order
  // Reload at quarry: only after a Collected load; duration 15 min per 2 qty, max 60 min
  static const String _reloadAtQuarryKey = '__reload_at_quarry__';
  final List<String> _reloadAtQuarryInsertedAt = [];
  static const String _breakKey = '__break__';
  final List<String> _breakInsertedAt = [];
  // Cached trip distances (km) and travel minutes for Load quantities table; index = trip index (includes return leg)
  List<double?> _tripDistancesKm = [];
  List<int?> _tripTravelMinutes = [];
  final PageController _mobilePageController = PageController();
  // Booking table sort: 'seq' | 'time' | 'scheduled'
  String _bookingTableSortMode = 'time';
  /// Start time offset in minutes from 6:00.
  int _scheduleStartOffsetMinutes = 0;

  DateTime _getWeekStart(DateTime date) {
    final w = date.weekday;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: w - 1));
  }

  DateTime _getWeekEnd(DateTime weekStart) => weekStart.add(const Duration(days: 6));

  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
      _selectedDay = null;
      _scheduleStartOffsetMinutes = 0;
      _scheduleDayStatus = 'preview';
      _sequenceByBookingId.clear();
      _returnToQuarryInsertedAt.clear();
      _reloadAtQuarryInsertedAt.clear();
      _breakInsertedAt.clear();
      _previewCalendarEvents = [];
      _load();
    });
  }

  void _nextWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
      _selectedDay = null;
      _scheduleStartOffsetMinutes = 0;
      _scheduleDayStatus = 'preview';
      _sequenceByBookingId.clear();
      _returnToQuarryInsertedAt.clear();
      _reloadAtQuarryInsertedAt.clear();
      _breakInsertedAt.clear();
      _previewCalendarEvents = [];
      _load();
    });
  }

  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
      _selectedDay = null;
      _scheduleStartOffsetMinutes = 0;
      _scheduleDayStatus = 'preview';
      _sequenceByBookingId.clear();
      _returnToQuarryInsertedAt.clear();
      _reloadAtQuarryInsertedAt.clear();
      _breakInsertedAt.clear();
      _previewCalendarEvents = [];
      _load();
    });
  }

  int _dayNameToWeekday(String name) {
    final i = _dayNames.indexOf(name);
    return i >= 0 ? i + 1 : 1;
  }

  double _quantityForDay(int weekday, bool scheduled) {
    double sum = 0;
    for (final b in _bookings) {
      final due = b['due_date_time'];
      if (due == null) continue;
      final dt = DateTime.parse(due.toString());
      if (dt.weekday != weekday) continue;
      if ((b['is_scheduled'] == true) != scheduled) continue;
      final q = b['concrete_qty'];
      if (q != null) sum += (q is num) ? (q as num).toDouble() : (double.tryParse(q.toString()) ?? 0);
    }
    return sum;
  }

  String _formatQuantity(double q) {
    if (q == q.roundToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Format quantity to exactly two decimal places for booking/load tables.
  String _formatQuantityTwoDecimals(double q) {
    return q.toStringAsFixed(2);
  }

  /// Format travel time as hh:mm (e.g. 90 -> "1:30").
  String _formatTravelTimeHhMm(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }

  String _formatCalendarDayHeader(DateTime d) {
    return '${DateFormat('EEEE').format(d)} - ${_ordinal(d.day)} ${DateFormat('MMMM yyyy').format(d)}';
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _previewCalendarEvents = [];
      _scheduleDayStatus = 'preview';
    });
    final weekEnd = _getWeekEnd(_selectedWeekStart);
    final startStr = _selectedWeekStart.toUtc().toIso8601String();
    final endStr = DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59).toUtc().toIso8601String();

    try {
      // concrete_mix_bookings: due_date_time range uses idx_cmb_due_date_time (see supabase_indexes.md)
      final list = await SupabaseService.client
          .from('concrete_mix_bookings')
          .select('*')
          .eq('is_active', true)
          .gte('due_date_time', startStr)
          .lte('due_date_time', endStr)
          .order('due_date_time');
      final bookings = List<Map<String, dynamic>>.from(list as List);

      final projectIds = <String>{};
      for (final b in bookings) {
        final p = b['project_id']?.toString();
        if (p != null) projectIds.add(p);
      }

      final projectNumbers = <String, String>{};
      final projectNames = <String, String>{};
      final projectCounties = <String, String>{};
      final projectCoords = <String, Map<String, dynamic>>{};
      if (projectIds.isNotEmpty) {
        final projects = await SupabaseService.client
            .from('projects')
            .select('id, project_number, project_name, county, latitude, longitude')
            .inFilter('id', projectIds.toList());
        for (final p in projects as List) {
          final m = Map<String, dynamic>.from(p as Map);
          final id = m['id']?.toString() ?? '';
          projectNumbers[id] = m['project_number']?.toString() ?? '—';
          projectNames[id] = m['project_name']?.toString() ?? '—';
          projectCounties[id] = m['county']?.toString() ?? '—';
          final lat = m['latitude'] != null ? (m['latitude'] as num).toDouble() : null;
          final lng = m['longitude'] != null ? (m['longitude'] as num).toDouble() : null;
          if (lat != null && lng != null) projectCoords[id] = {'lat': lat, 'lng': lng};
        }
      }

      final userIds = <String>{};
      for (final b in bookings) {
        final u = b['booking_user_id']?.toString();
        if (u != null) userIds.add(u);
      }
      final bookingUserNames = <String, String>{};
      if (userIds.isNotEmpty) {
        final users = await SupabaseService.client
            .from('users_setup')
            .select('user_id, display_name')
            .inFilter('user_id', userIds.toList());
        for (final u in users as List) {
          final m = Map<String, dynamic>.from(u as Map);
          bookingUserNames[m['user_id']?.toString() ?? ''] = m['display_name']?.toString() ?? '—';
        }
      }

      final mixTypeIds = <String>{};
      final siteContactIds = <String>{};
      for (final b in bookings) {
        final mid = b['concrete_mix_type']?.toString();
        if (mid != null && mid.isNotEmpty) mixTypeIds.add(mid);
        final sid = b['site_contact_id']?.toString();
        if (sid != null && sid.isNotEmpty) siteContactIds.add(sid);
      }
      final concreteMixNames = <String, String>{};
      if (mixTypeIds.isNotEmpty) {
        final mixList = await SupabaseService.client
            .from('concrete_mix')
            .select('id, name')
            .inFilter('id', mixTypeIds.toList());
        for (final m in mixList as List) {
          final row = Map<String, dynamic>.from(m as Map);
          concreteMixNames[row['id']?.toString() ?? ''] = row['name']?.toString() ?? '—';
        }
      }
      final siteContactNames = <String, String>{};
      if (siteContactIds.isNotEmpty) {
        final siteUsers = await SupabaseService.client
            .from('users_setup')
            .select('user_id, display_name')
            .inFilter('user_id', siteContactIds.toList());
        for (final u in siteUsers as List) {
          final m = Map<String, dynamic>.from(u as Map);
          siteContactNames[m['user_id']?.toString() ?? ''] = m['display_name']?.toString() ?? '—';
        }
      }

      final settings = await SupabaseService.client
          .from('system_settings')
          .select('concrete_mix_calendar_id, quarry_lat, quarry_lng, quarry_travel, max_speed_for_travel, wash_time, loading_time')
          .limit(1)
          .maybeSingle();
      final settingsMap = settings != null ? Map<String, dynamic>.from(settings as Map) : null;
      final calendarId = settingsMap?['concrete_mix_calendar_id']?.toString();
      final qLat = settingsMap?['quarry_lat'] != null ? (settingsMap!['quarry_lat'] as num).toDouble() : null;
      final qLng = settingsMap?['quarry_lng'] != null ? (settingsMap!['quarry_lng'] as num).toDouble() : null;
      final quarryTravel = settingsMap?['quarry_travel'];
      final quarryTravelMinutes = quarryTravel != null ? (quarryTravel is num ? (quarryTravel as num).toInt() : int.tryParse(quarryTravel.toString()) ?? 0) : 0;
      final maxSpeed = settingsMap?['max_speed_for_travel'];
      final maxSpeedKmh = maxSpeed != null ? (maxSpeed is num ? (maxSpeed as num).toInt() : int.tryParse(maxSpeed.toString())) : null;
      final washTime = settingsMap?['wash_time'];
      final washTimeMin = washTime != null ? (washTime is num ? (washTime as num).toInt() : int.tryParse(washTime.toString()) ?? 0) : 0;
      final loadingTime = settingsMap?['loading_time'];
      final loadingTimeMin = loadingTime != null ? (loadingTime is num ? (loadingTime as num).toInt() : int.tryParse(loadingTime.toString()) ?? 15) : 15;

      if (mounted) {
        setState(() {
          _bookings = bookings;
          _projectNumbers = projectNumbers;
          _projectNames = projectNames;
          _projectCounties = projectCounties;
          _projectCoords = projectCoords;
          _bookingUserNames = bookingUserNames;
          _concreteMixNames = concreteMixNames;
          _siteContactNames = siteContactNames;
          _calendarId = calendarId;
          _quarryLat = qLat;
          _quarryLng = qLng;
          _quarryTravelBufferMinutes = quarryTravelMinutes;
          _travelMaxSpeedKmh = maxSpeedKmh;
          _washTimeMinutes = washTimeMin;
          _loadingTimeMinutes = loadingTimeMin.clamp(1, 120);
          _isLoading = false;
        });
        if (_selectedDay != null) _loadCalendarForSelectedDay();
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'ConcreteMixSchedulerScreen._load', type: 'Load', description: '$e', stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  /// Load concrete_mix_calendar events for the selected day. If any exist, show as schedule (saved/synced route) so user can edit and re-save.
  Future<void> _loadCalendarForSelectedDay() async {
    if (_selectedDay == null) return;
    final weekday = _dayNameToWeekday(_selectedDay!);
    final dayDate = _selectedWeekStart.add(Duration(days: weekday - 1));
    final dayStart = DateTime(dayDate.year, dayDate.month, dayDate.day, 0, 0, 0);
    final dayEnd = DateTime(dayDate.year, dayDate.month, dayDate.day, 23, 59, 59);
    final startStr = dayStart.toUtc().toIso8601String();
    final endStr = dayEnd.toUtc().toIso8601String();

    try {
      final list = await SupabaseService.client
          .from('concrete_mix_calendar')
          .select('*')
          .gte('start_datetime', startStr)
          .lte('start_datetime', endStr)
          .order('start_datetime');
      final raw = List<Map<String, dynamic>>.from(list as List);
      // Normalize type for display (DB may store task_type)
      for (final e in raw) {
        if (e['type'] == null && e['task_type'] != null) e['type'] = e['task_type'];
      }
      if (mounted) {
        setState(() {
          _calendarEvents = raw;
          if (raw.isNotEmpty) {
            _previewCalendarEvents = List<Map<String, dynamic>>.from(raw);
            _scheduleDayStatus = raw.any((e) => e['google_event_id'] != null && (e['google_event_id']?.toString() ?? '').isNotEmpty) ? 'synced' : 'saved';
          } else {
            _previewCalendarEvents = [];
            _scheduleDayStatus = 'preview';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _calendarEvents = [];
        _scheduleDayStatus = 'preview';
      });
    }
  }

  void _assignDefaultSequence() {
    final bookings = _bookingsForSelectedDay();
    bookings.sort((a, b) {
      final ad = a['due_date_time']?.toString() ?? '';
      final bd = b['due_date_time']?.toString() ?? '';
      return ad.compareTo(bd);
    });
    final newSeq = <String, int>{};
    for (var i = 0; i < bookings.length; i++) {
      final id = bookings[i]['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        newSeq[id] = i + 1;
        _includedInSchedule.putIfAbsent(id, () => true);
      }
    }
    setState(() => _sequenceByBookingId.addAll(newSeq));
  }

  /// Per-trip delivered and collected from current ordered rows (dynamic as user allocates sequence).
  List<({double delivered, double collected})> _tripQuantitiesFromOrderedRowsRaw() {
    final rows = _orderedRowsForDayWithReturns();
    final trips = <({double delivered, double collected})>[];
    double delivered = 0, collected = 0;
    for (final row in rows) {
      if (row.isBreak) continue;
      if (row.isReturnToQuarry || row.isReloadAtQuarry) {
        if (delivered > 0 || collected > 0) trips.add((delivered: delivered, collected: collected));
        delivered = 0;
        collected = 0;
        if (row.isReloadAtQuarry) continue;
        continue;
      }
      if (_includedInSchedule[row.bookingId] == false) continue;
      final b = row.booking!;
      final q = (b['concrete_qty'] is num) ? (b['concrete_qty'] as num).toDouble() : double.tryParse(b['concrete_qty']?.toString() ?? '') ?? 0;
      if (b['delivered'] == true) {
        delivered += q;
      } else {
        collected += q;
      }
    }
    if (delivered > 0 || collected > 0) trips.add((delivered: delivered, collected: collected));
    return trips;
  }

  /// Load quantity rows for table: one "Collected" row (if any), then "Trip 1", "Trip 2", ... for delivered. Each has label, qty, tripIndex for map/distance (null for Collected).
  /// tripIndex is the raw segment index (0-based) so distance/time lookups match _waypointsForTrip(i).
  List<({String label, double qty, int? tripIndex})> _loadQuantityRows() {
    final trips = _tripQuantitiesFromOrderedRowsRaw();
    final result = <({String label, double qty, int? tripIndex})>[];
    double totalCollected = 0;
    int deliveredTripNumber = 0;
    for (int i = 0; i < trips.length; i++) {
      final t = trips[i];
      if (t.collected > 0) totalCollected += t.collected;
      if (t.delivered > 0) {
        deliveredTripNumber++;
        result.add((label: 'Trip $deliveredTripNumber', qty: t.delivered, tripIndex: i));
      }
    }
    if (totalCollected > 0) {
      result.insert(0, (label: 'Collected', qty: totalCollected, tripIndex: null));
    }
    return result;
  }

  /// Quantity per load/trip for the selected day (from calendar events: each Loading starts a new trip).
  List<double> _tripQuantitiesForSelectedDay() {
    if (_calendarEvents.isEmpty) return [];
    final qtyByBookingId = <String, double>{};
    for (final b in _bookings) {
      final id = b['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final q = b['concrete_qty'];
      if (q != null) qtyByBookingId[id] = (q is num) ? (q as num).toDouble() : (double.tryParse(q.toString()) ?? 0);
    }
    final sorted = List<Map<String, dynamic>>.from(_calendarEvents)
      ..sort((a, b) {
        final aStart = a['start_datetime']?.toString() ?? '';
        final bStart = b['start_datetime']?.toString() ?? '';
        return aStart.compareTo(bStart);
      });
    final trips = <double>[];
    double currentTripQty = 0;
    for (final e in sorted) {
      final type = e['type']?.toString() ?? '';
      if (type == 'Loading') {
        if (currentTripQty > 0) trips.add(currentTripQty);
        currentTripQty = 0;
      } else if (type == 'On Site') {
        final did = e['delivery_id']?.toString();
        if (did != null && did.isNotEmpty) currentTripQty += qtyByBookingId[did] ?? 0;
      }
    }
    if (currentTripQty > 0) trips.add(currentTripQty);
    return trips;
  }

  /// Waypoints for a trip (quarry + delivery coords in order + return to quarry) for View Trip map. Trip index 0-based.
  /// Uses same priority as schedule: custom coordinates first, then project coordinates.
  List<({double lat, double lng})> _waypointsForTrip(int tripIndex) {
    final waypoints = <({double lat, double lng})>[];
    if (_quarryLat == null || _quarryLng == null) return waypoints;
    waypoints.add((lat: _quarryLat!, lng: _quarryLng!));
    final rows = _orderedRowsForDayWithReturns();
    int currentTrip = 0;
    for (final row in rows) {
      if (row.isReloadAtQuarry || row.isBreak) continue;
      if (row.isReturnToQuarry) {
        currentTrip++;
        if (currentTrip > tripIndex) break;
        continue;
      }
      if (_includedInSchedule[row.bookingId] == false) continue;
      if (currentTrip != tripIndex) continue;
      if (row.booking == null) continue;
      final b = row.booking!;
      if (b['delivered'] == true) {
        final coords = _getDeliveryCoords(b);
        if (coords.lat != null && coords.lng != null) waypoints.add((lat: coords.lat!, lng: coords.lng!));
      }
    }
    if (waypoints.length > 1) waypoints.add((lat: _quarryLat!, lng: _quarryLng!));
    return waypoints;
  }

  void _openTripMap(int tripIndex) {
    final waypoints = _waypointsForTrip(tripIndex);
    if (waypoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No route for this trip.')));
      return;
    }
    final origin = '${waypoints.first.lat},${waypoints.first.lng}';
    final destination = '${waypoints.last.lat},${waypoints.last.lng}';
    final waypointsParam = waypoints.length > 2
        ? waypoints.skip(1).take(waypoints.length - 2).map((w) => '${w.lat},${w.lng}').join('|')
        : '';
    final url = waypointsParam.isEmpty
        ? 'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination'
        : 'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&waypoints=$waypointsParam';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _deriveSequenceFromCalendar(List<Map<String, dynamic>> events) {
    final onSite = events.where((e) => e['type']?.toString() == 'On Site').toList();
    onSite.sort((a, b) {
      final aStart = a['start_datetime']?.toString() ?? '';
      final bStart = b['start_datetime']?.toString() ?? '';
      return aStart.compareTo(bStart);
    });
    final newSeq = <String, int>{};
    int seq = 1;
    for (final e in onSite) {
      final did = e['delivery_id']?.toString();
      if (did != null && did.isNotEmpty) {
        newSeq[did] = seq++;
        _includedInSchedule.putIfAbsent(did, () => true);
      }
    }
    setState(() {
      _sequenceByBookingId.clear();
      _sequenceByBookingId.addAll(newSeq);
    });
  }

  /// Bookings for selected day, sorted by time (lowest at top).
  List<Map<String, dynamic>> _bookingsForSelectedDay() {
    if (_selectedDay == null) return [];
    final wd = _dayNameToWeekday(_selectedDay!);
    final list = _bookings.where((b) {
      final due = b['due_date_time'];
      if (due == null) return false;
      return DateTime.parse(due.toString()).weekday == wd;
    }).toList();
    list.sort((a, b) {
      final ad = a['due_date_time']?.toString() ?? '';
      final bd = b['due_date_time']?.toString() ?? '';
      return ad.compareTo(bd);
    });
    return list;
  }

  static const String _autoEndReturnKey = '__return_to_quarry__end';

  /// True when at least one booking (not return/reload placeholder) has a sequence number.
  bool _hasSequencePlanned() {
    for (final b in _bookingsForSelectedDay()) {
      final id = b['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if ((_sequenceByBookingId[id] ?? 0) >= 1) return true;
    }
    return false;
  }

  /// Ordered rows: bookings (by time) + reload placeholders + return-to-quarry placeholders + auto end return; sorted by sequence.
  /// Return-to-quarry rows are excluded until sequence is planned (so table doesn't show them until user has entered sequence).
  List<_SchedulerRow> _orderedRowsForDay() {
    final bookings = _bookingsForSelectedDay();
    final rows = <_SchedulerRow>[];
    for (final b in bookings) {
      final id = b['id']?.toString() ?? '';
      rows.add(_SchedulerRow(bookingId: id, booking: b));
    }
    for (final key in _reloadAtQuarryInsertedAt) {
      rows.add(_SchedulerRow(bookingId: key, booking: null, isReloadAtQuarry: true));
    }
    for (final key in _breakInsertedAt) {
      rows.add(_SchedulerRow(bookingId: key, booking: null, isBreak: true));
    }
    final includeReturnRows = _hasSequencePlanned();
    if (includeReturnRows) {
      for (final key in _returnToQuarryInsertedAt) {
        rows.add(_SchedulerRow(bookingId: key, booking: null, isReturnToQuarry: true));
      }
      rows.add(_SchedulerRow(bookingId: _autoEndReturnKey, booking: null, isReturnToQuarry: true));
    }
    final maxSeq = rows.where((r) => r.bookingId != _autoEndReturnKey).fold<int>(0, (m, r) {
      final s = _sequenceByBookingId[r.bookingId] ?? 0;
      return s > m ? s : m;
    });
    rows.sort((a, b) {
      final aSeq = a.bookingId == _autoEndReturnKey ? maxSeq + 1 : (_sequenceByBookingId[a.bookingId] ?? 9999);
      final bSeq = b.bookingId == _autoEndReturnKey ? maxSeq + 1 : (_sequenceByBookingId[b.bookingId] ?? 9999);
      if (aSeq != bSeq) return aSeq.compareTo(bSeq);
      return a.bookingId.compareTo(b.bookingId);
    });
    return rows;
  }

  /// Same as _orderedRowsForDay but always includes return rows (for Update Schedule and trip quantities).
  List<_SchedulerRow> _orderedRowsForDayWithReturns() {
    final bookings = _bookingsForSelectedDay();
    final rows = <_SchedulerRow>[];
    for (final b in bookings) {
      final id = b['id']?.toString() ?? '';
      rows.add(_SchedulerRow(bookingId: id, booking: b));
    }
    for (final key in _reloadAtQuarryInsertedAt) {
      rows.add(_SchedulerRow(bookingId: key, booking: null, isReloadAtQuarry: true));
    }
    for (final key in _breakInsertedAt) {
      rows.add(_SchedulerRow(bookingId: key, booking: null, isBreak: true));
    }
    for (final key in _returnToQuarryInsertedAt) {
      rows.add(_SchedulerRow(bookingId: key, booking: null, isReturnToQuarry: true));
    }
    rows.add(_SchedulerRow(bookingId: _autoEndReturnKey, booking: null, isReturnToQuarry: true));
    final maxSeq = rows.where((r) => r.bookingId != _autoEndReturnKey).fold<int>(0, (m, r) {
      final s = _sequenceByBookingId[r.bookingId] ?? 0;
      return s > m ? s : m;
    });
    rows.sort((a, b) {
      final aSeq = a.bookingId == _autoEndReturnKey ? maxSeq + 1 : (_sequenceByBookingId[a.bookingId] ?? 9999);
      final bSeq = b.bookingId == _autoEndReturnKey ? maxSeq + 1 : (_sequenceByBookingId[b.bookingId] ?? 9999);
      if (aSeq != bSeq) return aSeq.compareTo(bSeq);
      return a.bookingId.compareTo(b.bookingId);
    });
    return rows;
  }

  void _onDaySelected(String day) {
    setState(() {
      _selectedDay = day;
      _scheduleStartOffsetMinutes = 0;
      _scheduleDayStatus = 'preview';
      _sequenceByBookingId.clear();
      _returnToQuarryInsertedAt.clear();
      _reloadAtQuarryInsertedAt.clear();
      _breakInsertedAt.clear();
      _calendarEvents = [];
      _previewCalendarEvents = [];
      _tripDistancesKm = [];
      _tripTravelMinutes = [];
      for (final b in _bookingsForSelectedDay()) {
        final id = b['id']?.toString() ?? '';
        if (id.isNotEmpty) _includedInSchedule.putIfAbsent(id, () => true);
      }
    });
    _loadCalendarForSelectedDay();
  }

  void _insertReturnToQuarry() {
    setState(() {
      final key = '${_returnToQuarryKey}_${DateTime.now().millisecondsSinceEpoch}';
      _returnToQuarryInsertedAt.add(key);
      final maxSeq = _sequenceByBookingId.values.isEmpty ? 0 : _sequenceByBookingId.values.reduce((a, b) => a > b ? a : b);
      _sequenceByBookingId[key] = maxSeq + 1;
    });
  }

  void _removeReturnToQuarry(String key) {
    if (key == _autoEndReturnKey) return;
    setState(() {
      _returnToQuarryInsertedAt.remove(key);
      _sequenceByBookingId.remove(key);
    });
  }

  void _insertReloadAtQuarry() {
    // Validation that Reload comes after a Collected load is done only when Update Schedule is clicked.
    final rows = _orderedRowsForDayWithReturns();
    int? lastCollectedSeq;
    for (final row in rows) {
      if (row.isReturnToQuarry || row.isReloadAtQuarry) continue;
      if (_includedInSchedule[row.bookingId] == false) continue;
      if (row.booking != null && row.booking!['delivered'] != true) {
        lastCollectedSeq = _sequenceByBookingId[row.bookingId];
      }
    }
    final insertSeq = (lastCollectedSeq ?? 0) + 1;
    setState(() {
      final key = '${_reloadAtQuarryKey}_${DateTime.now().millisecondsSinceEpoch}';
      _reloadAtQuarryInsertedAt.add(key);
      _sequenceByBookingId[key] = insertSeq;
      for (final k in _sequenceByBookingId.keys.toList()) {
        if (k == key) continue;
        final s = _sequenceByBookingId[k]!;
        if (s >= insertSeq) _sequenceByBookingId[k] = s + 1;
      }
    });
  }

  void _removeReloadAtQuarry(String key) {
    setState(() {
      _reloadAtQuarryInsertedAt.remove(key);
      _sequenceByBookingId.remove(key);
    });
  }

  void _insertBreak() {
    setState(() {
      final key = '${_breakKey}_${DateTime.now().millisecondsSinceEpoch}';
      _breakInsertedAt.add(key);
      _sequenceByBookingId[key] = _nextAvailableSequence();
    });
  }

  void _removeBreak(String key) {
    setState(() {
      _breakInsertedAt.remove(key);
      _sequenceByBookingId.remove(key);
    });
  }

  /// Next sequence number (max in use + 1) for the current day's rows.
  int _nextAvailableSequence() {
    final rows = _orderedRowsForDayWithReturns();
    int maxSeq = 0;
    for (final r in rows) {
      final s = _sequenceByBookingId[r.bookingId] ?? 0;
      if (s > maxSeq) maxSeq = s;
    }
    return maxSeq + 1;
  }

  /// Assign the next available sequence to a row when it is clicked.
  void _assignNextSequenceToBooking(String bookingId) {
    final next = _nextAvailableSequence();
    setState(() => _sequenceByBookingId[bookingId] = next);
  }

  /// Clear all sequence numbers in the bookings table.
  void _clearAllSequences() {
    setState(() {
      _sequenceByBookingId.clear();
      _breakInsertedAt.clear();
    });
  }

  /// Last two characters of concrete_mix name for a booking (from public.concrete_mix.name via _concreteMixNames).
  String _mixNameLastTwo(Map<String, dynamic> b) {
    final mixId = b['concrete_mix_type']?.toString();
    final name = _concreteMixNames[mixId] ?? '';
    if (name.length >= 2) return name.substring(name.length - 2);
    return name;
  }

  /// Validate that within each trip, all delivered bookings have the same last-two digits in concrete_mix name.
  /// Returns error message if any trip has mixed mixes; null if ok.
  String? _validateMixConsistencyPerTrip() {
    final rows = _orderedRowsForDayWithReturns();
    final tripMixLastTwo = <String>{};
    for (final row in rows) {
      if (row.isReturnToQuarry || row.isReloadAtQuarry) {
        if (tripMixLastTwo.length > 1) {
          final mixList = tripMixLastTwo.toList()..sort();
          return 'This trip has deliveries with different concrete mix types (last two digits: ${mixList.join(", ")}). '
              'All deliveries in a single trip must use the same mix. Please change the mix on the bookings so they match.';
        }
        tripMixLastTwo.clear();
        continue;
      }
      if (row.isBreak) continue;
      if (_includedInSchedule[row.bookingId] == false) continue;
      final b = row.booking;
      if (b == null) continue;
      if (b['delivered'] == true) {
        tripMixLastTwo.add(_mixNameLastTwo(b));
      }
    }
    if (tripMixLastTwo.length > 1) {
      final mixList = tripMixLastTwo.toList()..sort();
      return 'This trip has deliveries with different concrete mix types (last two digits: ${mixList.join(", ")}). '
          'All deliveries in a single trip must use the same mix. Please change the mix on the bookings so they match.';
    }
    return null;
  }

  /// Validate sequence: 1..n consecutive, no duplicates
  String? _validateSequence() {
    final rows = _orderedRowsForDayWithReturns();
    final used = <int>{};
    for (final r in rows) {
      final seq = _sequenceByBookingId[r.bookingId];
      if (seq == null || seq < 1) return 'Every row must have a sequence number (1, 2, 3, ...).';
      if (used.contains(seq)) return 'Duplicate sequence $seq. Numbers must be unique.';
      used.add(seq);
    }
    if (used.isEmpty) return null;
    final sorted = used.toList()..sort();
    for (int i = 0; i < sorted.length; i++) {
      if (sorted[i] != i + 1) return 'Sequence numbers must be consecutive starting from 1 (found ${sorted[i]}).';
    }
    return null;
  }

  Future<void> _incrementApiCallCounter() async {
    try {
      final settings = await SupabaseService.client.from('system_settings').select('id, google_api_calls').limit(1).maybeSingle();
      if (settings != null) {
        final current = (settings['google_api_calls'] as int?) ?? 0;
        await SupabaseService.client.from('system_settings').update({'google_api_calls': current + 1}).eq('id', settings['id'] as Object);
      } else {
        await SupabaseService.client.from('system_settings').insert({'google_api_calls': 1, 'google_api_saves': 0, 'week_start': 1});
      }
    } catch (_) {}
  }

  Future<void> _incrementApiSaveCounter() async {
    try {
      final settings = await SupabaseService.client.from('system_settings').select('id, google_api_saves').limit(1).maybeSingle();
      if (settings != null) {
        final current = (settings['google_api_saves'] as int?) ?? 0;
        await SupabaseService.client.from('system_settings').update({'google_api_saves': current + 1}).eq('id', settings['id'] as Object);
      }
    } catch (_) {}
  }

  /// Returns travel time in minutes (with buffer and 15-min rounding). Optional [departureTime] requests traffic-aware duration from the API (not cached).
  Future<int?> _getTravelMinutes(double fromLat, double fromLng, double toLat, double toLng, {DateTime? departureTime}) async {
    final useTraffic = departureTime != null;
    if (!useTraffic) {
      try {
        final cached = await SupabaseService.client
            .from('google_api_calls')
            .select('travel_time_minutes, distance_kilometers')
            .eq('home_latitude', fromLat)
            .eq('home_longitude', fromLng)
            .eq('project_latitude', toLat)
            .eq('project_longitude', toLng)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (cached != null) {
          final min = cached['travel_time_minutes'] as int?;
          if (min != null) {
            await _incrementApiSaveCounter();
            double? distanceKm;
            final d = cached['distance_kilometers'];
            if (d != null) distanceKm = (d is num) ? (d as num).toDouble() : double.tryParse(d.toString());
            final capped = _applyMaxSpeedCap(min, distanceKm);
            return _applyTravelBufferAndRound(capped);
          }
        }
      } catch (_) {}
    }
    await _incrementApiCallCounter();
    final body = <String, dynamic>{
      'home_latitude': fromLat,
      'home_longitude': fromLng,
      'project_latitude': toLat,
      'project_longitude': toLng,
    };
    if (useTraffic) {
      body['departure_time'] = departureTime!.toUtc().millisecondsSinceEpoch ~/ 1000;
    }
    final response = await SupabaseService.client.functions.invoke('get_directions', body: body);
    if (response.status == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final min = data['travel_time_minutes'] as int?;
        if (min != null) {
          double? distanceKm;
          final d = data['distance_kilometers'];
          if (d != null) distanceKm = (d is num) ? (d as num).toDouble() : double.tryParse(d.toString());
          final capped = _applyMaxSpeedCap(min, distanceKm);
          if (!useTraffic) {
            try {
              await SupabaseService.client.from('google_api_calls').insert({
                'home_latitude': fromLat,
                'home_longitude': fromLng,
                'project_latitude': toLat,
                'project_longitude': toLng,
                'travel_time_minutes': min,
                'distance_kilometers': data['distance_kilometers'] ?? 0,
                'time_stamp': DateTime.now().toIso8601String(),
                'was_cached': false,
              });
            } catch (_) {}
          }
          return _applyTravelBufferAndRound(capped);
        }
      }
    }
    return null;
  }

  Future<double?> _getTravelDistanceKm(double fromLat, double fromLng, double toLat, double toLng) async {
    try {
      final cached = await SupabaseService.client
          .from('google_api_calls')
          .select('distance_kilometers')
          .eq('home_latitude', fromLat)
          .eq('home_longitude', fromLng)
          .eq('project_latitude', toLat)
          .eq('project_longitude', toLng)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (cached != null) {
        final km = cached['distance_kilometers'];
        if (km != null) return (km is num) ? (km as num).toDouble() : double.tryParse(km.toString());
      }
    } catch (_) {}
    final response = await SupabaseService.client.functions.invoke('get_directions', body: {
      'home_latitude': fromLat,
      'home_longitude': fromLng,
      'project_latitude': toLat,
      'project_longitude': toLng,
    });
    if (response.status == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final km = data['distance_kilometers'];
        if (km != null) return (km is num) ? (km as num).toDouble() : double.tryParse(km.toString());
      }
    }
    return null;
  }

  Future<double> _getTripDistanceKm(int tripIndex) async {
    final waypoints = _waypointsForTrip(tripIndex);
    if (waypoints.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      final d = await _getTravelDistanceKm(
        waypoints[i].lat, waypoints[i].lng,
        waypoints[i + 1].lat, waypoints[i + 1].lng,
      );
      if (d != null) total += d;
    }
    final back = await _getTravelDistanceKm(
      waypoints.last.lat, waypoints.last.lng,
      waypoints.first.lat, waypoints.first.lng,
    );
    if (back != null) total += back;
    return total;
  }

  /// Total travel time for trip including return to quarry (minutes).
  Future<int> _getTripTravelMinutes(int tripIndex) async {
    final waypoints = _waypointsForTrip(tripIndex);
    if (waypoints.length < 2) return 0;
    int total = 0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      final m = await _getTravelMinutes(
        waypoints[i].lat, waypoints[i].lng,
        waypoints[i + 1].lat, waypoints[i + 1].lng,
      );
      if (m != null) total += m;
    }
    final back = await _getTravelMinutes(
      waypoints.last.lat, waypoints.last.lng,
      waypoints.first.lat, waypoints.first.lng,
    );
    if (back != null) total += back;
    return total;
  }

  /// Add quarry_travel buffer and round to nearest 15 minutes.
  int _applyTravelBufferAndRound(int minutes) {
    final withBuffer = minutes + _quarryTravelBufferMinutes;
    return ((withBuffer + 7) ~/ 15) * 15;
  }

  /// If travel_max_speed_kmh is set, return minutes >= (distanceKm / maxSpeed) so average speed is never above max. Else return rawMinutes.
  int _applyMaxSpeedCap(int rawMinutes, double? distanceKm) {
    if (_travelMaxSpeedKmh == null || _travelMaxSpeedKmh! <= 0 || distanceKm == null || distanceKm <= 0) return rawMinutes;
    final minMinutes = (distanceKm / _travelMaxSpeedKmh!) * 60;
    final capped = minMinutes.ceil();
    return rawMinutes > capped ? rawMinutes : capped;
  }

  /// Compute start offset so the first booking's scheduled arrival matches its due_date_time. Returns offset in minutes (0 if no first booking/due).
  int _computeStartOffsetFromFirstBooking(List<Map<String, dynamic>> events) {
    final rows = _orderedRowsForDayWithReturns();
    String? firstBookingId;
    DateTime? firstDue;
    for (final row in rows) {
      if (row.isReturnToQuarry || row.isReloadAtQuarry) continue;
      if (_includedInSchedule[row.bookingId] == false) continue;
      final b = row.booking;
      if (b == null) continue;
      final due = b['due_date_time']?.toString();
      if (due == null || due.isEmpty) continue;
      firstBookingId = row.bookingId;
      try {
        firstDue = DateTime.parse(due);
      } catch (_) {
        return 0;
      }
      break;
    }
    if (firstBookingId == null || firstDue == null) return 0;
    DateTime? firstEventStart;
    for (final e in events) {
      final did = e['delivery_id']?.toString();
      if (did == firstBookingId) {
        final start = e['start_datetime']?.toString();
        if (start != null) {
          try {
            firstEventStart = DateTime.parse(start);
          } catch (_) {}
        }
        break;
      }
    }
    if (firstEventStart == null) return 0;
    return firstDue.difference(firstEventStart).inMinutes;
  }

  /// Validate Reload at Quarry: each must come after a Collected load (in sequence order). Call only when Update Schedule is clicked.
  String? _validateReloadAfterCollected() {
    final rows = _orderedRowsForDayWithReturns();
    bool seenCollected = false;
    for (final row in rows) {
      if (row.isReturnToQuarry) continue;
      if (row.isReloadAtQuarry) {
        if (!seenCollected) return 'Reload at Quarry can only be inserted after a collected load.';
        continue;
      }
      if (_includedInSchedule[row.bookingId] == false) continue;
      if (row.booking != null && row.booking!['delivered'] != true) seenCollected = true;
    }
    return null;
  }

  /// Google Calendar fields for an On Site event: description (4 lines), location (maps link), color_id (9=blue Delivered, 6=orange Collected).
  /// Location order: 1) If delivered=false use quarry GPS; 2) If custom_lat/lng set use them + add "Custom Coordinates provided"; 3) Else project lat/lng.
  Map<String, dynamic> _googleCalendarFieldsForBooking(Map<String, dynamic> b, double? projectLat, double? projectLng) {
    final mixId = b['concrete_mix_type']?.toString();
    final mixName = _concreteMixNames[mixId] ?? '—';
    final qty = (b['concrete_qty'] is num) ? (b['concrete_qty'] as num).toDouble() : double.tryParse(b['concrete_qty']?.toString() ?? '') ?? 0;
    final siteContactId = b['site_contact_id']?.toString();
    final siteContact = _siteContactNames[siteContactId] ?? '—';
    final note = b['comments']?.toString().trim() ?? '';
    final delivered = b['delivered'] == true;

    // Location: 1) Collected → quarry; 2) custom_lat/custom_lng → use them + note; 3) else project coords
    double? lat;
    double? lng;
    bool usedCustomCoords = false;
    if (!delivered && _quarryLat != null && _quarryLng != null) {
      lat = _quarryLat;
      lng = _quarryLng;
    } else {
      final cLat = b['custom_lat'];
      final cLng = b['custom_lng'];
      if (cLat != null && cLng != null) {
        final clat = (cLat is num) ? (cLat as num).toDouble() : double.tryParse(cLat.toString());
        final clng = (cLng is num) ? (cLng as num).toDouble() : double.tryParse(cLng.toString());
        if (clat != null && clng != null) {
          lat = clat;
          lng = clng;
          usedCustomCoords = true;
        }
      }
      if (lat == null || lng == null) {
        if (projectLat != null && projectLng != null) {
          lat = projectLat;
          lng = projectLng;
        } else {
          final coords = _projectCoords[b['project_id']?.toString()];
          if (coords != null) {
            lat = coords['lat'] as double?;
            lng = coords['lng'] as double?;
          }
        }
      }
    }
    final location = (lat != null && lng != null) ? 'https://www.google.com/maps?q=$lat,$lng' : null;

    final lines = <String>[
      'Mix Type: $mixName',
      'Quantity: ${_formatQuantityTwoDecimals(qty)}',
      'Site Contact: $siteContact',
      if (note.isNotEmpty) 'Note: $note',
      if (usedCustomCoords) 'Custom Coordinates provided',
    ];
    final description = lines.join('\n');

    // 9 = blue (Delivered), 6 = orange (Collected or mix name ending "10")
    final colorId = mixName.endsWith('10') ? '6' : (delivered ? '9' : '6');
    return {'description': description, 'location': location, 'color_id': colorId};
  }

  /// Coordinates for a delivered booking: custom_lat/custom_lng first, then project. Returns (lat, lng) or (null, null).
  ({double? lat, double? lng}) _getDeliveryCoords(Map<String, dynamic> b) {
    final cLat = b['custom_lat'];
    final cLng = b['custom_lng'];
    if (cLat != null && cLng != null) {
      final clat = (cLat is num) ? (cLat as num).toDouble() : double.tryParse(cLat.toString());
      final clng = (cLng is num) ? (cLng as num).toDouble() : double.tryParse(cLng.toString());
      if (clat != null && clng != null) return (lat: clat, lng: clng);
    }
    final projectId = b['project_id']?.toString();
    final coords = projectId != null ? _projectCoords[projectId] : null;
    final lat = coords?['lat'] as double?;
    final lng = coords?['lng'] as double?;
    return (lat: lat, lng: lng);
  }

  /// Build schedule events (same logic as Save) for preview or for DB. Returns events and optional error (coordinates missing).
  /// [startOffsetMinutes] offset from 6:00 in minutes (defaults to _scheduleStartOffsetMinutes).
  Future<({List<Map<String, dynamic>>? events, String? coordinateError})> _buildScheduleEvents({int? startOffsetMinutes}) async {
    final allRows = _orderedRowsForDayWithReturns();
    final rows = allRows.where((row) {
      if (row.isReturnToQuarry || row.isReloadAtQuarry || row.isBreak) return true;
      return _includedInSchedule[row.bookingId] != false;
    }).toList();
    if (rows.isEmpty) return (events: <Map<String, dynamic>>[], coordinateError: null);
    final weekday = _dayNameToWeekday(_selectedDay!);
    final dayDate = _selectedWeekStart.add(Duration(days: weekday - 1));
    final offset = startOffsetMinutes ?? _scheduleStartOffsetMinutes;
    final startAt = DateTime(dayDate.year, dayDate.month, dayDate.day, 6, 0, 0).add(Duration(minutes: offset));
    final events = <Map<String, dynamic>>[];
    DateTime currentTime = startAt;
    double loadRemaining = _maxLoadCapacity;
    double collectedSinceLoad = 0;
    double? lastLat = _quarryLat;
    double? lastLng = _quarryLng;
    bool firstDelivery = true;

    // First item in calendar is always "Loading at quarry" (duration from system_settings.loading_time)
    final firstLoadEnd = currentTime.add(Duration(minutes: _loadingTimeMinutes));
    events.add({
      'summary': 'Loading at quarry',
      'start_datetime': currentTime.toUtc().toIso8601String(),
      'end_datetime': firstLoadEnd.toUtc().toIso8601String(),
      'type': 'Loading',
      'delivery_id': null,
    });
    currentTime = firstLoadEnd;

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final isLastRow = rowIndex == rows.length - 1;
      if (row.isReloadAtQuarry) {
        final reloadEnd = currentTime.add(Duration(minutes: _loadingTimeMinutes));
        events.add({
          'summary': 'Reload at quarry',
          'start_datetime': currentTime.toUtc().toIso8601String(),
          'end_datetime': reloadEnd.toUtc().toIso8601String(),
          'type': 'Loading',
          'delivery_id': null,
        });
        currentTime = reloadEnd;
        loadRemaining = _maxLoadCapacity;
        collectedSinceLoad = 0;
        continue;
      }
      if (row.isBreak) {
        final breakEnd = currentTime.add(const Duration(minutes: 30));
        events.add({
          'summary': 'Break',
          'start_datetime': currentTime.toUtc().toIso8601String(),
          'end_datetime': breakEnd.toUtc().toIso8601String(),
          'type': 'Break',
          'delivery_id': null,
          'color_id': '10', // Google Calendar green
        });
        currentTime = breakEnd;
        continue;
      }
      if (row.isReturnToQuarry) {
        firstDelivery = false;
        collectedSinceLoad = 0;
        final travelMin = await _getTravelMinutes(lastLat!, lastLng!, _quarryLat!, _quarryLng!, departureTime: currentTime);
        if (travelMin != null) {
          final end = currentTime.add(Duration(minutes: travelMin));
          events.add({
            'summary': 'Travelling (to quarry)',
            'start_datetime': currentTime.toUtc().toIso8601String(),
            'end_datetime': end.toUtc().toIso8601String(),
            'type': 'Travelling',
            'delivery_id': null,
          });
          currentTime = end;
        }
        if (!isLastRow) {
          final loadEnd = currentTime.add(Duration(minutes: _loadingTimeMinutes));
          events.add({
            'summary': 'Loading at quarry',
            'start_datetime': currentTime.toUtc().toIso8601String(),
            'end_datetime': loadEnd.toUtc().toIso8601String(),
            'type': 'Loading',
            'delivery_id': null,
          });
          currentTime = loadEnd;
        }
        loadRemaining = _maxLoadCapacity;
        lastLat = _quarryLat;
        lastLng = _quarryLng;
        continue;
      }

      final b = row.booking!;
      final delivered = b['delivered'] == true;
      final projectId = b['project_id']?.toString();
      final qty = (b['concrete_qty'] is num) ? (b['concrete_qty'] as num).toDouble() : double.tryParse(b['concrete_qty']?.toString() ?? '') ?? 0;
      if (qty > _maxLoadCapacity) continue;
      final isOverCapacity = delivered && loadRemaining < qty;

      if (!delivered) {
        // Collected: location is the quarry, so no travel — one task block at quarry linked to booking so it appears on calendar and in Scheduled.
        firstDelivery = false;
        collectedSinceLoad += qty;
        final loadEnd = currentTime.add(const Duration(hours: 1));
        final projectName = _projectNames[projectId] ?? _projectNumbers[projectId] ?? '—';
        final googleFields = _googleCalendarFieldsForBooking(b, null, null);
        events.add({
          'summary': projectName,
          'description': googleFields['description'],
          'start_datetime': currentTime.toUtc().toIso8601String(),
          'end_datetime': loadEnd.toUtc().toIso8601String(),
          'type': 'On Site',
          'delivery_id': b['id'],
          'location': googleFields['location'],
          'color_id': googleFields['color_id'],
        });
        currentTime = loadEnd;
        if (_washTimeMinutes > 0) {
          final washEnd = currentTime.add(Duration(minutes: _washTimeMinutes));
          events.add({
            'summary': 'Wash',
            'start_datetime': currentTime.toUtc().toIso8601String(),
            'end_datetime': washEnd.toUtc().toIso8601String(),
            'type': 'Wash',
            'delivery_id': null,
          });
          currentTime = washEnd;
        }
        loadRemaining = _maxLoadCapacity;
        lastLat = _quarryLat;
        lastLng = _quarryLng;
        continue;
      }

      final deliveryCoords = _getDeliveryCoords(b);
      final projectLat = deliveryCoords.lat;
      final projectLng = deliveryCoords.lng;
      final hasCoords = projectLat != null && projectLng != null;

      if (!hasCoords) {
        final projectName = _projectNames[projectId] ?? _projectNumbers[projectId] ?? 'Job';
        return (
          events: null,
          coordinateError: 'Coordinates are missing for "$projectName". Please add custom coordinates to the booking or set coordinates for the project. Scheduling halted.',
        );
      }

      if (firstDelivery) {
        firstDelivery = false;
      }

      if (hasCoords) {
        final travelMin = await _getTravelMinutes(lastLat!, lastLng!, projectLat!, projectLng!, departureTime: currentTime);
        if (travelMin != null) {
          // Align scheduled arrival to booked (due) time when possible; only extend when travel would be too short.
          DateTime? bookedTime;
          final due = b['due_date_time']?.toString();
          if (due != null && due.isNotEmpty) {
            try {
              bookedTime = DateTime.parse(due);
            } catch (_) {}
          }
          final earliestArrival = currentTime.add(Duration(minutes: travelMin));
          final scheduledArrival = (bookedTime != null && bookedTime.isAfter(earliestArrival))
              ? bookedTime
              : earliestArrival;
          final actualTravelStart = scheduledArrival.subtract(Duration(minutes: travelMin));
          final travelStart = actualTravelStart.isBefore(currentTime) ? currentTime : actualTravelStart;
          final travelEnd = travelStart.add(Duration(minutes: travelMin));
          // Show gap as a separate "Waiting" block when we delay travel to hit the booked time.
          if (travelStart.isAfter(currentTime)) {
            events.add({
              'summary': 'Waiting',
              'start_datetime': currentTime.toUtc().toIso8601String(),
              'end_datetime': travelStart.toUtc().toIso8601String(),
              'type': 'Waiting',
              'delivery_id': null,
            });
          }
          events.add({
            'summary': 'Travelling to site',
            'start_datetime': travelStart.toUtc().toIso8601String(),
            'end_datetime': travelEnd.toUtc().toIso8601String(),
            'type': 'Travelling',
            'delivery_id': null,
          });
          currentTime = travelEnd;
        }
      }

      final durationOnSite = (b['duration_on_site'] as int?) ?? 0;
      final onSiteEnd = currentTime.add(Duration(minutes: durationOnSite));
      final projectName = _projectNames[projectId] ?? _projectNumbers[projectId] ?? '—';
      final googleFields = _googleCalendarFieldsForBooking(b, projectLat, projectLng);
      events.add({
        'summary': projectName,
        'description': googleFields['description'],
        'start_datetime': currentTime.toUtc().toIso8601String(),
        'end_datetime': onSiteEnd.toUtc().toIso8601String(),
        'type': 'On Site',
        'delivery_id': b['id'],
        'location': googleFields['location'],
        'color_id': googleFields['color_id'],
        if (isOverCapacity) 'over_capacity': true,
      });
      currentTime = onSiteEnd;
      if (_washTimeMinutes > 0) {
        final washEnd = currentTime.add(Duration(minutes: _washTimeMinutes));
        events.add({
          'summary': 'Wash',
          'start_datetime': currentTime.toUtc().toIso8601String(),
          'end_datetime': washEnd.toUtc().toIso8601String(),
          'type': 'Wash',
          'delivery_id': null,
        });
        currentTime = washEnd;
      }
      loadRemaining -= qty;
      lastLat = projectLat;
      lastLng = projectLng;
    }
    return (events: events, coordinateError: null);
  }

  /// Update: validate and build schedule preview (no DB write). Displays schedule in calendar panel for editing.
  Future<void> _onUpdate() async {
    final err = _validateSequence();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.orange));
      return;
    }
    final mixErr = _validateMixConsistencyPerTrip();
    if (mixErr != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mixed concrete mix in trip'),
          content: Text(mixErr),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    final reloadErr = _validateReloadAfterCollected();
    if (reloadErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reloadErr), backgroundColor: Colors.orange));
      return;
    }
    final loadRows = _loadQuantityRows();
    final overCapacityTripNumbers = <int>[];
    for (final r in loadRows) {
      if (r.tripIndex != null && r.qty > _maxLoadCapacity) {
        overCapacityTripNumbers.add(r.tripIndex! + 1);
      }
    }
    if (overCapacityTripNumbers.isNotEmpty) {
      final tripList = overCapacityTripNumbers.length == 1
          ? 'Trip ${overCapacityTripNumbers.single}'
          : 'Trips ${overCapacityTripNumbers.join(', ')}';
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Trip over maximum load'),
          content: Text(
            '$tripList ${overCapacityTripNumbers.length == 1 ? "has" : "have"} exceeded the maximum load quantity, please edit the booking / trip to be within the maximum of 8 Cu. M.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
    if (_selectedDay == null) return;
    if (_quarryLat == null || _quarryLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quarry GPS not set in system_settings.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isUpdating = true);
    try {
      var result = await _buildScheduleEvents(startOffsetMinutes: 0);
      if (result.coordinateError != null) {
        if (mounted) setState(() => _isUpdating = false);
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Coordinates missing'),
            content: Text(result.coordinateError!),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        return;
      }
      List<Map<String, dynamic>> events = result.events!;
      final offset = _computeStartOffsetFromFirstBooking(events);
      if (offset != 0) {
        result = await _buildScheduleEvents(startOffsetMinutes: offset);
        if (result.coordinateError != null) {
          if (mounted) setState(() => _isUpdating = false);
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Coordinates missing'),
              content: Text(result.coordinateError!),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
          return;
        }
        events = result.events!;
      }
      if (mounted) {
        setState(() {
          _scheduleStartOffsetMinutes = offset;
          _previewCalendarEvents = events;
          _scheduleDayStatus = 'preview';
          _bookingTableSortMode = 'seq';
          _isUpdating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schedule preview updated. Use Save to write to calendar.'), backgroundColor: Colors.green));
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'ConcreteMixSchedulerScreen._onUpdate', type: 'Update', description: '$e', stackTrace: st);
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Save: write schedule to concrete_mix_calendar for the selected day (uses same events as Update preview).
  Future<void> _onSave() async {
    final err = _validateSequence();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.orange));
      return;
    }
    final mixErr = _validateMixConsistencyPerTrip();
    if (mixErr != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mixed concrete mix in trip'),
          content: Text(mixErr),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    final reloadErr = _validateReloadAfterCollected();
    if (reloadErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reloadErr), backgroundColor: Colors.orange));
      return;
    }
    if (_selectedDay == null) return;
    if (_quarryLat == null || _quarryLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quarry GPS not set in system_settings.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final result = await _buildScheduleEvents();
      if (result.coordinateError != null) {
        if (mounted) setState(() => _isSaving = false);
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Coordinates missing'),
            content: Text(result.coordinateError!),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        return;
      }
      final events = result.events ?? [];
      if (events.isEmpty && mounted) {
        setState(() => _isSaving = false);
        return;
      }
      final weekday = _dayNameToWeekday(_selectedDay!);
      final dayDate = _selectedWeekStart.add(Duration(days: weekday - 1));
      final driverId = AuthService.getCurrentUser()?.id;
      final dayStart = DateTime(dayDate.year, dayDate.month, dayDate.day, 0, 0, 0);
      final dayEnd = DateTime(dayDate.year, dayDate.month, dayDate.day, 23, 59, 59);
      final existing = await SupabaseService.client
          .from('concrete_mix_calendar')
          .select('id')
          .gte('start_datetime', dayStart.toUtc().toIso8601String())
          .lte('start_datetime', dayEnd.toUtc().toIso8601String());
      for (final e in existing as List) {
        await SupabaseService.client.from('concrete_mix_calendar').delete().eq('id', (e as Map)['id'] as Object);
      }
      // Save all task types to concrete_mix_calendar: Loading, Travelling, On Site, Wash, Waiting.
      for (final ev in events) {
        final taskType = ev['type']?.toString();
        await SupabaseService.client.from('concrete_mix_calendar').insert({
          'summary': ev['summary'],
          if (ev['description'] != null) 'description': ev['description'],
          if (ev['location'] != null) 'location': ev['location'],
          if (ev['color_id'] != null) 'color_id': ev['color_id'],
          'start_datetime': ev['start_datetime'],
          'end_datetime': ev['end_datetime'],
          if (taskType != null && taskType.isNotEmpty) 'task_type': taskType,
          'delivery_id': ev['delivery_id'],
          'driver_id': driverId,
          'calendar_id': _calendarId,
        });
        if (ev['delivery_id'] != null) {
          await SupabaseService.client.from('concrete_mix_bookings').update({'is_scheduled': true}).eq('id', ev['delivery_id'] as Object);
        }
      }
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schedule saved to calendar.'), backgroundColor: Colors.green));
        _loadCalendarForSelectedDay();
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'ConcreteMixSchedulerScreen._onSave', type: 'Schedule', description: '$e', stackTrace: st);
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Sync: push concrete_mix_calendar events to Google Calendar via edge function.
  Future<void> _onSync() async {
    if (_calendarId == null || _calendarId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Calendar ID not set in system_settings.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final dayStart = _selectedWeekStart;
    final dayEnd = _getWeekEnd(_selectedWeekStart);
    final startStr = DateTime(dayStart.year, dayStart.month, dayStart.day, 0, 0, 0).toUtc().toIso8601String();
    final endStr = DateTime(dayEnd.year, dayEnd.month, dayEnd.day, 23, 59, 59).toUtc().toIso8601String();
    setState(() => _isSyncing = true);
    try {
      final response = await SupabaseService.client.functions.invoke(
        'sync_google_calendar',
        body: <String, dynamic>{'day_start': startStr, 'day_end': endStr},
      );
      if (!mounted) return;
      if (response.status == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>?;
        if (data != null && data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synced to Google Calendar.'), backgroundColor: Colors.green));
          if (_selectedDay != null) _loadCalendarForSelectedDay();
        } else {
          final err = data?['error']?.toString() ?? 'Sync failed';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.orange));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sync failed: ${response.status}'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'ConcreteMixSchedulerScreen._onSync', type: 'Sync', description: '$e', stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
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
          title: const Text('Concrete Mix Scheduler', style: TextStyle(color: Colors.black)),
          centerTitle: true,
          backgroundColor: const Color(0xFF0081FB),
          foregroundColor: Colors.black,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(4.0),
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFFFEFE00)),
              child: SizedBox(height: 4.0),
            ),
          ),
          actions: const [ScreenInfoIcon(screenName: 'concrete_mix_scheduler_screen.dart')],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Concrete Mix Scheduler', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(4.0),
          child: DecoratedBox(
            decoration: BoxDecoration(color: Color(0xFFFEFE00)),
            child: SizedBox(height: 4.0),
          ),
        ),
        actions: const [ScreenInfoIcon(screenName: 'concrete_mix_scheduler_screen.dart')],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 600;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 50,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: _buildLeftContent(constraints.maxWidth * 0.5),
                  ),
                ),
                Expanded(
                  flex: 50,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    child: _buildCalendarSection(),
                  ),
                ),
              ],
            );
          }
          return PageView(
            controller: _mobilePageController,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: _buildLeftContent(constraints.maxWidth),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text('Swipe right for scheduler', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    _buildCalendarSection(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLeftContent(double availableWidth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildWeekSelector(),
        const SizedBox(height: 16),
        _buildWeekSummaryTable(),
        const SizedBox(height: 16),
        _buildLoadQuantitiesTable(),
        const SizedBox(height: 16),
        _buildDaySelectorWithButtons(),
        const SizedBox(height: 16),
        if (_selectedDay != null) _buildBookingsSection(),
      ],
    );
  }

  Widget _buildWeekSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: _previousWeek, tooltip: 'Previous Week'),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${DateFormat('MMM dd').format(_selectedWeekStart)} - ${DateFormat('MMM dd, yyyy').format(_getWeekEnd(_selectedWeekStart))}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (!_selectedWeekStart.isAtSameMomentAs(_getWeekStart(DateTime.now())))
                  TextButton(onPressed: _goToCurrentWeek, child: const Text('Go to Current Week')),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _nextWeek, tooltip: 'Next Week'),
        ],
      ),
    );
  }

  Widget _buildCalendarSection() {
    final dayHeader = _selectedDay != null
        ? _formatCalendarDayHeader(_selectedWeekStart.add(Duration(days: _dayNameToWeekday(_selectedDay!) - 1)))
        : 'Day calendar';
    final eventsToShow = _previewCalendarEvents.isNotEmpty ? _previewCalendarEvents : _calendarEvents;
    final isEmpty = eventsToShow.isEmpty && !_isUpdating;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(dayHeader, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _scheduleDayStatus == 'synced'
                ? 'Synced with Google Calendar'
                : _scheduleDayStatus == 'saved'
                    ? 'Saved'
                    : _previewCalendarEvents.isNotEmpty
                        ? 'Preview (not saved)'
                        : '',
            style: TextStyle(
              fontSize: 12,
              color: _scheduleDayStatus == 'synced' ? Colors.green[800] : _scheduleDayStatus == 'saved' ? Colors.blue[800] : Colors.orange[800],
              fontStyle: _scheduleDayStatus == 'preview' ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
          child: _isUpdating
              ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              : isEmpty
                  ? const Center(child: Text('No events. Use Update to preview, Save to add entries.', textAlign: TextAlign.center))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: eventsToShow.length,
                      itemBuilder: (_, i) {
                        final e = eventsToShow[i];
                    final start = e['start_datetime']?.toString();
                    final end = e['end_datetime']?.toString();
                    String summary = e['summary']?.toString() ?? '—';
                    final type = e['type']?.toString() ?? '';
                    if (type == 'On Site') {
                      final did = e['delivery_id']?.toString();
                      summary = _projectNameForDeliveryId(did);
                    } else if (type == 'Break') {
                      summary = 'Break';
                    }
                    final overCapacity = e['over_capacity'] == true;
                    String timeRange = '—';
                    if (start != null && end != null) {
                      try {
                        final s = DateTime.parse(start);
                        final en = DateTime.parse(end);
                        timeRange = '${DateFormat('HH:mm').format(s)} - ${DateFormat('HH:mm').format(en)}';
                      } catch (_) {}
                    }
                    final barColor = overCapacity ? _calendarOverCapacity : (type == 'Loading' ? _calendarLoading : type == 'Travelling' ? _calendarTravelling : type == 'Waiting' ? _calendarWaiting : type == 'Wash' ? _calendarWash : type == 'Break' ? Colors.green : _calendarOnSite);
                    final rowContent = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 40,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(summary, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(timeRange, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      ],
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: overCapacity ? Colors.red.shade50 : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: rowContent,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// [Week summary table] – daily totals (Submitted / Scheduled) for the week.
  Widget _buildWeekSummaryTable() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Week summary table', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(color: Colors.grey),
          columnWidths: const {0: FixedColumnWidth(108), 1: FixedColumnWidth(108), 2: FixedColumnWidth(108)},
          children: [
            TableRow(
              decoration: const BoxDecoration(color: _headerBlue),
              children: const [
                Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Week Day', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Submitted', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Scheduled', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
              ],
            ),
            ..._dayNamesWithQuantity().map((day) {
              final wd = _dayNameToWeekday(day);
              final dateForDay = _selectedWeekStart.add(Duration(days: wd - 1));
              return TableRow(
                children: [
                  Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(DateFormat('EEE, d MMM').format(dateForDay)))),
                  Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(_formatQuantity(_quantityForDay(wd, false))))),
                  Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(_formatQuantity(_quantityForDay(wd, true))))),
                ],
              );
            }),
            TableRow(
              decoration: const BoxDecoration(color: _totalRowBlue),
              children: [
                const Padding(padding: EdgeInsets.all(8), child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: Text(_formatQuantity(_bookings.where((b) => b['is_scheduled'] != true).fold<double>(0, (s, b) {
                      final q = b['concrete_qty'];
                      if (q == null) return s;
                      return s + ((q is num) ? (q as num).toDouble() : (double.tryParse(q.toString()) ?? 0));
                    }))),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: Text(_formatQuantity(_bookings.where((b) => b['is_scheduled'] == true).fold<double>(0, (s, b) {
                      final q = b['concrete_qty'];
                      if (q == null) return s;
                      return s + ((q is num) ? (q as num).toDouble() : (double.tryParse(q.toString()) ?? 0));
                    }))),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  List<String> _dayNamesWithQuantity() {
    return _dayNames.where((day) {
      final wd = _dayNameToWeekday(day);
      return _quantityForDay(wd, false) > 0 || _quantityForDay(wd, true) > 0;
    }).toList();
  }

  static final _actionButtonStyle = FilledButton.styleFrom(
    backgroundColor: const Color(0xFF0081FB),
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  Widget _buildDaySelectorWithButtons() {
    final daysToShow = _dayNamesWithQuantity();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey[100],
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Day:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ...daysToShow.map((day) {
            final isSelected = _selectedDay == day;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ElevatedButton(
                onPressed: () => _onDaySelected(day),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? Colors.green : null,
                  foregroundColor: isSelected ? Colors.white : null,
                ),
                child: Text(day),
              ),
            );
          }),
          FilledButton.icon(
            onPressed: (_isSaving || _isUpdating) ? null : _onUpdate,
            icon: _isUpdating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.visibility, size: 18),
            label: Text(_isUpdating ? 'Preview...' : 'Preview'),
            style: _actionButtonStyle,
          ),
          FilledButton.icon(
            onPressed: _isSaving ? null : _onSave,
            icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save, size: 18),
            label: Text(_isSaving ? 'Saving...' : 'Save'),
            style: _actionButtonStyle,
          ),
          FilledButton.icon(
            onPressed: _isSyncing ? null : _onSync,
            icon: _isSyncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 18),
            label: Text(_isSyncing ? 'Syncing...' : 'Sync'),
            style: _actionButtonStyle,
          ),
        ],
      ),
    );
  }

  /// [Load quantities table] – Trip, Quantity, Travel Time, Distance, Map. Total row. Quantity/Distance/Time include return.
  Widget _buildLoadQuantitiesTable() {
    final loadRows = _loadQuantityRows();
    if (loadRows.isEmpty) return const SizedBox.shrink();
    final rawTrips = _tripQuantitiesFromOrderedRowsRaw();
    if (_tripDistancesKm.length != rawTrips.length || _tripTravelMinutes.length != rawTrips.length) {
      final expectedTripCount = rawTrips.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future(() async {
          final distList = <double?>[];
          final timeList = <int?>[];
          for (int i = 0; i < expectedTripCount; i++) {
            distList.add(await _getTripDistanceKm(i));
            timeList.add(await _getTripTravelMinutes(i));
          }
          if (!mounted) return;
          // Only update state if trip count hasn't changed (avoid stale callback overwriting newer data)
          final currentCount = _tripQuantitiesFromOrderedRowsRaw().length;
          if (distList.length == currentCount && timeList.length == currentCount) {
            setState(() {
              _tripDistancesKm = distList;
              _tripTravelMinutes = timeList;
            });
          }
        });
      });
    }
    double totalQty = 0;
    double totalDist = 0;
    int totalMinutes = 0;
    for (final r in loadRows) {
      totalQty += r.qty;
      if (r.tripIndex != null && r.tripIndex! < _tripDistancesKm.length && _tripDistancesKm[r.tripIndex!] != null) {
        totalDist += _tripDistancesKm[r.tripIndex!]!;
      }
      if (r.tripIndex != null && r.tripIndex! < _tripTravelMinutes.length && _tripTravelMinutes[r.tripIndex!] != null) {
        totalMinutes += _tripTravelMinutes[r.tripIndex!]!;
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Load quantities table', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(color: Colors.grey),
          columnWidths: const {
            0: FixedColumnWidth(108),
            1: FixedColumnWidth(108),
            2: FixedColumnWidth(108),
            3: FixedColumnWidth(108),
            4: FixedColumnWidth(108),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: _headerBlue),
              children: const [
                Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Trip', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Quantity', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Travel Time', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Distance', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Map', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
              ],
            ),
            ...loadRows.map((r) {
              final overCapacity = r.qty > _maxLoadCapacity;
              final dist = r.tripIndex != null && r.tripIndex! < _tripDistancesKm.length ? _tripDistancesKm[r.tripIndex!] : null;
              final mins = r.tripIndex != null && r.tripIndex! < _tripTravelMinutes.length ? _tripTravelMinutes[r.tripIndex!] : null;
              return TableRow(
                children: [
                  Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(r.label))),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: Text(
                        _formatQuantityTwoDecimals(r.qty),
                        style: TextStyle(backgroundColor: overCapacity ? Colors.red.shade200 : null, fontWeight: overCapacity ? FontWeight.bold : null),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(child: Text(mins != null ? _formatTravelTimeHhMm(mins!) : '—')),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(child: Text(r.tripIndex != null && dist != null ? '${dist.toStringAsFixed(1)} km' : '—')),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Center(
                      child: r.tripIndex != null
                          ? TextButton(
                              onPressed: () => _openTripMap(r.tripIndex!),
                              child: const Text('View Trip', style: TextStyle(fontSize: 12)),
                            )
                          : const Text('—'),
                    ),
                  ),
                ],
              );
            }),
            TableRow(
              decoration: const BoxDecoration(color: _totalRowBlue),
              children: [
                const Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)))),
                Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(_formatQuantityTwoDecimals(totalQty), style: const TextStyle(fontWeight: FontWeight.bold)))),
                Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(_formatTravelTimeHhMm(totalMinutes), style: const TextStyle(fontWeight: FontWeight.bold)))),
                Padding(padding: const EdgeInsets.all(8), child: Center(child: Text('${totalDist.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.bold)))),
                const Padding(padding: EdgeInsets.all(8), child: Center(child: Text(''))),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Booking ids that are the last delivery in a trip exceeding max capacity (8).
  Set<String> _overCapacityBookingIds() {
    final fromEvents = <String>{};
    final eventsToShow = _previewCalendarEvents.isNotEmpty ? _previewCalendarEvents : _calendarEvents;
    for (final e in eventsToShow) {
      if (e['over_capacity'] == true) {
        final did = e['delivery_id']?.toString();
        if (did != null && did.isNotEmpty) fromEvents.add(did);
      }
    }
    if (fromEvents.isNotEmpty) return fromEvents;
    final rows = _orderedRowsForDayWithReturns();
    double tripDelivered = 0;
    String? lastDeliveredId;
    final result = <String>{};
    for (final row in rows) {
      if (row.isReturnToQuarry || row.isReloadAtQuarry) {
        if (tripDelivered > _maxLoadCapacity && lastDeliveredId != null) result.add(lastDeliveredId);
        tripDelivered = 0;
        lastDeliveredId = null;
        continue;
      }
      if (_includedInSchedule[row.bookingId] == false) continue;
      if (row.booking == null) continue;
      final b = row.booking!;
      if (b['delivered'] == true) {
        final q = (b['concrete_qty'] is num) ? (b['concrete_qty'] as num).toDouble() : double.tryParse(b['concrete_qty']?.toString() ?? '') ?? 0;
        tripDelivered += q;
        lastDeliveredId = row.bookingId;
      }
    }
    if (tripDelivered > _maxLoadCapacity && lastDeliveredId != null) result.add(lastDeliveredId);
    return result;
  }

  /// Scheduled arrival time (HH:mm) per booking from calendar (preview or saved).
  Map<String, String> _getScheduledArrivalByBookingId() {
    final eventsToShow = _previewCalendarEvents.isNotEmpty ? _previewCalendarEvents : _calendarEvents;
    final map = <String, String>{};
    for (final e in eventsToShow) {
      if (e['type']?.toString() != 'On Site') continue;
      final did = e['delivery_id']?.toString();
      if (did == null || did.isEmpty) continue;
      final start = e['start_datetime']?.toString();
      if (start == null) continue;
      try {
        map[did] = DateFormat('HH:mm').format(DateTime.parse(start));
      } catch (_) {}
    }
    return map;
  }

  /// Rows for booking table display: sort by Seq, Time, or Scheduled. Seq = all rows (including Return/Reload) by sequence; Time/Scheduled = bookings by that key, placeholders at end.
  List<_SchedulerRow> _orderedRowsForDaySorted() {
    final rows = _orderedRowsForDay();
    final scheduledMap = _getScheduledArrivalByBookingId();
    if (_bookingTableSortMode == 'seq') {
      // Sort all rows (including Return and Reload) by sequence so placeholders appear in correct position
      final sorted = List<_SchedulerRow>.from(rows);
      sorted.sort((a, b) {
        final aSeq = _sequenceByBookingId[a.bookingId] ?? 999999;
        final bSeq = _sequenceByBookingId[b.bookingId] ?? 999999;
        if (aSeq != bSeq) return aSeq.compareTo(bSeq);
        if (a.booking != null && b.booking != null) {
          final aDue = a.booking!['due_date_time']?.toString() ?? '';
          final bDue = b.booking!['due_date_time']?.toString() ?? '';
          return aDue.compareTo(bDue);
        }
        return a.bookingId.compareTo(b.bookingId);
      });
      return sorted;
    }
    final bookings = rows.where((r) => r.booking != null).toList();
    final placeholders = rows.where((r) => r.booking == null).toList();
    if (_bookingTableSortMode == 'time') {
      bookings.sort((a, b) {
        final aDue = a.booking!['due_date_time']?.toString() ?? '';
        final bDue = b.booking!['due_date_time']?.toString() ?? '';
        return aDue.compareTo(bDue);
      });
    } else {
      bookings.sort((a, b) {
        final aSched = scheduledMap[a.bookingId] ?? 'zzz';
        final bSched = scheduledMap[b.bookingId] ?? 'zzz';
        if (aSched != bSched) return aSched.compareTo(bSched);
        final aDue = a.booking!['due_date_time']?.toString() ?? '';
        final bDue = b.booking!['due_date_time']?.toString() ?? '';
        return aDue.compareTo(bDue);
      });
    }
    placeholders.sort((a, b) {
      final aSeq = _sequenceByBookingId[a.bookingId] ?? 999999;
      final bSeq = _sequenceByBookingId[b.bookingId] ?? 999999;
      if (aSeq != bSeq) return aSeq.compareTo(bSeq);
      return a.bookingId.compareTo(b.bookingId);
    });
    return [...bookings, ...placeholders];
  }

  /// Project name for calendar: use trimmed job number (7 chars) to match project; for child projects returns parent job description.
  String _projectNameForDeliveryId(String? deliveryId) {
    if (deliveryId == null) return '—';
    String? projectId;
    for (final b in _bookings) {
      if (b['id']?.toString() == deliveryId) {
        projectId = b['project_id']?.toString();
        break;
      }
    }
    if (projectId == null) return '—';
    final jobNumber = _projectNumbers[projectId] ?? '—';
    final trimmed = jobNumber.length > 7 ? jobNumber.substring(0, 7) : jobNumber;
    for (final entry in _projectNumbers.entries) {
      if (entry.value == trimmed) {
        final name = _projectNames[entry.key];
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return _projectNames[projectId] ?? _projectNumbers[projectId] ?? '—';
  }

  /// [Bookings table] – Schedule checkbox, Seq, Time, Scheduled, Job No., … Manual sort: Seq, Time, Scheduled.
  Widget _buildBookingsSection() {
    final scheduledMap = _getScheduledArrivalByBookingId();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Bookings table', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            FilledButton(
              onPressed: () => setState(() => _bookingTableSortMode = 'seq'),
              style: FilledButton.styleFrom(
                backgroundColor: _bookingTableSortMode == 'seq' ? Colors.green : const Color(0xFF0081FB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: const Text('Seq'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => setState(() => _bookingTableSortMode = 'time'),
              style: FilledButton.styleFrom(
                backgroundColor: _bookingTableSortMode == 'time' ? Colors.green : const Color(0xFF0081FB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: const Text('Time'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => setState(() => _bookingTableSortMode = 'scheduled'),
              style: FilledButton.styleFrom(
                backgroundColor: _bookingTableSortMode == 'scheduled' ? Colors.green : const Color(0xFF0081FB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: const Text('Scheduled'),
            ),
            FilledButton.icon(
              onPressed: _insertReturnToQuarry,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Return'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0081FB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            FilledButton.icon(
              onPressed: _insertReloadAtQuarry,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Reload'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0081FB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            FilledButton.icon(
              onPressed: _insertBreak,
              icon: const Icon(Icons.free_breakfast, size: 18),
              label: const Text('Break'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            FilledButton(
              onPressed: _clearAllSequences,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0081FB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Table(
          key: ValueKey(_bookingTableSortMode),
          border: TableBorder.all(color: Colors.grey),
          columnWidths: const {
            0: FixedColumnWidth(35),
            1: FixedColumnWidth(36),
            2: FixedColumnWidth(36),
            3: FixedColumnWidth(36),
            4: FixedColumnWidth(36),
            5: FixedColumnWidth(34),
            6: FixedColumnWidth(38),
            7: FixedColumnWidth(72),
            8: FixedColumnWidth(_bookingsCommentColumnWidth),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: _headerBlue),
              children: const [
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('Seq', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('Scheduled', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('Job No.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('County', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('Ordered by', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
                Padding(padding: EdgeInsets.all(6), child: Center(child: Text('Comment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)))),
              ],
            ),
            ...() {
              final sorted = _orderedRowsForDaySorted();
              final overCapacityIds = _overCapacityBookingIds();
              return sorted.asMap().entries.map((entry) {
                final index = entry.key;
                final row = entry.value;
                final seq = _sequenceByBookingId[row.bookingId] ?? 0;
                final included = _includedInSchedule[row.bookingId] != false;
                void onRowTap() => _assignNextSequenceToBooking(row.bookingId);
                Widget seqCell(String text) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onRowTap,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Center(child: Text(text, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                      ),
                    );
                Widget tapCell(Widget child) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onRowTap,
                      child: child,
                    );
                if (row.isReturnToQuarry) {
                  final canDelete = row.bookingId != _autoEndReturnKey;
                  return TableRow(
                    children: [
                      seqCell(seq > 0 ? seq.toString() : ''),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('— Return —', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Center(
                          child: canDelete
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () => _removeReturnToQuarry(row.bookingId),
                                  tooltip: 'Remove',
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  );
                }
                if (row.isReloadAtQuarry) {
                  return TableRow(
                    children: [
                      seqCell(seq > 0 ? seq.toString() : ''),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('— Reload —', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Center(
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _removeReloadAtQuarry(row.bookingId),
                            tooltip: 'Remove',
                          ),
                        ),
                      ),
                    ],
                  );
                }
                if (row.isBreak) {
                  return TableRow(
                    children: [
                      seqCell(seq > 0 ? seq.toString() : ''),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('— Break (30 min) —', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      tapCell(const Padding(padding: EdgeInsets.all(6), child: Center(child: Text('—', style: TextStyle(fontSize: 12))))),
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Center(
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _removeBreak(row.bookingId),
                            tooltip: 'Remove',
                          ),
                        ),
                      ),
                    ],
                  );
                }
                final b = row.booking!;
                final projectId = b['project_id']?.toString();
                final jobNoRaw = _projectNumbers[projectId] ?? '—';
                final jobNo = jobNoRaw.length > 7 ? jobNoRaw.substring(0, 7) : jobNoRaw;
                final projectName = _projectNames[projectId] ?? '—';
                final county = _projectCounties[projectId] ?? '—';
                final qtyNum = b['concrete_qty'] != null ? ((b['concrete_qty'] is num) ? (b['concrete_qty'] as num).toDouble() : double.tryParse(b['concrete_qty'].toString())) : null;
                final qty = qtyNum != null ? _formatQuantityTwoDecimals(qtyNum) : '—';
                final typeStr = b['delivered'] == true ? 'Delivered' : 'Collected';
                final due = b['due_date_time'];
                final time = due != null ? DateFormat('HH:mm').format(DateTime.parse(due.toString())) : '—';
                final scheduledArrival = scheduledMap[row.bookingId] ?? '—';
                final orderedBy = _bookingUserNames[b['booking_user_id']?.toString() ?? ''] ?? '—';
                final commentText = b['comments']?.toString().trim();
                final hasComment = commentText != null && commentText.isNotEmpty;
                final overCapacity = overCapacityIds.contains(row.bookingId);
                final rowColor = overCapacity ? Colors.red.shade50 : (included ? Colors.green.shade50 : Colors.red.shade50);
                return TableRow(
                  decoration: BoxDecoration(color: rowColor),
                  children: [
                    seqCell(seq > 0 ? seq.toString() : ''),
                    tapCell(Padding(padding: const EdgeInsets.all(6), child: Center(child: Text(time, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))),
                    tapCell(Padding(padding: const EdgeInsets.all(6), child: Center(child: Text(scheduledArrival, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Center(
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Job'),
                                content: Text(projectName),
                                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                              ),
                            );
                          },
                          child: Text(jobNo, style: const TextStyle(fontSize: 12, color: Colors.blue, decoration: TextDecoration.underline), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                    tapCell(Padding(padding: const EdgeInsets.all(6), child: Center(child: Text(county, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))),
                    tapCell(Padding(padding: const EdgeInsets.all(6), child: Center(child: Text(qty, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))),
                    tapCell(Padding(
                      padding: const EdgeInsets.all(6),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          color: typeStr == 'Collected' ? Colors.yellow : null,
                          child: Text(typeStr, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    )),
                    tapCell(Padding(padding: const EdgeInsets.all(6), child: Center(child: Text(orderedBy, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))),
                    tapCell(Padding(
                      padding: const EdgeInsets.all(6),
                      child: Center(
                        child: hasComment
                            ? Text(
                                commentText!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                              )
                            : const SizedBox.shrink(),
                      ),
                    )),
                  ],
                );
              });
            }(),
          ],
        ),
      ],
    );
  }
}

class _SchedulerRow {
  final String bookingId;
  final Map<String, dynamic>? booking;
  final bool isReturnToQuarry;
  final bool isReloadAtQuarry;
  final bool isBreak;

  _SchedulerRow({
    required this.bookingId,
    required this.booking,
    this.isReturnToQuarry = false,
    this.isReloadAtQuarry = false,
    this.isBreak = false,
  });
}
