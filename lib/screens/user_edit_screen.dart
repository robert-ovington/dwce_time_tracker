/// User Editing Screen
/// 
/// Admin interface for editing existing users
/// Allows editing of auth.users, users_data, and users_setup fields

import 'package:flutter/material.dart';
import '../modules/users/user_edit_service.dart';
import '../modules/users/user_service.dart';
import '../config/supabase_config.dart';
import '../modules/errors/error_log_service.dart';
import '../widgets/screen_info_icon.dart';

class UserEditScreen extends StatefulWidget {
  const UserEditScreen({super.key});

  @override
  State<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends State<UserEditScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // User selection
  String? _selectedUserId;
  String? _selectedDisplayName;
  List<Map<String, dynamic>> _usersList = [];
  bool _isLoadingUsers = false;
  
  // Auth.Users fields
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  // users_data fields
  final _forenameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _initialsController = TextEditingController();
  final _homeLatController = TextEditingController();
  final _homeLngController = TextEditingController();
  final _eircodeController = TextEditingController();
  final _homeAddressController = TextEditingController();
  String? _selectedStockLocation;
  List<String> _stockLocations = [];
  String? _selectedEmployer;
  List<String> _employers = [];
  
  // Daily times and breaks (Monday-Sunday)
  // Monday-Thursday: 2 breaks, Friday: 1 break, Saturday-Sunday: 1 break
  final Map<String, TextEditingController> _dailyStartTimes = {};
  final Map<String, TextEditingController> _dailyEndTimes = {};
  final Map<String, TextEditingController> _dailyBreak1Starts = {};
  final Map<String, TextEditingController> _dailyBreak1Ends = {};
  final Map<String, TextEditingController> _dailyBreak2Starts = {};
  final Map<String, TextEditingController> _dailyBreak2Ends = {};
  
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
  
  // Boolean flags
  bool _showProject = false;
  bool _showFleet = false;
  bool _showAllowances = false;
  bool _showComments = false;
  bool _concreteMixLorry = false;
  bool _reinstatementCrew = false;
  bool _cablePulling = false;
  bool _isMechanic = false;
  bool _isPublic = false;
  bool _isActive = true;
  
  // users_setup fields
  String? _selectedRole;
  int _selectedSecurity = 7;
  int _securityLimit = 1; // Default to 1
  
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
  
  bool _isLoading = false;
  bool _isSaving = false;
  String _statusMessage = '';
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _loadUsersList();
    _loadStockLocations();
    _loadEmployers();
    _initializeDailyTimeControllers();
    _setupDisplayNameListeners();
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
          // ignore: avoid_print
          print('⚠️ No employers found in employers table');
        } else {
          // ignore: avoid_print
          print('✅ Loaded ${employers.length} employers');
        }
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'User Edit Screen - Load Employers',
        type: 'Database',
        description: 'Failed to load employers: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _employers = [];
      });
    }
  }
  
  void _setupDisplayNameListeners() {
    // Auto-update display_name when forename or surname changes
    _forenameController.addListener(_updateDisplayName);
    _surnameController.addListener(_updateDisplayName);
  }
  
  void _updateDisplayName() {
    final forename = _forenameController.text.trim();
    final surname = _surnameController.text.trim();
    
    // Format: "Surname, Forename"
    String newDisplayName = '';
    if (surname.isNotEmpty && forename.isNotEmpty) {
      newDisplayName = '$surname, $forename';
    } else if (surname.isNotEmpty) {
      newDisplayName = surname;
    } else if (forename.isNotEmpty) {
      newDisplayName = forename;
    }
    
    // Only update if it's different to avoid infinite loops
    if (_displayNameController.text != newDisplayName) {
      _displayNameController.text = newDisplayName;
    }
  }
  
  void _initializeDailyTimeControllers() {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
    for (final day in days) {
      _dailyStartTimes[day] = TextEditingController();
      _dailyEndTimes[day] = TextEditingController();
      _dailyBreak1Starts[day] = TextEditingController();
      _dailyBreak1Ends[day] = TextEditingController();
      // Only Mon-Thu have break 2
      if (['Monday', 'Tuesday', 'Wednesday', 'Thursday'].contains(day)) {
        _dailyBreak2Starts[day] = TextEditingController();
        _dailyBreak2Ends[day] = TextEditingController();
      }
    }
  }
  
  Future<void> _loadStockLocations() async {
    try {
      final locations = <String>[];
      
      // First, load from stock_locations table (active only)
      try {
        final stockLocationsResponse = await SupabaseService.client
            .from('stock_locations')
            .select('description')
            .eq('is_active', true)
            .order('description');
        
        for (var item in stockLocationsResponse) {
          final desc = item['description'] as String?;
          if (desc != null && desc.isNotEmpty) {
            locations.add(desc);
          }
        }
        print('✅ Loaded ${locations.length} stock locations from stock_locations table');
      } catch (e) {
        print('⚠️ Error loading from stock_locations table: $e');
      }
      
      // Then, load from large_plant table (active only, exclude where is_stock_location is NULL)
      try {
        final plantResponse = await SupabaseService.client
            .from('large_plant')
            .select('plant_description, is_stock_location')
            .eq('is_active', true)
            .order('plant_description');
        
        final plantLocations = <String>[];
        for (var item in plantResponse) {
          // Exclude entries where is_stock_location is NULL
          final isStockLocation = item['is_stock_location'];
          if (isStockLocation == null) {
            continue;
          }
          
          final desc = item['plant_description'] as String?;
          if (desc != null && desc.isNotEmpty && !locations.contains(desc)) {
            plantLocations.add(desc);
          }
        }
        locations.addAll(plantLocations);
        print('✅ Loaded ${plantLocations.length} additional stock locations from large_plant table');
      } catch (e) {
        print('⚠️ Error loading from large_plant table: $e');
      }
      
      setState(() {
        _stockLocations = locations;
        if (locations.isEmpty) {
          print('⚠️ No stock locations found');
        } else {
          print('✅ Total ${locations.length} stock locations loaded');
        }
      });
    } catch (e, stackTrace) {
      print('⚠️ Error loading stock locations: $e');
      await ErrorLogService.logError(
        location: 'User Edit Screen - Load Stock Locations',
        type: 'Database',
        description: 'Failed to load stock locations: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _stockLocations = [];
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _forenameController.dispose();
    _surnameController.dispose();
    _initialsController.dispose();
    _homeLatController.dispose();
    _homeLngController.dispose();
    _eircodeController.dispose();
    _homeAddressController.dispose();
    for (var controller in _dailyStartTimes.values) {
      controller.dispose();
    }
    for (var controller in _dailyEndTimes.values) {
      controller.dispose();
    }
    for (var controller in _dailyBreak1Starts.values) {
      controller.dispose();
    }
    for (var controller in _dailyBreak1Ends.values) {
      controller.dispose();
    }
    for (var controller in _dailyBreak2Starts.values) {
      controller.dispose();
    }
    for (var controller in _dailyBreak2Ends.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _checkAdminStatus() async {
    final isAdmin = await UserService.isCurrentUserAdmin();
    setState(() {
      _isAdmin = isAdmin;
      if (!isAdmin) {
        _statusMessage = '⚠️ You must have security level 1 to edit users';
      }
    });
  }

  Future<void> _loadUsersList() async {
    setState(() {
      _isLoadingUsers = true;
      _statusMessage = 'Loading users list...';
    });

    try {
      print('🔍 Loading users list...');
      final users = await UserEditService.getAllUsers();
      print('🔍 Received ${users.length} users');
      
      // Sort users alphabetically by display_name
      users.sort((a, b) {
        final nameA = (a['display_name'] ?? '').toString().toLowerCase();
        final nameB = (b['display_name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
      
      setState(() {
        _usersList = users;
        if (users.isEmpty) {
          _statusMessage = '⚠️ No users found.\n\n'
              'This could be due to:\n'
              '1. RLS policies blocking access\n'
              '2. No users exist in users_data table\n'
              '3. You need to create users first';
        } else {
          _statusMessage = '✅ Loaded ${users.length} user(s)';
        }
      });
    } catch (e, stackTrace) {
      print('❌ Error in _loadUsersList: $e');
      await ErrorLogService.logError(
        location: 'User Edit Screen - Load Users List',
        type: 'Database',
        description: 'Failed to load users list: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error loading users: $e\n\n'
            'Check:\n'
            '1. RLS policies on users_data table\n'
            '2. You are logged in as admin\n'
            '3. Table exists and has data';
      });
    } finally {
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }

  Future<void> _loadUserData(String userId) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading user data...';
    });

    try {
      final userData = await UserEditService.getUserData(userId);

      // Populate form fields
      final usersData = userData['users_data'] as Map<String, dynamic>?;
      final usersSetup = userData['users_setup'] as Map<String, dynamic>?;
      final authUser = userData['auth_user'] as Map<String, dynamic>?;

      // Auth.Users fields - try to get from Edge Function response
      if (authUser != null) {
        // Try different possible field names for email
        final email = authUser['email']?.toString() ?? 
                     authUser['email_address']?.toString() ?? 
                     authUser['user_email']?.toString() ?? '';
        
        // Try different possible field names for phone
        final phone = authUser['phone']?.toString() ?? 
                     authUser['phone_number']?.toString() ?? 
                     authUser['user_phone']?.toString() ?? 
                     authUser['phoneNumber']?.toString() ?? '';
        
        _emailController.text = email;
        _phoneController.text = phone;
        
        print('✅ Loaded email: $email, phone: $phone');
        print('🔍 Full authUser data: $authUser');
      } else {
        // If auth data not available, clear fields
        _emailController.clear();
        _phoneController.clear();
        print('⚠️ No auth user data available - email/phone fields will be empty');
        print('🔍 Full userData keys: ${userData.keys.toList()}');
      }

      // users_data fields
      if (usersData != null) {
        _displayNameController.text = (usersData['display_name'] as String?) ?? '';
        _forenameController.text = (usersData['forename'] as String?) ?? '';
        _surnameController.text = (usersData['surname'] as String?) ?? '';
        _initialsController.text = (usersData['initials'] as String?) ?? '';
        _homeLatController.text = usersData['home_latitude']?.toString() ?? '';
        _homeLngController.text = usersData['home_longitude']?.toString() ?? '';
        _eircodeController.text = (usersData['eircode'] as String?) ?? '';
        _homeAddressController.text = (usersData['home_address'] as String?) ?? '';
        _selectedStockLocation = usersData['stock_location'] as String?;
        _selectedEmployer = usersData['employer_name'] as String?;
        
        // Load daily times (Monday-Friday only)
        // Schema uses: monday_start_time, monday_finish_time, monday_break_1_start, etc.
        final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
        for (final day in days) {
          final dayLower = day.toLowerCase();
          _dailyStartTimes[day]?.text = usersData['${dayLower}_start_time']?.toString() ?? '';
          _dailyEndTimes[day]?.text = usersData['${dayLower}_finish_time']?.toString() ?? '';
          _dailyBreak1Starts[day]?.text = usersData['${dayLower}_break_1_start']?.toString() ?? '';
          _dailyBreak1Ends[day]?.text = usersData['${dayLower}_break_1_finish']?.toString() ?? '';
          // Only Mon-Thu have break 2
          if (['Monday', 'Tuesday', 'Wednesday', 'Thursday'].contains(day)) {
            _dailyBreak2Starts[day]?.text = usersData['${dayLower}_break_2_start']?.toString() ?? '';
            _dailyBreak2Ends[day]?.text = usersData['${dayLower}_break_2_finish']?.toString() ?? '';
          }
        }
        
        // Boolean fields
        _showProject = (usersData['show_project'] as bool?) ?? false;
        _showFleet = (usersData['show_fleet'] as bool?) ?? false;
        _showAllowances = (usersData['show_allowances'] as bool?) ?? false;
        _showComments = (usersData['show_comments'] as bool?) ?? false;
        _concreteMixLorry = (usersData['concrete_mix_lorry'] as bool?) ?? false;
        _reinstatementCrew = (usersData['reinstatement_crew'] as bool?) ?? false;
        _cablePulling = (usersData['cable_pulling'] as bool?) ?? false;
        _isMechanic = (usersData['is_mechanic'] as bool?) ?? false;
        _isPublic = (usersData['is_public'] as bool?) ?? false;
        _isActive = (usersData['is_active'] as bool?) ?? true;
        
      } else {
        // Clear all users_data fields if no data
        _displayNameController.clear();
        _forenameController.clear();
        _surnameController.clear();
        _initialsController.clear();
        _homeLatController.clear();
        _homeLngController.clear();
        _eircodeController.clear();
        _homeAddressController.clear();
        _selectedStockLocation = null;
        _selectedEmployer = null;
      }

      // users_setup fields
      if (usersSetup != null) {
        final roleFromDb = usersSetup['role'] as String?;
        // Ensure role is in validRoles list, default to first valid role if not
        if (roleFromDb != null && UserService.validRoles.contains(roleFromDb)) {
          _selectedRole = roleFromDb;
        } else {
          _selectedRole = UserService.validRoles.first; // Default to first valid role
        }
        _selectedSecurity = (usersSetup['security'] as int?) ?? _roleSecurityMap[_selectedRole] ?? 7;
        _securityLimit = (usersSetup['security_limit'] as int?) ?? 1;
        
        // Auto-set security based on role if not already set
        if (_selectedRole != null && _roleSecurityMap.containsKey(_selectedRole)) {
          final defaultSecurity = _roleSecurityMap[_selectedRole]!;
          if (_selectedSecurity != defaultSecurity) {
            _selectedSecurity = defaultSecurity;
          }
        }
        
        // Load menu permissions
        _menuClockIn = (usersSetup['menu_clock_in'] as bool?) ?? true;
        _menuTimePeriods = (usersSetup['menu_time_periods'] as bool?) ?? true;
        _menuPlantChecks = (usersSetup['menu_plant_checks'] as bool?) ?? true;
        _menuDeliveries = (usersSetup['menu_deliveries'] as bool?) ?? true;
        _menuPaperwork = (usersSetup['menu_paperwork'] as bool?) ?? true;
        _menuTimeOff = (usersSetup['menu_time_off'] as bool?) ?? true;
        _menuSites = (usersSetup['menu_sites'] as bool?) ?? true;
        _menuReports = (usersSetup['menu_reports'] as bool?) ?? true;
        _menuManagers = (usersSetup['menu_managers'] as bool?) ?? true;
        _ppeManager = (usersSetup['ppe_manager'] as bool?) ?? false;
        _menuExports = (usersSetup['menu_exports'] as bool?) ?? true;
        _menuAdministration = (usersSetup['menu_administration'] as bool?) ?? true;
        _menuMessages = (usersSetup['menu_messages'] as bool?) ?? true;
        _menuMessenger = (usersSetup['menu_messenger'] as bool?) ?? true;
        _menuTraining = (usersSetup['menu_training'] as bool?) ?? true;
        _menuCubeTest = (usersSetup['menu_cube_test'] as bool?) ?? true;
        _menuOffice = (usersSetup['menu_office'] as bool?) ?? true;
        _menuOfficeAdmin = (usersSetup['menu_office_admin'] as bool?) ?? true;
        _menuOfficeProject = (usersSetup['menu_office_project'] as bool?) ?? false;
        _menuConcreteMix = (usersSetup['menu_concrete_mix'] as bool?) ?? false;
        _menuWorkshop = (usersSetup['menu_workshop'] as bool?) ?? false;
      } else {
        // If no users_setup, default to first valid role
        _selectedRole = UserService.validRoles.first;
      }

      setState(() {
        _statusMessage = '✅ User data loaded';
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'User Edit Screen - Load User Data',
        type: 'Database',
        description: 'Failed to load user data for user $_selectedUserId: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error loading user data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUserId == null) {
      setState(() {
        _statusMessage = '❌ Please select a user first';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = 'Saving user data...';
    });

    try {
      // Display name in same format as users_setup and auth.users: "Surname, Forename"
      final _displayNameForSave = _surnameController.text.trim().isNotEmpty && _forenameController.text.trim().isNotEmpty
          ? '${_surnameController.text.trim()}, ${_forenameController.text.trim()}'
          : _displayNameController.text.trim();

      // Prepare users_data fields
      final usersDataFields = <String, dynamic>{
        'display_name': _displayNameForSave,
        'forename': _forenameController.text.trim(),
        'surname': _surnameController.text.trim(),
        'initials': _initialsController.text.trim(),
        'stock_location': _selectedStockLocation,
        'eircode': _eircodeController.text.trim(),
        'home_address': _homeAddressController.text.trim(),
        'employer_name': _selectedEmployer,
        'show_project': _showProject,
        'show_fleet': _showFleet,
        'show_allowances': _showAllowances,
        'show_comments': _showComments,
        'concrete_mix_lorry': _concreteMixLorry,
        'reinstatement_crew': _reinstatementCrew,
        'cable_pulling': _cablePulling,
        'is_mechanic': _isMechanic,
        'is_public': _isPublic,
        'is_active': _isActive,
      };

      // Add home coordinates if provided
      if (_homeLatController.text.isNotEmpty) {
        usersDataFields['home_latitude'] = double.tryParse(_homeLatController.text);
      }
      if (_homeLngController.text.isNotEmpty) {
        usersDataFields['home_longitude'] = double.tryParse(_homeLngController.text);
      }

      // Add daily times (Monday-Friday only)
      // Schema uses: monday_start_time, monday_finish_time, monday_break_1_start, etc.
      final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
      for (final day in days) {
        final dayLower = day.toLowerCase();
        if (_dailyStartTimes[day]?.text.isNotEmpty ?? false) {
          usersDataFields['${dayLower}_start_time'] = _dailyStartTimes[day]!.text.trim();
        }
        if (_dailyEndTimes[day]?.text.isNotEmpty ?? false) {
          usersDataFields['${dayLower}_finish_time'] = _dailyEndTimes[day]!.text.trim();
        }
        if (_dailyBreak1Starts[day]?.text.isNotEmpty ?? false) {
          usersDataFields['${dayLower}_break_1_start'] = _dailyBreak1Starts[day]!.text.trim();
        }
        if (_dailyBreak1Ends[day]?.text.isNotEmpty ?? false) {
          usersDataFields['${dayLower}_break_1_finish'] = _dailyBreak1Ends[day]!.text.trim();
        }
        // Only Mon-Thu have break 2
        if (['Monday', 'Tuesday', 'Wednesday', 'Thursday'].contains(day)) {
          if (_dailyBreak2Starts[day]?.text.isNotEmpty ?? false) {
            usersDataFields['${dayLower}_break_2_start'] = _dailyBreak2Starts[day]!.text.trim();
          }
          if (_dailyBreak2Ends[day]?.text.isNotEmpty ?? false) {
            usersDataFields['${dayLower}_break_2_finish'] = _dailyBreak2Ends[day]!.text.trim();
          }
        }
      }

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

      await UserEditService.updateUser(
        userId: _selectedUserId!,
        email: _emailController.text.isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.isEmpty ? null : _phoneController.text.trim(),
        displayName: _displayNameForSave.isEmpty ? null : _displayNameForSave,
        forename: _forenameController.text.trim(),
        surname: _surnameController.text.trim(),
        initials: _initialsController.text.trim(),
        role: _selectedRole ?? UserService.validRoles.first,
        security: _selectedSecurity,
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
        usersDataFields: usersDataFields,
        usersSetupFields: usersSetupFields,
      );

      // Reload users list to update the dropdown with new display_name
      await _loadUsersList();
      
      // Update the selected display name in the dropdown (use same format we saved)
      if (_displayNameForSave.isNotEmpty) {
        setState(() {
          _selectedDisplayName = _displayNameForSave;
        });
      }

      setState(() {
        _statusMessage = '✅ User updated successfully!';
        _passwordController.clear();
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'User Edit Screen - Update User',
        type: 'Database',
        description: 'Failed to update user $_selectedUserId: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error updating user: $e';
      });
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _findGPS() async {
    // Get Eircode and remove spaces (Eircodes can have spaces like "D02 AF30")
    var eircode = _eircodeController.text.trim().replaceAll(' ', '');
    if (eircode.isEmpty) {
      setState(() {
        _statusMessage = '⚠️ Please enter an Eircode first';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Finding GPS coordinates for $eircode...';
    });

    try {
      print('🔍 Checking cache for eircode: $eircode');
      
      // First, check if we have cached data for this Eircode
      try {
        final cachedResult = await SupabaseService.client
            .from('google_api_calls')
            .select('home_latitude, home_longitude, display_name, was_cached')
            .eq('eircode', eircode)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (cachedResult != null) {
          final cachedLat = cachedResult['home_latitude'] as double?;
          final cachedLng = cachedResult['home_longitude'] as double?;
          final cachedAddress = cachedResult['display_name'] as String?;
          
          if (cachedLat != null && cachedLng != null) {
            print('✅ Found cached coordinates: $cachedLat, $cachedLng');
            
            // Increment save counter because we're using cached data (saving an API call)
            await _incrementApiSaveCounter();
            
            setState(() {
              _homeLatController.text = cachedLat.toStringAsFixed(6);
              _homeLngController.text = cachedLng.toStringAsFixed(6);
              if (cachedAddress != null && cachedAddress.isNotEmpty) {
                _homeAddressController.text = cachedAddress;
              }
              _statusMessage = '✅ GPS coordinates found (cached): $cachedLat, $cachedLng';
            });
            return; // Exit early, we have cached data
          }
        }
        print('⚠️ No cached data found, making API call...');
      } catch (e, stackTrace) {
        print('⚠️ Error checking cache: $e, proceeding with API call...');
        await ErrorLogService.logError(
          location: 'User Edit Screen - Find GPS (Cache Check)',
          type: 'Database',
          description: 'Error checking cache for eircode $eircode: $e',
          stackTrace: stackTrace,
        );
        // Continue to API call if cache check fails
      }

      // No cached data found, make API call
      print('🔍 Calling Edge Function with eircode: $eircode');
      
      // Increment API call counter
      await _incrementApiCallCounter();
      
      // Call Edge Function which has access to GOOGLE_MAPS_API_KEY secret
      final response = await SupabaseService.client.functions.invoke(
        'geocode_eircode_edge_function',
        body: {'eircode': eircode},
      );

      print('🔍 Edge Function response status: ${response.status}');
      print('🔍 Edge Function response data: ${response.data}');

      if (response.status == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true) {
          final lat = data['lat'] as double?;
          final lng = data['lng'] as double?;
          final formattedAddress = data['formatted_address'] as String?;
          
          if (lat != null && lng != null) {
            // Save to database cache
            // Get the user's display name from the form
            var userDisplayName = _displayNameController.text.trim();
            
            // If display name is empty, try to get it from the selected user
            if (userDisplayName.isEmpty && _selectedUserId != null) {
              try {
                final userData = await UserEditService.getUserData(_selectedUserId!);
                final usersData = userData['users_data'] as Map<String, dynamic>?;
                if (usersData != null) {
                  userDisplayName = (usersData['display_name'] as String?)?.trim() ?? '';
                }
              } catch (e) {
                print('⚠️ Could not fetch user display name: $e');
              }
            }
            
            final address = formattedAddress ?? 'Unknown Address';
            
            // Format display_name as "User Display Name - Address" (using " - " separator)
            // Always ensure we have at least the address
            final displayName = userDisplayName.isNotEmpty 
                ? '$userDisplayName - $address'
                : address;
            
            // Truncate to 255 characters if needed (common database limit)
            var finalDisplayName = displayName.length > 255 
                ? '${displayName.substring(0, 252)}...'
                : displayName;
            
            // Ensure display_name is never empty
            if (finalDisplayName.isEmpty) {
              print('⚠️ Warning: display_name would be empty, using address only');
              finalDisplayName = address;
            }
            
            try {
              print('🔍 Attempting to save to google_api_calls:');
              print('   - eircode: $eircode');
              print('   - lat: $lat');
              print('   - lng: $lng');
              print('   - userDisplayName from form: "$userDisplayName"');
              print('   - address: "$address"');
              print('   - display_name (original): "$displayName"');
              print('   - display_name (final, length ${finalDisplayName.length}): "$finalDisplayName"');
              
              // Prepare insert data - ensure display_name is never null or empty
              final insertData = {
                'eircode': eircode,
                'home_latitude': lat,
                'home_longitude': lng,
                'display_name': finalDisplayName.isNotEmpty ? finalDisplayName : address,
                'time_stamp': DateTime.now().toIso8601String(),
                'was_cached': false,
              };
              
              print('🔍 Insert data: $insertData');
              
              final insertResult = await SupabaseService.client
                  .from('google_api_calls')
                  .insert(insertData)
                  .select();
              
              print('✅ Saved GPS coordinates to cache with display_name: $finalDisplayName');
              print('🔍 Insert result: $insertResult');
              
              // Increment save counter
              print('🔍 Attempting to increment API save counter...');
              await _incrementApiSaveCounter();
            } catch (e, stackTrace) {
              print('❌ Error saving to cache: $e');
              print('❌ Stack trace: $stackTrace');
              print('❌ Failed insert data was:');
              print('   - eircode: $eircode');
              print('   - lat: $lat');
              print('   - lng: $lng');
              print('   - display_name: $finalDisplayName');
              print('   - display_name length: ${finalDisplayName.length}');
              
              await ErrorLogService.logError(
                location: 'User Edit Screen - Find GPS (Cache Save)',
                type: 'Database',
                description: 'Failed to save GPS data to cache for eircode $eircode: $e',
                stackTrace: stackTrace,
              );
              
              // If it's a constraint violation, try different formats
              if (e.toString().contains('check constraint') || e.toString().contains('23514')) {
                print('⚠️ Check constraint violation detected. Trying alternative formats...');
                
                // Try format: "User Display Name, Address" (comma separator)
                try {
                  final altDisplayName1 = userDisplayName.isNotEmpty 
                      ? '$userDisplayName, $address'
                      : address;
                  await SupabaseService.client.from('google_api_calls').insert({
                    'eircode': eircode,
                    'home_latitude': lat,
                    'home_longitude': lng,
                    'display_name': altDisplayName1,
                    'time_stamp': DateTime.now().toIso8601String(),
                    'was_cached': false,
                  });
                  print('✅ Saved to cache with format "User, Address"');
                  await _incrementApiSaveCounter();
                  return; // Success, exit early
                } catch (e2, stackTrace2) {
                  print('❌ Format "User, Address" also failed: $e2');
                  await ErrorLogService.logError(
                    location: 'User Edit Screen - Find GPS (Cache Save Alternative Format)',
                    type: 'Database',
                    description: 'Failed to save GPS data with alternative format "User, Address": $e2',
                    stackTrace: stackTrace2,
                  );
                }
                
                // Try format: Just the address
                try {
                  await SupabaseService.client.from('google_api_calls').insert({
                    'eircode': eircode,
                    'home_latitude': lat,
                    'home_longitude': lng,
                    'display_name': address,
                    'time_stamp': DateTime.now().toIso8601String(),
                    'was_cached': false,
                  });
                  print('✅ Saved to cache with format "Address only"');
                  await _incrementApiSaveCounter();
                  return; // Success, exit early
                } catch (e2, stackTrace3) {
                  print('❌ Format "Address only" also failed: $e2');
                  await ErrorLogService.logError(
                    location: 'User Edit Screen - Find GPS (Cache Save Address Only)',
                    type: 'Database',
                    description: 'Failed to save GPS data with address only format: $e2',
                    stackTrace: stackTrace3,
                  );
                }
                
                // Last resort: Save without display_name
                try {
                  await SupabaseService.client.from('google_api_calls').insert({
                    'eircode': eircode,
                    'home_latitude': lat,
                    'home_longitude': lng,
                    'time_stamp': DateTime.now().toIso8601String(),
                    'was_cached': false,
                  });
                  print('⚠️ Saved to cache without display_name (all formats failed constraint)');
                  await _incrementApiSaveCounter();
                } catch (e2, stackTrace4) {
                  print('❌ Still failed without display_name: $e2');
                  await ErrorLogService.logError(
                    location: 'User Edit Screen - Find GPS (Cache Save Without Display Name)',
                    type: 'Database',
                    description: 'Failed to save GPS data even without display_name: $e2',
                    stackTrace: stackTrace4,
                  );
                }
              }
              
              setState(() {
                _statusMessage = '✅ GPS coordinates found: $lat, $lng\n'
                    '⚠️ Warning: Failed to save to cache: $e';
              });
              // Don't fail the whole operation if cache save fails
            }
            
            setState(() {
              _homeLatController.text = lat.toStringAsFixed(6);
              _homeLngController.text = lng.toStringAsFixed(6);
              if (formattedAddress != null && formattedAddress.isNotEmpty) {
                _homeAddressController.text = formattedAddress;
              }
              _statusMessage = '✅ GPS coordinates found: $lat, $lng';
            });
          } else {
            setState(() {
              _statusMessage = '❌ Could not find GPS coordinates for $eircode';
            });
          }
        } else {
          final errorMsg = data['error'] as String? ?? 'Could not find GPS coordinates';
          setState(() {
            _statusMessage = '❌ $errorMsg';
          });
        }
      } else {
        // Try to extract error message from response
        String errorMsg = 'Error calling geocoding service: ${response.status}';
        if (response.data != null) {
          try {
            final errorData = response.data as Map<String, dynamic>?;
            if (errorData != null && errorData['error'] != null) {
              errorMsg = errorData['error'].toString();
            }
          } catch (e, stackTrace) {
            print('⚠️ Could not parse error response: $e');
            await ErrorLogService.logError(
              location: 'User Edit Screen - Find GPS (Parse Error Response)',
              type: 'Data Processing',
              description: 'Could not parse error response from geocoding service: $e',
              stackTrace: stackTrace,
            );
          }
        }
        setState(() {
          _statusMessage = '❌ $errorMsg\n\nStatus: ${response.status}';
        });
      }
    } catch (e, stackTrace) {
      print('❌ Exception in _findGPS: $e');
      await ErrorLogService.logError(
        location: 'User Edit Screen - Find GPS',
        type: 'GPS',
        description: 'Exception in _findGPS for eircode $eircode: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error finding GPS: $e\n\n'
            'Check:\n'
            '1. Edge Function is deployed\n'
            '2. GOOGLE_MAPS_API_KEY secret is set\n'
            '3. Google Maps API key is valid';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0081FB), // #0081FB
          title: const Text(
            'Edit User',
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
          actions: const [ScreenInfoIcon(screenName: 'user_edit_screen.dart')],
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
          'Edit User',
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
        actions: const [ScreenInfoIcon(screenName: 'user_edit_screen.dart')],
      ),
      body: _isLoadingUsers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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

                    // User selection
                    DropdownButtonFormField<String>(
                      value: _selectedDisplayName,
                      decoration: const InputDecoration(
                        labelText: 'Select User *',
                        border: OutlineInputBorder(),
                        hintText: 'Choose a user to edit',
                      ),
                      items: _usersList.map<DropdownMenuItem<String>>((user) {
                        final displayName = (user['display_name'] ?? 'Unknown') as String;
                        return DropdownMenuItem<String>(
                          value: displayName,
                          child: Text(displayName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          final user = _usersList.firstWhere(
                            (u) => u['display_name'] == value,
                          );
                          setState(() {
                            _selectedDisplayName = value;
                            _selectedUserId = user['user_id'] as String;
                          });
                          _loadUserData(_selectedUserId!);
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    if (_selectedUserId != null) ...[
                      // USER'S DETAILS SECTION
                      _buildSectionHeader('User\'s Details'),
                      // Forename, Surname, Initials in one row
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: TextFormField(
                              controller: _forenameController,
                              decoration: const InputDecoration(
                                labelText: 'Forename',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 4,
                            child: TextFormField(
                              controller: _surnameController,
                              decoration: const InputDecoration(
                                labelText: 'Surname',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _initialsController,
                              decoration: const InputDecoration(
                                labelText: 'Initials',
                                border: OutlineInputBorder(),
                              ),
                              maxLength: 10,
                              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'New Password (optional)',
                          border: OutlineInputBorder(),
                          helperText: 'Leave blank to keep current password',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 24),

                      // ROLE / SECURITY LEVEL SECTION
                      _buildSectionHeader('Role / Security Level'),
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
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 24),

                      // Menu Permissions Section
                      _buildSectionHeader('Menu Permissions'),
                      _buildMenuPermissionsSection(),
                      const SizedBox(height: 24),

                      // USERS_DATA - LOCATION SECTION
                      _buildSectionHeader('Location'),
                      Row(
                        children: [
                          Expanded(
                            flex: 8,
                            child: TextFormField(
                              controller: _homeAddressController,
                              decoration: const InputDecoration(
                                labelText: 'Home Address',
                                border: OutlineInputBorder(),
                                helperText: 'Full address',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _eircodeController,
                              decoration: const InputDecoration(
                                labelText: 'Eircode',
                                border: OutlineInputBorder(),
                                helperText: 'Irish postal code',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _homeLatController,
                              decoration: const InputDecoration(
                                labelText: 'Home Latitude',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _homeLngController,
                              decoration: const InputDecoration(
                                labelText: 'Home Longitude',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _findGPS,
                            icon: const Icon(Icons.location_searching),
                            label: const Text('Find GPS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedStockLocation,
                        decoration: const InputDecoration(
                          labelText: 'Stock Location',
                          border: OutlineInputBorder(),
                          helperText: 'Select from stock_locations or large_plant',
                        ),
                        items: _stockLocations.isEmpty
                            ? [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('No locations available'),
                                )
                              ]
                            : [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('None'),
                                ),
                                ..._stockLocations.map((location) {
                                  return DropdownMenuItem(
                                    value: location,
                                    child: Text(location),
                                  );
                                }),
                              ],
                        onChanged: (value) {
                          setState(() {
                            _selectedStockLocation = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 24),

                      // USERS_DATA - FLAGS SECTION
                      _buildSectionHeader('User Flags'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  title: const Text('Show Project', textAlign: TextAlign.left),
                                  value: _showProject,
                                  onChanged: (value) => setState(() => _showProject = value ?? false),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                ),
                                SwitchListTile(
                                  title: const Text('Show Fleet', textAlign: TextAlign.left),
                                  value: _showFleet,
                                  onChanged: (value) => setState(() => _showFleet = value ?? false),
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
                                  title: const Text('Show Allowances', textAlign: TextAlign.left),
                                  value: _showAllowances,
                                  onChanged: (value) => setState(() => _showAllowances = value ?? false),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                ),
                                SwitchListTile(
                                  title: const Text('Show Comments', textAlign: TextAlign.left),
                                  value: _showComments,
                                  onChanged: (value) => setState(() => _showComments = value ?? false),
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
                                  title: const Text('Concrete Mix Lorry', textAlign: TextAlign.left),
                                  value: _concreteMixLorry,
                                  onChanged: (value) => setState(() => _concreteMixLorry = value ?? false),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                ),
                                SwitchListTile(
                                  title: const Text('Reinstatement Crew', textAlign: TextAlign.left),
                                  value: _reinstatementCrew,
                                  onChanged: (value) => setState(() => _reinstatementCrew = value ?? false),
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
                                  title: const Text('Cable Pulling', textAlign: TextAlign.left),
                                  value: _cablePulling,
                                  onChanged: (value) => setState(() => _cablePulling = value ?? false),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                ),
                                SwitchListTile(
                                  title: const Text('Is Mechanic', textAlign: TextAlign.left),
                                  value: _isMechanic,
                                  onChanged: (value) => setState(() => _isMechanic = value ?? false),
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
                                  title: const Text('Is Public', textAlign: TextAlign.left),
                                  value: _isPublic,
                                  onChanged: (value) => setState(() => _isPublic = value ?? false),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                ),
                                SwitchListTile(
                                  title: const Text('Is Active', textAlign: TextAlign.left),
                                  value: _isActive,
                                  onChanged: (value) => setState(() => _isActive = value ?? true),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                ),
                              ],
                            ),
                          ),
                          const Expanded(child: SizedBox()), // Empty 6th column for spacing
                        ],
                      ),
                      const SizedBox(height: 24),

                      // USERS_DATA - DAILY TIMES SECTION
                      _buildSectionHeader('Daily Times and Breaks'),
                      ...['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'].map((day) {
                        final hasBreak2 = ['Monday', 'Tuesday', 'Wednesday', 'Thursday'].contains(day);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  day,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    // Column 1: Start Time & End Time
                                    Expanded(
                                      child: Column(
                                        children: [
                                          TextFormField(
                                            controller: _dailyStartTimes[day],
                                            decoration: const InputDecoration(
                                              labelText: 'Start Time',
                                              border: OutlineInputBorder(),
                                              hintText: 'HH:MM',
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _dailyEndTimes[day],
                                            decoration: const InputDecoration(
                                              labelText: 'End Time',
                                              border: OutlineInputBorder(),
                                              hintText: 'HH:MM',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Column 2: Break 1
                                    Expanded(
                                      child: Column(
                                        children: [
                                          TextFormField(
                                            controller: _dailyBreak1Starts[day],
                                            decoration: const InputDecoration(
                                              labelText: 'Break 1 Start',
                                              border: OutlineInputBorder(),
                                              hintText: 'HH:MM',
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: _dailyBreak1Ends[day],
                                            decoration: const InputDecoration(
                                              labelText: 'Break 1 End',
                                              border: OutlineInputBorder(),
                                              hintText: 'HH:MM',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Column 3: Break 2 (only Mon-Thu)
                                    Expanded(
                                      child: hasBreak2
                                          ? Column(
                                              children: [
                                                TextFormField(
                                                  controller: _dailyBreak2Starts[day],
                                                  decoration: const InputDecoration(
                                                    labelText: 'Break 2 Start',
                                                    border: OutlineInputBorder(),
                                                    hintText: 'HH:MM',
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                  controller: _dailyBreak2Ends[day],
                                                  decoration: const InputDecoration(
                                                    labelText: 'Break 2 End',
                                                    border: OutlineInputBorder(),
                                                    hintText: 'HH:MM',
                                                  ),
                                                ),
                                              ],
                                            )
                                          : const SizedBox(), // Empty for Fri-Sun
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 24),

                      // Save button
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveUser,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF90EE90), // Pastel green
                          foregroundColor: Colors.black87,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save Changes'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
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

  /// Increment the Google API call counter in system_settings
  Future<void> _incrementApiCallCounter() async {
    try {
      print('🔍 [COUNTER] Fetching system_settings...');
      // Get the first (and should be only) system_settings record
      final settings = await SupabaseService.client
          .from('system_settings')
          .select('id, google_api_calls')
          .limit(1)
          .maybeSingle();

      print('🔍 [COUNTER] Settings result: $settings');

      if (settings != null) {
        // Update existing record
        final currentCount = (settings['google_api_calls'] as int?) ?? 0;
        final settingsId = settings['id']?.toString();
        print('🔍 [COUNTER] Current count: $currentCount, ID: $settingsId');
        
        // Try using RPC function if available, otherwise use direct update
        // The trigger issue is caused by trigger trying to update non-existent 'updated_at' column
        try {
          // Attempt direct update without select
          await SupabaseService.client
              .from('system_settings')
              .update({'google_api_calls': currentCount + 1})
              .eq('id', settingsId ?? '');
          
          print('✅ [COUNTER] Incremented API call counter to ${currentCount + 1}');
        } catch (triggerError, triggerStackTrace) {
          // If trigger fails, try using RPC function as workaround
          print('⚠️ [COUNTER] Direct update failed (trigger issue), trying alternative...');
          await ErrorLogService.logError(
            location: 'User Edit Screen - Increment API Call Counter',
            type: 'Database',
            description: 'Direct update failed (trigger issue) for API call counter: $triggerError',
            stackTrace: triggerStackTrace,
          );
          try {
            // Try using a stored procedure/RPC if available
            // Note: This requires a database function to be created
            await SupabaseService.client.rpc('increment_google_api_calls', params: {
              'p_id': settingsId,
            });
            print('✅ [COUNTER] Incremented via RPC function');
          } catch (rpcError, rpcStackTrace) {
            print('❌ [COUNTER] RPC also failed: $rpcError');
            print('💡 [COUNTER] Database trigger needs to be fixed - it references non-existent "updated_at" column');
            await ErrorLogService.logError(
              location: 'User Edit Screen - Increment API Call Counter (RPC)',
              type: 'Database',
              description: 'RPC function also failed for API call counter: $rpcError',
              stackTrace: rpcStackTrace,
            );
            throw triggerError; // Re-throw original error
          }
        }
      } else {
        // Create new record if none exists
        print('🔍 [COUNTER] No settings found, creating new record...');
        final insertResult = await SupabaseService.client.from('system_settings').insert({
          'google_api_calls': 1,
          'google_api_saves': 0,
          'week_start': 1,
        }).select();
        print('✅ [COUNTER] Created system_settings record with API call count: 1');
        print('🔍 [COUNTER] Insert result: $insertResult');
      }
    } catch (e, stackTrace) {
      print('❌ [COUNTER] Error incrementing API call counter: $e');
      print('❌ [COUNTER] Stack trace: $stackTrace');
      await ErrorLogService.logError(
        location: 'User Edit Screen - Increment API Call Counter (Outer)',
        type: 'Database',
        description: 'Error incrementing API call counter: $e',
        stackTrace: stackTrace,
      );
      // Don't fail the operation if counter update fails
    }
  }

  /// Increment the Google API save counter in system_settings
  Future<void> _incrementApiSaveCounter() async {
    try {
      print('🔍 [COUNTER] Fetching system_settings for save counter...');
      // Get the first (and should be only) system_settings record
      final settings = await SupabaseService.client
          .from('system_settings')
          .select('id, google_api_saves')
          .limit(1)
          .maybeSingle();

      print('🔍 [COUNTER] Settings result: $settings');

      if (settings != null) {
        // Update existing record
        final currentCount = (settings['google_api_saves'] as int?) ?? 0;
        final settingsId = settings['id']?.toString();
        print('🔍 [COUNTER] Current save count: $currentCount, ID: $settingsId');
        
        // Try using RPC function if available, otherwise use direct update
        // The trigger issue is caused by trigger trying to update non-existent 'updated_at' column
        try {
          // Attempt direct update without select
          await SupabaseService.client
              .from('system_settings')
              .update({'google_api_saves': currentCount + 1})
              .eq('id', settingsId ?? '');
          
          print('✅ [COUNTER] Incremented API save counter to ${currentCount + 1}');
        } catch (triggerError, triggerStackTrace) {
          // If trigger fails, try using RPC function as workaround
          print('⚠️ [COUNTER] Direct update failed (trigger issue), trying alternative...');
          await ErrorLogService.logError(
            location: 'User Edit Screen - Increment API Save Counter',
            type: 'Database',
            description: 'Direct update failed (trigger issue) for API save counter: $triggerError',
            stackTrace: triggerStackTrace,
          );
          try {
            // Try using a stored procedure/RPC if available
            // Note: This requires a database function to be created
            await SupabaseService.client.rpc('increment_google_api_saves', params: {
              'p_id': settingsId,
            });
            print('✅ [COUNTER] Incremented via RPC function');
          } catch (rpcError, rpcStackTrace) {
            print('❌ [COUNTER] RPC also failed: $rpcError');
            print('💡 [COUNTER] Database trigger needs to be fixed - it references non-existent "updated_at" column');
            await ErrorLogService.logError(
              location: 'User Edit Screen - Increment API Save Counter (RPC)',
              type: 'Database',
              description: 'RPC function also failed for API save counter: $rpcError',
              stackTrace: rpcStackTrace,
            );
            throw triggerError; // Re-throw original error
          }
        }
      } else {
        // Create new record if none exists
        print('🔍 [COUNTER] No settings found, creating new record...');
        final insertResult = await SupabaseService.client.from('system_settings').insert({
          'google_api_calls': 0,
          'google_api_saves': 1,
          'week_start': 1,
        }).select();
        print('✅ [COUNTER] Created system_settings record with API save count: 1');
        print('🔍 [COUNTER] Insert result: $insertResult');
      }
    } catch (e, stackTrace) {
      print('❌ [COUNTER] Error incrementing API save counter: $e');
      await ErrorLogService.logError(
        location: 'User Edit Screen - Increment API Save Counter (Outer)',
        type: 'Database',
        description: 'Error incrementing API save counter: $e',
        stackTrace: stackTrace,
      );
      print('❌ [COUNTER] Stack trace: $stackTrace');
      // Don't fail the operation if counter update fails
    }
  }
}

