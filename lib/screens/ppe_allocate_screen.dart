/// Allocate PPE – list ppe_requests with status purchasing_approved;
/// options: set status to dispatched, rejected, or cancelled.

import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/errors/error_log_service.dart';

class PpeAllocateScreen extends StatefulWidget {
  const PpeAllocateScreen({super.key});

  @override
  State<PpeAllocateScreen> createState() => _PpeAllocateScreenState();
}

class _PpeAllocateScreenState extends State<PpeAllocateScreen> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, String> _ppeNames = {};
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.client
          .from('ppe_requests')
          .select('*, ppe_sizes(size_code)')
          .eq('status', 'purchasing_approved')
          .eq('is_active', true)
          .order('requested_date', ascending: false) as List<dynamic>;
      _requests = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ppeIds = _requests.map((e) => e['ppe_id']?.toString()).whereType<String>().toSet().toList();
      final userIds = _requests.map((e) => e['user_id']?.toString()).whereType<String>().toSet().toList();
      if (ppeIds.isNotEmpty) {
        final plist = await SupabaseService.client.from('ppe_list').select('id, name').inFilter('id', ppeIds) as List<dynamic>;
        for (final p in plist) {
          final m = Map<String, dynamic>.from(p as Map);
          _ppeNames[m['id']?.toString() ?? ''] = m['name']?.toString() ?? '';
        }
      }
      if (userIds.isNotEmpty) {
        final ulist = await SupabaseService.client.from('users_setup').select('user_id, display_name').inFilter('user_id', userIds) as List<dynamic>;
        for (final u in ulist) {
          final m = Map<String, dynamic>.from(u as Map);
          _userNames[m['user_id']?.toString() ?? ''] = m['display_name']?.toString() ?? '';
        }
      }
      setState(() => _loading = false);
    } catch (e, st) {
      ErrorLogService.logError(location: 'PPE Allocate - Load', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String requestId, String newStatus) async {
    try {
      final payload = <String, dynamic>{'status': newStatus};
      if (newStatus == 'dispatched') {
        payload['allocated_date'] = DateTime.now().toUtc().toIso8601String();
      }
      await SupabaseService.client.from('ppe_requests').update(payload).eq('id', requestId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated to $newStatus'), backgroundColor: Colors.green));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Allocate PPE'),
        actions: const [ScreenInfoIcon(screenName: 'ppe_allocate_screen.dart')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? const Center(child: Text('No purchasing-approved requests'))
                  : ListView.builder(
                      itemCount: _requests.length,
                      itemBuilder: (context, i) {
                        final r = _requests[i];
                        final ppeName = _ppeNames[r['ppe_id']?.toString() ?? ''] ?? '—';
                        final userName = _userNames[r['user_id']?.toString() ?? ''] ?? '—';
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            title: Text(ppeName),
                            subtitle: Text('$userName • ${_requestSizeDisplay(r)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(onPressed: () => _updateStatus(r['id'] as String, 'cancelled'), child: const Text('Cancelled')),
                                TextButton(onPressed: () => _updateStatus(r['id'] as String, 'rejected'), child: const Text('Rejected')),
                                FilledButton(onPressed: () => _updateStatus(r['id'] as String, 'dispatched'), child: const Text('Dispatched')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
