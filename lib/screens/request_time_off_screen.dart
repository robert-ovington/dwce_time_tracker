/// Request Time Off – create leave_requests for current user.

import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../modules/auth/auth_service.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/errors/error_log_service.dart';

class RequestTimeOffScreen extends StatefulWidget {
  const RequestTimeOffScreen({super.key});

  @override
  State<RequestTimeOffScreen> createState() => _RequestTimeOffScreenState();
}

class _RequestTimeOffScreenState extends State<RequestTimeOffScreen> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final _reasonController = TextEditingController();
  bool _saving = false;
  List<Map<String, dynamic>> _managers = [];
  String? _selectedManagerId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadManagers();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadManagers() async {
    try {
      final typeRow = await SupabaseService.client.from('request_type').select('id').eq('code', 'time_off').maybeSingle();
      final typeId = typeRow != null && typeRow is Map ? typeRow['id']?.toString() : null;
      if (typeId != null) {
        final managerRows = await SupabaseService.client.from('request_manager_list').select('user_id, users_setup(display_name)').eq('request_type_id', typeId).order('display_order') as List<dynamic>;
        _managers = managerRows.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final us = m['users_setup'];
          final displayName = us is Map ? us['display_name']?.toString() : null;
          return {'user_id': m['user_id']?.toString(), 'display_name': displayName ?? ''};
        }).toList();
      } else {
        _managers = [];
      }
    } catch (e, st) {
      await ErrorLogService.logError(location: 'Request Time Off - Load managers', type: 'Database', description: '$e', stackTrace: st);
      _managers = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit() async {
    final uid = AuthService.getCurrentUser()?.id;
    if (uid == null) return;
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date must be on or after start date')));
      return;
    }
    if (_managers.isNotEmpty && _selectedManagerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select the manager to send the request to')));
      return;
    }
    setState(() => _saving = true);
    try {
      for (var d = DateTime(_startDate.year, _startDate.month, _startDate.day);
          !d.isAfter(DateTime(_endDate.year, _endDate.month, _endDate.day));
          d = d.add(const Duration(days: 1))) {
        final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        await SupabaseService.client.from('leave_requests').insert({
          'user_id': uid,
          'submission_date': dateStr,
          'reason': _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
          'status': 'submitted',
          if (_selectedManagerId != null) 'manager_id': _selectedManagerId,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time off requested'), backgroundColor: Colors.green));
        _reasonController.clear();
      }
    } catch (e, st) {
      await ErrorLogService.logError(location: 'Request Time Off', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Time Off'),
        actions: const [ScreenInfoIcon(screenName: 'request_time_off_screen.dart')],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedManagerId,
              decoration: InputDecoration(
                labelText: 'Send request to manager',
                hintText: _managers.isEmpty ? 'No managers configured for Time Off' : null,
              ),
              items: _managers.isEmpty
                  ? [const DropdownMenuItem(value: null, child: Text('— No managers configured —'))]
                  : [const DropdownMenuItem(value: null, child: Text('Select manager')), ..._managers.map((e) => DropdownMenuItem(value: e['user_id']?.toString(), child: Text(e['display_name']?.toString() ?? '')))],
              onChanged: _managers.isEmpty ? null : (v) => setState(() => _selectedManagerId = v),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Start date'),
              subtitle: Text('${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (d != null) setState(() => _startDate = d);
              },
            ),
            ListTile(
              title: const Text('End date'),
              subtitle: Text('${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _endDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (d != null) setState(() => _endDate = d);
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: _reasonController, decoration: const InputDecoration(labelText: 'Reason (optional)'), maxLines: 2),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
  }
}
