/// My Time Off Requests – list current user's leave_requests.

import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';

class MyTimeOffRequestsScreen extends StatefulWidget {
  const MyTimeOffRequestsScreen({super.key});

  @override
  State<MyTimeOffRequestsScreen> createState() => _MyTimeOffRequestsScreenState();
}

class _MyTimeOffRequestsScreenState extends State<MyTimeOffRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = AuthService.getCurrentUser()?.id;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.client
          .from('leave_requests')
          .select('*')
          .eq('user_id', uid)
          .order('submission_date', ascending: false) as List<dynamic>;
      _requests = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() => _loading = false);
    } catch (e, st) {
      await ErrorLogService.logError(location: 'My Time Off Requests', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Time Off Requests'),
        actions: const [ScreenInfoIcon(screenName: 'my_time_off_requests_screen.dart')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? const Center(child: Text('No time off requests yet'))
                  : ListView.builder(
                      itemCount: _requests.length,
                      itemBuilder: (context, i) {
                        final r = _requests[i];
                        final date = r['submission_date']?.toString() ?? '—';
                        final status = r['status']?.toString() ?? '—';
                        return ListTile(
                          title: Text(date),
                          subtitle: Text('${r['reason'] ?? '—'} • $status'),
                        );
                      },
                    ),
            ),
    );
  }
}
