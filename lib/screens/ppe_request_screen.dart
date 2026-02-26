/// Request PPE – create a new ppe_requests for current user.

import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../widgets/screen_info_icon.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';
import '../modules/messaging/messaging_service.dart';
class PpeRequestScreen extends StatefulWidget {
  const PpeRequestScreen({super.key});

  @override
  State<PpeRequestScreen> createState() => _PpeRequestScreenState();
}

class _SizeOption {
  const _SizeOption({required this.id, required this.sizeCode});
  final String id;
  final String sizeCode;
}

class _PpeRequestScreenState extends State<PpeRequestScreen> {
  List<Map<String, dynamic>> _ppeList = [];
  List<Map<String, dynamic>> _managers = [];
  List<_SizeOption> _sizesForSelected = [];
  String? _requesterDisplayName;
  bool _loading = true;
  bool _loadingSizes = false;
  String? _selectedPpeId;
  String? _selectedSizeId;
  /// Saved when an item is added; used to prefill size when a new PPE is selected (if valid for that PPE).
  String? _savedSizeId;
  String? _selectedManagerId;
  final _qtyController = TextEditingController(text: '1');
  final _reasonController = TextEditingController();
  bool _saving = false;
  final List<Map<String, dynamic>> _lineItems = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = AuthService.getCurrentUser()?.id;
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
      final typeRow = await SupabaseService.client.from('request_type').select('id').eq('code', 'ppe').maybeSingle();
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
      if (uid != null) {
        final me = await SupabaseService.client.from('users_setup').select('display_name').eq('user_id', uid).maybeSingle();
        if (me != null && me is Map) _requesterDisplayName = me['display_name']?.toString();
      }
      setState(() => _loading = false);
    } catch (e, st) {
      ErrorLogService.logError(location: 'PPE Request - Load', type: 'Database', description: '$e', stackTrace: st);
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
      if (e['id'] == ppeId) { item = e; break; }
    }
    if (item == null) {
      setState(() => _sizesForSelected = []);
      return;
    }
    setState(() => _loadingSizes = true);
    try {
      // Source: ppe_sizes (id, category, size_code, is_active, sort_order) filtered by selected item's category
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
          // Use saved size from last add if valid for this PPE; otherwise "Select Size"
          _selectedSizeId = _savedSizeId != null && options.any((o) => o.id == _savedSizeId) ? _savedSizeId : null;
        });
      }
    } catch (e, st) {
      ErrorLogService.logError(location: 'PPE Request - Load sizes', type: 'Database', description: '$e', stackTrace: st);
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

  void _addToList() {
    _SizeOption? opt;
    for (final o in _sizesForSelected) {
      if (o.id == _selectedSizeId) { opt = o; break; }
    }
    if (_selectedPpeId == null || opt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select PPE and size')));
      return;
    }
    final sizeOpt = opt!;
    final qty = int.tryParse(_qtyController.text);
    if (qty == null || qty < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantity must be at least 1')));
      return;
    }
    String ppeName = 'PPE item';
    for (final e in _ppeList) {
      if (e['id']?.toString() == _selectedPpeId) {
        ppeName = e['name']?.toString() ?? ppeName;
        break;
      }
    }
    setState(() {
      _lineItems.add({
        'ppe_id': _selectedPpeId,
        'ppe_name': ppeName,
        'size_id': sizeOpt.id,
        'size_code': sizeOpt.sizeCode,
        'quantity': qty,
        'reason': _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
      });
      _qtyController.text = '1';
      _reasonController.clear();
      _savedSizeId = sizeOpt.id;
      _selectedPpeId = null;
    });
  }

  Future<void> _submit() async {
    final uid = AuthService.getCurrentUser()?.id;
    if (uid == null) return;
    if (_managers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No managers are configured for PPE requests. Please ask an administrator to add managers in Administration.')));
      return;
    }
    if (_selectedManagerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select the manager to send the request to')));
      return;
    }
    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item to the request')));
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      for (final line in _lineItems) {
        final qty = line['quantity'] as int? ?? 1;
        for (var i = 0; i < qty; i++) {
          await SupabaseService.client.from('ppe_requests').insert({
            'user_id': uid,
            'manager_id': _selectedManagerId,
            'ppe_id': line['ppe_id'],
            'size_id': line['size_id'],
            'reason': line['reason'],
            'status': 'submitted',
            'requested_date': now,
          }).select('id');
        }
      }
      final requester = _requesterDisplayName ?? 'A user';
      final parts = _lineItems.map((l) => '${l['ppe_name']} ${l['size_code']} × ${l['quantity']}').toList();
      final summary = 'PPE Request (${_lineItems.length} item(s)): ${parts.join('; ')}. Requested by $requester.';
      await MessagingService.sendMessage(recipientId: _selectedManagerId!, message: summary, isImportant: true);
      final ppeManagers = await SupabaseService.client.from('users_setup').select('user_id').eq('ppe_manager', true) as List<dynamic>;
      final managerIds = ppeManagers.map((e) => (e as Map)['user_id']?.toString()).whereType<String>().toSet();
      for (final pmId in managerIds) {
        if (pmId != _selectedManagerId) {
          await MessagingService.sendMessage(recipientId: pmId, message: summary, isImportant: false);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_lineItems.length} request(s) submitted'), backgroundColor: Colors.green));
        _lineItems.clear();
        _qtyController.text = '1';
        _reasonController.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
    setState(() => _saving = false);
  }

  /// Section card in timesheet style: bordered container, blue header, padded content.
  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request PPE'),
        actions: const [ScreenInfoIcon(screenName: 'ppe_request_screen.dart')],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionCard(
              title: 'Send request to',
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedManagerId,
                  decoration: InputDecoration(
                    labelText: 'Manager',
                    hintText: _managers.isEmpty ? 'No managers configured for PPE' : null,
                  ),
                  items: _managers.isEmpty
                      ? [const DropdownMenuItem(value: null, child: Text('— No managers configured —'))]
                      : [
                          const DropdownMenuItem(value: null, child: Text('Select manager')),
                          ..._managers.map((e) => DropdownMenuItem(
                                value: e['user_id']?.toString(),
                                child: Text(e['display_name']?.toString() ?? ''),
                              )),
                        ],
                  onChanged: _managers.isEmpty ? null : (v) => setState(() => _selectedManagerId = v),
                ),
              ],
            ),
            _buildSectionCard(
              title: 'Add items',
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedPpeId != null && _ppeList.any((e) => e['id'] == _selectedPpeId) ? _selectedPpeId : null,
                  decoration: InputDecoration(
                    labelText: 'PPE item',
                    hintText: _ppeList.isEmpty ? 'No PPE items' : null,
                  ),
                  items: _ppeList.isEmpty
                      ? [const DropdownMenuItem(value: null, child: Text('— No PPE items —'))]
                      : [
                          const DropdownMenuItem(value: null, child: Text('Select PPE item')),
                          ..._ppeList.map((e) => DropdownMenuItem<String>(
                                value: e['id'] as String,
                                child: Text((e['name'] as String).isEmpty ? e['id'] as String : e['name'] as String),
                              )),
                        ],
                  onChanged: _ppeList.isEmpty
                      ? null
                      : (v) {
                          setState(() => _selectedPpeId = v);
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
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Select Size')),
                          ..._sizesForSelected.map((o) => DropdownMenuItem(value: o.id, child: Text(o.sizeCode))),
                        ],
                        onChanged: _sizesForSelected.isEmpty ? null : (v) => setState(() => _selectedSizeId = v),
                      ),
                const SizedBox(height: 12),
                TextField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(labelText: 'Reason (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _addToList,
                  icon: const Icon(Icons.add),
                  label: const Text('Add to list'),
                ),
              ],
            ),
            if (_lineItems.isNotEmpty) ...[
              _buildSectionCard(
                title: 'Request list (${_lineItems.length})',
                children: [
                  ..._lineItems.asMap().entries.map((e) {
                    final i = e.key;
                    final line = e.value;
                    final reason = line['reason'] as String?;
                    final hasReason = reason != null && reason.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${line['ppe_name']} • ${line['size_code']} × ${line['quantity']}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (hasReason)
                                  Text(
                                    reason!,
                                    style: Theme.of(context).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => setState(() => _lineItems.removeAt(i)),
                            tooltip: 'Remove',
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit request'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
