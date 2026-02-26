import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/screen_info_icon.dart';
import '../utils/run_import_script_stub.dart' if (dart.library.io) '../utils/run_import_script_io.dart' as run_import;

/// Import Payroll: select week, load employees from Excel (Allocated Week sheet),
/// select employees and run the Python import script. Duplicates and "Site 1"-"Site 20" rows are skipped.
/// Requires desktop (Python script); CSV file import is hidden for now.
class ImportPayrollScreen extends StatefulWidget {
  const ImportPayrollScreen({super.key});

  @override
  State<ImportPayrollScreen> createState() => _ImportPayrollScreenState();
}

class _ImportPayrollScreenState extends State<ImportPayrollScreen> {
  static const int _minWeek = 1;
  static const int _maxWeek = 52;

  int _selectedWeek = 1;
  List<String> _employeeNames = [];
  final Map<String, bool> _selected = {}; // name -> selected
  bool _loadingEmployees = false;
  bool _importing = false;
  String? _error;
  String? _importOutput;

  bool get _canRunScript => !kIsWeb;

  Future<void> _loadEmployees() async {
    if (!_canRunScript) return;
    setState(() {
      _error = null;
      _importOutput = null;
      _loadingEmployees = true;
      _employeeNames = [];
      _selected.clear();
    });
    try {
      final result = await run_import.runImportScript(
        [
          'code-workspace/import_payroll_bland_david.py',
          '--list-employees',
          '--week',
          '$_selectedWeek',
        ],
        _workingDirectory,
      );
      final stdout = result.stdout;
      final stderr = result.stderr;
      List<String> names = [];
      try {
        // Last line or only line may be JSON
        final lines = stdout.trim().split('\n');
        for (final line in lines.reversed) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final decoded = jsonDecode(trimmed) as Map<String, dynamic>?;
          if (decoded != null && decoded['employees'] != null) {
            names = List<String>.from(decoded['employees'] as List);
            break;
          }
        }
      } catch (_) {
        names = [];
      }
      setState(() {
        _loadingEmployees = false;
        _employeeNames = names;
        for (final n in names) {
          _selected[n] = true;
        }
        if (names.isEmpty && stderr.isNotEmpty) _error = stderr.split('\n').first;
        if (names.isEmpty && stdout.isEmpty && stderr.isEmpty) _error = 'No employees found. Check Excel path and sheet "Allocated Week ($_selectedWeek)".';
      });
    } catch (e) {
      setState(() {
        _loadingEmployees = false;
        _employeeNames = [];
        _error = 'Failed to run script: $e. Ensure Python is in PATH and run from project root.';
      });
    }
  }

  /// Pass empty so the IO implementation uses current directory (project root when run from IDE).
  String get _workingDirectory => '';

  Future<void> _runImport() async {
    if (!_canRunScript) return;
    final chosen = _selected.entries.where((e) => e.value).map((e) => e.key).toList();
    if (chosen.isEmpty) {
      setState(() => _error = 'Select at least one employee.');
      return;
    }
    setState(() {
      _error = null;
      _importOutput = null;
      _importing = true;
    });
    try {
      // Pass names with comma; if a name contains comma, script splits by comma so we need a safe separator or quote. Script uses split(",") so "Surname, Forename" would break. Use a different separator for the app->script contract, e.g. | or \t. So we'll use | and update the script to accept --employees with | as separator when from app. Actually the script says --employees "Name1,Name2" - so "Tracey, Paul" would become two names if we join with comma. So we need to pass in a way that preserves commas in names. Option: pass multiple --employees args, or use a separator that won't appear in names (e.g. | or \x00). Let me use | and update the Python script to split by | when the string contains |.
      final employeesArg = chosen.join('|');
      final result = await run_import.runImportScript(
        [
          'code-workspace/import_payroll_bland_david.py',
          '--week',
          '$_selectedWeek',
          '--employees',
          employeesArg,
        ],
        _workingDirectory,
      );
      final stdout = result.stdout;
      final stderr = result.stderr;
      setState(() {
        _importing = false;
        _importOutput = [stdout, if (stderr.isNotEmpty) stderr].join('\n').trim();
        if (result.exitCode != 0) _error = _importOutput;
      });
    } catch (e) {
      setState(() {
        _importing = false;
        _error = 'Import failed: $e';
      });
    }
  }

  void _selectAll(bool value) {
    setState(() {
      for (final k in _selected.keys) {
        _selected[k] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Payroll', style: TextStyle(color: Colors.black)),
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'import_payroll_screen.dart')],
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
                      'Import from Excel (Allocated Week)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _canRunScript
                          ? 'Select a week, load employees from the spreadsheet, choose who to import, then run Import. Entries already imported are skipped. Rows with Employee "Site 1"–"Site 20" are ignored.'
                          : 'Week and employee import is only available on desktop (requires Python and the import script). Use the Python script from the project root for import.',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            if (!_canRunScript) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.orange.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Run the script manually from project root:\n'
                    'python code-workspace/import_payroll_bland_david.py --list-employees --week 1\n'
                    'python code-workspace/import_payroll_bland_david.py --week 1 --employees "Name1,Name2"',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
            if (_canRunScript) ...[
              const SizedBox(height: 24),
              // Week selector
              Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Week:',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 16),
                    DropdownButton<int>(
                      value: _selectedWeek.clamp(_minWeek, _maxWeek),
                      items: List.generate(_maxWeek - _minWeek + 1, (i) => _minWeek + i)
                          .map((w) => DropdownMenuItem<int>(value: w, child: Text('Week $w')))
                          .toList(),
                      onChanged: _loadingEmployees || _importing
                          ? null
                          : (v) {
                              if (v != null) setState(() => _selectedWeek = v);
                            },
                    ),
                    const SizedBox(width: 24),
                    ElevatedButton.icon(
                      onPressed: (_loadingEmployees || _importing) ? null : _loadEmployees,
                      icon: _loadingEmployees ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 20),
                      label: Text(_loadingEmployees ? 'Loading…' : 'Load employees'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Employee list
            if (_employeeNames.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Employees (${_selected.values.where((v) => v).length}/${_employeeNames.length})',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: _importing ? null : () => _selectAll(true),
                            child: const Text('Select all'),
                          ),
                          TextButton(
                            onPressed: _importing ? null : () => _selectAll(false),
                            child: const Text('Select none'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _employeeNames.map((name) {
                              return CheckboxListTile(
                                value: _selected[name] ?? false,
                                onChanged: _importing ? null : (v) => setState(() => _selected[name] = v ?? false),
                                title: Text(name),
                                controlAffinity: ListTileControlAffinity.leading,
                                dense: true,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _importing ? null : _runImport,
                        icon: _importing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload, size: 20),
                        label: Text(_importing ? 'Importing…' : 'Import selected'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0081FB),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
                ),
              ),
            ],
            if (_importOutput != null && _error == null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_importOutput!, style: TextStyle(color: Colors.green.shade900)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
