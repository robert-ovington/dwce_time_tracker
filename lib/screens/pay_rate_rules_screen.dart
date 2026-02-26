/// Pay Rate Rules Screen (Pay Types)
///
/// CRUD for public.pay_rate_rules. Access: Main Menu > Administration > Pay Types.

import 'package:flutter/material.dart';
import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/errors/error_log_service.dart';
import 'package:dwce_time_tracker/widgets/screen_info_icon.dart';

class PayRateRulesScreen extends StatefulWidget {
  const PayRateRulesScreen({super.key});

  @override
  State<PayRateRulesScreen> createState() => _PayRateRulesScreenState();
}

class _PayRateRulesScreenState extends State<PayRateRulesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ruleNameController = TextEditingController();
  final _monLimitController = TextEditingController();
  final _tueLimitController = TextEditingController();
  final _wedLimitController = TextEditingController();
  final _thuLimitController = TextEditingController();
  final _friLimitController = TextEditingController();
  final _satThLimitController = TextEditingController();
  final _weekdayFlatCutoffController = TextEditingController();

  List<Map<String, dynamic>> _rules = [];
  bool _flatMonFri = false;
  bool _flatSat = false;
  bool _noDouble = false;
  bool _isLoading = false;
  bool _isLoadingList = false;
  String _statusMessage = '';
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  @override
  void dispose() {
    _ruleNameController.dispose();
    _monLimitController.dispose();
    _tueLimitController.dispose();
    _wedLimitController.dispose();
    _thuLimitController.dispose();
    _friLimitController.dispose();
    _satThLimitController.dispose();
    _weekdayFlatCutoffController.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoadingList = true);
    try {
      // pay_rate_rules: order by rule_name uses idx_pay_rate_rules_rule_name (see supabase_indexes.md)
      final response = await SupabaseService.client
          .from('pay_rate_rules')
          .select()
          .order('rule_name');
      setState(() {
        _rules = List<Map<String, dynamic>>.from(response as List);
        _isLoadingList = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Pay Rate Rules Screen - Load',
        type: 'Database',
        description: 'Failed to load pay_rate_rules: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error loading rules: $e';
        _isLoadingList = false;
      });
    }
  }

  static int? _parseInt(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return int.tryParse(s.trim());
  }

  /// Send time as HH:mm or HH:mm:ss for time without time zone
  static String? _timeFromController(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    return t.length <= 5 ? t : t.substring(0, 5);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = _editingId == null ? 'Creating...' : 'Updating...';
    });

    try {
      final data = <String, dynamic>{
        'rule_name': _ruleNameController.text.trim(),
        'flat_mon_fri': _flatMonFri,
        'flat_sat': _flatSat,
        'no_double': _noDouble,
        'mon_flat_limit': _parseInt(_monLimitController.text),
        'tue_flat_limit': _parseInt(_tueLimitController.text),
        'wed_flat_limit': _parseInt(_wedLimitController.text),
        'thu_flat_limit': _parseInt(_thuLimitController.text),
        'fri_flat_limit': _parseInt(_friLimitController.text),
        'sat_th_limit': _parseInt(_satThLimitController.text),
        'weekday_flat_cutoff': _timeFromController(_weekdayFlatCutoffController.text),
      };

      if (_editingId == null) {
        await SupabaseService.client.from('pay_rate_rules').insert(data);
        setState(() => _statusMessage = '✅ Rule created.');
      } else {
        await SupabaseService.client
            .from('pay_rate_rules')
            .update(data)
            .eq('id', _editingId!);
        setState(() => _statusMessage = '✅ Rule updated.');
      }
      await _loadRules();
      _clearForm();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Pay Rate Rules Screen - Save',
        type: 'Database',
        description: 'Failed to save pay_rate_rule: $e',
        stackTrace: stackTrace,
      );
      setState(() => _statusMessage = '❌ Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _editRule(Map<String, dynamic> rule) {
    setState(() {
      _editingId = rule['id'] as String?;
      _ruleNameController.text = (rule['rule_name'] as String?) ?? '';
      _flatMonFri = rule['flat_mon_fri'] == true;
      _flatSat = rule['flat_sat'] == true;
      _noDouble = rule['no_double'] == true;
      _monLimitController.text = _limitToText(rule['mon_flat_limit']);
      _tueLimitController.text = _limitToText(rule['tue_flat_limit']);
      _wedLimitController.text = _limitToText(rule['wed_flat_limit']);
      _thuLimitController.text = _limitToText(rule['thu_flat_limit']);
      _friLimitController.text = _limitToText(rule['fri_flat_limit']);
      _satThLimitController.text = _limitToText(rule['sat_th_limit']);
      _weekdayFlatCutoffController.text =
          (rule['weekday_flat_cutoff']?.toString() ?? '').trim().length > 5
              ? (rule['weekday_flat_cutoff']?.toString() ?? '').substring(0, 5)
              : (rule['weekday_flat_cutoff']?.toString() ?? '').trim();
      _statusMessage = '';
    });
  }

  String _limitToText(dynamic v) {
    if (v == null) return '';
    if (v is int) return v.toString();
    final s = v.toString().trim();
    return s.isEmpty ? '' : s;
  }

  Future<void> _deleteRule(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Pay Rate Rule'),
        content: Text('Delete rule "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await SupabaseService.client.from('pay_rate_rules').delete().eq('id', id);
      setState(() => _statusMessage = '✅ Rule deleted.');
      await _loadRules();
      _clearForm();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Pay Rate Rules Screen - Delete',
        type: 'Database',
        description: 'Failed to delete pay_rate_rule: $e',
        stackTrace: stackTrace,
      );
      setState(() => _statusMessage = '❌ Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _ruleNameController.clear();
      _flatMonFri = false;
      _flatSat = false;
      _noDouble = false;
      _monLimitController.clear();
      _tueLimitController.clear();
      _wedLimitController.clear();
      _thuLimitController.clear();
      _friLimitController.clear();
      _satThLimitController.clear();
      _weekdayFlatCutoffController.clear();
      if (!_statusMessage.contains('❌')) _statusMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay Types'),
        actions: const [ScreenInfoIcon(screenName: 'pay_rate_rules_screen.dart')],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Pay rate rules',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Expanded(
                    child: _isLoadingList
                        ? const Center(child: CircularProgressIndicator())
                        : _rules.isEmpty
                            ? const Center(child: Text('No rules'))
                            : ListView.builder(
                                itemCount: _rules.length,
                                itemBuilder: (context, index) {
                                  final r = _rules[index];
                                  final id = r['id'] as String? ?? '';
                                  final name =
                                      (r['rule_name'] as String?) ?? 'Unnamed';
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    color: _editingId == id
                                        ? Colors.blue.shade50
                                        : null,
                                    child: ListTile(
                                      title: Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: _editingId == id
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () => _editRule(r),
                                            tooltip: 'Edit',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () =>
                                                _deleteRule(id, name),
                                            tooltip: 'Delete',
                                            color: Colors.red,
                                          ),
                                        ],
                                      ),
                                      onTap: () => _editRule(r),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_statusMessage.isNotEmpty)
                      Card(
                        color: _statusMessage.contains('✅')
                            ? Colors.green.shade50
                            : _statusMessage.contains('❌')
                                ? Colors.red.shade50
                                : Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(_statusMessage, style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      _editingId == null
                          ? 'New pay rate rule'
                          : 'Edit pay rate rule',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _ruleNameController,
                      decoration: const InputDecoration(
                        labelText: 'Rule name *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('Flat Mon–Fri'),
                      value: _flatMonFri,
                      onChanged: (v) =>
                          setState(() => _flatMonFri = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      title: const Text('Flat Sat'),
                      value: _flatSat,
                      onChanged: (v) =>
                          setState(() => _flatSat = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      title: const Text('No double'),
                      value: _noDouble,
                      onChanged: (v) =>
                          setState(() => _noDouble = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 12),
                    const Text('Daily flat limits (optional)',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _limitField('Mon', _monLimitController)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _limitField('Tue', _tueLimitController)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _limitField('Wed', _wedLimitController)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _limitField('Thu', _thuLimitController)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _limitField('Fri', _friLimitController)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _limitField('Sat/TH', _satThLimitController)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _weekdayFlatCutoffController,
                      decoration: const InputDecoration(
                        labelText: 'Weekday flat cutoff (time)',
                        hintText: 'HH:mm',
                        border: OutlineInputBorder(),
                        helperText: 'Optional; e.g. 17:30',
                      ),
                      keyboardType: TextInputType.datetime,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _isLoading ? null : _save,
                          child: Text(_editingId == null ? 'Create' : 'Update'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: _clearForm,
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        if (int.tryParse(v.trim()) == null) return 'Number';
        return null;
      },
    );
  }
}
