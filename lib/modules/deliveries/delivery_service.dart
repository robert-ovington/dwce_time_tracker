/// Delivery Service
/// 
/// Handles database operations for waste deliveries

import 'package:postgrest/postgrest.dart';
import '../../config/supabase_config.dart';
import '../errors/error_log_service.dart';

class DeliveryService {
  /// Get all projects for dropdown
  static Future<List<Map<String, dynamic>>> getProjects() async {
    try {
      final response = await SupabaseService.client
          .from('projects')
          .select('id, project_name')
          .eq('is_active', true)
          .order('project_name');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Service - Get Projects',
        type: 'Database',
        description: 'Failed to load projects: $e',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get all large plant (vehicles) for dropdown
  /// Filtered to only show vehicles with haulage = TRUE
  static Future<List<Map<String, dynamic>>> getLargePlant() async {
    try {
      final response = await SupabaseService.client
          .from('large_plant')
          .select('id, plant_no, plant_description, short_description')
          .eq('is_active', true)
          .eq('haulage', true)
          .order('plant_no');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Service - Get Large Plant',
        type: 'Database',
        description: 'Failed to load large plant: $e',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get all waste facilities for dropdown
  static Future<List<Map<String, dynamic>>> getWasteFacilities() async {
    try {
      print('🔍 Querying waste_facilities table...');
      
      // Try querying with await to catch any Postgrest errors
      final response = await SupabaseService.client
          .from('waste_facilities')
          .select('id, facility_name, facility_address, facility_town, facility_county, facility_eircode, facility_phone, epa_licence_no')
          .order('facility_name');
      
      // Check if response is a list
      if (response == null) {
        print('⚠️ Query returned null response');
        return [];
      }
      
      final facilities = List<Map<String, dynamic>>.from(response);
      print('✅ Loaded ${facilities.length} waste facilities from database');
      
      if (facilities.isEmpty) {
        print('⚠️ No facilities found in waste_facilities table');
        print('💡 Troubleshooting:');
        print('   1. Check if table has data: SELECT COUNT(*) FROM waste_facilities;');
        print('   2. Check RLS policies: SELECT * FROM pg_policies WHERE tablename = \'waste_facilities\';');
        print('   3. Verify policy allows SELECT for current user');
        print('   4. Check if table exists: SELECT tablename FROM pg_tables WHERE schemaname = \'public\' AND tablename = \'waste_facilities\';');
      } else {
        print('   Sample facility: ${facilities.first['facility_name']} (id: ${facilities.first['id']})');
      }
      
      return facilities;
    } on PostgrestException catch (e, stackTrace) {
      final errorDetails = StringBuffer();
      errorDetails.writeln('Postgrest error loading waste facilities:');
      errorDetails.writeln('Code: ${e.code}');
      errorDetails.writeln('Message: ${e.message}');
      if (e.details != null) errorDetails.writeln('Details: ${e.details}');
      if (e.hint != null) errorDetails.writeln('Hint: ${e.hint}');
      
      print('❌ $errorDetails');
      await ErrorLogService.logError(
        location: 'Delivery Service - Get Waste Facilities',
        type: 'Database',
        description: errorDetails.toString(),
        stackTrace: stackTrace,
        errorCode: e.code,
      );
      return [];
    } catch (e, stackTrace) {
      print('❌ Error loading waste facilities: $e');
      print('   Error type: ${e.runtimeType}');
      print('   Full error: ${e.toString()}');
      
      // Try to extract more details if it's a Postgrest-style error
      String errorDescription = 'Failed to load waste facilities: $e (Type: ${e.runtimeType})';
      if (e.toString().contains('PostgrestException') || e.toString().contains('postgrest')) {
        errorDescription += '\n\nThis appears to be a Postgrest/RLS error. Check:\n';
        errorDescription += '1. RLS policies on waste_facilities table\n';
        errorDescription += '2. User has SELECT permissions\n';
        errorDescription += '3. Table exists and has data';
      }
      
      await ErrorLogService.logError(
        location: 'Delivery Service - Get Waste Facilities',
        type: 'Database',
        description: errorDescription,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get all materials for dropdown
  static Future<List<Map<String, dynamic>>> getMaterials() async {
    try {
      final response = await SupabaseService.client
          .from('material_list')
          .select('id, material_name, ewc_code')
          .order('material_name');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Service - Get Materials',
        type: 'Database',
        description: 'Failed to load materials: $e',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Create a delivery record
  static Future<Map<String, dynamic>?> createDelivery(Map<String, dynamic> deliveryData) async {
    try {
      final response = await SupabaseService.client
          .from('deliveries')
          .insert(deliveryData)
          .select()
          .single();
      
      return response as Map<String, dynamic>;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Service - Create Delivery',
        type: 'Database',
        description: 'Failed to create delivery: $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

