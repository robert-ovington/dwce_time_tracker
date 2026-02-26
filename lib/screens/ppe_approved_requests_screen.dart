/// PPE Requests (PPE Management) – PPE Manager sees all requests; filter by status; Pick/Dispatch.
/// Layout aligned with ppe_request_approvals_screen: section cards, column headers, Pick All / Dispatch All.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/errors/error_log_service.dart';
import '../utils/picking_list_export.dart';

class PpeApprovedRequestsScreen extends StatefulWidget {
  const PpeApprovedRequestsScreen({super.key});

  @override
  State<PpeApprovedRequestsScreen> createState() => _PpeApprovedRequestsScreenState();
}

class _PpeApprovedRequestsScreenState extends State<PpeApprovedRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, String> _ppeNames = {};
  Map<String, String> _ppeCategories = {};
  Map<String, String> _userNames = {};
  Map<String, String> _managerNames = {};
  List<Map<String, dynamic>> _allUsers = [];
  bool _loading = true;

  /// One of 'approved', 'submitted', 'picked', 'dispatched', 'all'. Default 'approved'.
  String _statusFilter = 'approved';
  String? _userFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _requestSizeDisplay(Map<String, dynamic> r) {
    final sz = r['ppe_sizes'];
    if (sz is Map && sz['size_code'] != null) return sz['size_code'].toString();
    return '—';
  }

  static String _formatRequestedDate(Map<String, dynamic> r) {
    final requestedDate = r['requested_date'];
    if (requestedDate == null) return '—';
    try {
      final dt = DateTime.tryParse(requestedDate.toString());
      return dt != null ? DateFormat('d MMM yyyy, HH:mm').format(dt) : requestedDate.toString();
    } catch (_) {
      return requestedDate.toString();
    }
  }

  /// Group key: same requested_date (day) + user_id
  static String _groupKey(Map<String, dynamic> r) {
    final date = r['requested_date']?.toString();
    final userId = r['user_id']?.toString() ?? '';
    if (date == null) return 'unknown_$userId';
    final dt = DateTime.tryParse(date);
    final dayStr = dt != null ? DateFormat('yyyy-MM-dd').format(dt) : date;
    return '${dayStr}_$userId';
  }

  Future<void> _updateStatus(String requestId, String newStatus) async {
    try {
      await SupabaseService.client.from('ppe_requests').update({'status': newStatus}).eq('id', requestId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated to $newStatus'), backgroundColor: Colors.green));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _updateStatusForGroup(List<Map<String, dynamic>> items, String newStatus) async {
    try {
      for (final r in items) {
        final id = r['id']?.toString();
        if (id != null) await SupabaseService.client.from('ppe_requests').update({'status': newStatus}).eq('id', id);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${items.length} request(s) $newStatus'), backgroundColor: Colors.green));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  /// Unpick All: set each item to 'approved' if approved_date is set, else 'submitted'.
  Future<void> _unpickGroup(List<Map<String, dynamic>> items) async {
    try {
      for (final r in items) {
        final id = r['id']?.toString();
        if (id == null) continue;
        final newStatus = r['approved_date'] != null ? 'approved' : 'submitted';
        await SupabaseService.client.from('ppe_requests').update({'status': newStatus}).eq('id', id);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${items.length} request(s) reverted'), backgroundColor: Colors.green));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  static String _formatApprovalDate(dynamic approvedDate) {
    if (approvedDate == null) return '—';
    try {
      final dt = DateTime.tryParse(approvedDate.toString());
      return dt != null ? DateFormat('d MMM yyyy, HH:mm').format(dt) : approvedDate.toString();
    } catch (_) {
      return approvedDate.toString();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final usersList = await SupabaseService.client.from('users_setup').select('user_id, display_name').order('display_name') as List<dynamic>;
      _allUsers = usersList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      var q = SupabaseService.client.from('ppe_requests').select('*, ppe_sizes(size_code)').eq('is_active', true);
      if (_statusFilter != 'all') {
        q = q.eq('status', _statusFilter);
      }
      final userFilter = _userFilter;
      if (userFilter != null && userFilter.isNotEmpty) {
        q = q.eq('user_id', userFilter);
      }
      final list = await q.order('requested_date', ascending: false) as List<dynamic>;
      _requests = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final ppeIds = _requests.map((e) => e['ppe_id']?.toString()).whereType<String>().toSet().toList();
      final userIds = _requests.map((e) => e['user_id']?.toString()).whereType<String>().toSet().toList();
      final managerIds = _requests.map((e) => e['manager_id']?.toString()).whereType<String>().where((id) => id.isNotEmpty).toSet().toList();
      if (ppeIds.isNotEmpty) {
        final plist = await SupabaseService.client.from('ppe_list').select('id, name, category').inFilter('id', ppeIds) as List<dynamic>;
        for (final p in plist) {
          final m = Map<String, dynamic>.from(p as Map);
          final id = m['id']?.toString() ?? '';
          _ppeNames[id] = m['name']?.toString() ?? '';
          final cat = m['category']?.toString();
          if (cat != null) _ppeCategories[id] = cat;
        }
      }
      if (userIds.isNotEmpty) {
        final ulist = await SupabaseService.client.from('users_setup').select('user_id, display_name').inFilter('user_id', userIds) as List<dynamic>;
        for (final u in ulist) {
          final m = Map<String, dynamic>.from(u as Map);
          _userNames[m['user_id']?.toString() ?? ''] = m['display_name']?.toString() ?? '';
        }
      }
      if (managerIds.isNotEmpty) {
        final mlist = await SupabaseService.client.from('users_setup').select('user_id, display_name').inFilter('user_id', managerIds) as List<dynamic>;
        for (final x in mlist) {
          final m = Map<String, dynamic>.from(x as Map);
          _managerNames[m['user_id']?.toString() ?? ''] = m['display_name']?.toString() ?? '—';
        }
      }
      setState(() => _loading = false);
    } catch (e, st) {
      ErrorLogService.logError(location: 'PPE Approved Requests', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      setState(() => _loading = false);
    }
  }

  List<({String key, String dateStr, String userName, String managerName, String? approvalDateStr, List<Map<String, dynamic>> items})> _buildGroups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in _requests) {
      final k = _groupKey(r);
      map.putIfAbsent(k, () => []).add(r);
    }
    final list = <({String key, String dateStr, String userName, String managerName, String? approvalDateStr, List<Map<String, dynamic>> items})>[];
    for (final e in map.entries) {
      final items = e.value;
      items.sort((a, b) {
        final catA = _ppeCategories[a['ppe_id']?.toString() ?? ''] ?? '';
        final catB = _ppeCategories[b['ppe_id']?.toString() ?? ''] ?? '';
        final c = catA.compareTo(catB);
        if (c != 0) return c;
        final nameA = _ppeNames[a['ppe_id']?.toString() ?? ''] ?? '';
        final nameB = _ppeNames[b['ppe_id']?.toString() ?? ''] ?? '';
        return nameA.compareTo(nameB);
      });
      final first = items.first;
      final dateStr = _formatRequestedDate(first);
      final userId = first['user_id']?.toString();
      final userName = userId != null ? (_userNames[userId] ?? '—') : '—';
      final managerId = first['manager_id']?.toString();
      final managerName = managerId != null ? (_managerNames[managerId] ?? '—') : '—';
      String? approvalDateStr;
      if (_statusFilter == 'approved') {
        final ad = first['approved_date'] ?? first['updated_at'];
        approvalDateStr = ad != null ? _formatApprovalDate(ad) : null;
      }
      list.add((key: e.key, dateStr: dateStr, userName: userName, managerName: managerName, approvalDateStr: approvalDateStr, items: items));
    }
    list.sort((a, b) => b.key.compareTo(a.key));
    return list;
  }

  Widget _buildByUserPreviewGroup(
    int gi,
    ({String key, String dateStr, String userName, String managerName, String? approvalDateStr, List<Map<String, dynamic>> items}) g,
    Map<String, String> pickedValues,
    void Function(void Function()) setState,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(g.userName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Requested: ${g.dateStr}', style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(color: Colors.grey),
            columnWidths: const {0: FlexColumnWidth(1), 1: FixedColumnWidth(134), 2: FixedColumnWidth(134), 3: FixedColumnWidth(134)},
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade300),
                children: const [
                  Padding(padding: EdgeInsets.all(12), child: Text('PPE Item', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  Center(child: Padding(padding: EdgeInsets.all(12), child: Text('Size', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)))),
                  Center(child: Padding(padding: EdgeInsets.all(12), child: Text('Required', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)))),
                  Center(child: Padding(padding: EdgeInsets.all(12), child: Text('Picked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)))),
                ],
              ),
              ...g.items.asMap().entries.map((ie) {
                final ii = ie.key;
                final r = ie.value;
                final name = _ppeNames[r['ppe_id']?.toString() ?? ''] ?? '—';
                final size = _requestSizeDisplay(r);
                final qty = r['quantity'];
                final qtyStr = (qty is int) ? '$qty' : (qty != null ? qty.toString() : '1');
                final key = '${gi}_$ii';
                return TableRow(
                  children: [
                    Padding(padding: const EdgeInsets.all(12), child: Text(name, style: const TextStyle(fontSize: 20))),
                    Center(child: Padding(padding: const EdgeInsets.all(12), child: Text(size, style: const TextStyle(fontSize: 20)))),
                    Center(child: Padding(padding: const EdgeInsets.all(12), child: Text(qtyStr, style: const TextStyle(fontSize: 20)))),
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: Text('', style: TextStyle(fontSize: 20)))),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _doPrintPickingListByUser() async {
    final groups = _buildGroups();
    final exportGroups = groups.map((g) => (userName: g.userName, dateStr: g.dateStr, items: g.items)).toList();
    final ok = await printPickingListByUser(
      groups: exportGroups,
      sizeDisplay: _requestSizeDisplay,
      ppeName: (id) => _ppeNames[id ?? ''] ?? '—',
    );
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Print is available on web (opens print dialog; you can Save as PDF)')),
      );
    }
  }

  List<Map<String, dynamic>> _buildByItemRows() {
    final map = <String, Map<String, dynamic>>{};
    for (final r in _requests) {
      final ppeId = r['ppe_id']?.toString() ?? '';
      final name = _ppeNames[ppeId] ?? '—';
      final size = _requestSizeDisplay(r);
      final key = '$name|$size';
      final qty = r['quantity'];
      final qtyInt = qty is int ? qty : (qty != null ? int.tryParse(qty.toString()) ?? 1 : 1);
      map[key] ??= {'name': name, 'size': size, 'qty': 0};
      map[key]!['qty'] = (map[key]!['qty'] as int) + qtyInt;
    }
    final rows = map.values.toList()
      ..sort((a, b) {
        final n = (a['name'] as String).compareTo(b['name'] as String);
        if (n != 0) return n;
        return (a['size'] as String).compareTo(b['size'] as String);
      });
    return rows;
  }

  Future<void> _doPrintPickingListByItem() async {
    final rows = _buildByItemRows();
    final ok = await printPickingListByItem(rows: rows);
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Print is available on web (opens print dialog; you can Save as PDF)')),
      );
    }
  }

  void _showPickingListDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Print Picking List'),
        content: const Text('Choose format:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showPickingListPreviewByUser();
            },
            child: const Text('By User'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showPickingListPreviewByItem();
            },
            child: const Text('By Item'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  static const double _a4LandscapeRatio = 1.414; // width/height for A4 landscape (210/297 inverted)

  void _showPickingListPreviewByUser() {
    final groups = _buildGroups();
    final pickedValues = <String, String>{};
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => Dialog(
          backgroundColor: Colors.white,
          child: Container(
            color: Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 320,
                maxWidth: MediaQuery.of(ctx2).size.width - 48,
                maxHeight: MediaQuery.of(ctx2).size.height - 48,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text('Picking List (By User)', style: Theme.of(ctx2).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 28)),
                  ),
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: _a4LandscapeRatio,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final ge in groups.asMap().entries) ...[
                              _buildByUserPreviewGroup(
                                ge.key,
                                ge.value,
                                pickedValues,
                                setState,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx2).pop(),
                          child: const Text('Close', style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: () {
                            _doPrintPickingListByUser();
                            Navigator.of(ctx2).pop();
                          },
                          icon: const Icon(Icons.print, size: 24),
                          label: const Text('Print', style: TextStyle(fontSize: 20)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPickingListPreviewByItem() {
    final rows = _buildByItemRows();
    final pickedValues = <int, String>{};
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => Dialog(
          backgroundColor: Colors.white,
          child: Container(
            color: Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 320,
                maxWidth: MediaQuery.of(ctx2).size.width - 48,
                maxHeight: MediaQuery.of(ctx2).size.height - 48,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text('Picking List (By Item)', style: Theme.of(ctx2).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 28)),
                  ),
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: _a4LandscapeRatio,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Table(
                          border: TableBorder.all(color: Colors.grey),
                          columnWidths: const {0: FlexColumnWidth(1), 1: FixedColumnWidth(134), 2: FixedColumnWidth(134), 3: FixedColumnWidth(134)},
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: Colors.grey.shade300),
                              children: const [
                                Padding(padding: EdgeInsets.all(12), child: Text('PPE Item', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                                Center(child: Padding(padding: EdgeInsets.all(12), child: Text('Size', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)))),
                                Center(child: Padding(padding: EdgeInsets.all(12), child: Text('Required', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)))),
                                Center(child: Padding(padding: EdgeInsets.all(12), child: Text('Picked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)))),
                              ],
                            ),
                            ...rows.asMap().entries.map((e) {
                              final i = e.key;
                              final row = e.value;
                              return TableRow(
                                children: [
                                  Padding(padding: const EdgeInsets.all(12), child: Text(row['name'] as String, style: const TextStyle(fontSize: 20))),
                                  Center(child: Padding(padding: const EdgeInsets.all(12), child: Text(row['size'] as String, style: const TextStyle(fontSize: 20)))),
                                  Center(child: Padding(padding: const EdgeInsets.all(12), child: Text('${row['qty']}', style: const TextStyle(fontSize: 20)))),
                                  const Center(child: Padding(padding: EdgeInsets.all(12), child: Text('', style: TextStyle(fontSize: 20)))),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx2).pop(),
                          child: const Text('Close', style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: () {
                            _doPrintPickingListByItem();
                            Navigator.of(ctx2).pop();
                          },
                          icon: const Icon(Icons.print, size: 24),
                          label: const Text('Print', style: TextStyle(fontSize: 20)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PPE Requests'),
        actions: const [ScreenInfoIcon(screenName: 'ppe_approved_requests_screen.dart')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFiltersCard(),
                    ..._requests.isEmpty
                        ? [const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: Text('No requests match filters')))]
                        : _buildGroups().map((g) => Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: _buildSectionCard(
                                userName: g.userName,
                                dateStr: g.dateStr,
                                managerName: g.managerName,
                                approvalDateStr: g.approvalDateStr,
                                items: g.items,
                                onPickAll: () => _updateStatusForGroup(g.items, 'picked'),
                                onDispatchAll: () => _updateStatusForGroup(g.items, 'dispatched'),
                                onUnpickAll: () => _unpickGroup(g.items),
                              ),
                            )),
                  ],
                ),
              ),
            ),
    );
  }

  /// Filters: status buttons (Approved, Submitted, Pick, Dispatched, All), User dropdown, Print Picking List.
  Widget _buildFiltersCard() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Column(
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
              child: const Text('Filters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _statusButton('Approved', 'approved'),
                      _statusButton('Submitted', 'submitted'),
                      _statusButton('Pick', 'picked'),
                      _statusButton('Dispatched', 'dispatched'),
                      _statusButton('All', 'all'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _userFilter,
                    decoration: const InputDecoration(labelText: 'User'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All users')),
                      ..._allUsers.map((e) => DropdownMenuItem(
                            value: e['user_id']?.toString(),
                            child: Text(e['display_name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() => _userFilter = v);
                      _load();
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _requests.isEmpty ? null : _showPickingListDialog,
                    icon: const Icon(Icons.print),
                    label: const Text('Print Picking List'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusButton(String label, String value) {
    final selected = _statusFilter == value;
    return selected
        ? FilledButton(onPressed: () {}, style: FilledButton.styleFrom(backgroundColor: Colors.green), child: Text(label))
        : OutlinedButton(
            onPressed: () {
              setState(() {
                _statusFilter = value;
                _load();
              });
            },
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF005AB0), side: const BorderSide(color: Color(0xFF005AB0))),
            child: Text(label),
          );
  }

  /// Section card: subheader (user, date, manager, approval) + Pick All / Unpick All / Dispatch All; then column headers + rows.
  Widget _buildSectionCard({
    required String userName,
    required String dateStr,
    required String managerName,
    String? approvalDateStr,
    required List<Map<String, dynamic>> items,
    required VoidCallback onPickAll,
    required VoidCallback onDispatchAll,
    required VoidCallback onUnpickAll,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF005AB0), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFBADDFF),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                border: Border(bottom: BorderSide(color: Color(0xFF005AB0), width: 2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(userName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(dateStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        Text('Submitted to $managerName', style: const TextStyle(fontSize: 11)),
                        if (approvalDateStr != null && approvalDateStr.isNotEmpty)
                          Text('Approved on $approvalDateStr', style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onPickAll,
                    style: FilledButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: const Size(90, 36)),
                    icon: const Icon(Icons.inventory_2, size: 18),
                    label: const Text('Pick All', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: onUnpickAll,
                    style: FilledButton.styleFrom(backgroundColor: Colors.grey, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: const Size(95, 36)),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Unpick All', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: onDispatchAll,
                    style: FilledButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: const Size(100, 36)),
                    icon: const Icon(Icons.local_shipping, size: 18),
                    label: const Text('Dispatch All', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildColumnHeaders(),
                  ...items.map((r) => _buildRequestItem(r)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const double _colSizeWidth = 48;
  static const double _colQtyWidth = 32;
  static const double _colStatusWidth = 64;
  static const double _btnPickWidth = 44;
  static const double _btnDispatchedWidth = 44;
  static const double _btnMinHeight = 40;
  static const double _actionsGap = 4;
  static const double _colGap = 8;

  Widget _buildColumnHeaders() {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF005AB0), width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text('PPE Item', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _colSizeWidth,
            child: Text('Size', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _colQtyWidth,
            child: Text('Qty', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _colStatusWidth,
            child: Text('Status', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _btnPickWidth + _actionsGap + _btnDispatchedWidth,
            child: Text('Actions', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(Map<String, dynamic> r) {
    final ppeName = _ppeNames[r['ppe_id']?.toString() ?? ''] ?? '—';
    final sizeStr = _requestSizeDisplay(r);
    final status = r['status']?.toString() ?? '—';
    final qty = r['quantity'];
    final qtyStr = (qty is int) ? '$qty' : (qty != null ? qty.toString() : '1');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(ppeName, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _colSizeWidth,
            child: Text(sizeStr, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _colQtyWidth,
            child: Text(qtyStr, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _colStatusWidth,
            child: Text(status, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _btnPickWidth,
            height: _btnMinHeight,
            child: Tooltip(
              message: 'Pick',
              child: FilledButton(
                onPressed: () => _updateStatus(r['id'] as String, 'picked'),
                style: FilledButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.all(8), minimumSize: const Size(_btnPickWidth, _btnMinHeight)),
                child: const Icon(Icons.inventory_2, size: 22),
              ),
            ),
          ),
          const SizedBox(width: _actionsGap),
          SizedBox(
            width: _btnDispatchedWidth,
            height: _btnMinHeight,
            child: Tooltip(
              message: 'Dispatched',
              child: FilledButton(
                onPressed: () => _updateStatus(r['id'] as String, 'dispatched'),
                style: FilledButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.all(8), minimumSize: const Size(_btnDispatchedWidth, _btnMinHeight)),
                child: const Icon(Icons.local_shipping, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
