/// Employer Management Screen
/// 
/// Interface for creating, editing, and managing employers
/// Allows CRUD operations on public.employers table

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../modules/employers/employer_service.dart';
import '../modules/employers/employer_csv_parser.dart';
import '../modules/errors/error_log_service.dart';

class EmployerManagementScreen extends StatefulWidget {
  const EmployerManagementScreen({super.key});

  @override
  State<EmployerManagementScreen> createState() => _EmployerManagementScreenState();
}

class _EmployerManagementScreenState extends State<EmployerManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employerNameController = TextEditingController();
  
  List<Map<String, dynamic>> _employers = [];
  List<String> _employerTypes = [];
  String? _selectedEmployerType;
  bool _isActive = true;
  bool _isLoading = false;
  String _statusMessage = '';
  String? _editingEmployerId;
  bool _isLoadingList = false;

  @override
  void initState() {
    super.initState();
    _loadEmployers();
    _loadEmployerTypes();
  }

  @override
  void dispose() {
    _employerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployers() async {
    setState(() {
      _isLoadingList = true;
    });

    try {
      final employers = await EmployerService.getAllEmployers();
      setState(() {
        _employers = employers;
        _isLoadingList = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Employer Management Screen - Load Employers',
        type: 'Database',
        description: 'Failed to load employers: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error loading employers: $e';
        _isLoadingList = false;
      });
    }
  }

  Future<void> _loadEmployerTypes() async {
    try {
      final types = await EmployerService.getEmployerTypes();
      setState(() {
        _employerTypes = types;
        if (types.isEmpty) {
          print('⚠️ No employer types found in employer_type table');
        } else {
          print('✅ Loaded ${types.length} employer types');
        }
      });
    } catch (e, stackTrace) {
      print('⚠️ Error loading employer types: $e');
      await ErrorLogService.logError(
        location: 'Employer Management Screen - Load Employer Types',
        type: 'Database',
        description: 'Failed to load employer types: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _employerTypes = [];
      });
    }
  }

  Future<void> _saveEmployer() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedEmployerType == null || _selectedEmployerType!.isEmpty) {
      setState(() {
        _statusMessage = '❌ Please select an employer type';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = _editingEmployerId == null ? 'Creating employer...' : 'Updating employer...';
    });

    try {
      if (_editingEmployerId == null) {
        // Create new employer
        await EmployerService.createEmployer(
          employerName: _employerNameController.text.trim(),
          employerType: _selectedEmployerType!,
          isActive: _isActive,
        );
        setState(() {
          _statusMessage = '✅ Employer created successfully!';
        });
      } else {
        // Update existing employer
        await EmployerService.updateEmployer(
          id: _editingEmployerId!,
          employerName: _employerNameController.text.trim(),
          employerType: _selectedEmployerType,
          isActive: _isActive,
        );
        setState(() {
          _statusMessage = '✅ Employer updated successfully!';
        });
      }

      // Reload list and clear form
      await _loadEmployers();
      _clearForm();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Employer Management Screen - Save Employer',
        type: 'Database',
        description: 'Failed to save employer "${_employerNameController.text}": $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _editEmployer(Map<String, dynamic> employer) async {
    setState(() {
      _editingEmployerId = employer['id'] as String;
      _employerNameController.text = (employer['employer_name'] as String?) ?? '';
      _selectedEmployerType = employer['employer_type'] as String?;
      _isActive = employer['is_active'] as bool? ?? true;
      _statusMessage = '';
    });
    
    // Scroll to form
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      Scrollable.ensureVisible(
        _formKey.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _deleteEmployer(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employer'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Deleting employer...';
      });

      try {
        await EmployerService.deleteEmployer(id);
        setState(() {
          _statusMessage = '✅ Employer deleted successfully!';
        });
        await _loadEmployers();
      } catch (e, stackTrace) {
        await ErrorLogService.logError(
          location: 'Employer Management Screen - Delete Employer',
          type: 'Database',
          description: 'Failed to delete employer with id $id: $e',
          stackTrace: stackTrace,
        );
        setState(() {
          _statusMessage = '❌ Error deleting employer: $e';
        });
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearForm() {
    setState(() {
      _editingEmployerId = null;
      _employerNameController.clear();
      _selectedEmployerType = null;
      _isActive = true;
    });
  }

  Future<void> _importFromCsv() async {
    try {
      print('🔍 Starting employer CSV import...');
      
      setState(() {
        _isLoading = true;
        _statusMessage = 'Selecting CSV file...';
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      print('🔍 File picker result: ${result != null ? 'File selected' : 'No file selected'}');

      if (result == null) {
        setState(() {
          _statusMessage = '⚠️ No file selected';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Reading CSV file...';
      });

      final file = result.files.single;
      print('🔍 File name: ${file.name}, size: ${file.size} bytes');
      
      final bytes = file.bytes;
      if (bytes == null) {
        print('❌ File bytes are null');
        setState(() {
          _statusMessage = '❌ Could not read file. Make sure the file is a valid CSV.';
          _isLoading = false;
        });
        return;
      }

      print('🔍 File bytes length: ${bytes.length}');
      final csvContent = utf8.decode(bytes);
      print('🔍 CSV content length: ${csvContent.length}');

      final employers = EmployerCsvParser.parseEmployersCsv(csvContent);
      print('🔍 Parsed employers count: ${employers.length}');

      if (employers.isEmpty) {
        setState(() {
          _statusMessage = '❌ No valid employers found in CSV file.\n\n'
              'Make sure:\n'
              '1. CSV has header row: employer_name,employer_type,is_active\n'
              '2. All required fields are filled (employer_name, employer_type)\n'
              '3. is_active is optional (true/false/yes/1, defaults to true)';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Importing ${employers.length} employer(s)...';
      });

      print('🔍 Starting bulk employer creation...');
      final results = await EmployerService.createEmployersBulk(employers);
      print('🔍 Bulk creation complete. Results: $results');

      final successCount = results.where((r) => r['success'] == true).length;
      final failCount = results.length - successCount;

      setState(() {
        if (successCount > 0 && failCount == 0) {
          _statusMessage = '✅ Import complete!\n\n'
              'Successfully imported: $successCount employer(s)';
        } else if (successCount > 0 && failCount > 0) {
          _statusMessage = '⚠️ Partial success!\n\n'
              'Successful: $successCount\n'
              'Failed: $failCount\n\n'
              'Failed employers:';
          for (var result in results) {
            if (result['success'] == false) {
              _statusMessage += '\n- ${result['employer_name']}: ${result['error']}';
            }
          }
        } else {
          _statusMessage = '❌ Import failed!\n\n'
              'All $failCount employer(s) failed:\n';
          for (var result in results) {
            if (result['success'] == false) {
              _statusMessage += '\n- ${result['employer_name']}: ${result['error']}';
            }
          }
        }
      });

      await _loadEmployers();
    } catch (e, stackTrace) {
      print('❌ CSV import error: $e');
      print('❌ Stack trace: $stackTrace');
      await ErrorLogService.logError(
        location: 'Employer Management Screen - Import CSV',
        type: 'File Processing',
        description: 'Failed to import CSV file: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error importing CSV: $e\n\n'
            'Please check:\n'
            '1. File is a valid CSV format\n'
            '2. File is not corrupted\n'
            '3. You have proper permissions';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _downloadCsvTemplate() {
    final template = EmployerCsvParser.generateCsvTemplate();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('CSV Template'),
        content: SingleChildScrollView(
          child: Text(template),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0081FB), // #0081FB
        title: const Text(
          'Employer Management',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        foregroundColor: Colors.black,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: Container(
            height: 4.0,
            color: const Color(0xFFFEFE00), // Yellow #FEFE00
          ),
        ),
        actions: const [ScreenInfoIcon(screenName: 'employer_management_screen.dart')],
      ),
      body: Row(
        children: [
          // Left side - List of employers
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Column(
                children: [
                  // Header with import buttons
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _importFromCsv,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Import CSV'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _downloadCsvTemplate,
                          icon: const Icon(Icons.download),
                          label: const Text('Template'),
                        ),
                      ],
                    ),
                  ),
                  // Employers list
                  Expanded(
                    child: _isLoadingList
                        ? const Center(child: CircularProgressIndicator())
                        : _employers.isEmpty
                            ? const Center(
                                child: Text('No employers found'),
                              )
                            : ListView.builder(
                                itemCount: _employers.length,
                                itemBuilder: (context, index) {
                                  final employer = _employers[index];
                                  final isActive = employer['is_active'] as bool? ?? true;
                                  final employerName = (employer['employer_name'] as String?) ?? 'Unknown';
                                  final employerType = (employer['employer_type'] as String?) ?? 'Unknown';
                                  final id = employer['id'] as String;

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 4.0,
                                    ),
                                    color: _editingEmployerId == id
                                        ? Colors.blue.shade50
                                        : null,
                                    child: ListTile(
                                      title: Text(
                                        employerName,
                                        style: TextStyle(
                                          fontWeight: _editingEmployerId == id
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Type: $employerType'),
                                          Row(
                                            children: [
                                              Icon(
                                                isActive ? Icons.check_circle : Icons.cancel,
                                                size: 16,
                                                color: isActive ? Colors.green : Colors.red,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                isActive ? 'Active' : 'Inactive',
                                                style: TextStyle(
                                                  color: isActive ? Colors.green : Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () => _editEmployer(employer),
                                            tooltip: 'Edit',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () => _deleteEmployer(id, employerName),
                                            tooltip: 'Delete',
                                            color: Colors.red,
                                          ),
                                        ],
                                      ),
                                      onTap: () => _editEmployer(employer),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
          // Right side - Form
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status message
                    if (_statusMessage.isNotEmpty)
                      Card(
                        color: _statusMessage.contains('✅')
                            ? Colors.green.shade50
                            : _statusMessage.contains('❌')
                                ? Colors.red.shade50
                                : Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Form title
                    Text(
                      _editingEmployerId == null
                          ? 'Create New Employer'
                          : 'Edit Employer',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),

                    // Employer Name
                    TextFormField(
                      controller: _employerNameController,
                      decoration: const InputDecoration(
                        labelText: 'Employer Name *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Employer name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Employer Type dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedEmployerType,
                      decoration: const InputDecoration(
                        labelText: 'Employer Type *',
                        border: OutlineInputBorder(),
                        helperText: 'Select from employer_type table',
                      ),
                      items: _employerTypes.isEmpty
                          ? [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('No types available'),
                              )
                            ]
                          : _employerTypes.map((type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedEmployerType = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Employer type is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Is Active checkbox
                    CheckboxListTile(
                      title: const Text('Active'),
                      subtitle: const Text('Uncheck to deactivate this employer'),
                      value: _isActive,
                      onChanged: (value) {
                        setState(() {
                          _isActive = value ?? true;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveEmployer,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Text(
                                    _editingEmployerId == null
                                        ? 'Create Employer'
                                        : 'Update Employer',
                                  ),
                          ),
                        ),
                        if (_editingEmployerId != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _clearForm,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                        ],
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
}

