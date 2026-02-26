/// User Creation Screen
/// 
/// Admin interface for creating new users (single or bulk via CSV)

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../modules/users/user_service.dart';
import '../modules/users/csv_parser.dart';
import '../config/supabase_config.dart';
import '../modules/errors/error_log_service.dart';

class UserCreationScreen extends StatefulWidget {
  const UserCreationScreen({super.key});

  @override
  State<UserCreationScreen> createState() => _UserCreationScreenState();
}

class _UserCreationScreenState extends State<UserCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _forenameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _initialsController = TextEditingController();
  final _passwordController = TextEditingController();
  final _eircodeController = TextEditingController();
  
  String? _selectedRole;
  int _selectedSecurity = 7;
  int _securityLimit = 1; // Default to 1
  String? _selectedEmployer;
  List<String> _employers = [];
  
  // Menu permissions (all default to true)
  bool _menuClockIn = true;
  bool _menuTimePeriods = true;
  bool _menuPlantChecks = true;
  bool _menuDeliveries = true;
  bool _menuPaperwork = true;
  bool _menuTimeOff = true;
  bool _menuSites = true;
  bool _menuReports = true;
  bool _menuManagers = true;
  bool _ppeManager = false;
  bool _menuExports = true;
  bool _menuAdministration = true;
  bool _menuMessages = true;
  bool _menuMessenger = true;
  bool _menuTraining = true;
  bool _menuCubeTest = true;
  bool _menuOffice = true;
  bool _menuOfficeAdmin = true;
  bool _menuOfficeProject = false;
  bool _menuConcreteMix = false;
  bool _menuWorkshop = false;
  
  // Role to security level mapping
  static const Map<String, int> _roleSecurityMap = {
    'Admin': 1,
    'Manager': 2,
    'Foreman': 3,
    'Supervisor': 3,
    'Crew Leader': 4,
    'Engineer': 4,
    'Technical Operative': 5,
    'Skilled Operative': 5,
    'Excavator/Truck Operative': 5,
    'Truck Operative': 5,
    'Semi-skilled Operative': 6,
    'Basic Operative': 6,
    'Excavator Operative': 6,
    'Pipe Layer': 6,
    'Mechanic': 6,
    'Miscellaneous': 6,
    'Subcontractor': 7,
    'External': 8,
    'Visitor': 9,
  };
  bool _isLoading = false;
  String _statusMessage = '';
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _loadEmployers();
  }
  
  Future<void> _loadEmployers() async {
    try {
      final response = await SupabaseService.client
          .from('employers')
          .select('employer_name')
          .order('employer_name');
      
      final employers = <String>[];
      for (var item in response) {
        final name = item['employer_name'] as String?;
        if (name != null && name.isNotEmpty) {
          employers.add(name);
        }
      }
      
      setState(() {
        _employers = employers;
        if (employers.isEmpty) {
          print('⚠️ No employers found in employers table');
        } else {
          print('✅ Loaded ${employers.length} employers');
        }
      });
    } catch (e, stackTrace) {
      print('⚠️ Error loading employers: $e');
      await ErrorLogService.logError(
        location: 'User Creation Screen - Load Employers',
        type: 'Database',
        description: 'Failed to load employers: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _employers = [];
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _forenameController.dispose();
    _surnameController.dispose();
    _initialsController.dispose();
    _passwordController.dispose();
    _eircodeController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminStatus() async {
    final isAdmin = await UserService.isCurrentUserAdmin();
    setState(() {
      _isAdmin = isAdmin;
      if (!isAdmin) {
        _statusMessage = '⚠️ You must have security level 1 to create users';
      }
    });
  }


  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validate role is selected
    if (_selectedRole == null || _selectedRole!.isEmpty) {
      setState(() {
        _statusMessage = '❌ Please select a role';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating user...';
    });

    try {
      // Prepare users_data_fields
      final usersDataFields = <String, dynamic>{};
      if (_selectedEmployer != null && _selectedEmployer!.isNotEmpty) {
        usersDataFields['employer_name'] = _selectedEmployer;
      }
      
      // Geocode Eircode if provided
      final eircode = _eircodeController.text.trim();
      if (eircode.isNotEmpty) {
        setState(() {
          _statusMessage = 'Geocoding Eircode...';
        });
        
        final geocodeResult = await UserService.geocodeEircode(eircode);
        if (geocodeResult != null) {
          usersDataFields['eircode'] = geocodeResult['eircode'];
          usersDataFields['home_latitude'] = geocodeResult['lat'];
          usersDataFields['home_longitude'] = geocodeResult['lng'];
          if (geocodeResult['formatted_address'] != null && 
              (geocodeResult['formatted_address'] as String).isNotEmpty) {
            usersDataFields['home_address'] = geocodeResult['formatted_address'];
          }
          print('✅ Eircode geocoded successfully');
        } else {
          // Still save Eircode even if geocoding fails
          usersDataFields['eircode'] = eircode;
          print('⚠️ Eircode geocoding failed, but saving Eircode anyway');
        }
      }
      
      setState(() {
        _statusMessage = 'Creating user...';
      });
      
      // Prepare users_setup fields
      final usersSetupFields = <String, dynamic>{
        'security_limit': _securityLimit,
        'menu_clock_in': _menuClockIn,
        'menu_time_periods': _menuTimePeriods,
        'menu_plant_checks': _menuPlantChecks,
        'menu_deliveries': _menuDeliveries,
        'menu_paperwork': _menuPaperwork,
        'menu_time_off': _menuTimeOff,
        'menu_sites': _menuSites,
        'menu_reports': _menuReports,
        'menu_managers': _menuManagers,
        'ppe_manager': _ppeManager,
        'menu_exports': _menuExports,
        'menu_administration': _menuAdministration,
        'menu_messages': _menuMessages,
        'menu_messenger': _menuMessenger,
        'menu_training': _menuTraining,
        'menu_cube_test': _menuCubeTest,
        'menu_office': _menuOffice,
        'menu_office_admin': _menuOfficeAdmin,
        'menu_office_project': _menuOfficeProject,
        'menu_concrete_mix': _menuConcreteMix,
        'menu_workshop': _menuWorkshop,
      };

      final result = await UserService.createUser(
        email: _emailController.text.trim(),
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text.trim(),
        forename: _forenameController.text.trim(),
        surname: _surnameController.text.trim(),
        initials: _initialsController.text.trim(),
        role: _selectedRole!,
        security: _selectedSecurity,
        usersDataFields: usersDataFields.isNotEmpty ? usersDataFields : null,
        usersSetupFields: usersSetupFields,
      );

      setState(() {
        _statusMessage = '✅ User created successfully!\n\nEmail: ${result['user']?['email'] ?? _emailController.text}';
      });

      // Clear form
      _emailController.clear();
      _phoneController.clear();
      _forenameController.clear();
      _surnameController.clear();
      _initialsController.clear();
      _passwordController.clear();
      _eircodeController.clear();
      setState(() {
        _selectedEmployer = null;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'User Creation Screen - Create User',
        type: 'Database',
        description: 'Failed to create user with email ${_emailController.text.trim()}: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error creating user: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _importFromCsv() async {
    try {
      print('🔍 Starting CSV import...');
      
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

      if (result.files.isEmpty) {
        setState(() {
          _statusMessage = '❌ No file selected';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Reading CSV file...';
      });

      // Read CSV file
      final file = result.files.single;
      print('🔍 File name: ${file.name}, size: ${file.size} bytes');
      
      // For web, use bytes directly; for other platforms, might need path
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
      print('🔍 CSV content preview (first 200 chars): ${csvContent.substring(0, csvContent.length > 200 ? 200 : csvContent.length)}');

      final users = CsvParser.parseUsersCsv(csvContent);
      print('🔍 Parsed users count: ${users.length}');

      if (users.isEmpty) {
        setState(() {
          _statusMessage = '❌ No valid users found in CSV file.\n\n'
              'Make sure:\n'
              '1. CSV has a header row (required: email, forename, surname, initials, role, security)\n'
              '2. Optional columns: ${CsvParser.csvHeaders.skip(6).join(", ")}\n'
              '3. Security is a number 1-9; role is one of: ${UserService.validRoles.join(", ")}\n'
              '4. Use "Download Template" for the full header list and example rows.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Importing ${users.length} user(s)...';
      });

      print('🔍 Starting bulk user creation...');
      // Create users
      final results = await UserService.createUsersBulk(users);
      print('🔍 Bulk creation complete. Results: $results');

      final successCount = results.where((r) => r['success'] == true).length;
      final failCount = results.length - successCount;

      setState(() {
        if (successCount > 0 && failCount == 0) {
          _statusMessage = '✅ Import complete!\n\n'
              'Successfully imported: $successCount user(s)';
        } else if (successCount > 0 && failCount > 0) {
          _statusMessage = '⚠️ Partial success!\n\n'
              'Successful: $successCount\n'
              'Failed: $failCount\n\n'
              'Failed users:';
          for (var result in results) {
            if (result['success'] == false) {
              _statusMessage += '\n- ${result['email']}: ${result['error']}';
            }
          }
        } else {
          _statusMessage = '❌ Import failed!\n\n'
              'All $failCount user(s) failed:\n';
          for (var result in results) {
            if (result['success'] == false) {
              _statusMessage += '\n- ${result['email']}: ${result['error']}';
            }
          }
        }
      });
    } catch (e, stackTrace) {
      print('❌ CSV import error: $e');
      print('❌ Stack trace: $stackTrace');
      await ErrorLogService.logError(
        location: 'User Creation Screen - Import CSV',
        type: 'File Processing',
        description: 'Failed to import CSV file: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error importing CSV: $e\n\n'
            'Please check:\n'
            '1. File is a valid CSV format\n'
            '2. File is not corrupted\n'
            '3. You have admin permissions';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _downloadCsvTemplate() {
    final template = CsvParser.generateCsvTemplate();
    // In a real app, you'd save this to a file
    // For now, we'll show it in a dialog
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
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0081FB), // #0081FB
          title: const Text(
            'Create User',
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
          actions: const [ScreenInfoIcon(screenName: 'user_creation_screen.dart')],
        ),
        body: const Center(
          child: Text('You must have security level 1 to access this page'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0081FB), // #0081FB
        title: const Text(
          'Create New User',
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
        actions: const [ScreenInfoIcon(screenName: 'user_creation_screen.dart')],
      ),
      body: SingleChildScrollView(
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

              // Form fields
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Email is required';
                  }
                  if (!value.contains('@')) {
                    return 'Invalid email format';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  hintText: 'Optional',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _forenameController,
                      decoration: const InputDecoration(
                        labelText: 'Forename *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _surnameController,
                      decoration: const InputDecoration(
                        labelText: 'Surname *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _initialsController,
                decoration: const InputDecoration(
                  labelText: 'Initials *',
                  border: OutlineInputBorder(),
                ),
                maxLength: 10,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Role dropdown
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role *',
                  border: OutlineInputBorder(),
                ),
                items: UserService.validRoles.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(role),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedRole = value;
                      // Auto-set security based on role
                      if (_roleSecurityMap.containsKey(value)) {
                        _selectedSecurity = _roleSecurityMap[value]!;
                      }
                    });
                  }
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Role is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Security level dropdown
              DropdownButtonFormField<int>(
                value: _selectedSecurity,
                decoration: const InputDecoration(
                  labelText: 'Security Level *',
                  border: OutlineInputBorder(),
                  helperText: '1 (Admin), 2 (Manager), 3 (Foreman/Supervisor), 4 (Crew Leader/Engineer), 5–6 (Operatives/Mechanic), 7 (Subcontractor), 8 (External), 9 (Visitor)',
                ),
                items: List.generate(9, (index) {
                  final level = index + 1;
                  return DropdownMenuItem(
                    value: level,
                    child: Text('$level'),
                  );
                }),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedSecurity = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Security Limit: allows submitting time on behalf of others. NULL = cannot submit for others.
              DropdownButtonFormField<int>(
                value: _securityLimit,
                decoration: const InputDecoration(
                  labelText: 'Security Limit',
                  border: OutlineInputBorder(),
                  helperText: 'Can submit time for users with security ≥ this value (1-9). NULL = cannot submit for others.',
                ),
                items: List.generate(9, (index) {
                  final level = index + 1;
                  return DropdownMenuItem(
                    value: level,
                    child: Text('$level'),
                  );
                }),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _securityLimit = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Employer dropdown
              DropdownButtonFormField<String>(
                value: _selectedEmployer,
                decoration: const InputDecoration(
                  labelText: 'Employer',
                  border: OutlineInputBorder(),
                  helperText: 'Select from employers table',
                ),
                items: _employers.isEmpty
                    ? [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No employers available'),
                        )
                      ]
                    : [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('None'),
                        ),
                        ..._employers.map((employer) {
                          return DropdownMenuItem(
                            value: employer,
                            child: Text(employer),
                          );
                        }),
                      ],
                onChanged: (value) {
                  setState(() {
                    _selectedEmployer = value;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Password field (optional)
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Leave blank for user to set',
                  helperText: 'If left blank, user will set password themselves',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),

              // Eircode field (optional)
              TextFormField(
                controller: _eircodeController,
                decoration: const InputDecoration(
                  labelText: 'Eircode (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Will automatically geocode to get GPS coordinates',
                ),
              ),
              const SizedBox(height: 24),

              // Menu Permissions Section
              const Text(
                'Menu Permissions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildMenuPermissionsSection(),
              const SizedBox(height: 24),

              // Create button
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _createUser,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.person_add, size: 24),
                label: const Text(
                  'Create User',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 20),

              const Divider(),
              const SizedBox(height: 20),

              // CSV Import section
              const Text(
                'Bulk Import',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Import multiple users from a CSV file',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _downloadCsvTemplate,
                      icon: const Icon(Icons.download),
                      label: const Text('Download Template'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _importFromCsv,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import CSV'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuPermissionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Clock In', textAlign: TextAlign.left),
                    value: _menuClockIn,
                    onChanged: (value) => setState(() => _menuClockIn = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Time Periods', textAlign: TextAlign.left),
                    value: _menuTimePeriods,
                    onChanged: (value) => setState(() => _menuTimePeriods = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Plant Checks', textAlign: TextAlign.left),
                    value: _menuPlantChecks,
                    onChanged: (value) => setState(() => _menuPlantChecks = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Deliveries', textAlign: TextAlign.left),
                    value: _menuDeliveries,
                    onChanged: (value) => setState(() => _menuDeliveries = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Paperwork', textAlign: TextAlign.left),
                    value: _menuPaperwork,
                    onChanged: (value) => setState(() => _menuPaperwork = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Time Off', textAlign: TextAlign.left),
                    value: _menuTimeOff,
                    onChanged: (value) => setState(() => _menuTimeOff = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Sites', textAlign: TextAlign.left),
                    value: _menuSites,
                    onChanged: (value) => setState(() => _menuSites = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Reports', textAlign: TextAlign.left),
                    value: _menuReports,
                    onChanged: (value) => setState(() => _menuReports = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Managers', textAlign: TextAlign.left),
                    value: _menuManagers,
                    onChanged: (value) => setState(() => _menuManagers = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('PPE Manager', textAlign: TextAlign.left),
                    subtitle: const Text('PPE Management menu and allocation access'),
                    value: _ppeManager,
                    onChanged: (value) => setState(() => _ppeManager = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Exports', textAlign: TextAlign.left),
                    value: _menuExports,
                    onChanged: (value) => setState(() => _menuExports = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Administration', textAlign: TextAlign.left),
                    value: _menuAdministration,
                    onChanged: (value) => setState(() => _menuAdministration = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Messages', textAlign: TextAlign.left),
                    value: _menuMessages,
                    onChanged: (value) => setState(() => _menuMessages = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Messenger', textAlign: TextAlign.left),
                    value: _menuMessenger,
                    onChanged: (value) => setState(() => _menuMessenger = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Training', textAlign: TextAlign.left),
                    value: _menuTraining,
                    onChanged: (value) => setState(() => _menuTraining = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Testing', textAlign: TextAlign.left),
                    value: _menuCubeTest,
                    onChanged: (value) => setState(() => _menuCubeTest = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Office', textAlign: TextAlign.left),
                    value: _menuOffice,
                    onChanged: (value) => setState(() => _menuOffice = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Office Admin', textAlign: TextAlign.left),
                    value: _menuOfficeAdmin,
                    onChanged: (value) => setState(() => _menuOfficeAdmin = value ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Office Project', textAlign: TextAlign.left),
                    value: _menuOfficeProject,
                    onChanged: (value) => setState(() => _menuOfficeProject = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Concrete Mix', textAlign: TextAlign.left),
                    value: _menuConcreteMix,
                    onChanged: (value) => setState(() => _menuConcreteMix = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  SwitchListTile(
                    title: const Text('Workshop', textAlign: TextAlign.left),
                    value: _menuWorkshop,
                    onChanged: (value) => setState(() => _menuWorkshop = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

