import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/screen_info_icon.dart';

/// Export Payroll: query time_periods (and related) for a date range and
/// download CSV in two-tab layout (hours & allowances, project allocation)
/// for feeding back into Excel. See PAYROLL_IMPORT_EXPORT.md.
class ExportPayrollScreen extends StatefulWidget {
  const ExportPayrollScreen({super.key});

  @override
  State<ExportPayrollScreen> createState() => _ExportPayrollScreenState();
}

class _ExportPayrollScreenState extends State<ExportPayrollScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _loading = false;
  String? _message;

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _export() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    // TODO: Query time_periods (and related) for _startDate.._endDate,
    // build two CSVs (hours/allowances, project allocation), trigger download.
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _loading = false;
        _message = 'Export not yet implemented. Date range: '
            '${DateFormat('yyyy-MM-dd').format(_startDate)} to ${DateFormat('yyyy-MM-dd').format(_endDate)}. '
            'See PAYROLL_IMPORT_EXPORT.md for the planned two-tab CSV layout.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Payroll', style: TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'export_payroll_screen.dart')],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export to CSV for Excel',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select a date range. The app will export time period data in two files: '
                      '(1) hours & allowances per user, (2) project allocation. '
                      'You can open these in Excel or paste into your spreadsheet.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date range',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickStartDate,
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(DateFormat('yyyy-MM-dd').format(_startDate)),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('to'),
                        ),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickEndDate,
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(DateFormat('yyyy-MM-dd').format(_endDate)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _export,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download),
                      label: Text(_loading ? 'Preparing…' : 'Export CSV'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0081FB),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_message!, style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
