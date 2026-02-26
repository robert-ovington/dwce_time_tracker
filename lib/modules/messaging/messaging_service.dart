/// Messaging Service
/// 
/// Centralized service for managing in-app messages and notifications.
/// Handles message storage, delivery, and notification permissions.
/// Can be extended with push notifications (Firebase Cloud Messaging, etc.)

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';

class MessagingService {
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static const String _lastMessageCheckKey = 'last_message_check';
  static bool _notificationsEnabled = false;
  static bool _hasCheckedNotifications = false;
  
  // Notification plugin instance
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = 
      FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  /// Check if notifications are enabled
  static bool get notificationsEnabled => _notificationsEnabled;

  /// Initialize messaging service
  static Future<void> initialize() async {
    await _loadNotificationPreference();
    await _initializeNotifications();
  }
  
  /// Initialize notification plugin and set up channels
  static Future<void> _initializeNotifications() async {
    if (kIsWeb) {
      return; // Notifications not supported on web
    }
    
    if (_notificationsInitialized) {
      return; // Already initialized
    }
    
    try {
      // Android initialization settings
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings (if needed in future)
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      // Initialize the plugin
      final bool? initialized = await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      if (initialized == true) {
        _notificationsInitialized = true;
        print('✅ Notifications plugin initialized');
        
        // Set up Android notification channels
        await _createNotificationChannels();
      } else {
        print('⚠️ Failed to initialize notifications plugin');
      }
    } catch (e) {
      print('❌ Error initializing notifications: $e');
    }
  }
  
  /// Create Android notification channels
  static Future<void> _createNotificationChannels() async {
    if (kIsWeb) return;
    
    try {
      // Default channel for regular messages
      const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
        'messages_default',
        'Messages',
        description: 'Notifications for new messages',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      );
      
      // High priority channel for important messages
      const AndroidNotificationChannel importantChannel = AndroidNotificationChannel(
        'messages_important',
        'Important Messages',
        description: 'Notifications for important messages that require attention',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );
      
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(defaultChannel);
      
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(importantChannel);
      
      print('✅ Notification channels created');
    } catch (e) {
      print('❌ Error creating notification channels: $e');
    }
  }
  
  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    print('📱 Notification tapped: ${response.payload}');
    // Could navigate to messages screen here if needed
  }

  /// Load notification preference from local storage
  static Future<void> _loadNotificationPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? false;
      _hasCheckedNotifications = true;
      print('📱 Notification preference loaded: $_notificationsEnabled');
    } catch (e) {
      print('❌ Error loading notification preference: $e');
      _notificationsEnabled = false;
      _hasCheckedNotifications = true;
    }
  }

  /// Save notification preference
  static Future<void> setNotificationsEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notificationsEnabledKey, enabled);
      _notificationsEnabled = enabled;
      print('📱 Notification preference saved: $enabled');
    } catch (e) {
      print('❌ Error saving notification preference: $e');
    }
  }

  /// Request notification permission (platform-specific)
  /// Returns true if permission is granted
  static Future<bool> requestNotificationPermission() async {
    if (kIsWeb) {
      // Web notifications require browser permission
      // This is a placeholder - implement web notification request if needed
      return false;
    }

    // Ensure notifications are initialized
    if (!_notificationsInitialized) {
      await _initializeNotifications();
    }
    
    try {
      // Request permissions - handle Android and iOS separately
      bool? result;
      
      // Android 13+ requires explicit permission
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        result = await androidImplementation.requestNotificationsPermission();
      }
      
      // iOS requires permission request
      if (result == null) {
        final iosImplementation = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        if (iosImplementation != null) {
          result = await iosImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
        }
      }
      
      // For Android < 13, permissions are granted by default
      // So if result is null, assume granted
      if (result == null) {
        print('✅ Notification permission granted (default for this Android version)');
        return true;
      }
      
      if (result == true) {
        print('✅ Notification permission granted');
        return true;
      } else {
        print('⚠️ Notification permission denied');
        return false;
      }
    } catch (e) {
      print('❌ Error requesting notification permission: $e');
      return false;
    }
  }

  /// Show dialog to request notification permission
  static Future<bool> showNotificationPermissionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.notifications, color: Colors.blue),
              SizedBox(width: 8),
              Text('Enable Notifications'),
            ],
          ),
          content: const Text(
            'Would you like to receive notifications for messages and important updates? '
            'You can change this setting later in your profile.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () async {
                final granted = await requestNotificationPermission();
                if (granted) {
                  await setNotificationsEnabled(true);
                }
                Navigator.of(context).pop(granted);
              },
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  /// Get unread message count for current user
  static Future<int> getUnreadMessageCount() async {
    try {
      final user = AuthService.getCurrentUser();
      if (user == null) return 0;

      final userId = user.id;
      
      // Query text_message_log for unread messages
      // Using the partial index: idx_tml_unread_by_user
      // Only count non-archived messages (deleted_at IS NULL)
      final response = await SupabaseService.client
          .from('text_message_log')
          .select('id')
          .eq('recipient_id', userId)
          .isFilter('deleted_at', null) // Exclude archived messages
          .or('status.is.null,status.neq.read'); // Unread: status is null or not 'read'

      return (response as List).length;
    } catch (e) {
      print('❌ Error getting unread message count: $e');
      return 0;
    }
  }

  /// Get unread important messages for current user
  /// Returns list of unread messages where is_important = true
  static Future<List<Map<String, dynamic>>> getUnreadImportantMessages() async {
    try {
      final user = AuthService.getCurrentUser();
      if (user == null) return [];

      final userId = user.id;
      
      // Query text_message_log with join to text_messages for important unread messages
      dynamic query = SupabaseService.client
          .from('text_message_log')
          .select('''
            id,
            text_message_id,
            recipient_id,
            sent_at,
            read_at,
            delivered_at,
            status,
            error_text,
            created_at,
            deleted_at,
            deleted_by,
            text_messages!inner (
              id,
              created_by,
              message,
              date_created,
              date_sent,
              is_important,
              recipient_type,
              recipient_user_id,
              recipient_role,
              recipient_security,
              deleted_at
            )
          ''')
          .eq('recipient_id', userId)
          .isFilter('deleted_at', null) // Exclude archived
          .or('status.is.null,status.neq.read') // Unread only
          .eq('text_messages.is_important', true) // Important messages only
          .isFilter('text_messages.deleted_at', null); // Message not deleted
      
      // Order by sent_at DESC NULLS LAST, created_at DESC
      query = query.order('sent_at', ascending: false, nullsFirst: false);
      query = query.order('created_at', ascending: false);

      final response = await query;
      final logs = List<Map<String, dynamic>>.from(response as Iterable<dynamic>);
      
      // Transform the data
      final messages = logs.map((log) {
        final message = log['text_messages'];
        final messageData = message is List ? (message.isNotEmpty ? message[0] : {}) : (message ?? {});
        
        return {
          'id': log['id'], // log id
          'text_message_id': log['text_message_id'],
          'recipient_id': log['recipient_id'],
          'sent_at': log['sent_at'],
          'read_at': log['read_at'],
          'delivered_at': log['delivered_at'],
          'status': log['status'],
          'error_text': log['error_text'],
          'created_at': log['created_at'],
          'deleted_at': log['deleted_at'],
          'deleted_by': log['deleted_by'],
          // Message content from joined table
          'message': messageData['message'],
          'created_by': messageData['created_by'],
          'date_created': messageData['date_created'],
          'date_sent': messageData['date_sent'],
          'is_important': messageData['is_important'] ?? false,
          'recipient_type': messageData['recipient_type'],
          'recipient_user_id': messageData['recipient_user_id'],
          'recipient_role': messageData['recipient_role'],
          'recipient_security': messageData['recipient_security'],
          'message_deleted_at': messageData['deleted_at'],
        };
      }).toList();

      return messages;
    } catch (e) {
      print('❌ Error getting unread important messages: $e');
      return [];
    }
  }

  /// Get messages for current user (inbox)
  /// Queries text_message_log and joins with text_messages to get full message content
  /// Default filter: deleted_at IS NULL (only non-archived messages)
  static Future<List<Map<String, dynamic>>> getMessages({
    int? limit,
    bool unreadOnly = false,
    bool showArchived = false,
  }) async {
    try {
      final user = AuthService.getCurrentUser();
      if (user == null) return [];

      final userId = user.id;
      
      // Build query on text_message_log with join to text_messages
      // Supabase uses nested select syntax for joins
      dynamic query = SupabaseService.client
          .from('text_message_log')
          .select('''
            id,
            text_message_id,
            recipient_id,
            sent_at,
            read_at,
            delivered_at,
            status,
            error_text,
            created_at,
            deleted_at,
            deleted_by,
            text_messages!inner (
              id,
              created_by,
              message,
              date_created,
              date_sent,
              is_important,
              recipient_type,
              recipient_user_id,
              recipient_role,
              recipient_security,
              deleted_at
            )
          ''')
          .eq('recipient_id', userId);
      
      // Default filter: deleted_at IS NULL (non-archived)
      // If showArchived is true, include archived messages
      if (!showArchived) {
        query = query.isFilter('deleted_at', null);
      }
      
      // Filter for unread only if requested
      if (unreadOnly) {
        query = query.or('status.is.null,status.neq.read');
      }
      
      // Order by sent_at DESC NULLS LAST, created_at DESC (matches index idx_tml_inbox_by_user)
      query = query.order('sent_at', ascending: false, nullsFirst: false);
      query = query.order('created_at', ascending: false);
      
      if (limit != null) {
        query = query.limit(limit);
      }

      final response = await query;
      final logs = List<Map<String, dynamic>>.from(response as Iterable<dynamic>);
      
      // Transform the data to a flatter structure for easier use in UI
      final messages = logs.map((log) {
        final message = log['text_messages'];
        // Handle case where text_messages might be a list (if multiple messages match)
        final messageData = message is List ? (message.isNotEmpty ? message[0] : {}) : (message ?? {});
        
        return {
          'id': log['id'], // log id
          'text_message_id': log['text_message_id'],
          'recipient_id': log['recipient_id'],
          'sent_at': log['sent_at'],
          'read_at': log['read_at'],
          'delivered_at': log['delivered_at'],
          'status': log['status'],
          'error_text': log['error_text'],
          'created_at': log['created_at'],
          'deleted_at': log['deleted_at'],
          'deleted_by': log['deleted_by'],
          // Message content from joined table
          'message': messageData['message'],
          'created_by': messageData['created_by'],
          'date_created': messageData['date_created'],
          'date_sent': messageData['date_sent'],
          'is_important': messageData['is_important'] ?? false,
          'recipient_type': messageData['recipient_type'],
          'recipient_user_id': messageData['recipient_user_id'],
          'recipient_role': messageData['recipient_role'],
          'recipient_security': messageData['recipient_security'],
          'message_deleted_at': messageData['deleted_at'],
          'image_urls': messageData['image_urls'],
          // Computed fields for UI
          'is_read': log['status'] == 'read',
          'is_archived': log['deleted_at'] != null,
          'is_failed': log['status'] == 'failed',
          'subject': messageData['is_important'] == true ? '⭐ Important' : 'Message',
        };
      }).toList();

      return messages;
    } catch (e) {
      print('❌ Error getting messages: $e');
      return [];
    }
  }

  /// Mark message as read
  /// Updates text_message_log with status='read' and read_at timestamp
  static Future<void> markMessageAsRead(String logId) async {
    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await SupabaseService.client
          .from('text_message_log')
          .update({
            'status': 'read',
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', logId)
          .eq('recipient_id', user.id); // Ensure user can only update their own logs
    } catch (e) {
      print('❌ Error marking message as read: $e');
      rethrow;
    }
  }

  /// Send a message
  /// Creates a message in text_messages table
  /// Note: Delivery rows in text_message_log must be created by backend using service_role
  static Future<Map<String, dynamic>?> sendMessage({
    required String recipientId,
    required String message,
    bool isImportant = false,
    String? idempotencyKey,
  }) async {
    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final messageData = {
        'created_by': user.id,
        'owner_user_id': user.id,
        'message': message,
        'date_created': DateTime.now().toIso8601String().split('T')[0], // Date only
        'recipient_type': 'user',
        'recipient_user_id': recipientId,
        'is_important': isImportant,
        'is_active': true,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      };

      final result = await DatabaseService.create('text_messages', messageData);
      
      // If notifications are enabled, send a notification
      // Important messages always trigger notifications regardless of preference
      if (_notificationsEnabled || isImportant) {
        await _sendNotification(
          recipientId, 
          isImportant ? '⭐ Important Message' : 'New Message', 
          message,
          isImportant: isImportant,
        );
      }

      return result;
    } catch (e) {
      print('❌ Error sending message: $e');
      return null;
    }
  }

  /// Send notification
  /// For important messages, this should trigger immediately
  /// Important messages bypass notification preferences
  static Future<void> _sendNotification(
    String recipientId,
    String subject,
    String body, {
    bool isImportant = false,
  }) async {
    if (kIsWeb || !_notificationsInitialized) {
      print('📱 ⚠️ Notifications not available (web or not initialized)');
      return;
    }
    
    // Check if notifications are enabled (unless it's important)
    if (!_notificationsEnabled && !isImportant) {
      print('📱 Notifications disabled, skipping');
      return;
    }
    
    try {
      // Choose channel based on importance
      final String channelId = isImportant ? 'messages_important' : 'messages_default';
      final Importance importance = isImportant ? Importance.high : Importance.defaultImportance;
      
      // Truncate body for notification (max ~200 chars)
      final String notificationBody = body.length > 200 
          ? '${body.substring(0, 200)}...' 
          : body;
      
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'messages_important',
        'Important Messages',
        channelDescription: 'Notifications for important messages',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        showWhen: true,
      );
      
      const AndroidNotificationDetails androidDetailsDefault = AndroidNotificationDetails(
        'messages_default',
        'Messages',
        channelDescription: 'Notifications for new messages',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: true,
        enableVibration: true,
        showWhen: true,
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      final NotificationDetails notificationDetails = NotificationDetails(
        android: isImportant ? androidDetails : androidDetailsDefault,
        iOS: iosDetails,
      );
      
      // Generate a unique notification ID (use timestamp or hash)
      final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      
      await _notificationsPlugin.show(
        id: notificationId,
        title: subject,
        body: notificationBody,
        notificationDetails: notificationDetails,
        payload: recipientId, // Can be used to navigate to specific message
      );
      
      print('📱 ✅ Notification sent: $subject');
    } catch (e) {
      print('❌ Error sending notification: $e');
    }
  }

  /// Show notification settings dialog
  static Future<void> showNotificationSettingsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.notifications, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Notification Settings'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Enable Notifications'),
                    subtitle: const Text('Receive notifications for messages and updates'),
                    value: _notificationsEnabled,
                    onChanged: (value) async {
                      if (value) {
                        // Request permission when enabling
                        final granted = await requestNotificationPermission();
                        if (granted) {
                          await setNotificationsEnabled(true);
                          setState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Notifications enabled successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } else {
                          // Permission denied - don't enable
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Notification permission is required to enable notifications'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        }
                      } else {
                        // Disabling - just save preference
                        await setNotificationsEnabled(false);
                        setState(() {});
                      }
                    },
                  ),
                  if (!_notificationsEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Notifications are disabled. You will not receive push notifications for new messages.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Check for new messages periodically
  static Future<void> checkForNewMessages() async {
    try {
      final unreadCount = await getUnreadMessageCount();
      if (unreadCount > 0 && _notificationsEnabled) {
        // Show notification or badge
        print('📱 You have $unreadCount unread message(s)');
        // TODO: Show actual notification
      }
      
      // Check for important messages and send notifications
      // Important messages always trigger notifications (bypass preference)
      final importantMessages = await getUnreadImportantMessages();
      if (importantMessages.isNotEmpty) {
        for (final msg in importantMessages) {
          await _sendNotification(
            msg['recipient_id']?.toString() ?? '',
            '⭐ Important Message',
            msg['message']?.toString() ?? 'You have an important message',
            isImportant: true,
          );
        }
      }
    } catch (e) {
      print('❌ Error checking for new messages: $e');
    }
  }

  /// Show blocking dialog for unread important messages
  /// User must read all important messages before continuing
  static Future<void> showImportantMessagesDialog(BuildContext context) async {
    try {
      final importantMessages = await getUnreadImportantMessages();
      if (importantMessages.isEmpty) {
        return; // No important messages, allow user to continue
      }

      // Show dialog for each important message (one at a time)
      for (final message in importantMessages) {
        final logId = message['id']?.toString();
        if (logId == null) continue;

        final messageText = message['message']?.toString() ?? 'No content';
        final sentAt = message['sent_at'] != null
            ? DateTime.tryParse(message['sent_at']?.toString() ?? '')
            : null;
        final createdAt = message['created_at'] != null
            ? DateTime.tryParse(message['created_at']?.toString() ?? '')
            : null;
        final dateTime = sentAt ?? createdAt ?? DateTime.now();

        // Blocking dialog - user must acknowledge
        await showDialog(
          context: context,
          barrierDismissible: false, // Cannot dismiss by tapping outside
          builder: (BuildContext context) {
            return PopScope(
              canPop: false, // Prevent back button from dismissing
              child: AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.priority_high, color: Colors.red, size: 32),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Important Message',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200, width: 2),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.red),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'You must read this important message before continuing.',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (dateTime != null)
                        Text(
                          'Date: ${DateFormat('EEEE, MMMM d, yyyy h:mm a').format(dateTime)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          messageText,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  // No cancel button - user must acknowledge
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Mark as read
                      if (logId.isNotEmpty) {
                        try {
                          await markMessageAsRead(logId);
                        } catch (e) {
                          print('❌ Error marking important message as read: $e');
                        }
                      }
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check_circle),
                    label: const Text('I Have Read This Message'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }
    } catch (e) {
      print('❌ Error showing important messages dialog: $e');
      // Don't block the app if there's an error checking messages
    }
  }

  /// Soft-delete a message (marks as deleted in text_message_log)
  /// Updates deleted_at and deleted_by fields
  /// This archives the message for the recipient
  static Future<void> deleteMessage(String logId) async {
    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await SupabaseService.client
          .from('text_message_log')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'deleted_by': user.id,
          })
          .eq('id', logId)
          .eq('recipient_id', user.id); // Ensure user can only delete their own logs
    } catch (e) {
      print('❌ Error deleting message: $e');
      rethrow;
    }
  }

  /// Restore a soft-deleted message (clears deleted_at and deleted_by)
  /// Un-archives the message for the recipient
  static Future<void> restoreMessage(String logId) async {
    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await SupabaseService.client
          .from('text_message_log')
          .update({
            'deleted_at': null,
            'deleted_by': null,
          })
          .eq('id', logId)
          .eq('recipient_id', user.id); // Ensure user can only restore their own logs
    } catch (e) {
      print('❌ Error restoring message: $e');
      rethrow;
    }
  }
}
