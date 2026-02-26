/// Messages Screen
/// 
/// Message management screen for viewing, reading, and managing messages.
/// Integrates with MessagingService for message operations.

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:intl/intl.dart';
import 'package:dwce_time_tracker/modules/messaging/messaging_service.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';
import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/messaging/message_image_helper.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _showUnreadOnly = false;
  bool _showArchived = false;
  int _unreadCount = 0;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadMessages();
  }

  Future<void> _loadUserData() async {
    try {
      final userData = await UserService.getCurrentUserData();
      if (userData != null) {
        setState(() {
          _displayName = userData['display_name']?.toString() ?? 
                        userData['forename']?.toString() ?? 
                        'Unknown User';
        });
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
    }
  }

  void _showImageFullScreen(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      color: Colors.grey.shade800,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image, color: Colors.white, size: 64),
                          SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _getSenderName(String? userId) async {
    if (userId == null) return 'Unknown';
    try {
      // users_data.user_id references auth.users.id (sender created_by is auth id)
      final response = await SupabaseService.client
          .from('users_data')
          .select('display_name, forename, surname')
          .eq('user_id', userId)
          .maybeSingle();
      
      if (response != null) {
        final name = response['display_name']?.toString() ??
            '${response['forename'] ?? ''} ${response['surname'] ?? ''}'.trim();
        if (name.isNotEmpty) return name;
      }
    } catch (e) {
      print('❌ Error loading sender name: $e');
    }
    return 'Unknown';
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    
    try {
      final messages = await MessagingService.getMessages(
        unreadOnly: _showUnreadOnly,
        showArchived: _showArchived,
      );
      final unreadCount = await MessagingService.getUnreadMessageCount();
      
      setState(() {
        _messages = messages;
        _unreadCount = unreadCount;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading messages: $e');
      // Check if it's a table not found error
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('relation') && errorString.contains('does not exist')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Messages table not found. Please create the messages table in your database.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading messages: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String messageId) async {
    try {
      await MessagingService.markMessageAsRead(messageId);
      await _loadMessages(); // Reload to update UI
    } catch (e) {
      print('❌ Error marking message as read: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMessage(String logId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Message'),
        content: const Text('Are you sure you want to archive this message? You can restore it later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await MessagingService.deleteMessage(logId);
        await _loadMessages(); // Reload to update UI
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message archived'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print('❌ Error archiving message: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error archiving message: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _restoreMessage(String logId) async {
    try {
      await MessagingService.restoreMessage(logId);
      await _loadMessages(); // Reload to update UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message restored'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error restoring message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error restoring message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMessageDetails(Map<String, dynamic> message) async {
                      final isUnread = message['status'] != 'read' && message['read_at'] == null;
    
    // Mark as read if unread
    if (isUnread) {
      await _markAsRead(message['id']?.toString() ?? '');
    }

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              if (message['is_important'] == true) ...[
                const Icon(Icons.star, color: Colors.amber),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  message['is_important'] == true ? '⭐ Important Message' : 'Message',
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message['created_by'] != null) ...[
                  FutureBuilder<String>(
                    future: _getSenderName(message['created_by'].toString()),
                    builder: (context, snapshot) {
                      return Text(
                        'From: ${snapshot.data ?? message['created_by']?.toString() ?? 'Unknown'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                              if (message['sent_at'] != null) ...[
                                  Text(
                                    'Date: ${DateFormat('EEEE, MMMM d, yyyy h:mm a').format(DateTime.parse(message['sent_at'].toString()))}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 16),
                                ]
                              else if (message['created_at'] != null) ...[
                                  Text(
                                    'Date: ${DateFormat('EEEE, MMMM d, yyyy h:mm a').format(DateTime.parse(message['created_at'].toString()))}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                const SizedBox(height: 16),
                // Message body: strip markdown image links so we show images below
                Builder(
                  builder: (context) {
                    String body = message['message']?.toString() ?? 'No content';
                    body = body.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '[Image]');
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        body,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  },
                ),
                
                // Display images if any
                if (message['image_urls'] != null && 
                    message['image_urls'] is List && 
                    (message['image_urls'] as List).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Images:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: (message['image_urls'] as List).length,
                      itemBuilder: (context, imgIndex) {
                        final imagePath = (message['image_urls'] as List)[imgIndex]?.toString() ?? '';
                        if (imagePath.isEmpty) return const SizedBox.shrink();
                        
                        // Get signed URL for private image
                        return FutureBuilder<String?>(
                          future: MessageImageHelper.getSignedImageUrl(imagePath),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Container(
                                width: 200,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            
                            final imageUrl = snapshot.data;
                            if (imageUrl == null) {
                              return Container(
                                width: 200,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              );
                            }
                            
                            return GestureDetector(
                              onTap: () => _showImageFullScreen(context, imageUrl),
                              child: Container(
                                width: 200,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                          child: Icon(Icons.broken_image, color: Colors.grey),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
                
                if (message['error_text'] != null && message['error_text'].toString().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Delivery Error:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message['error_text']?.toString() ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (message['is_archived'] == true)
              IconButton(
                icon: const Icon(Icons.restore, color: Colors.green),
                onPressed: () {
                  Navigator.of(context).pop();
                  _restoreMessage(message['id']?.toString() ?? '');
                },
                tooltip: 'Restore',
              )
            else
              IconButton(
                icon: const Icon(Icons.archive, color: Colors.orange),
                onPressed: () {
                  Navigator.of(context).pop();
                  _deleteMessage(message['id']?.toString() ?? '');
                },
                tooltip: 'Archive',
              ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.mail),
            const SizedBox(width: 8),
            Text('Messages${_unreadCount > 0 ? ' ($_unreadCount)' : ''}'),
          ],
        ),
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [
          const ScreenInfoIcon(screenName: 'messages_screen.dart'),
          // Show archived toggle
          IconButton(
            icon: Icon(_showArchived ? Icons.archive : Icons.archive_outlined),
            tooltip: _showArchived ? 'Hide Archived' : 'Show Archived',
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              _loadMessages();
            },
          ),
          // Filter toggle
          IconButton(
            icon: Icon(_showUnreadOnly ? Icons.filter_list : Icons.filter_list_off),
            tooltip: _showUnreadOnly ? 'Show All Messages' : 'Show Unread Only',
            onPressed: () {
              setState(() => _showUnreadOnly = !_showUnreadOnly);
              _loadMessages();
            },
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadMessages,
          ),
          // Notification settings
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Notification Settings',
            onPressed: () => MessagingService.showNotificationSettingsDialog(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _showArchived
                            ? (_showUnreadOnly
                                ? 'No unread archived messages'
                                : 'No archived messages')
                            : (_showUnreadOnly
                                ? 'No unread messages'
                                : 'No messages'),
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMessages,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final status = message['status']?.toString();
                      final isUnread = status != 'read' && message['read_at'] == null;
                      final isArchived = message['is_archived'] == true;
                      final isFailed = message['is_failed'] == true;
                      final errorText = message['error_text']?.toString();
                      final createdAt = message['created_at'] != null
                          ? DateTime.tryParse(message['created_at']?.toString() ?? '')
                          : null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isArchived 
                            ? Colors.grey.shade200 
                            : (isUnread ? Colors.blue.shade50 : null),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isFailed
                                ? Colors.red
                                : (isUnread
                                    ? Colors.blue
                                    : Colors.grey),
                            child: Icon(
                              isFailed
                                  ? Icons.error
                                  : (isUnread ? Icons.mail : Icons.mail_outline),
                              color: Colors.white,
                            ),
                          ),
                          title: Row(
                            children: [
                              if (message['is_important'] == true) ...[
                                const Icon(Icons.star, color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  message['is_important'] == true
                                      ? '⭐ Important'
                                      : 'Message',
                                  style: TextStyle(
                                    fontWeight: isUnread
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Status pill
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isFailed
                                          ? Colors.red.shade100
                                          : (isUnread
                                              ? Colors.blue.shade100
                                              : Colors.grey.shade200),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isFailed
                                          ? 'Failed'
                                          : (isUnread
                                              ? 'Unread'
                                              : 'Read'),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isFailed
                                            ? Colors.red.shade700
                                            : (isUnread
                                                ? Colors.blue.shade700
                                                : Colors.grey.shade700),
                                      ),
                                    ),
                                  ),
                                  if (isArchived) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Archived',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (message['created_by'] != null)
                                FutureBuilder<String>(
                                  future: _getSenderName(message['created_by'].toString()),
                                  builder: (context, snapshot) {
                                    return Text(
                                      'From: ${snapshot.data ?? message['created_by']?.toString() ?? 'Unknown'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    );
                                  },
                                ),
                              if (message['sent_at'] != null)
                                Text(
                                  DateFormat('MMM d, yyyy h:mm a').format(
                                    DateTime.parse(message['sent_at']?.toString() ?? ''),
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                )
                              else if (createdAt != null)
                                Text(
                                  DateFormat('MMM d, yyyy h:mm a').format(createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              if (errorText != null && errorText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          errorText,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (message['message'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    (message['message']?.toString().length ?? 0) > 100
                                        ? '${message['message']?.toString().substring(0, 100)}...'
                                        : message['message']?.toString() ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              // Show image indicator
                              if (message['image_urls'] != null && 
                                  message['image_urls'] is List && 
                                  (message['image_urls'] as List).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.image, size: 16, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${(message['image_urls'] as List).length} image(s)',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          trailing: PopupMenuButton(
                            itemBuilder: (context) => [
                              if (isArchived)
                                PopupMenuItem(
                                  child: const Row(
                                    children: [
                                      Icon(Icons.restore, color: Colors.green),
                                      SizedBox(width: 8),
                                      Text('Restore'),
                                    ],
                                  ),
                                  onTap: () {
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () => _restoreMessage(message['id']?.toString() ?? ''),
                                    );
                                  },
                                )
                              else
                                PopupMenuItem(
                                  child: const Row(
                                    children: [
                                      Icon(Icons.archive, color: Colors.orange),
                                      SizedBox(width: 8),
                                      Text('Archive'),
                                    ],
                                  ),
                                  onTap: () {
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () => _deleteMessage(message['id']?.toString() ?? ''),
                                    );
                                  },
                                ),
                            ],
                          ),
                          onTap: () => _showMessageDetails(message),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
