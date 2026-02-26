/// PPE Request Approvals – managers approve/reject ppe_requests assigned to them.
/// Grouped by requesting user; layout similar to ppe_my_requests_screen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';

class PpeRequestApprovalsScreen extends StatefulWidget {
  const PpeRequestApprovalsScreen({super.key});

  @override
  State<PpeRequestApprovalsScreen> createState() => _PpeRequestApprovalsScreenState();
}

class _PpeRequestApprovalsScreenState extends State<PpeRequestApprovalsScreen> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, String> _ppeNames = {};
  Map<String, String> _ppeCategories = {};
  Map<String, String> _userNames = {};
  bool _loading = true;

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
      return dt != null ? DateFormat('d MMM yyyy').format(dt) : requestedDate.toString();
    } catch (_) {
      return requestedDate.toString();
    }
  }

  Future<void> _load() async {
    final managerId = AuthService.getCurrentUser()?.id;
    if (managerId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.client
          .from('ppe_requests')
          .select('*, ppe_sizes(size_code)')
          .eq('is_active', true)
          .eq('manager_id', managerId)
          .eq('status', 'submitted')
          .order('requested_date', ascending: false) as List<dynamic>;
      _requests = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ppeIds = _requests.map((e) => e['ppe_id']?.toString()).whereType<String>().toSet().toList();
      final userIds = _requests.map((e) => e['user_id']?.toString()).whereType<String>().toSet().toList();
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
          _userNames[m['user_id']?.toString() ?? ''] = m['display_name']?.toString() ?? '—';
        }
      }
      setState(() => _loading = false);
    } catch (e, st) {
      ErrorLogService.logError(location: 'PPE Request Approvals', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      setState(() => _loading = false);
    }
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

  /// Group by user_id; each group: (userId, userName, dateStr, items).
  List<({String userId, String userName, String dateStr, List<Map<String, dynamic>> items})> _buildGroups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in _requests) {
      final uid = r['user_id']?.toString() ?? '';
      map.putIfAbsent(uid, () => []).add(r);
    }
    final list = <({String userId, String userName, String dateStr, List<Map<String, dynamic>> items})>[];
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
      final userId = e.key;
      final userName = _userNames[userId] ?? '—';
      final dateStr = _formatRequestedDate(first);
      list.add((userId: userId, userName: userName, dateStr: dateStr, items: items));
    }
    list.sort((a, b) => b.dateStr.compareTo(a.dateStr));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PPE Request Approvals'),
        actions: const [ScreenInfoIcon(screenName: 'ppe_request_approvals_screen.dart')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? const Center(child: Text('No requests assigned to you'))
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _buildGroups().map((g) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildSectionCard(
                              userName: g.userName,
                              dateStr: g.dateStr,
                              items: g.items,
                              onApproveAll: () => _updateStatusForGroup(g.items, 'approved'),
                              onRejectAll: () => _updateStatusForGroup(g.items, 'rejected'),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
    );
  }

  /// Section card: blue header with "Requested by" / "Requested on" and Approve All / Reject All; then item rows.
  Widget _buildSectionCard({
    required String userName,
    required String dateStr,
    required List<Map<String, dynamic>> items,
    required VoidCallback onApproveAll,
    required VoidCallback onRejectAll,
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
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF005AB0), width: 2),
                ),
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
                        Text(
                          userName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateStr,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onRejectAll,
                    style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: const Size(100, 36)),
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('Reject All', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: onApproveAll,
                    style: FilledButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: const Size(100, 36)),
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Approve All', style: TextStyle(fontSize: 13)),
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
  static const double _btnRejectWidth = 44;
  static const double _btnApproveWidth = 44;
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
            width: _btnRejectWidth + _actionsGap + _btnApproveWidth,
            child: Text('Actions', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(Map<String, dynamic> r) {
    final ppeName = _ppeNames[r['ppe_id']?.toString() ?? ''] ?? '—';
    final sizeStr = _requestSizeDisplay(r);
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
            width: _btnRejectWidth,
            height: _btnMinHeight,
            child: Tooltip(
              message: 'Reject',
              child: FilledButton(
                onPressed: () => _updateStatus(r['id'] as String, 'rejected'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.all(8), minimumSize: const Size(_btnRejectWidth, _btnMinHeight)),
                child: const Icon(Icons.cancel, size: 22),
              ),
            ),
          ),
          const SizedBox(width: _actionsGap),
          SizedBox(
            width: _btnApproveWidth,
            height: _btnMinHeight,
            child: Tooltip(
              message: 'Approve',
              child: FilledButton(
                onPressed: () => _updateStatus(r['id'] as String, 'approved'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(8), minimumSize: const Size(_btnApproveWidth, _btnMinHeight)),
                child: const Icon(Icons.check_circle, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
