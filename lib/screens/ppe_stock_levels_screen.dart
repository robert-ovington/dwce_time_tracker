/// PPE Stock Levels – view on-hand stock from ppe_stock_levels view.

import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/errors/error_log_service.dart';

class PpeStockLevelsScreen extends StatefulWidget {
  const PpeStockLevelsScreen({super.key});

  @override
  State<PpeStockLevelsScreen> createState() => _PpeStockLevelsScreenState();
}

class _PpeStockLevelsScreenState extends State<PpeStockLevelsScreen> {
  List<Map<String, dynamic>> _levels = [];
  Map<String, String> _ppeNames = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await SupabaseService.client.from('ppe_stock_levels').select('ppe_id, size_id, size_code, on_hand').order('ppe_id').order('size_code') as List<dynamic>;
      final levels = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ppeIds = levels.map((e) => e['ppe_id']?.toString()).whereType<String>().toSet().toList();
      Map<String, String> names = {};
      if (ppeIds.isNotEmpty) {
        final plist = await SupabaseService.client.from('ppe_list').select('id, name').inFilter('id', ppeIds) as List<dynamic>;
        for (final p in plist) {
          final m = Map<String, dynamic>.from(p as Map);
          names[m['id']?.toString() ?? ''] = m['name']?.toString() ?? '';
        }
      }
      setState(() {
        _levels = levels;
        _ppeNames = names;
        _isLoading = false;
      });
    } catch (e, st) {
      await ErrorLogService.logError(location: 'PPE Stock Levels', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PPE Stock Levels'),
        actions: const [ScreenInfoIcon(screenName: 'ppe_stock_levels_screen.dart')],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _levels.isEmpty
                  ? const Center(child: Text('No stock levels'))
                  : ListView.builder(
                      itemCount: _levels.length,
                      itemBuilder: (context, i) {
                        final r = _levels[i];
                        final name = _ppeNames[r['ppe_id']?.toString() ?? ''] ?? r['ppe_id']?.toString() ?? '—';
                        return ListTile(
                          title: Text(name),
                          subtitle: Text('Size: ${r['size_code']}'),
                          trailing: Text('${r['on_hand']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
            ),
    );
  }
}
