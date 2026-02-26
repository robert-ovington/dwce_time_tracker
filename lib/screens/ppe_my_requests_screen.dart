/// My PPE Requests – list current user's ppe_requests.
/// Grouped by submitted date and manager; layout matches timesheet_screen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';

class PpeMyRequestsScreen extends StatefulWidget {
  const PpeMyRequestsScreen({super.key});

  @override
  State<PpeMyRequestsScreen> createState() => _PpeMyRequestsScreenState();
}

class _PpeMyRequestsScreenState extends State<PpeMyRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, String> _ppeNames = {};
  Map<String, String> _ppeCategories = {};
  Map<String, String> _managerNames = {};
  Map<String, List<Map<String, dynamic>>> _sizesByCategory = {};
  bool _loading = true;

  String? _editingRequestId;
  String? _editedSizeId;

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

  /// Group key: same requested_date (as ISO day) + manager_id = same submission.
  static String _groupKey(Map<String, dynamic> r) {
    final date = r['requested_date']?.toString();
    final managerId = r['manager_id']?.toString() ?? '';
    if (date == null) return 'unknown_$managerId';
    final dt = DateTime.tryParse(date);
    final dayStr = dt != null ? DateFormat('yyyy-MM-dd').format(dt) : date;
    return '${dayStr}_$managerId';
  }

  /// Format requested_date for display.
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

  Future<void> _load() async {
    final uid = AuthService.getCurrentUser()?.id;
    if (uid == null) return;
    setState(() {
      _loading = true;
      _editingRequestId = null;
      _editedSizeId = null;
    });
    try {
      final list = await SupabaseService.client
          .from('ppe_requests')
          .select('*, ppe_sizes(size_code)')
          .eq('user_id', uid)
          .eq('is_active', true)
          .order('requested_date', ascending: false) as List<dynamic>;
      _requests = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final ppeIds = _requests.map((e) => e['ppe_id']?.toString()).whereType<String>().toSet().toList();
      if (ppeIds.isNotEmpty) {
        final plist = await SupabaseService.client
            .from('ppe_list')
            .select('id, name, category')
            .inFilter('id', ppeIds) as List<dynamic>;
        for (final p in plist) {
          final m = Map<String, dynamic>.from(p as Map);
          final id = m['id']?.toString() ?? '';
          _ppeNames[id] = m['name']?.toString() ?? '';
          final cat = m['category']?.toString();
          if (cat != null) _ppeCategories[id] = cat;
        }
      }

      final managerIds = _requests
          .map((e) => e['manager_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (managerIds.isNotEmpty) {
        final mlist = await SupabaseService.client
            .from('users_setup')
            .select('user_id, display_name')
            .inFilter('user_id', managerIds) as List<dynamic>;
        for (final x in mlist) {
          final m = Map<String, dynamic>.from(x as Map);
          _managerNames[m['user_id']?.toString() ?? ''] = m['display_name']?.toString() ?? '—';
        }
      }

      final sizesList = await SupabaseService.client
          .from('ppe_sizes')
          .select('id, size_code, category, sort_order')
          .eq('is_active', true)
          .order('sort_order')
          .order('size_code') as List<dynamic>;
      _sizesByCategory.clear();
      for (final s in sizesList) {
        final m = Map<String, dynamic>.from(s as Map);
        final cat = m['category']?.toString() ?? '';
        _sizesByCategory.putIfAbsent(cat, () => []).add(m);
      }

      setState(() => _loading = false);
    } catch (e, st) {
      ErrorLogService.logError(location: 'PPE My Requests', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
      setState(() => _loading = false);
    }
  }

  void _startEditing(Map<String, dynamic> r) {
    setState(() {
      _editingRequestId = r['id']?.toString();
      _editedSizeId = r['size_id']?.toString();
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingRequestId = null;
      _editedSizeId = null;
    });
  }

  bool _hasSizeChange(Map<String, dynamic> r) {
    if (_editingRequestId != r['id']?.toString()) return false;
    final current = r['size_id']?.toString();
    return _editedSizeId != null && _editedSizeId != current;
  }

  Future<void> _saveSizeChange(Map<String, dynamic> r) async {
    final id = r['id']?.toString();
    if (id == null || _editedSizeId == null) return;
    try {
      await SupabaseService.client.from('ppe_requests').update({'size_id': _editedSizeId}).eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Size updated')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _cancelRequest(Map<String, dynamic> r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SupabaseService.client.from('ppe_requests').update({'status': 'cancelled'}).eq('id', r['id'] as Object);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Build grouped list: [(groupKey, dateStr, managerName, items), ...]
  List<({String key, String dateStr, String managerName, List<Map<String, dynamic>> items})> _buildGroups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in _requests) {
      final k = _groupKey(r);
      map.putIfAbsent(k, () => []).add(r);
    }
    final list = <({String key, String dateStr, String managerName, List<Map<String, dynamic>> items})>[];
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
      final managerId = first['manager_id']?.toString();
      final managerName = managerId != null ? (_managerNames[managerId] ?? '—') : '—';
      list.add((key: e.key, dateStr: dateStr, managerName: managerName, items: items));
    }
    list.sort((a, b) => b.key.compareTo(a.key));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My PPE Requests'),
        actions: const [ScreenInfoIcon(screenName: 'ppe_my_requests_screen.dart')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? const Center(child: Text('No requests yet'))
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _buildGroups().map((g) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildSectionCard(
                              submittedOn: g.dateStr,
                              submittedTo: g.managerName,
                              children: g.items.map((r) => _buildRequestItem(r)).toList(),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
    );
  }

  /// One section card in timesheet style: bordered container, blue header (two lines), content.
  Widget _buildSectionCard({
    required String submittedOn,
    required String submittedTo,
    required List<Widget> children,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Submitted on $submittedOn',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Submitted to $submittedTo',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestItem(Map<String, dynamic> r) {
    final requestId = r['id']?.toString();
    final ppeId = r['ppe_id']?.toString() ?? '';
    final name = _ppeNames[ppeId] ?? '—';
    final status = r['status']?.toString() ?? '—';
    final sizeStr = _requestSizeDisplay(r);
    final isEditing = _editingRequestId == requestId;
    final category = _ppeCategories[ppeId];
    final sizeOptions = category != null ? (_sizesByCategory[category] ?? []) : <Map<String, dynamic>>[];
    final currentSizeId = isEditing ? (_editedSizeId ?? r['size_id']?.toString()) : r['size_id']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Text(name, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          if (isEditing && sizeOptions.isNotEmpty)
            SizedBox(
              width: 72,
              child: DropdownButtonFormField<String>(
                value: currentSizeId,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                items: sizeOptions.map((s) {
                  final id = s['id']?.toString() ?? '';
                  final code = s['size_code']?.toString() ?? id;
                  return DropdownMenuItem(value: id, child: Text(code, overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (v) => setState(() => _editedSizeId = v),
              ),
            )
          else
            SizedBox(
              width: 48,
              child: Text(sizeStr, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ),
          if (status == 'submitted') ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => _cancelRequest(r),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (isEditing) {
                  if (_hasSizeChange(r)) _saveSizeChange(r);
                  else _cancelEditing();
                } else {
                  _startEditing(r);
                }
              },
              child: Text(isEditing ? 'Save' : 'Edit'),
            ),
          ],
        ],
      ),
    );
  }
}
