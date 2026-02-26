/// Employer Management Service
/// 
/// This module handles employer CRUD operations.
/// 
/// PREREQUISITES:
/// - Module 1 (Supabase Config) must be initialized
/// - Module 2 (Auth) - User must be logged in

import '../../config/supabase_config.dart';

class EmployerService {
  // Get all employers
  static Future<List<Map<String, dynamic>>> getAllEmployers() async {
    try {
      final response = await SupabaseService.client
          .from('employers')
          .select()
          .order('employer_name');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Get all employers error: $e');
      rethrow;
    }
  }

  // Get a single employer by ID
  static Future<Map<String, dynamic>?> getEmployerById(String id) async {
    try {
      final response = await SupabaseService.client
          .from('employers')
          .select()
          .eq('id', id)
          .maybeSingle();
      
      return response;
    } catch (e) {
      print('❌ Get employer error: $e');
      rethrow;
    }
  }

  // Get all employer types
  static Future<List<String>> getEmployerTypes() async {
    try {
      print('🔍 Querying employer_type table...');
      final response = await SupabaseService.client
          .from('employer_type')
          .select('employer_type')
          .order('employer_type');
      
      print('🔍 Raw response from employer_type: $response');
      print('🔍 Response type: ${response.runtimeType}');
      print('🔍 Response length: ${response.length}');
      
      final types = <String>[];
      for (var item in response) {
        print('🔍 Processing item: $item');
        final type = item['employer_type'] as String?;
        if (type != null && type.isNotEmpty) {
          types.add(type);
          print('✅ Added employer type: $type');
        }
      }
      
      print('✅ Total employer types loaded: ${types.length}');
      return types;
    } catch (e, stackTrace) {
      print('❌ Get employer types error: $e');
      print('❌ Stack trace: $stackTrace');
      // Return empty list instead of rethrowing so the UI doesn't crash
      return [];
    }
  }

  // Create a new employer
  static Future<Map<String, dynamic>> createEmployer({
    required String employerName,
    required String employerType,
    bool isActive = true,
  }) async {
    try {
      final response = await SupabaseService.client
          .from('employers')
          .insert({
            'employer_name': employerName,
            'employer_type': employerType,
            'is_active': isActive,
          })
          .select()
          .single();
      
      print('✅ Employer created successfully');
      return response;
    } catch (e) {
      print('❌ Create employer error: $e');
      rethrow;
    }
  }

  // Update an existing employer
  static Future<Map<String, dynamic>> updateEmployer({
    required String id,
    String? employerName,
    String? employerType,
    bool? isActive,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (employerName != null && employerName.isNotEmpty) {
        updateData['employer_name'] = employerName;
      }
      if (employerType != null && employerType.isNotEmpty) {
        updateData['employer_type'] = employerType;
      }
      if (isActive != null) {
        updateData['is_active'] = isActive;
      }

      if (updateData.isEmpty) {
        throw Exception('No fields to update');
      }

      final response = await SupabaseService.client
          .from('employers')
          .update(updateData)
          .eq('id', id)
          .select()
          .single();
      
      print('✅ Employer updated successfully');
      return response;
    } catch (e) {
      print('❌ Update employer error: $e');
      rethrow;
    }
  }

  // Check if employer is in use (referenced in users_data)
  static Future<bool> isEmployerInUse(String employerName) async {
    try {
      final response = await SupabaseService.client
          .from('users_data')
          .select('user_id')
          .eq('employer_name', employerName)
          .limit(1);
      
      return response.isNotEmpty;
    } catch (e) {
      print('❌ Check employer in use error: $e');
      // If we can't check, assume it's in use to be safe
      return true;
    }
  }

  // Get employer name by ID
  static Future<String?> getEmployerNameById(String id) async {
    try {
      final response = await SupabaseService.client
          .from('employers')
          .select('employer_name')
          .eq('id', id)
          .maybeSingle();
      
      if (response == null) return null;
      return response['employer_name'] as String?;
    } catch (e) {
      print('❌ Get employer name error: $e');
      return null;
    }
  }

  // Delete an employer (only if not in use)
  static Future<void> deleteEmployer(String id) async {
    try {
      // First, get the employer name to check if it's in use
      final employerName = await getEmployerNameById(id);
      if (employerName == null) {
        throw Exception('Employer not found');
      }

      // Check if employer is referenced in users_data
      final inUse = await isEmployerInUse(employerName);
      if (inUse) {
        throw Exception(
          'Cannot delete employer "$employerName" because it is assigned to one or more users. '
          'Please reassign or remove the employer from all users before deleting.'
        );
      }

      // Safe to delete
      await SupabaseService.client
          .from('employers')
          .delete()
          .eq('id', id);
      
      print('✅ Employer deleted successfully');
    } catch (e) {
      print('❌ Delete employer error: $e');
      rethrow;
    }
  }

  // Create multiple employers from a list
  static Future<List<Map<String, dynamic>>> createEmployersBulk(
    List<Map<String, dynamic>> employers,
  ) async {
    final results = <Map<String, dynamic>>[];

    for (var employer in employers) {
      try {
        final result = await createEmployer(
          employerName: employer['employer_name'] as String,
          employerType: employer['employer_type'] as String,
          isActive: employer['is_active'] as bool? ?? true,
        );
        results.add({
          'success': true,
          'employer_name': employer['employer_name'],
          'data': result,
        });
      } catch (e) {
        results.add({
          'success': false,
          'employer_name': employer['employer_name'],
          'error': e.toString(),
        });
      }
    }

    return results;
  }
}

