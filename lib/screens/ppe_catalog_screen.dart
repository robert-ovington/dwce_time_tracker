/// PPE Catalog – list and manage PPE items (ppe_list). Manager-only create/edit.

import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/errors/error_log_service.dart';

class PpeCatalogScreen extends StatefulWidget {
  const PpeCatalogScreen({super.key});

  @override
  State<PpeCatalogScreen> createState() => _PpeCatalogScreenState();
}

class _PpeCatalogScreenState extends State<PpeCatalogScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      // Source: ppe_list (id, name, category, is_active)
      final q = SupabaseService.client.from('ppe_list').select('id, name, category, is_active');
      final list = await (_showInactive ? q.order('name') : q.eq('is_active', true).order('name')) as List<dynamic>;
      setState(() {
        _items = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _isLoading = false;
      });
    } catch (e, st) {
      await ErrorLogService.logError(
        location: 'PPE Catalog - Load',
        type: 'Database',
        description: '$e',
        stackTrace: st,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addOrEdit([Map<String, dynamic>? item]) async {
    final nameController = TextEditingController(text: item?['name']?.toString() ?? '');
    final isNew = item == null;
    String category = item?['category']?.toString() ?? 'clothing';
    bool isActive = (item?['is_active'] as bool?) ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(isNew ? 'Add PPE item' : 'Edit PPE item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(value: 'clothing', child: Text('Clothing')),
                    DropdownMenuItem(value: 'footwear', child: Text('Footwear')),
                  ],
                  onChanged: isNew ? (v) => setDialog(() => category = v ?? 'clothing') : null,
                ),
                if (!isNew) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Active'),
                    value: isActive,
                    onChanged: (v) => setDialog(() => isActive = v ?? true),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                try {
                  if (isNew) {
                    await SupabaseService.client.from('ppe_list').insert({
                      'name': nameController.text.trim(),
                      'category': category,
                      'is_active': true,
                    });
                  } else {
                    await SupabaseService.client.from('ppe_list').update({
                      'name': nameController.text.trim(),
                      'is_active': isActive,
                    }).eq('id', item!['id'] as Object);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PPE Catalog'),
        actions: [
          IconButton(
            icon: Icon(_showInactive ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() => _showInactive = !_showInactive);
              _load();
            },
          ),
          const ScreenInfoIcon(screenName: 'ppe_catalog_screen.dart'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final it = _items[i];
                return ListTile(
                  title: Text(it['name']?.toString() ?? ''),
                  subtitle: Text('${it['category']} • ${(it['is_active'] as bool?) == true ? 'Active' : 'Inactive'}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _addOrEdit(it),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
