/// MODULE 5: User Editing Service
/// 
/// This module handles fetching and updating existing user data.
/// 
/// PREREQUISITES:
/// - Module 1 (Supabase Config) must be initialized
/// - Module 2 (Auth) - Admin user must be logged in
/// 
/// TESTING:
/// Call UserEditService methods to fetch and update user data

import 'dart:convert';
import '../../config/supabase_config.dart';

class UserEditService {
  // Get list of all users with display names (for selection)
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      print('🔍 Fetching all users from users_data...');
      
      // Get users from users_data (idx_users_data_user_id; filter by user_id when loading one)
      // Note: users_data.user_id references auth.users.id
      final response = await SupabaseService.client
          .from('users_data')
          .select('user_id, display_name, forename, surname, employer_name')
          .order('display_name');

      final users = List<Map<String, dynamic>>.from(response);
      print('✅ Found ${users.length} users from users_data');
      
      if (users.isEmpty) {
        print('⚠️ No users found in users_data table');
        print('💡 This could be due to:');
        print('   1. RLS policies blocking access');
        print('   2. No users exist in users_data table');
        print('   3. Table is empty');
        return users;
      }
      
      print('🔍 Sample users: ${users.take(3).map((u) => u['display_name']).join(", ")}');
      
      // Now fetch security levels from users_setup for each user
      print('🔍 Fetching security levels from users_setup...');
      try {
        final securityResponse = await SupabaseService.client
            .from('users_setup')
            .select('user_id, security');
        
        final securityData = List<Map<String, dynamic>>.from(securityResponse);
        print('✅ Found ${securityData.length} security records');
        
        // Create a map of user_id -> security
        final securityMap = <String, int?>{};
        for (final record in securityData) {
          final userId = record['user_id']?.toString();
          if (userId != null) {
            securityMap[userId] = record['security'] as int?;
          }
        }
        
        // Merge security data into users
        for (final user in users) {
          final userId = user['user_id']?.toString();
          if (userId != null && securityMap.containsKey(userId)) {
            // Add users_setup as a nested object to match expected structure
            user['users_setup'] = {
              'security': securityMap[userId],
            };
          } else {
            // User has no security record
            user['users_setup'] = null;
          }
        }
        
        print('✅ Merged security data with user records');
      } catch (e) {
        print('⚠️ Error fetching security levels: $e');
        print('💡 Continuing without security data - users will still be loaded');
        // Continue without security data - users will have null users_setup
        for (final user in users) {
          user['users_setup'] = null;
        }
      }

      return users;
    } catch (e) {
      print('❌ Get all users error: $e');
      print('💡 Check RLS policies on users_data table');
      rethrow;
    }
  }

  // Get complete user data (auth.users, users_data, users_setup)
  static Future<Map<String, dynamic>> getUserData(String userId) async {
    try {
      final result = <String, dynamic>{
        'user_id': userId,
      };

      // Get auth user data (via admin API - requires service role or admin)
      // For now, we'll get what we can from the tables
      try {
        // users_data: eq user_id uses idx_users_data_user_id (see supabase_indexes.md)
        final userData = await SupabaseService.client
            .from('users_data')
            .select()
            .eq('user_id', userId)
            .maybeSingle();

        if (userData != null) {
          result['users_data'] = userData;
        } else {
          result['users_data'] = null;
          print('⚠️ No users_data record found for user: $userId');
        }
      } catch (e) {
        print('⚠️ Error fetching users_data: $e');
        result['users_data'] = null;
      }

      // Get users_setup
      try {
        final userSetup = await SupabaseService.client
            .from('users_setup')
            .select()
            .eq('user_id', userId)
            .maybeSingle();

        if (userSetup != null) {
          result['users_setup'] = userSetup;
        } else {
          result['users_setup'] = null;
          print('⚠️ No users_setup record found for user: $userId');
        }
      } catch (e) {
        print('⚠️ Error fetching users_setup: $e');
        result['users_setup'] = null;
      }

      // Get auth user info (email, phone) via Edge Function
      try {
        final response = await SupabaseService.client.functions.invoke(
          'get_user_auth_data',
          body: {'user_id': userId},
        );
        print('🔍 Edge Function response status: ${response.status}');
        print('🔍 Edge Function response data: ${response.data}');
        
        if (response.status == 200 && response.data != null) {
          // Handle both direct data and nested data structures
          final data = response.data;
          Map<String, dynamic>? authData;
          
          if (data is Map<String, dynamic>) {
            // Check if data is nested in a 'data' or 'user' field
            if (data.containsKey('data')) {
              authData = data['data'] as Map<String, dynamic>?;
            } else if (data.containsKey('user')) {
              authData = data['user'] as Map<String, dynamic>?;
            } else if (data.containsKey('email') || data.containsKey('phone')) {
              // Direct format with email/phone
              authData = data;
            } else if (data.containsKey('success') && data['success'] == true && data.containsKey('data')) {
              // Format: {success: true, data: {...}}
              authData = data['data'] as Map<String, dynamic>?;
            } else if (data.containsKey('success') && data['success'] == true && (data.containsKey('email') || data.containsKey('phone'))) {
              // Format: {success: true, email: ..., phone: ...}
              authData = data;
            }
            
            if (authData != null) {
              result['auth_user'] = authData;
              print('✅ Fetched auth user data: email=${authData['email']}, phone=${authData['phone']}');
            } else {
              result['auth_user'] = null;
              print('⚠️ Could not extract auth data from response: $data');
              print('💡 Available keys: ${data.keys.toList()}');
            }
          } else {
            result['auth_user'] = null;
            print('⚠️ Unexpected data format from Edge Function: ${data.runtimeType}');
          }
        } else {
          result['auth_user'] = null;
          print('⚠️ Could not fetch auth.users data: status=${response.status}, data=${response.data}');
        }
      } catch (e) {
        result['auth_user'] = null;
        print('⚠️ Error fetching auth.users data: $e (Edge Function may not exist)');
        print('💡 Make sure the get_user_auth_data Edge Function is deployed in Supabase');
      }

      return result;
    } catch (e) {
      print('❌ Get user data error: $e');
      rethrow;
    }
  }

  // Update user data via Edge Function
  // This will update auth.users, users_data, and users_setup
  static Future<Map<String, dynamic>> updateUser({
    required String userId,
    String? email,
    String? phone,
    String? displayName,
    String? forename,
    String? surname,
    String? initials,
    String? role,
    int? security,
    Map<String, dynamic>? usersDataFields,
    Map<String, dynamic>? usersSetupFields,
    String? password,
  }) async {
    try {
      final session = SupabaseService.client.auth.currentSession;
      if (session == null) {
        throw Exception('User must be logged in to update users');
      }

      // Prepare update body
      final body = <String, dynamic>{
        'user_id': userId,
      };

      // Add fields if provided
      if (email != null && email.isNotEmpty) body['email'] = email;
      if (phone != null) body['phone'] = phone;
      if (displayName != null && displayName.isNotEmpty) body['display_name'] = displayName;
      if (forename != null && forename.isNotEmpty) body['forename'] = forename;
      if (surname != null && surname.isNotEmpty) body['surname'] = surname;
      if (initials != null && initials.isNotEmpty) body['initials'] = initials;
      if (role != null && role.isNotEmpty) body['role'] = role;
      if (security != null) body['security'] = security;
      if (password != null && password.isNotEmpty) {
        body['password'] = password;
        // When setting a password, also confirm the email so user can sign in
        body['email_confirm'] = true;
      }
      if (usersDataFields != null && usersDataFields.isNotEmpty) {
        body['users_data_fields'] = usersDataFields;
      }
      if (usersSetupFields != null && usersSetupFields.isNotEmpty) {
        body['users_setup_fields'] = usersSetupFields;
      }

      print('🔍 Calling Edge Function update_user_admin for user: $userId');
      print('🔍 Request body: ${jsonEncode(body)}');
      if (usersSetupFields != null && usersSetupFields.isNotEmpty) {
        print('🔍 users_setup_fields being sent: ${jsonEncode(usersSetupFields)}');
      } else {
        print('⚠️ No users_setup_fields provided');
      }

      // Call Edge Function to update user
      // Note: You'll need to create an update_user_admin Edge Function
      final response = await SupabaseService.client.functions.invoke(
        'update_user_admin',
        body: body,
      );

      print('🔍 Edge Function response status: ${response.status}');

      if (response.status != 200 && response.status != 201) {
        final errorData = response.data;
        final errorMessage = errorData?['error'] ?? errorData?['detail'] ?? 'Failed to update user: ${response.status}';
        print('❌ Edge Function error: $errorMessage');
        throw Exception(errorMessage);
      }

      print('✅ User updated successfully');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('❌ Update user error: $e');
      rethrow;
    }
  }

  // Get user by display name
  static Future<Map<String, dynamic>?> getUserByDisplayName(String displayName) async {
    try {
      final response = await SupabaseService.client
          .from('users_data')
          .select('user_id, display_name')
          .eq('display_name', displayName)
          .maybeSingle();

      if (response == null) return null;

      final userId = response['user_id'] as String;
      return await getUserData(userId);
    } catch (e) {
      print('❌ Get user by display name error: $e');
      return null;
    }
  }
}

