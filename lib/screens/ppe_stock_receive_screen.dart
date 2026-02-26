/// Stock / Receive PPE – record deliveries in ppe_stock (transaction_type = receive).

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/supabase_config.dart';
import '../utils/export_file.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';
import '../widgets/screen_info_icon.dart';
class _SizeOption {
  const _SizeOption({required this.id, required this.sizeCode});
  final String id;
  final String sizeCode;
}

class PpeStockReceiveScreen extends StatefulWidget {
  const PpeStockReceiveScreen({super.key});

  @override
  State<PpeStockReceiveScreen> createState() => _PpeStockReceiveScreenState();
}

class _PpeStockReceiveScreenState extends State<PpeStockReceiveScreen> {
  List<Map<String, dynamic>> _ppeList = [];
  List<_SizeOption> _sizesForSelected = [];
  bool _loading = true;
  bool _loadingSizes = false;
  String? _selectedPpeId;
  String? _selectedSizeId;
  final _qtyController = TextEditingController(text: '1');
  final _costController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  bool _saving = false;
  bool _importingCsv = false;

  static const String _templateAssetPath = 'assets/templates/ppe_stock_import_template.csv';

  Future<void> _downloadTemplate() async {
    try {
      final contents = await rootBundle.loadString(_templateAssetPath);
      final path = await saveTextFile(
        filename: 'ppe_stock_import_template.csv',
        contents: contents,
        mimeType: 'text/csv',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(path != null ? 'Template saved' : 'Template downloaded'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not download template: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Source: ppe_list (id, name, category, is_active)
      final list = await SupabaseService.client.from('ppe_list').select('id, name, category').eq('is_active', true).order('name') as List<dynamic>;
      _ppeList = (list as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['id'] != null && e['id'].toString().trim().isNotEmpty)
          .map((e) => {
                'id': e['id'].toString().trim(),
                'name': e['name']?.toString().trim() ?? '',
                'category': e['category']?.toString().trim() ?? 'clothing',
              })
          .toList();
      setState(() => _loading = false);
    } catch (e, st) {
      ErrorLogService.logError(location: 'PPE Stock Receive - Load', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSizesForSelectedItem() async {
    final ppeId = _selectedPpeId;
    if (ppeId == null) {
      setState(() => _sizesForSelected = []);
      return;
    }
    Map<String, dynamic>? item;
    for (final e in _ppeList) {
      if (e['id']?.toString() == ppeId) { item = e; break; }
    }
    if (item == null) {
      setState(() => _sizesForSelected = []);
      return;
    }
    setState(() => _loadingSizes = true);
    try {
      final category = item['category']?.toString() ?? 'clothing';
      final list = await SupabaseService.client.from('ppe_sizes').select('id, size_code, sort_order').eq('category', category).eq('is_active', true).order('sort_order').order('size_code') as List<dynamic>;
      final options = (list as List<dynamic>).map((e) {
        final m = e as Map;
        return _SizeOption(id: m['id']?.toString() ?? '', sizeCode: m['size_code']?.toString() ?? '');
      }).where((o) => o.id.isNotEmpty).toList();
      if (mounted) {
        setState(() {
          _sizesForSelected = options;
          _loadingSizes = false;
          if (!options.any((o) => o.id == _selectedSizeId)) _selectedSizeId = options.isNotEmpty ? options.first.id : null;
        });
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'PPE Stock Receive - Load sizes', type: 'Database', description: '$e', stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
        setState(() {
          _sizesForSelected = [];
          _loadingSizes = false;
          _selectedSizeId = null;
        });
      }
    }
  }

  Future<void> _submit() async {
    final uid = AuthService.getCurrentUser()?.id;
    if (uid == null || _selectedPpeId == null || _selectedSizeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select PPE and size')));
      return;
    }
    final qty = int.tryParse(_qtyController.text);
    final cost = double.tryParse(_costController.text);
    if (qty == null || qty < 0 || cost == null || cost < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valid quantity and unit cost required')));
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService.client.from('ppe_stock').insert({
        'ppe_id': _selectedPpeId,
        'size_id': _selectedSizeId,
        'quantity': qty,
        'price': cost,
        'transaction_type': 'receive',
        'transaction_date': DateTime.now().toUtc().toIso8601String(),
        'user_id': uid,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Received'), backgroundColor: Colors.green));
        _qtyController.text = '1';
        _costController.text = '0';
        _notesController.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
    setState(() => _saving = false);
  }

  /// Parse one CSV line respecting quoted commas.
  static List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        values.add(current.toString().trim());
        current.clear();
      } else {
        current.write(char);
      }
    }
    values.add(current.toString().trim());
    return values;
  }

  /// Try parse date string; return null if invalid. Tries ISO then dd/MM/yyyy, MM/dd/yyyy.
  static DateTime? _parseDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    try {
      final iso = DateTime.tryParse(t);
      if (iso != null) return iso;
    } catch (_) {}
    final parts = t.split(RegExp(r'[/\-.]'));
    if (parts.length >= 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null && y > 1900 && y < 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        try {
          return DateTime(y, m, d);
        } catch (_) {}
      }
      final y2 = int.tryParse(parts[0]);
      final m2 = int.tryParse(parts[1]);
      final d2 = int.tryParse(parts[2]);
      if (y2 != null && m2 != null && d2 != null && y2 > 1900 && y2 < 2100 && m2 >= 1 && m2 <= 12 && d2 >= 1 && d2 <= 31) {
        try {
          return DateTime(y2, m2, d2);
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> _importCsv() async {
    final uid = AuthService.getCurrentUser()?.id;
    if (uid == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read file')));
      return;
    }
    setState(() => _importingCsv = true);
    try {
      final csvContent = utf8.decode(bytes);
      final lines = csvContent.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (lines.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV is empty')));
        setState(() => _importingCsv = false);
        return;
      }
      final header = _parseCsvLine(lines[0]);
      final headerLower = header.map((e) => e.toLowerCase().trim()).toList();
      int idxDate = headerLower.indexOf('date');
      int idxPpeItem = headerLower.indexOf('ppe item');
      if (idxPpeItem < 0) idxPpeItem = headerLower.indexWhere((e) => e.contains('ppe') && e.contains('item'));
      int idxSize = headerLower.indexOf('size');
      int idxQty = headerLower.indexOf('quantity');
      int idxUnitCost = headerLower.indexOf('unit cost');
      int idxNotes = headerLower.indexOf('notes');
      if (idxPpeItem < 0) {
        final alt = headerLower.indexWhere((e) => e.contains('ppe') && e.contains('item'));
        if (alt >= 0) idxPpeItem = alt;
      }
      if (idxDate < 0 || idxPpeItem < 0 || idxSize < 0 || idxQty < 0 || idxUnitCost < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('CSV must have columns: Date, PPE Item, Size, Quantity, Unit Cost. Optional: Notes'),
            backgroundColor: Colors.orange,
          ));
        }
        setState(() => _importingCsv = false);
        return;
      }
      final nameToPpe = <String, Map<String, dynamic>>{};
      for (final p in _ppeList) {
        final name = (p['name']?.toString() ?? '').trim();
        if (name.isNotEmpty) nameToPpe[name] = p;
      }
      final sizesRows = await SupabaseService.client.from('ppe_sizes').select('id, category, size_code').eq('is_active', true) as List<dynamic>;
      final sizeIdByCategoryCode = <String, String>{};
      for (final s in sizesRows) {
        final m = s as Map;
        final cat = m['category']?.toString() ?? '';
        final code = m['size_code']?.toString() ?? '';
        if (cat.isNotEmpty && code.isNotEmpty) sizeIdByCategoryCode['$cat|$code'] = m['id']?.toString() ?? '';
      }
      int imported = 0;
      int skipped = 0;
      for (var i = 1; i < lines.length; i++) {
        final values = _parseCsvLine(lines[i]);
        if (values.length <= idxQty) continue;
        final ppeName = (values.length > idxPpeItem ? values[idxPpeItem] : '').trim();
        final sizeCode = (values.length > idxSize ? values[idxSize] : '').trim();
        final qtyStr = values.length > idxQty ? values[idxQty] : '0';
        final costStr = values.length > idxUnitCost ? values[idxUnitCost] : '0';
        final ppe = nameToPpe[ppeName];
        if (ppe == null || ppeName.isEmpty) {
          skipped++;
          continue;
        }
        final ppeId = ppe['id']?.toString() ?? '';
        final category = ppe['category']?.toString() ?? 'clothing';
        final sizeId = sizeIdByCategoryCode['$category|$sizeCode'];
        if (sizeId == null || sizeId.isEmpty) {
          skipped++;
          continue;
        }
        final qty = int.tryParse(qtyStr.replaceAll(RegExp(r'[^\d\-]'), '')) ?? 0;
        final cost = double.tryParse(costStr.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
        if (qty < 0 || cost < 0) {
          skipped++;
          continue;
        }
        final dateStr = values.length > idxDate ? values[idxDate] : '';
        final txnDate = _parseDate(dateStr);
        try {
          await SupabaseService.client.from('ppe_stock').insert({
            'ppe_id': ppeId,
            'size_id': sizeId,
            'quantity': qty,
            'price': cost,
            'transaction_type': 'receive',
            'transaction_date': txnDate?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String(),
            'user_id': uid,
          });
          imported++;
        } catch (_) {
          skipped++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imported $imported row(s)${skipped > 0 ? "; $skipped skipped" : ""}'),
          backgroundColor: imported > 0 ? Colors.green : Colors.orange,
        ));
      }
    } catch (e, st) {
      await ErrorLogService.logError(location: 'PPE Stock Receive - CSV import', type: 'Import', description: '$e', stackTrace: st);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red));
    }
    setState(() => _importingCsv = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock / Receive PPE'),
        actions: [
          TextButton.icon(
            onPressed: _downloadTemplate,
            icon: const Icon(Icons.download),
            label: const Text('Download template'),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import CSV',
            onPressed: _importingCsv ? null : _importCsv,
          ),
          const ScreenInfoIcon(screenName: 'ppe_stock_receive_screen.dart'),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedPpeId,
              decoration: const InputDecoration(labelText: 'PPE item'),
              items: _ppeList.map((e) => DropdownMenuItem(value: e['id']?.toString(), child: Text(e['name']?.toString() ?? ''))).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedPpeId = v;
                  _selectedSizeId = null;
                  _sizesForSelected = [];
                });
                if (v != null) _loadSizesForSelectedItem();
              },
            ),
            const SizedBox(height: 12),
            _loadingSizes
                ? const InputDecorator(
                    decoration: InputDecoration(labelText: 'Size'),
                    child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : DropdownButtonFormField<String>(
                    value: _sizesForSelected.any((o) => o.id == _selectedSizeId) ? _selectedSizeId : null,
                    decoration: const InputDecoration(labelText: 'Size'),
                    items: _sizesForSelected.map((o) => DropdownMenuItem(value: o.id, child: Text(o.sizeCode))).toList(),
                    onChanged: _sizesForSelected.isEmpty ? null : (v) => setState(() => _selectedSizeId = v),
                  ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity received'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Unit cost'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Record receipt'),
            ),
          ],
        ),
      ),
    );
  }
}
