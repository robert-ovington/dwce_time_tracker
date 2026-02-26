/// Error Logging Service
/// 
/// Logs errors to the public.errors_log table for tracking and pattern analysis

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../config/supabase_config.dart';
import '../auth/auth_service.dart';

class ErrorLogService {
  /// Get the current platform name
  static String _getPlatform() {
    if (kIsWeb) {
      return 'web';
    } else if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else {
      return 'unknown';
    }
  }

  /// Log an error to the errors_log table
  /// 
  /// [location] - Where the error occurred (e.g., "Timesheet Screen", "Login Screen")
  /// [type] - Category of error (e.g., "GPS", "Validation", "Network", "Database")
  /// [description] - Detailed description of the error
  /// [userId] - Optional user ID (will try to get from auth if not provided)
  /// [stackTrace] - Optional stack trace (stored in separate column)
  /// [severity] - Optional severity level (defaults to 'error')
  /// [errorCode] - Optional standardized error code for pattern matching
  static Future<void> logError({
    required String location,
    required String type,
    required String description,
    String? userId,
    StackTrace? stackTrace,
    String severity = 'error',
    String? errorCode,
  }) async {
    try {
      // Validate severity (use local to avoid assigning to parameter)
      final effectiveSeverity = ['critical', 'error', 'warning', 'info'].contains(severity.toLowerCase())
          ? severity
          : 'error';

      // Get user ID if not provided
      String? finalUserId = userId;
      if (finalUserId == null) {
        try {
          final user = AuthService.getCurrentUser();
          finalUserId = user?.id;
        } catch (e) {
          // If we can't get user ID, continue without it
          print('⚠️ Could not get user ID for error log: $e');
        }
      }

      // Process stack trace - store in separate column
      String? stackTraceStr;
      if (stackTrace != null) {
        final fullStackTrace = stackTrace.toString();
        // Truncate stack trace if too long (keep first 5000 chars for separate column)
        stackTraceStr = fullStackTrace.length > 5000 
            ? '${fullStackTrace.substring(0, 5000)}... [truncated]'
            : fullStackTrace;
      }

      // Insert error log (created_at has default value, so we don't need to set it)
      await SupabaseService.client.from('errors_log').insert({
        'user_id': finalUserId,
        'platform': _getPlatform(),
        'location': location,
        'type': type,
        'severity': effectiveSeverity.toLowerCase(),
        'error_code': errorCode,
        'description': description,
        'stack_trace': stackTraceStr,
      });

      print('✅ Error logged: $type - $location (severity: $effectiveSeverity)');
    } catch (e) {
      // Don't throw - we don't want error logging to break the app
      print('❌ Failed to log error to database: $e');
      print('   Error details: location=$location, type=$type, description=$description');
    }
  }
}

