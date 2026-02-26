/// MODULE 4: User Management Service
/// 
/// This module handles user creation via the Supabase Edge Function.
/// 
/// PREREQUISITES:
/// - Module 1 (Supabase Config) must be initialized
/// - Module 2 (Auth) - Admin user must be logged in
/// - Edge Function "create_user_admin" must be deployed in Supabase
/// 
/// TESTING:
/// Call UserService.createUser() with required fields

import 'dart:convert';
import '../../config/supabase_config.dart';

class UserService {
  // Create a new user via Edge Function
  static Future<Map<String, dynamic>> createUser({
    required String email,
    String? password,
    String? phone,
    required String forename,
    required String surname,
    required String initials,
    required String role,
    required int security,
    Map<String, dynamic>? usersDataFields,
    Map<String, dynamic>? usersSetupFields,
  }) async {
    try {
      // Get the current user's session token
      final session = SupabaseService.client.auth.currentSession;
      if (session == null) {
        throw Exception('User must be logged in to create users');
      }

      // Display name: same format as users_setup.display_name; create_user_admin writes it to auth.users.display_name and raw_user_meta_data.name
      final displayName = '$surname, $forename'.trim();

      // Prepare the request body (matches create_user_admin: email, display_name, password, etc.)
      final body = <String, dynamic>{
        'email': email.trim(),
        'display_name': displayName,
        'forename': forename.trim(),
        'surname': surname.trim(),
        'initials': initials.trim(),
        'role': role,
        'security': security,
        'email_confirm': true, // Admin-created users are confirmed so they can sign in immediately
      };

      // Add optional fields
      // Always send password field (even if empty) to satisfy Edge Function validation
      body['password'] = (password != null && password.isNotEmpty) ? password : '';
      
      if (phone != null && phone.isNotEmpty) {
        body['phone'] = phone.trim();
      }
      if (usersDataFields != null && usersDataFields.isNotEmpty) {
        body['users_data_fields'] = usersDataFields;
      }
      if (usersSetupFields != null && usersSetupFields.isNotEmpty) {
        body['users_setup_fields'] = usersSetupFields;
      }

      // Call the Edge Function
      // The Supabase Flutter SDK automatically adds the Authorization header
      // from the current session, so we don't need to pass it explicitly
      print('🔍 Calling Edge Function create_user_admin');
      print('🔍 User: ${session.user.email}, Token present: ${session.accessToken != null}'); // ignore: unnecessary_null_comparison
      print('🔍 Request body: ${jsonEncode(body)}');
      if (usersSetupFields != null && usersSetupFields.isNotEmpty) {
        print('🔍 users_setup_fields being sent: ${jsonEncode(usersSetupFields)}');
      } else {
        print('⚠️ No users_setup_fields provided');
      }
      
      final response = await SupabaseService.client.functions.invoke(
        'create_user_admin',
        body: body,
      );

      print('🔍 Edge Function response status: ${response.status}');
      
      if (response.status != 200 && response.status != 201) {
        final errorData = response.data;
        final errorMessage = errorData?['error'] ?? errorData?['detail'] ?? 'Failed to create user: ${response.status}';
        print('❌ Edge Function error: $errorMessage');
        print('❌ Full response: $errorData');
        
        if (response.status == 401) {
          throw Exception(
            'Authentication failed. The token may have expired.\n\n'
            'Please try:\n'
            '1. Sign out and sign back in\n'
            '2. Then try creating the user again\n\n'
            'Error: $errorMessage',
          );
        }
        
        throw Exception(errorMessage);
      }

      print('✅ User created successfully');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('❌ Create user error: $e');
      rethrow;
    }
  }

  /// Increment the Google API call counter in system_settings
  static Future<void> _incrementApiCallCounter() async {
    try {
      final settings = await SupabaseService.client
          .from('system_settings')
          .select('id, google_api_calls')
          .limit(1)
          .maybeSingle();

      if (settings != null) {
        final currentCount = (settings['google_api_calls'] as int?) ?? 0;
        await SupabaseService.client
            .from('system_settings')
            .update({'google_api_calls': currentCount + 1})
            .eq('id', settings['id'] as Object);
        print('✅ Incremented API call counter to ${currentCount + 1}');
      } else {
        await SupabaseService.client.from('system_settings').insert({
          'google_api_calls': 1,
          'google_api_saves': 0,
          'week_start': 1,
        });
        print('✅ Created system_settings record with API call count: 1');
      }
    } catch (e) {
      print('⚠️ Error incrementing API call counter: $e');
    }
  }

  /// Increment the Google API save counter in system_settings
  static Future<void> _incrementApiSaveCounter() async {
    try {
      final settings = await SupabaseService.client
          .from('system_settings')
          .select('id, google_api_saves')
          .limit(1)
          .maybeSingle();

      if (settings != null) {
        final currentCount = (settings['google_api_saves'] as int?) ?? 0;
        await SupabaseService.client
            .from('system_settings')
            .update({'google_api_saves': currentCount + 1})
            .eq('id', settings['id'] as Object);
        print('✅ Incremented API save counter to ${currentCount + 1}');
      } else {
        await SupabaseService.client.from('system_settings').insert({
          'google_api_calls': 0,
          'google_api_saves': 1,
          'week_start': 1,
        });
        print('✅ Created system_settings record with API save count: 1');
      }
    } catch (e) {
      print('⚠️ Error incrementing API save counter: $e');
    }
  }

  // Geocode Eircode and return coordinates and address
  static Future<Map<String, dynamic>?> geocodeEircode(String eircode) async {
    try {
      // Remove spaces from Eircode
      final cleanEircode = eircode.trim().replaceAll(' ', '');
      if (cleanEircode.isEmpty) return null;

      print('🔍 Geocoding Eircode: $cleanEircode');

      // First, check cache
      try {
        final cachedResult = await SupabaseService.client
            .from('google_api_calls')
            .select('home_latitude, home_longitude, display_name, was_cached')
            .eq('eircode', cleanEircode)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (cachedResult != null) {
          final cachedLat = cachedResult['home_latitude'] as double?;
          final cachedLng = cachedResult['home_longitude'] as double?;
          final cachedAddress = cachedResult['display_name'] as String?;
          
          if (cachedLat != null && cachedLng != null) {
            print('✅ Found cached coordinates for $cleanEircode');
            // Increment save counter
            await _incrementApiSaveCounter();
            return {
              'lat': cachedLat,
              'lng': cachedLng,
              'formatted_address': cachedAddress ?? '',
              'eircode': cleanEircode,
            };
          }
        }
      } catch (e) {
        print('⚠️ Error checking cache: $e, proceeding with API call...');
      }

      // No cached data, call Edge Function
      print('🔍 Calling Edge Function for eircode: $cleanEircode');
      // Increment API call counter
      await _incrementApiCallCounter();
      
      final response = await SupabaseService.client.functions.invoke(
        'geocode_eircode_edge_function',
        body: {'eircode': cleanEircode},
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true) {
          final lat = data['lat'] as double?;
          final lng = data['lng'] as double?;
          final formattedAddress = data['formatted_address'] as String?;
          
          if (lat != null && lng != null) {
            // Save to cache
            try {
              await SupabaseService.client.from('google_api_calls').insert({
                'eircode': cleanEircode,
                'home_latitude': lat,
                'home_longitude': lng,
                'display_name': formattedAddress ?? '',
                'time_stamp': DateTime.now().toIso8601String(),
                'was_cached': false,
              });
              print('✅ Saved GPS coordinates to cache');
              // Note: API call counter already incremented above
            } catch (e) {
              print('⚠️ Error saving to cache: $e');
            }
            
            return {
              'lat': lat,
              'lng': lng,
              'formatted_address': formattedAddress ?? '',
              'eircode': cleanEircode,
            };
          }
        }
      }
      
      print('⚠️ Could not geocode Eircode: $cleanEircode');
      return null;
    } catch (e) {
      print('❌ Geocoding error: $e');
      return null;
    }
  }

  // Create multiple users from a list
  static Future<List<Map<String, dynamic>>> createUsersBulk(
    List<Map<String, dynamic>> users,
  ) async {
    final results = <Map<String, dynamic>>[];

    for (var user in users) {
      try {
        // Extract users_data_fields if present (employer_name, eircode, User Flags)
        final usersDataFields = <String, dynamic>{};
        if (user.containsKey('employer_name') && user['employer_name'] != null) {
          usersDataFields['employer_name'] = user['employer_name'];
        }
        final dataFlagKeys = [
          'show_project', 'show_fleet', 'show_allowances', 'show_comments',
          'concrete_mix_lorry', 'reinstatement_crew', 'cable_pulling',
          'is_mechanic', 'is_public', 'is_active',
        ];
        for (final key in dataFlagKeys) {
          if (user.containsKey(key) && user[key] != null && user[key] is bool) {
            usersDataFields[key] = user[key] as bool;
          }
        }
        
        // Geocode Eircode if provided
        if (user.containsKey('eircode') && user['eircode'] != null) {
          final eircode = user['eircode'] as String;
          if (eircode.isNotEmpty) {
            print('🔍 Geocoding Eircode for ${user['email']}: $eircode');
            final geocodeResult = await geocodeEircode(eircode);
            if (geocodeResult != null) {
              usersDataFields['eircode'] = geocodeResult['eircode'];
              usersDataFields['home_latitude'] = geocodeResult['lat'];
              usersDataFields['home_longitude'] = geocodeResult['lng'];
              if (geocodeResult['formatted_address'] != null && 
                  (geocodeResult['formatted_address'] as String).isNotEmpty) {
                usersDataFields['home_address'] = geocodeResult['formatted_address'];
              }
              print('✅ Eircode geocoded successfully for ${user['email']}');
            } else {
              // Still save Eircode even if geocoding fails
              usersDataFields['eircode'] = eircode;
              print('⚠️ Eircode geocoding failed for ${user['email']}, but saving Eircode anyway');
            }
          }
        }

        // Build users_setup fields from CSV when present (security_limit, menu_*)
        final usersSetupFields = <String, dynamic>{};
        if (user.containsKey('security_limit') && user['security_limit'] != null) {
          usersSetupFields['security_limit'] = user['security_limit'] as int;
        }
        final setupBoolKeys = [
          'menu_clock_in', 'menu_time_periods', 'menu_plant_checks', 'menu_deliveries',
          'menu_paperwork', 'menu_time_off', 'menu_sites', 'menu_reports', 'menu_managers',
          'menu_exports', 'menu_administration', 'menu_messenger',
          'menu_training', 'menu_cube_test', 'menu_office', 'menu_office_admin', 'menu_office_project',
          'menu_concrete_mix', 'menu_workshop',
          'ppe_manager',
        ];
        for (final key in setupBoolKeys) {
          if (user.containsKey(key) && user[key] != null && user[key] is bool) {
            usersSetupFields[key] = user[key] as bool;
          }
        }
        
        final result = await createUser(
          email: user['email'] as String,
          password: user['password'] as String?,
          phone: user['phone'] as String?,
          forename: user['forename'] as String,
          surname: user['surname'] as String,
          initials: user['initials'] as String,
          role: user['role'] as String,
          security: user['security'] as int,
          usersDataFields: usersDataFields.isNotEmpty ? usersDataFields : null,
          usersSetupFields: usersSetupFields.isNotEmpty ? usersSetupFields : null,
        );
        results.add({
          'success': true,
          'email': user['email'],
          'data': result,
        });
      } catch (e) {
        results.add({
          'success': false,
          'email': user['email'],
          'error': e.toString(),
        });
      }
    }

    return results;
  }

  // Get current user's setup data
  static Future<Map<String, dynamic>?> getCurrentUserSetup() async {
    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) {
        print('⚠️ No user ID found - user not logged in');
        return null;
      }

      print('🔍 Querying users_setup for user_id: $userId');
      print('🔍 Current auth user: ${SupabaseService.client.auth.currentUser?.email}');

      // Use maybeSingle() instead of single() to handle 0 rows gracefully
      final response = await SupabaseService.client
          .from('users_setup')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        print('⚠️ No users_setup record found for user: $userId');
        print('💡 Troubleshooting steps:');
        print('   1. Verify RLS policy exists: SELECT * FROM pg_policies WHERE tablename = \'users_setup\';');
        print('   2. Verify policy allows SELECT: The policy should have FOR SELECT');
        print('   3. Verify auth.uid() matches: Run SELECT auth.uid(); in SQL Editor');
        print('   4. Try signing out and back in to refresh the session');
        print('   5. Check if user_id in table matches: ${userId}');
        return null;
      }

      print('✅ Found users_setup record: $response');
      return response;
    } catch (e) {
      print('❌ Get user setup error: $e');
      print('💡 Error details: ${e.toString()}');
      print('💡 Check RLS policies on users_setup table');
      return null;
    }
  }

  // Get current user's data
  static Future<Map<String, dynamic>?> getCurrentUserData() async {
    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) return null;

      // Use maybeSingle() instead of single() to handle 0 rows gracefully
      final response = await SupabaseService.client
          .from('users_data')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        print('⚠️ No users_data record found for user: $userId');
        return null;
      }

      return response;
    } catch (e) {
      print('❌ Get user data error: $e');
      return null;
    }
  }

  // Check if current user has security level 1 (highest level)
  // Only security = 1 is allowed to create/edit users
  static Future<bool> isCurrentUserAdmin() async {
    try {
      print('🔍 Checking user security level...');
      final setup = await getCurrentUserSetup();
      if (setup == null) {
        print('⚠️ No users_setup record found - cannot verify security level');
        return false;
      }

      final security = setup['security'];
      print('🔍 Security check - Security level: $security');

      // Only security level 1 is allowed
      if (security != null) {
        final securityInt = security is int ? security : int.tryParse(security.toString());
        if (securityInt != null && securityInt == 1) {
          print('✅ User has security level 1 - access granted');
          return true;
        } else {
          print('❌ User security level is $securityInt (required: 1)');
        }
      } else {
        print('❌ Security level is null');
      }

      return false;
    } catch (e) {
      print('❌ Check security level error: $e');
      return false;
    }
  }

  // Check if current user is Supervisor, Manager, or Admin
  // Security level 1-4 OR role is Supervisor/Manager/Admin
  static Future<bool> isCurrentUserSupervisorOrManager() async {
    try {
      print('🔍 Checking supervisor/manager status...');
      final setup = await getCurrentUserSetup();
      if (setup == null) {
        print('⚠️ No users_setup record found');
        return false;
      }

      final security = setup['security'];
      final role = setup['role']?.toString() ?? '';

      // Check security level (1-4 are supervisory levels)
      if (security != null) {
        final securityInt = security is int ? security : int.tryParse(security.toString());
        if (securityInt != null && securityInt <= 4) {
          print('✅ User has security level $securityInt (≤4) - supervisor access granted');
          return true;
        }
      }

      // Check role (security 1–4 roles that grant supervisor/manager access)
      if (role == 'Admin' || role == 'Manager' || role == 'Supervisor' ||
          role == 'Foreman' || role == 'Crew Leader' || role == 'Engineer') {
        print('✅ User has role $role - supervisor access granted');
        return true;
      }

      print('❌ User is not a supervisor/manager (security: $security, role: $role)');
      return false;
    } catch (e) {
      print('❌ Check supervisor status error: $e');
      return false;
    }
  }

  // Valid roles list (order matches default security levels 1–9)
  static const List<String> validRoles = [
    'Admin',
    'Manager',
    'Foreman',
    'Supervisor',
    'Crew Leader',
    'Engineer',
    'Technical Operative',
    'Skilled Operative',
    'Excavator/Truck Operative',
    'Truck Operative',
    'Semi-skilled Operative',
    'Basic Operative',
    'Excavator Operative',
    'Pipe Layer',
    'Mechanic',
    'Miscellaneous',
    'Subcontractor',
    'External',
    'Visitor',
  ];

  // Menu permission keys (matching database column names)
  static const String menuClockIn = 'menu_clock_in';
  static const String menuTimePeriods = 'menu_time_periods';
  static const String menuPlantChecks = 'menu_plant_checks';
  static const String menuDeliveries = 'menu_deliveries';
  static const String menuPaperwork = 'menu_paperwork';
  static const String menuTimeOff = 'menu_time_off';
  static const String menuTraining = 'menu_training';
  static const String menuCubeTest = 'menu_cube_test';
  static const String menuSites = 'menu_sites';
  static const String menuReports = 'menu_reports';
  static const String menuManagers = 'menu_managers';
  static const String menuExports = 'menu_exports';
  static const String menuAdministration = 'menu_administration';
  static const String menuOffice = 'menu_office';
  static const String menuOfficeAdmin = 'menu_office_admin';
  static const String menuOfficeProject = 'menu_office_project';
  static const String menuConcreteMix = 'menu_concrete_mix';
  static const String menuWorkshop = 'menu_workshop';
  static const String menuMessages = 'menu_messages';
  static const String menuMessenger = 'menu_messenger';
  /// PPE Management menu (stocking, allocation) - visible when users_setup.ppe_manager = true
  static const String ppeManager = 'ppe_manager';

  /// Check if a specific menu item is enabled for the current user
  /// Returns true if enabled, false if disabled or if user setup not found
  static Future<bool> isMenuEnabled(String menuKey) async {
    try {
      final setup = await getCurrentUserSetup();
      if (setup == null) {
        // If no setup found, default to false for safety
        return false;
      }

      final enabled = setup[menuKey];
      if (enabled == null) {
        // If column doesn't exist or is null, default to true for backward compatibility
        return true;
      }

      return enabled == true;
    } catch (e) {
      print('❌ Check menu permission error for $menuKey: $e');
      // Default to false on error for security
      return false;
    }
  }

  /// Get all menu permissions for the current user
  /// Returns a map of menu keys to enabled/disabled status
  /// [setup] if provided, use it instead of fetching (avoids duplicate getCurrentUserSetup calls).
  static Future<Map<String, bool>> getAllMenuPermissions({Map<String, dynamic>? setup}) async {
    try {
      final Map<String, dynamic>? resolvedSetup = setup ?? await getCurrentUserSetup();
      if (resolvedSetup == null) {
        // Return all false if no setup found
        return {
          menuClockIn: false,
          menuTimePeriods: false,
          menuPlantChecks: false,
          menuDeliveries: false,
          menuPaperwork: false,
          menuTimeOff: false,
          menuTraining: false,
          menuCubeTest: false,
          menuSites: false,
          menuReports: false,
          menuManagers: false,
          menuExports: false,
          menuAdministration: false,
          menuOffice: false,
          menuOfficeAdmin: false,
          menuConcreteMix: false,
          menuWorkshop: false,
          menuMessages: false,
          menuMessenger: false,
          ppeManager: false,
        };
      }

      // Extract menu permissions, defaulting to true if null (backward compatibility). ppe_manager defaults to false.
      return {
        menuClockIn: (resolvedSetup[menuClockIn] as bool?) ?? true,
        menuTimePeriods: (resolvedSetup[menuTimePeriods] as bool?) ?? true,
        menuPlantChecks: (resolvedSetup[menuPlantChecks] as bool?) ?? true,
        menuDeliveries: (resolvedSetup[menuDeliveries] as bool?) ?? true,
        menuPaperwork: (resolvedSetup[menuPaperwork] as bool?) ?? true,
        menuTimeOff: (resolvedSetup[menuTimeOff] as bool?) ?? true,
        menuTraining: (resolvedSetup[menuTraining] as bool?) ?? true,
        menuCubeTest: (resolvedSetup[menuCubeTest] as bool?) ?? true,
        menuSites: (resolvedSetup[menuSites] as bool?) ?? true,
        menuReports: (resolvedSetup[menuReports] as bool?) ?? true,
        menuManagers: (resolvedSetup[menuManagers] as bool?) ?? true,
        menuExports: (resolvedSetup[menuExports] as bool?) ?? true,
        menuAdministration: (resolvedSetup[menuAdministration] as bool?) ?? true,
        menuOffice: (resolvedSetup[menuOffice] as bool?) ?? true,
        menuOfficeAdmin: (resolvedSetup[menuOfficeAdmin] as bool?) ?? true,
        menuConcreteMix: (resolvedSetup[menuConcreteMix] as bool?) ?? false,
        menuWorkshop: (resolvedSetup[menuWorkshop] as bool?) ?? false,
        menuMessages: (resolvedSetup[menuMessages] as bool?) ?? true,
        menuMessenger: (resolvedSetup[menuMessenger] as bool?) ?? true,
        ppeManager: (resolvedSetup[ppeManager] as bool?) ?? false,
      };
    } catch (e) {
      print('❌ Get all menu permissions error: $e');
      // Return all false on error
      return {
        menuClockIn: false,
        menuTimePeriods: false,
        menuPlantChecks: false,
        menuDeliveries: false,
        menuPaperwork: false,
        menuTimeOff: false,
        menuTraining: false,
        menuCubeTest: false,
        menuSites: false,
        menuReports: false,
        menuManagers: false,
        menuExports: false,
        menuAdministration: false,
        menuOffice: false,
        menuOfficeAdmin: false,
        menuConcreteMix: false,
        menuWorkshop: false,
        menuMessages: false,
        menuMessenger: false,
        ppeManager: false,
      };
    }
  }

  // Validate security level (1-9)
  static bool isValidSecurity(int security) {
    return security >= 1 && security <= 9;
  }

  // Validate role
  static bool isValidRole(String role) {
    return validRoles.contains(role);
  }
}

