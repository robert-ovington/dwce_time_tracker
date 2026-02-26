/// Request type – admin screen to manage public.request_type (Time Off, PPE, etc.).

import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../modules/errors/error_log_service.dart';
import '../widgets/screen_info_icon.dart';

class RequestTypeScreen extends StatefulWidget {
  const RequestTypeScreen({super.key});

  @override
  State<RequestTypeScreen> createState() => _RequestTypeScreenState();
}

class _RequestTypeScreenState extends State<RequestTypeScreen> {
  List<Map<String, dynamic>> _types = [];
  bool _loading = true;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.client
          .from('request_type')
          .select('*')
          .order('display_order')
          .order('name') as List<dynamic>;
      _types = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _statusMessage = '';
    } catch (e, st) {
      ErrorLogService.logError(location: 'Request Type Screen', type: 'Database', description: '$e', stackTrace: st);
      setState(() => _statusMessage = 'Error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _showAddEdit({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final codeController = TextEditingController(text: existing?['code']?.toString() ?? '');
    final nameController = TextEditingController(text: existing?['name']?.toString() ?? '');
    final orderController = TextEditingController(text: existing?['display_order']?.toString() ?? '0');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit request type' : 'Add request type'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Code *',
                  hintText: 'e.g. time_off, ppe',
                ),
                enabled: !isEdit,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name *', hintText: 'e.g. Time Off, PPE'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: orderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Display order', hintText: '0'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              final name = nameController.text.trim();
              final order = int.tryParse(orderController.text.trim()) ?? 0;
              if (code.isEmpty || name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code and name are required')));
                return;
              }
              try {
                if (isEdit) {
                  await SupabaseService.client.from('request_type').update({
                    'name': name,
                    'display_order': order,
                    'updated_at': DateTime.now().toIso8601String(),
                  }).eq('id', existing!['id'] as Object);
                } else {
                  await SupabaseService.client.from('request_type').insert({
                    'code': code,
                    'name': name,
                    'display_order': order,
                  });
                }
                if (context.mounted) Navigator.pop(context, true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete request type?'),
        content: Text(
          'Delete "${row['name']}" (${row['code']})? Managers assigned to this type will also be removed from the list.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SupabaseService.client.from('request_type').delete().eq('id', row['id'] as Object);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted'), backgroundColor: Colors.green));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Type'),
        actions: const [ScreenInfoIcon(screenName: 'request_type_screen.dart')],
      ),
      body: Column(
        children: [
          if (_statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_statusMessage, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _types.isEmpty
                ? const Center(child: Text('No request types. Add one to use with Request List.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _types.length,
                    itemBuilder: (context, i) {
                      final t = _types[i];
                      return Card(
                        child: ListTile(
                          title: Text(t['name']?.toString() ?? ''),
                          subtitle: Text('${t['code']} • order ${t['display_order']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _showAddEdit(existing: t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(t),
                              ),
                            ],
                          ),
                          onTap: () => _showAddEdit(existing: t),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
