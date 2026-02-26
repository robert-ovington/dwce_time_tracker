/// Sync Service
/// 
/// Handles syncing of offline queued entries to Supabase when online.

import '../database/database_service.dart';
import '../../config/supabase_config.dart';
import 'offline_storage_service.dart';

class SyncService {
  /// Sync all pending offline entries to Supabase
  static Future<Map<String, dynamic>> syncOfflineData() async {
    final pendingEntries = await OfflineStorageService.getPendingEntries();
    
    if (pendingEntries.isEmpty) {
      return {
        'success': 0,
        'failed': 0,
        'message': 'No pending entries to sync.',
      };
    }

    int successCount = 0;
    int failedCount = 0;
    final errors = <String>[];

    for (final entry in pendingEntries) {
      try {
        final entryData = entry['entry_data'] as Map<String, dynamic>;
        final entryId = entry['id'] as int;
        final entryType = entryData['_entry_type']?.toString();
        final tableName = entryData['_table_name']?.toString() ?? 'time_periods';

        // Handle time_attendance records differently
        if (tableName == 'time_attendance') {
          await _syncTimeAttendanceEntry(entry, entryData, entryId, entryType);
          successCount++;
          continue;
        }

        // Add sync metadata (sync_datetime is not in time_periods schema)
        entryData['synced'] = true;
        entryData['offline_created'] = false;

        // Extract breaks and fleet data (stored for offline entries)
        final breaks = entryData.remove('_breaks') as List<dynamic>?;
        final usedFleet = entryData.remove('_usedFleet') as List<dynamic>?;
        final mobilisedFleet = entryData.remove('_mobilisedFleet') as List<dynamic>?;

        // Store offline queue id in time_periods.offline_id before removing metadata
        entryData['offline_id'] = entryId.toString();
        // Remove metadata fields before saving
        entryData.remove('_entry_type');
        entryData.remove('_table_name');
        entryData.remove('_offline_id');
        entryData.remove('_clock_in_offline_id');
        entryData.remove('_clock_in_offline_record');
        entryData.remove('_clock_in_record_id');

        // Insert into Supabase
        final result = await DatabaseService.create('time_periods', entryData);
        final timePeriodId = result['id']?.toString();

        // Save breaks and fleet to separate tables using timePeriodId
        if (timePeriodId != null) {
          // Save breaks
          if (breaks != null && breaks.isNotEmpty) {
            for (final breakData in breaks) {
              if (breakData is Map<String, dynamic>) {
                try {
                  await DatabaseService.create('time_breaks', {
                    'time_period_id': timePeriodId,
                    'break_start': breakData['start'],
                    'break_finish': breakData['finish'],
                    'break_reason': breakData['reason'],
                  });
                } catch (e) {
                  print('⚠️ Error saving break: $e');
                }
              }
            }
          }
          
          // Save used fleet
          if (usedFleet != null && usedFleet.isNotEmpty) {
            try {
              final fleetData = <String, dynamic>{
                'time_period_id': timePeriodId,
              };
              for (int i = 0; i < 6 && i < usedFleet.length; i++) {
                final plantNo = usedFleet[i]?.toString().trim().toUpperCase();
                if (plantNo != null && plantNo.isNotEmpty) {
                  fleetData['large_plant_id_${i + 1}'] = plantNo;
                }
              }
              if (fleetData.keys.any((key) => key.startsWith('large_plant_id_'))) {
                await DatabaseService.create('time_used_large_plant', fleetData);
              }
            } catch (e) {
              print('⚠️ Error saving used fleet: $e');
            }
          }
          
          // Save mobilised fleet
          if (mobilisedFleet != null && mobilisedFleet.isNotEmpty) {
            try {
              final fleetData = <String, dynamic>{
                'time_period_id': timePeriodId,
              };
              for (int i = 0; i < 4 && i < mobilisedFleet.length; i++) {
                final plantNo = mobilisedFleet[i]?.toString().trim().toUpperCase();
                if (plantNo != null && plantNo.isNotEmpty) {
                  fleetData['large_plant_no_${i + 1}'] = plantNo;
                }
              }
              if (fleetData.keys.any((key) => key.startsWith('large_plant_no_'))) {
                await DatabaseService.create('time_mobilised_large_plant', fleetData);
              }
            } catch (e) {
              print('⚠️ Error saving mobilised fleet: $e');
            }
          }
          
          // Update user project history if project_id exists
          final projectId = entryData['project_id']?.toString();
          final projectName = entryData['project_name']?.toString();
          final workDate = entryData['work_date']?.toString();
          final userId = entryData['user_id']?.toString();
          if (projectId != null && projectName != null && workDate != null && userId != null) {
            // Note: This requires access to _updateUserProjectHistory method
            // For now, we'll skip this in sync service as it's handled in the main save flow
          }
        }

        // Mark as synced
        await OfflineStorageService.markAsSynced(entryId);
        
        // Delete from local storage after successful sync
        await OfflineStorageService.deleteSyncedEntry(entryId);

        successCount++;
      } catch (e) {
        failedCount++;
        final entryId = entry['id'] as int;
        await OfflineStorageService.incrementSyncAttempts(entryId);
        errors.add('Entry ${entryId}: ${e.toString()}');
        print('❌ Sync error for entry ${entryId}: $e');
      }
    }

    return {
      'success': successCount,
      'failed': failedCount,
      'errors': errors,
    };
  }

  /// Schedule automatic sync (call this periodically when online)
  static Future<void> scheduleAutoSync({
    Function(Map<String, dynamic>)? onComplete,
  }) async {
    try {
      final results = await syncOfflineData();
      onComplete?.call(results);
    } catch (e) {
      print('❌ Auto-sync error: $e');
      onComplete?.call({
        'success': 0,
        'failed': 0,
        'error': e.toString(),
      });
    }
  }

  /// Sync time_attendance entry (clock-in or clock-out)
  static Future<void> _syncTimeAttendanceEntry(
    Map<String, dynamic> entry,
    Map<String, dynamic> entryData,
    int entryId,
    String? entryType,
  ) async {
    // Remove metadata fields
    final cleanData = Map<String, dynamic>.from(entryData);
    cleanData.remove('_entry_type');
    cleanData.remove('_table_name');
    cleanData.remove('_offline_id');
    
    if (entryType == 'clock_in') {
      // Create new time_attendance record
      cleanData['synced'] = true;
      cleanData['offline_created'] = false;
      
      await DatabaseService.create('time_attendance', cleanData);
    } else if (entryType == 'clock_out') {
      // Find the clock-in record to update
      final clockInRecordId = entryData['_clock_in_record_id']?.toString();
      final clockInOfflineRecord = entryData['_clock_in_offline_record']?.toString();
      
      String? recordIdToUpdate;
      
      if (clockInRecordId != null) {
        // Clock-in was online - use the online ID
        recordIdToUpdate = clockInRecordId;
      } else if (clockInOfflineRecord != null) {
        // Clock-in was offline - need to find it in pending entries first
        // Check if there's a pending clock-in with this offline_id
        final pendingEntries = await OfflineStorageService.getPendingEntries();
        for (final pendingEntry in pendingEntries) {
          final pendingData = pendingEntry['entry_data'] as Map<String, dynamic>;
          if (pendingData['_entry_type'] == 'clock_in' && 
              pendingData['_offline_id']?.toString() == clockInOfflineRecord) {
            // Found the clock-in, but it's still pending - sync it first
            await _syncTimeAttendanceEntry(pendingEntry, pendingData, pendingEntry['id'] as int, 'clock_in');
            break;
          }
        }
        
        // Try to find the recently synced clock-in by matching user_id and start_time
        try {
          final userId = cleanData['user_id']?.toString();
          if (userId != null) {
            // Find clock-in records for this user without finish_time, sorted by start_time
            final response = await SupabaseService.client
                .from('time_attendance')
                .select('id, start_time')
                .eq('user_id', userId)
                .isFilter('finish_time', null)
                .order('start_time', ascending: false)
                .limit(1)
                .maybeSingle();
            
            if (response != null) {
              recordIdToUpdate = response['id']?.toString();
            }
          }
        } catch (e) {
          print('⚠️ Error finding clock-in record for clock-out: $e');
        }
      }
      
      if (recordIdToUpdate != null) {
        cleanData['synced'] = true;
        await DatabaseService.update('time_attendance', recordIdToUpdate, cleanData);
      } else {
        throw Exception('Could not find clock-in record to update for clock-out');
      }
    }
    
    // Mark as synced
    await OfflineStorageService.markAsSynced(entryId);
    await OfflineStorageService.deleteSyncedEntry(entryId);
  }
}

