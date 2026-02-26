/// MODULE 3: Database Service
/// 
/// This module handles basic database operations (Create, Read, Update, Delete)
/// 
/// PREREQUISITES:
/// - Module 1 (Supabase Config) must be initialized
/// - Module 2 (Auth) - User should be logged in for protected operations
/// - In Supabase Dashboard: Create a table (e.g., 'items' or 'tasks')
///   Example SQL:
///   CREATE TABLE items (
///     id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
///     name TEXT NOT NULL,
///     description TEXT,
///     created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
///     user_id UUID REFERENCES auth.users(id)
///   );
/// 
/// TESTING:
/// 1. Create: Call DatabaseService.create('items', {'name': 'Test Item', 'description': 'Test'})
/// 2. Read: Call DatabaseService.read('items')
/// 3. Update: Call DatabaseService.update('items', id, {'name': 'Updated Item'})
/// 4. Delete: Call DatabaseService.delete('items', id)

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';

class DatabaseService {
  // Create a new record in a table
  static Future<Map<String, dynamic>> create(
    String tableName,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await SupabaseService.client
          .from(tableName)
          .insert(data)
          .select()
          .single();
      
      print('✅ Record created in $tableName: $response');
      return response;
    } catch (e) {
      print('❌ Create error: $e');
      rethrow;
    }
  }

  // Read all records from a table
  static Future<List<Map<String, dynamic>>> read(
    String tableName, {
    String? filterColumn,
    dynamic filterValue,
    int? limit,
    String? orderBy,
    bool ascending = true,
  }) async {
    try {
      // Start building the query
      var query = SupabaseService.client.from(tableName).select();

      // Apply filter if provided (this returns PostgrestFilterBuilder)
      if (filterColumn != null && filterValue != null) {
        query = query.eq(filterColumn, filterValue as Object);
      }

      // Build the query chain - apply ordering and limit in sequence
      // Note: order() and limit() return PostgrestTransformBuilder, so we chain them
      // Supabase PostgREST caps .limit() at 1000, so use .range() for higher limits
      dynamic finalQuery = query;
      
      if (orderBy != null) {
        finalQuery = finalQuery.order(orderBy, ascending: ascending);
      }

      if (limit != null && limit > 1000) {
        // For limits > 1000, use pagination to fetch all records
        // Supabase PostgREST has a default max-rows of 1000 (configurable in Dashboard)
        // Pagination ensures we get all records regardless of server setting
        print('🔍 [DatabaseService.read] Requested limit: $limit for table $tableName (using pagination)');
        final allRecords = <Map<String, dynamic>>[];
        const pageSize = 1000; // Fetch 1000 at a time
        int offset = 0;
        bool hasMore = true;

        while (hasMore && allRecords.length < limit) {
          final pageLimit = (offset + pageSize) < limit ? pageSize : (limit - offset);
          dynamic pageQuery = query;
          
          if (orderBy != null) {
            pageQuery = pageQuery.order(orderBy, ascending: ascending);
          }
          
          // Use range for pagination (0-indexed)
          final pageRangeEnd = offset + pageLimit - 1;
          pageQuery = pageQuery.range(offset, pageRangeEnd);
          
          final pageResponse = await pageQuery;
          final pageResults = List<Map<String, dynamic>>.from(pageResponse as Iterable<dynamic>);
          
          allRecords.addAll(pageResults);
          print('🔍 [DatabaseService.read] Fetched page: ${pageResults.length} records (total: ${allRecords.length})');
          
          // If we got fewer records than requested, we've reached the end
          if (pageResults.length < pageLimit || allRecords.length >= limit) {
            hasMore = false;
          } else {
            offset += pageSize;
          }
        }
        
        print('✅ Read ${allRecords.length} records from $tableName (via pagination)');
        return allRecords;
      } else if (limit != null) {
        finalQuery = finalQuery.limit(limit);
      }

      final response = await finalQuery;
      
      print('✅ Read ${response.length} records from $tableName');
      return List<Map<String, dynamic>>.from(response as Iterable<dynamic>);
    } catch (e) {
      print('❌ Read error: $e');
      rethrow;
    }
  }

  // Read a single record by ID
  static Future<Map<String, dynamic>?> readById(
    String tableName,
    String id,
  ) async {
    try {
      final response = await SupabaseService.client
          .from(tableName)
          .select()
          .eq('id', id)
          .single();
      
      print('✅ Read record from $tableName: $response');
      return response;
    } catch (e) {
      print('❌ Read by ID error: $e');
      return null;
    }
  }

  // Update a record by ID
  static Future<Map<String, dynamic>> update(
    String tableName,
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await SupabaseService.client
          .from(tableName)
          .update(data)
          .eq('id', id)
          .select()
          .single();
      
      print('✅ Record updated in $tableName: $response');
      return response;
    } catch (e) {
      print('❌ Update error: $e');
      rethrow;
    }
  }

  // Delete a record by ID
  static Future<void> delete(
    String tableName,
    String id,
  ) async {
    try {
      await SupabaseService.client
          .from(tableName)
          .delete()
          .eq('id', id);
      
      print('✅ Record deleted from $tableName (id: $id)');
    } catch (e) {
      print('❌ Delete error: $e');
      rethrow;
    }
  }

  // Execute a custom query using RPC or direct SQL via a Supabase function
  // Note: For complex queries with JOINs, we recommend creating a Postgres function
  // and calling it via RPC, or using the select() method with proper relationship syntax
  static Future<List<Map<String, dynamic>>> rpcQuery(
    String functionName,
    Map<String, dynamic>? params,
  ) async {
    try {
      final response = await SupabaseService.client.rpc(
        functionName,
        params: params,
      );
      
      print('✅ RPC query executed: $functionName');
      return List<Map<String, dynamic>>.from(response as Iterable<dynamic>);
    } catch (e) {
      print('❌ RPC query error: $e');
      rethrow;
    }
  }

  // Advanced read with multiple filters and ordering
  static Future<List<Map<String, dynamic>>> readAdvanced(
    String tableName, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    String? selectColumns,
  }) async {
    try {
      // Start building the query with custom columns if provided
      var query = SupabaseService.client
          .from(tableName)
          .select(selectColumns ?? '*');

      // Apply filters
      if (filters != null) {
        filters.forEach((column, value) {
          if (value != null) {
            query = query.eq(column, value as Object);
          }
        });
      }

      // Build the query chain
      dynamic finalQuery = query;
      
      if (orderBy != null) {
        finalQuery = finalQuery.order(orderBy, ascending: ascending);
      }

      if (limit != null) {
        finalQuery = finalQuery.limit(limit);
      }

      final response = await finalQuery;
      
      print('✅ Read ${response.length} records from $tableName');
      return List<Map<String, dynamic>>.from(response as Iterable<dynamic>);
    } catch (e) {
      print('❌ Advanced read error: $e');
      rethrow;
    }
  }

  // Listen to real-time changes in a table
  static RealtimeChannel subscribe(
    String tableName,
    Function(Map<String, dynamic>) onInsert,
    Function(Map<String, dynamic>) onUpdate,
    Function(Map<String, dynamic>) onDelete,
  ) {
    final channel = SupabaseService.client
        .channel('$tableName-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: tableName,
          callback: (payload) => onInsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: tableName,
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: tableName,
          callback: (payload) => onDelete(payload.oldRecord),
        )
        .subscribe();

    print('✅ Subscribed to real-time changes for $tableName');
    return channel;
  }
}

