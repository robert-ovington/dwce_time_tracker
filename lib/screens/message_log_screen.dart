/// Message Log Screen
/// 
/// Displays sent messages and their delivery status.
/// Shows who received messages and who has read them.

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:intl/intl.dart';
import '../config/supabase_config.dart';
import '../modules/auth/auth_service.dart';
import '../modules/errors/error_log_service.dart';
import '../modules/messaging/message_image_helper.dart';
import '../modules/users/user_service.dart';

class MessageLogScreen extends StatefulWidget {
  const MessageLogScreen({super.key});

  @override
  State<MessageLogScreen> createState() => _MessageLogScreenState();
}

/// Created date format: "d mmm yy - h:mm tt" (e.g. 29 Jan 26 - 10:10 AM)
final DateFormat _createdFormat = DateFormat('d MMM yy - h:mm a');

class _MessageLogScreenState extends State<MessageLogScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String _statusMessage = '';

  // Filters for column-based log
  String _filterFrom = '';
  String _filterTo = '';
  String _filterReadStatus = 'all'; // 'all' | 'all_read' | 'some_unread'

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Load messages created by current user
      // Join with text_message_log to get recipient status; include image_urls
      final response = await SupabaseService.client
          .from('text_messages')
          .select('''
            id,
            message,
            date_created,
            date_sent,
            is_sent,
            is_important,
            recipient_type,
            recipient_user_id,
            recipient_role,
            recipient_security,
            created_by,
            image_urls,
            text_message_log (
              id,
              recipient_id,
              sent_at,
              read_at,
              delivered_at,
              status,
              error_text
            )
          ''')
          .eq('created_by', user.id)
          .isFilter('deleted_at', null)
          .order('date_created', ascending: false)
          .order('created_at', ascending: false);

      final messages = List<Map<String, dynamic>>.from(response);
      
      // Sender display name (current user)
      String senderDisplayName = 'Unknown';
      try {
        final userData = await UserService.getCurrentUserData();
        if (userData != null && userData['display_name'] != null) {
          senderDisplayName = userData['display_name']!.toString();
        }
      } catch (e) {
        print('⚠️ Error fetching sender name: $e');
      }
      
      // Collect all unique recipient IDs (from logs) and recipient_user_id (for user-type messages)
      final recipientIds = <String>{};
      for (final msg in messages) {
        final logs = msg['text_message_log'] as List? ?? [];
        for (final log in logs) {
          final recipientId = log['recipient_id']?.toString();
          if (recipientId != null && recipientId.isNotEmpty) {
            recipientIds.add(recipientId);
          }
        }
        // For user-type messages, include recipient_user_id so we can show name when log is empty
        if (msg['recipient_type'] == 'user') {
          final uid = msg['recipient_user_id']?.toString();
          if (uid != null && uid.isNotEmpty) recipientIds.add(uid);
        }
      }
      
      // Batch fetch all recipient names
      final recipientNames = <String, String>{};
      if (recipientIds.isNotEmpty) {
        try {
          final usersData = await SupabaseService.client
              .from('users_data')
              .select('user_id, display_name')
              .inFilter('user_id', recipientIds.toList());
          
          for (final user in usersData) {
            final userId = user['user_id']?.toString();
            final displayName = user['display_name']?.toString();
            if (userId != null && displayName != null) {
              recipientNames[userId] = displayName;
            }
          }
        } catch (e) {
          print('⚠️ Error batch fetching recipient names: $e');
        }
      }
      
      // Process and flatten the data
      final processedMessages = <Map<String, dynamic>>[];
      for (final msg in messages) {
        final logs = msg['text_message_log'] as List? ?? [];
        final recipients = <Map<String, dynamic>>[];
        
        for (final log in logs) {
          final recipientId = log['recipient_id']?.toString();
          final recipientName = recipientId != null
              ? (recipientNames[recipientId] ?? 'Unknown')
              : 'Unknown';
          
          recipients.add({
            'log_id': log['id'],
            'recipient_id': recipientId,
            'recipient_name': recipientName,
            'sent_at': log['sent_at'],
            'read_at': log['read_at'],
            'delivered_at': log['delivered_at'],
            'status': log['status']?.toString() ?? 'queued',
            'error_text': log['error_text'],
          });
        }
        
        // When no log entries (e.g. not yet sent), show target for user-type
        if (recipients.isEmpty && msg['recipient_type'] == 'user') {
          final uid = msg['recipient_user_id']?.toString();
          if (uid != null && uid.isNotEmpty) {
            recipients.add({
              'log_id': null,
              'recipient_id': uid,
              'recipient_name': recipientNames[uid] ?? 'Unknown',
              'sent_at': null,
              'read_at': null,
              'delivered_at': null,
              'status': 'pending',
              'error_text': null,
            });
          }
        }

        processedMessages.add({
          'id': msg['id'],
          'message': msg['message'],
          'date_created': msg['date_created'],
          'date_sent': msg['date_sent'],
          'is_sent': msg['is_sent'] == true,
          'is_important': msg['is_important'] == true,
          'recipient_type': msg['recipient_type'],
          'recipient_user_id': msg['recipient_user_id'],
          'recipient_role': msg['recipient_role'],
          'recipient_security': msg['recipient_security'],
          'recipients': recipients,
          'image_urls': msg['image_urls'],
          'sender_display_name': senderDisplayName,
          'created_by': msg['created_by'],
        });
      }

      setState(() {
        _messages = processedMessages;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Message Log Screen - Load Messages',
        type: 'Database',
        description: 'Failed to load messages: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error loading messages: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredMessages {
    var list = _messages;
    if (_filterFrom.isNotEmpty) {
      final lower = _filterFrom.toLowerCase();
      list = list.where((m) => (m['sender_display_name']?.toString() ?? '').toLowerCase().contains(lower)).toList();
    }
    if (_filterTo.isNotEmpty) {
      final lower = _filterTo.toLowerCase();
      list = list.where((m) => _getRecipientDescription(m).toLowerCase().contains(lower)).toList();
    }
    if (_filterReadStatus == 'all_read') {
      list = list.where((m) {
        final recipients = m['recipients'] as List<Map<String, dynamic>>? ?? [];
        return recipients.isNotEmpty && recipients.every((r) => (r['status']?.toString() ?? '') == 'read');
      }).toList();
    } else if (_filterReadStatus == 'some_unread') {
      list = list.where((m) {
        final recipients = m['recipients'] as List<Map<String, dynamic>>? ?? [];
        return recipients.any((r) => (r['status']?.toString() ?? '') != 'read');
      }).toList();
    }
    return list;
  }

  String _getRecipientDescription(Map<String, dynamic> message) {
    final recipients = message['recipients'] as List<Map<String, dynamic>>? ?? [];
    if (recipients.isNotEmpty) {
      final names = recipients.map((r) => r['recipient_name']?.toString() ?? 'Unknown').toSet().toList();
      return 'To: ${names.join(', ')}';
    }
    if (message['recipient_type'] == 'user') {
      return 'To: (recipient not yet resolved)';
    } else if (message['recipient_type'] == 'role') {
      return 'To: Role ${message['recipient_role'] ?? 'Unknown'}';
    } else if (message['recipient_type'] == 'security') {
      return 'To: Security Level ${message['recipient_security'] ?? 'Unknown'}';
    }
    return 'To: Unknown';
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

  String _getStatusColor(String? status) {
    switch (status) {
      case 'read':
        return 'green';
      case 'delivered':
        return 'blue';
      case 'sent':
        return 'orange';
      case 'queued':
        return 'grey';
      case 'failed':
        return 'red';
      default:
        return 'grey';
    }
  }

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _dataCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Log', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [
          const ScreenInfoIcon(screenName: 'message_log_screen.dart'),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _statusMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages found',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMessages,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Filter bar (column filters)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Filters',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            decoration: const InputDecoration(
                                              labelText: 'From',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            onChanged: (v) => setState(() => _filterFrom = v),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            decoration: const InputDecoration(
                                              labelText: 'To',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            onChanged: (v) => setState(() => _filterTo = v),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: DropdownButtonFormField<String>(
                                            value: _filterReadStatus,
                                            decoration: const InputDecoration(
                                              labelText: 'Read status',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            items: const [
                                              DropdownMenuItem(value: 'all', child: Text('All')),
                                              DropdownMenuItem(value: 'all_read', child: Text('All read')),
                                              DropdownMenuItem(value: 'some_unread', child: Text('Some unread')),
                                            ],
                                            onChanged: (v) => setState(() => _filterReadStatus = v ?? 'all'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Table header row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Table(
                              columnWidths: const {
                                0: FlexColumnWidth(1.4),
                                1: FlexColumnWidth(1.2),
                                2: FlexColumnWidth(1.5),
                                3: FlexColumnWidth(2.5),
                                4: FlexColumnWidth(0.8),
                                5: FlexColumnWidth(0.4),
                              },
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(color: Colors.grey.shade300),
                                  children: [
                                    _headerCell('Created'),
                                    _headerCell('From'),
                                    _headerCell('To'),
                                    _headerCell('Message'),
                                    _headerCell('Read'),
                                    _headerCell('!'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _filteredMessages.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                        'No messages match the current filters',
                                        style: TextStyle(fontSize: 14, color: Colors.grey),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                              padding: const EdgeInsets.all(8.0),
                              itemCount: _filteredMessages.length,
                              itemBuilder: (context, index) {
                                final message = _filteredMessages[index];
                                final recipients = message['recipients'] as List<Map<String, dynamic>>;
                                final allRead = recipients.isNotEmpty &&
                                    recipients.every((r) => (r['status']?.toString() ?? '') == 'read');
                                final readCount = recipients.where((r) => (r['status']?.toString() ?? '') == 'read').length;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  color: allRead ? Colors.lightGreen.shade100 : null,
                                  child: ExpansionTile(
                                    leading: message['is_important'] == true
                                        ? const Icon(Icons.priority_high, color: Colors.red)
                                        : const Icon(Icons.message),
                                    title: Table(
                                      columnWidths: const {
                                        0: FlexColumnWidth(1.4),
                                        1: FlexColumnWidth(1.2),
                                        2: FlexColumnWidth(1.5),
                                        3: FlexColumnWidth(2.5),
                                        4: FlexColumnWidth(0.8),
                                        5: FlexColumnWidth(0.4),
                                      },
                                      children: [
                                        TableRow(
                                          children: [
                                            _dataCell(
                                              message['date_created'] != null
                                                  ? _createdFormat.format(
                                                      DateTime.parse(message['date_created'].toString()))
                                                  : '--',
                                            ),
                                            _dataCell(message['sender_display_name']?.toString() ?? 'Unknown'),
                                            _dataCell(_getRecipientDescription(message).replaceFirst('To: ', '')),
                                            _dataCell(
                                              () {
                                                final msg = message['message']?.toString() ?? '';
                                                if (msg.isEmpty) return 'No message';
                                                return msg.length > 50 ? '${msg.substring(0, 50)}...' : msg;
                                              }(),
                                            ),
                                            _dataCell(recipients.isEmpty ? '--' : '$readCount/${recipients.length}'),
                                            _dataCell(message['is_important'] == true ? '!' : ''),
                                          ],
                                        ),
                                      ],
                                    ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Full message text (strip markdown image links so we show images below)
                                      Builder(
                                        builder: (context) {
                                          String body = message['message']?.toString() ?? '';
                                          // Replace ![Image](url) or ![](url) with [Image] so body doesn't show raw links
                                          body = body.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '[Image]');
                                          return Container(
                                            padding: const EdgeInsets.all(12.0),
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
                                      
                                      const SizedBox(height: 16),
                                      
                                      // Read / Not read summary
                                      Builder(
                                        builder: (context) {
                                          final read = recipients.where((r) => (r['status']?.toString() ?? '') == 'read').toList();
                                          final notRead = recipients.where((r) => (r['status']?.toString() ?? '') != 'read').toList();
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (read.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 6.0),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Icon(Icons.done_all, color: Colors.green, size: 18),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          'Read: ${read.map((r) => r['recipient_name']?.toString() ?? 'Unknown').join(', ')}',
                                                          style: const TextStyle(
                                                            color: Colors.green,
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (notRead.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 8.0),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Icon(Icons.schedule, color: Colors.orange.shade700, size: 18),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          'Not read: ${notRead.map((r) => r['recipient_name']?.toString() ?? 'Unknown').join(', ')}',
                                                          style: TextStyle(
                                                            color: Colors.orange.shade700,
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                      
                                      // Recipients list
                                      const Text(
                                        'Recipients:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      
                                      recipients.isEmpty
                                          ? const Text(
                                              'No recipients found',
                                              style: TextStyle(color: Colors.grey),
                                            )
                                          : Table(
                                              columnWidths: const {
                                                0: FlexColumnWidth(3),
                                                1: FlexColumnWidth(2),
                                                2: FlexColumnWidth(2),
                                                3: FlexColumnWidth(2),
                                              },
                                              children: [
                                                // Header row
                                                const TableRow(
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      bottom: BorderSide(color: Colors.grey),
                                                    ),
                                                  ),
                                                  children: [
                                                    Padding(
                                                      padding: EdgeInsets.all(8.0),
                                                      child: Text(
                                                        'Recipient',
                                                        style: TextStyle(fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: EdgeInsets.all(8.0),
                                                      child: Text(
                                                        'Status',
                                                        style: TextStyle(fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: EdgeInsets.all(8.0),
                                                      child: Text(
                                                        'Sent',
                                                        style: TextStyle(fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: EdgeInsets.all(8.0),
                                                      child: Text(
                                                        'Read',
                                                        style: TextStyle(fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                
                                                // Data rows
                                                ...recipients.map((recipient) {
                                                  final status = recipient['status']?.toString() ?? 'queued';
                                                  final statusColor = _getStatusColor(status);
                                                  
                                                  return TableRow(
                                                    children: [
                                                      Padding(
                                                        padding: const EdgeInsets.all(8.0),
                                                        child: Text(
                                                          recipient['recipient_name']?.toString() ?? 'Unknown',
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: const EdgeInsets.all(8.0),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: _getStatusColor(status) == 'green'
                                                                ? Colors.green.shade100
                                                                : _getStatusColor(status) == 'red'
                                                                    ? Colors.red.shade100
                                                                    : _getStatusColor(status) == 'blue'
                                                                        ? Colors.blue.shade100
                                                                        : Colors.grey.shade100,
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            status.toUpperCase(),
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.bold,
                                                              color: _getStatusColor(status) == 'green'
                                                                  ? Colors.green.shade800
                                                                  : _getStatusColor(status) == 'red'
                                                                      ? Colors.red.shade800
                                                                      : _getStatusColor(status) == 'blue'
                                                                          ? Colors.blue.shade800
                                                                          : Colors.grey.shade800,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: const EdgeInsets.all(8.0),
                                                        child: Text(
                                                          recipient['sent_at'] != null
                                                              ? DateFormat('MMM dd, HH:mm').format(
                                                                  DateTime.parse(recipient['sent_at'].toString()))
                                                              : '--',
                                                          style: const TextStyle(fontSize: 12),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: const EdgeInsets.all(8.0),
                                                        child: Text(
                                                          recipient['read_at'] != null
                                                              ? DateFormat('MMM dd, HH:mm').format(
                                                                  DateTime.parse(recipient['read_at'].toString()))
                                                              : '--',
                                                          style: const TextStyle(fontSize: 12),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                }).toList(),
                                              ],
                                            ),
                                      
                                      // Error messages if any
                                      if (recipients.any((r) => r['error_text'] != null)) ...[
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Errors:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                        ...recipients
                                            .where((r) => r['error_text'] != null)
                                            .map((r) => Padding(
                                                  padding: const EdgeInsets.only(top: 4.0),
                                                  child: Text(
                                                    '${r['recipient_name']}: ${r['error_text']}',
                                                    style: const TextStyle(color: Colors.red),
                                                  ),
                                                )),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                        ],
                      ),
                    ),
    );
  }
}
