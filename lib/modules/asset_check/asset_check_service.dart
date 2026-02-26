/// Asset Check Service
/// 
/// Handles all database operations for asset checking functionality:
/// - Loading stock locations from large_plant
/// - Loading/saving user stock location from users_data
/// - Validating small plant by small_plant_no
/// - Creating small_plant_check records
/// - Creating small_plant_faults records

import '../../config/supabase_config.dart';
import '../auth/auth_service.dart';
import '../errors/error_log_service.dart';

class AssetCheckService {
  /// Get distinct stock locations from stock_locations and large_plant
  static Future<List<String>> getStockLocations() async {
    try {
      final descriptions = <String>[];
      
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
            descriptions.add(desc);
          }
        }
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
        
        for (var item in plantResponse) {
          // Exclude entries where is_stock_location is NULL
          final isStockLocation = item['is_stock_location'];
          if (isStockLocation == null) {
            continue;
          }
          
          final desc = item['plant_description'] as String?;
          if (desc != null && desc.isNotEmpty && !descriptions.contains(desc)) {
            descriptions.add(desc);
          }
        }
      } catch (e) {
        print('⚠️ Error loading from large_plant table: $e');
      }
      
      return descriptions..sort();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Service - Get Stock Locations',
        type: 'Database',
        description: 'Failed to load stock locations: $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Get current user's default stock location from users_data
  static Future<String?> getUserStockLocation() async {
    try {
      final userId = AuthService.getCurrentUser()?.id;
      if (userId == null) return null;

      final response = await SupabaseService.client
          .from('users_data')
          .select('stock_location')
          .eq('user_id', userId)
          .maybeSingle();

      return response?['stock_location'] as String?;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Service - Get User Stock Location',
        type: 'Database',
        description: 'Failed to load user stock location: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Update user's default stock location in users_data
  static Future<void> updateUserStockLocation(String stockLocation) async {
    try {
      final userId = AuthService.getCurrentUser()?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      await SupabaseService.client
          .from('users_data')
          .update({'stock_location': stockLocation})
          .eq('user_id', userId);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Service - Update User Stock Location',
        type: 'Database',
        description: 'Failed to update user stock location: $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Validate small plant by small_plant_no and return details
  /// Returns null if not found or inactive
  /// Format: SP followed by 4 digits (e.g., "SP1234")
  static Future<Map<String, dynamic>?> validateSmallPlant(String plantNo) async {
    try {
      // Validate format: SP followed by exactly 4 digits
      if (!RegExp(r'^SP\d{4}$').hasMatch(plantNo)) {
        return null;
      }

      final response = await SupabaseService.client
          .from('small_plant')
          .select('id, small_plant_no, small_plant_description, is_active, type, make_model, serial_number')
          .eq('small_plant_no', plantNo)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      // Check if active
      final isActive = response['is_active'] as bool? ?? true;
      if (!isActive) {
        return null;
      }

      return {
        'id': response['id'],
        'small_plant_no': response['small_plant_no'],
        'small_plant_description': response['small_plant_description'],
        'type': response['type'],
        'make_model': response['make_model'],
        'serial_number': response['serial_number'],
        'is_active': isActive,
      };
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Service - Validate Small Plant',
        type: 'Database',
        description: 'Failed to validate small plant: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Create a small_plant_check record
  /// Returns the created record with its ID
  static Future<Map<String, dynamic>> createSmallPlantCheck({
    required DateTime date,
    required String stockLocation,
    required String smallPlantNo,
    bool synced = true,
    bool offlineCreated = false,
  }) async {
    try {
      final userId = AuthService.getCurrentUser()?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final response = await SupabaseService.client
          .from('small_plant_check')
          .insert({
            'date': date.toIso8601String().split('T')[0], // Format as YYYY-MM-DD
            'user_id': userId,
            'stock_location': stockLocation,
            'small_plant_no': smallPlantNo,
            'created_by': userId,
            'synced': synced,
            'offline_created': offlineCreated,
          })
          .select()
          .single();

      return response;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Service - Create Small Plant Check',
        type: 'Database',
        description: 'Failed to create small plant check: $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Create a small_plant_faults record
  static Future<Map<String, dynamic>> createSmallPlantFault({
    required String smallPlantCheckId,
    required String comment,
    String? photoUrl,
    String? supervisorId,
    String? actionType,
    DateTime? actionDate,
    String? actionNotes,
    bool synced = true,
    bool offlineCreated = false,
  }) async {
    try {
      final data = <String, dynamic>{
        'small_plant_check_id': smallPlantCheckId,
        'comment': comment,
        'synced': synced,
        'offline_created': offlineCreated,
      };

      if (photoUrl != null) {
        data['photo_url'] = photoUrl;
      }
      if (supervisorId != null) {
        data['supervisor_id'] = supervisorId;
      }
      if (actionType != null) {
        data['action_type'] = actionType;
      }
      if (actionDate != null) {
        data['action_date'] = actionDate.toIso8601String();
      }
      if (actionNotes != null) {
        data['action_notes'] = actionNotes;
      }

      final response = await SupabaseService.client
          .from('small_plant_faults')
          .insert(data)
          .select()
          .single();

      return response;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Service - Create Small Plant Fault',
        type: 'Database',
        description: 'Failed to create small plant fault: $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Batch create multiple small_plant_check records
  /// Returns list of created records with their IDs
  static Future<List<Map<String, dynamic>>> createSmallPlantChecksBatch({
    required DateTime date,
    required String stockLocation,
    required List<String> smallPlantNos,
    bool synced = true,
    bool offlineCreated = false,
  }) async {
    try {
      final userId = AuthService.getCurrentUser()?.id;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      final records = smallPlantNos.map((plantNo) => {
        'date': date.toIso8601String().split('T')[0],
        'user_id': userId,
        'stock_location': stockLocation,
        'small_plant_no': plantNo,
        'created_by': userId,
        'synced': synced,
        'offline_created': offlineCreated,
      }).toList();

      final response = await SupabaseService.client
          .from('small_plant_check')
          .insert(records)
          .select();

      return List<Map<String, dynamic>>.from(response);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Asset Check Service - Create Small Plant Checks Batch',
        type: 'Database',
        description: 'Failed to create small plant checks batch: $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

