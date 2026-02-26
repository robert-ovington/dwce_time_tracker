/// Request manager list – admin screen to assign managers per request type (Time Off, PPE).
/// Users on Request PPE / Request Time Off see only these managers in the dropdown.

import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../modules/errors/error_log_service.dart';
import '../widgets/screen_info_icon.dart';

class RequestManagerListScreen extends StatefulWidget {
  const RequestManagerListScreen({super.key});

  @override
  State<RequestManagerListScreen> createState() => _RequestManagerListScreenState();
}

class _RequestManagerListScreenState extends State<RequestManagerListScreen> {
  List<Map<String, dynamic>> _requestTypes = [];
  List<Map<String, dynamic>> _currentManagers = [];
  List<Map<String, dynamic>> _allManagers = [];
  String? _selectedTypeId;
  bool _loading = true;
  String _statusMessage = '';
  /// User IDs selected in the "available to add" list (multi-select before submit)
  final Set<String> _selectedToAdd = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final types = await SupabaseService.client.from('request_type').select('id, code, name').order('display_order') as List<dynamic>;
      _requestTypes = types.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (_requestTypes.isNotEmpty && _selectedTypeId == null) _selectedTypeId = _requestTypes.first['id']?.toString();
      await _loadManagersForType();
      // Pool: users with security between 2 and 3 (not role = Manager)
      final managers = await SupabaseService.client
          .from('users_setup')
          .select('user_id, display_name')
          .gte('security', 2)
          .lte('security', 3)
          .order('display_name') as List<dynamic>;
      _allManagers = managers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e, st) {
      ErrorLogService.logError(location: 'Request Manager List', type: 'Database', description: '$e', stackTrace: st);
      setState(() => _statusMessage = 'Error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _loadManagersForType() async {
    if (_selectedTypeId == null) {
      setState(() => _currentManagers = []);
      return;
    }
    try {
      final rows = await SupabaseService.client
          .from('request_manager_list')
          .select('id, user_id, users_setup(display_name)')
          .eq('request_type_id', _selectedTypeId!)
          .order('display_order') as List<dynamic>;
      _currentManagers = rows.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final us = m['users_setup'];
        m['display_name'] = us is Map ? us['display_name']?.toString() : '';
        return m;
      }).toList();
    } catch (e) {
      setState(() => _currentManagers = []);
    }
  }

  Future<void> _addSelectedManagers() async {
    if (_selectedTypeId == null || _selectedToAdd.isEmpty) return;
    setState(() => _saving = true);
    try {
      final rows = _selectedToAdd.map((userId) => {
        'request_type_id': _selectedTypeId,
        'user_id': userId,
      }).toList();
      await SupabaseService.client.from('request_manager_list').insert(rows);
      setState(() => _selectedToAdd.clear());
      await _loadManagersForType();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rows.length} manager(s) added'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
    setState(() => _saving = false);
  }

  Future<void> _removeManager(String listRowId) async {
    try {
      await SupabaseService.client.from('request_manager_list').delete().eq('id', listRowId);
      await _loadManagersForType();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manager removed'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final typeName = _requestTypes.isEmpty ? '' : (_requestTypes.firstWhere((t) => t['id']?.toString() == _selectedTypeId, orElse: () => _requestTypes.first))['name']?.toString() ?? '';
    final currentIds = _currentManagers.map((e) => e['user_id']?.toString()).whereType<String>().toSet();
    final availableToAdd = _allManagers.where((e) => !currentIds.contains(e['user_id']?.toString())).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request manager lists'),
        actions: const [ScreenInfoIcon(screenName: 'request_manager_list_screen.dart')],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_statusMessage.isNotEmpty) ...[
              Text(_statusMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            const Text('Select request type. Managers are users with Security 2–3. Add multiple, then submit.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedTypeId,
              decoration: const InputDecoration(labelText: 'Request type'),
              items: _requestTypes.map((t) => DropdownMenuItem(value: t['id']?.toString(), child: Text(t['name']?.toString() ?? ''))).toList(),
              onChanged: (v) async {
                setState(() {
                  _selectedTypeId = v;
                  _selectedToAdd.clear();
                });
                await _loadManagersForType();
              },
            ),
            const SizedBox(height: 24),
            Text('Already in list ($typeName)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_currentManagers.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No managers assigned. Add from the list below and submit.')))
            else
              ..._currentManagers.map((m) => Card(
                child: ListTile(
                  title: Text(m['display_name']?.toString() ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _removeManager(m['id']?.toString() ?? ''),
                  ),
                ),
              )),
            const SizedBox(height: 24),
            Text('Add managers (Security 2–3)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (availableToAdd.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('All users with Security 2–3 are already in the list, or none exist.')))
            else ...[
              ...availableToAdd.map((e) {
                final uid = e['user_id']?.toString() ?? '';
                final name = e['display_name']?.toString() ?? '';
                final isSelected = _selectedToAdd.contains(uid);
                return CheckboxListTile(
                  title: Text(name),
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) _selectedToAdd.add(uid);
                      else _selectedToAdd.remove(uid);
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: (_saving || _selectedToAdd.isEmpty) ? null : _addSelectedManagers,
                icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_circle_outline),
                label: Text(_selectedToAdd.isEmpty ? 'Select managers above, then submit' : 'Add ${_selectedToAdd.length} selected'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
