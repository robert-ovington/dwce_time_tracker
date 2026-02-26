/// New Message Screen
/// 
/// Step-by-step message creation:
/// Step 1: Create Message from scratch or template
/// Step 2: Add recipients (multiple users, roles, or security levels)
/// Step 3: Mark as Important if necessary
/// Step 4: Send message
/// 
/// Supports image placement: marker in text or top/bottom of message

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../config/supabase_config.dart';
import '../modules/auth/auth_service.dart';
import '../modules/database/database_service.dart';
import '../modules/errors/error_log_service.dart';
import '../modules/messaging/message_image_helper.dart';
import 'recipient_selection_screen.dart';
import 'message_template_screen.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final GlobalKey _messageFieldKey = GlobalKey();
  
  // Step management
  int _currentStep = 0; // 0-3 for Steps 1-4
  
  // Step 1: Message content
  String? _selectedTemplateId;
  List<XFile> _selectedImages = [];
  List<String> _uploadedImagePaths = [];
  bool _isUploadingImages = false;
  String _imagePlacement = 'bottom'; // 'top', 'bottom', or 'marker' (legacy, kept for compatibility)
  final String _imageMarker = '{{IMAGE}}'; // Marker text for image placement
  Map<int, String> _imageMarkers = {}; // Map of image index to unique marker (e.g., {{IMAGE_0}}, {{IMAGE_1}})
  
  // Step 2: Recipients
  List<String> _selectedUserIds = [];
  List<String> _selectedRoles = [];
  List<int> _selectedSecurityLevels = [];
  
  // Step 3: Important flag
  bool _isImportant = false;
  
  // Data lists
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = false;
  bool _isLoadingTemplates = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoadingTemplates = true);
    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        setState(() => _isLoadingTemplates = false);
        return;
      }

      final response = await SupabaseService.client
          .from('text_message_template')
          .select('id, template_name, message, category, is_important, image_urls')
          .eq('is_active', true)
          .order('template_name');

      setState(() {
        _templates = List<Map<String, dynamic>>.from(response);
        _isLoadingTemplates = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'New Message Screen - Load Templates',
        type: 'Database',
        description: 'Failed to load templates: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _isLoadingTemplates = false;
      });
    }
  }

  void _onTemplateSelected(String? templateId) async {
    if (templateId == null) {
      setState(() {
        _selectedTemplateId = null;
        _messageController.clear();
        _isImportant = false;
        _selectedImages.clear();
      });
      return;
    }
    
    final template = _templates.firstWhere(
      (t) => t['id']?.toString() == templateId,
      orElse: () => {},
    );
    
    if (template.isNotEmpty) {
      setState(() {
        _selectedTemplateId = templateId;
        _messageController.text = template['message']?.toString() ?? '';
        _isImportant = template['is_important'] == true;
      });
    }
  }

  Future<void> _pickImages() async {
    try {
      final images = await MessageImageHelper.pickMultipleImages(maxImages: 5);
      if (images.isNotEmpty) {
        // Validate images
        final validImages = <XFile>[];
        for (final image in images) {
          final validationError = await MessageImageHelper.validateImage(image);
          if (validationError == null) {
            validImages.add(image);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Image ${image.name}: $validationError'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
        
        setState(() {
          _selectedImages.addAll(validImages);
          // Limit to 5 total images
          if (_selectedImages.length > 5) {
            _selectedImages = _selectedImages.take(5).toList();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Maximum 5 images allowed. Only first 5 will be used.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking images: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      // Remove the marker for this image if it exists
      final marker = _imageMarkers[index];
      if (marker != null) {
        _messageController.text = _messageController.text.replaceAll(marker, '');
        _imageMarkers.remove(index);
      }
      _selectedImages.removeAt(index);
      // Reindex remaining markers
      _imageMarkers = Map.fromEntries(
        _imageMarkers.entries.map((e) {
          if (e.key > index) {
            return MapEntry(e.key - 1, e.value);
          }
          return e;
        }),
      );
    });
  }

  /// Insert image marker at cursor position
  void _insertImageMarker(int imageIndex) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursorPosition = selection.baseOffset;
    
    // Generate unique marker for this image
    final marker = '{{IMAGE_$imageIndex}}';
    _imageMarkers[imageIndex] = marker;
    
    // Insert marker at cursor position
    final newText = text.substring(0, cursorPosition) + 
                    marker + 
                    text.substring(cursorPosition);
    
    setState(() {
      _messageController.text = newText;
      // Move cursor after the inserted marker
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: cursorPosition + marker.length),
      );
    });
  }

  Future<void> _uploadImages(String userId, String messageId) async {
    _uploadedImagePaths.clear();
    
    if (_selectedImages.isEmpty) {
      return;
    }

    setState(() {
      _isUploadingImages = true;
      _statusMessage = 'Uploading images...';
    });

    try {
      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        final storagePath = await MessageImageHelper.uploadImage(
          imageFile: image,
          userId: userId,
          messageId: messageId,
          imageIndex: i,
        );
        
        if (storagePath != null) {
          _uploadedImagePaths.add(storagePath);
        }
      }
    } catch (e) {
      throw Exception('Failed to upload images: $e');
    } finally {
      setState(() {
        _isUploadingImages = false;
      });
    }
  }

  String _buildMessageWithImages(String baseMessage, List<String> imagePaths) {
    if (imagePaths.isEmpty) {
      return baseMessage;
    }

    // Get image URLs (public URLs or signed URLs)
    final imageUrls = imagePaths.map((path) {
      return MessageImageHelper.getImageUrl(path);
    }).toList();

    // First, handle individual image markers ({{IMAGE_0}}, {{IMAGE_1}}, etc.)
    String message = baseMessage;
    for (int i = 0; i < imageUrls.length && i < _selectedImages.length; i++) {
      final marker = '{{IMAGE_$i}}';
      if (message.contains(marker)) {
        message = message.replaceAll(marker, '![Image](${imageUrls[i]})');
      }
    }

    // If there are remaining images without markers, handle legacy placement
    final remainingImages = imageUrls.length > _imageMarkers.length
        ? imageUrls.sublist(_imageMarkers.length)
        : <String>[];

    if (remainingImages.isNotEmpty) {
      final imageSection = remainingImages.map((url) => '![Image]($url)').join('\n\n');
      
      switch (_imagePlacement) {
        case 'top':
          message = '$imageSection\n\n$message';
          break;
        case 'bottom':
          message = '$message\n\n$imageSection';
          break;
        case 'marker':
          // Replace generic marker if it exists
          if (message.contains(_imageMarker)) {
            message = message.replaceAll(_imageMarker, imageSection);
          } else {
            // Marker not found, append at bottom
            message = '$message\n\n$imageSection';
          }
          break;
      }
    }

    return message;
  }

  Future<void> _openRecipientSelection() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => RecipientSelectionScreen(
          initialSelectedUserIds: _selectedUserIds,
          initialSelectedRoles: _selectedRoles,
          initialSelectedSecurityLevels: _selectedSecurityLevels,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedUserIds = List<String>.from((result['userIds'] as List<dynamic>?)?.cast<String>() ?? []);
        _selectedRoles = List<String>.from((result['roles'] as List<dynamic>?)?.cast<String>() ?? []);
        _selectedSecurityLevels = List<int>.from((result['securityLevels'] as List<dynamic>?)?.cast<int>() ?? []);
      });
    }
  }

  bool _canProceedToNextStep() {
    switch (_currentStep) {
      case 0: // Step 1: Message
        return _messageController.text.trim().isNotEmpty;
      case 1: // Step 2: Recipients
        return _selectedUserIds.isNotEmpty ||
               _selectedRoles.isNotEmpty ||
               _selectedSecurityLevels.isNotEmpty;
      case 2: // Step 3: Important (always can proceed)
        return true;
      default:
        return false;
    }
  }

  /// Fetch display name, role, and security for selected user IDs
  Future<List<Map<String, dynamic>>> _fetchSelectedUserDetails() async {
    if (_selectedUserIds.isEmpty) return [];
    try {
      final userIds = _selectedUserIds.toList();
      final usersData = await SupabaseService.client
          .from('users_data')
          .select('user_id, display_name')
          .inFilter('user_id', userIds);
      final setupData = await SupabaseService.client
          .from('users_setup')
          .select('user_id, role, security')
          .inFilter('user_id', userIds);

      final setupByUser = <String, Map<String, dynamic>>{};
      for (final row in (setupData as List)) {
        final uid = row['user_id']?.toString();
        if (uid != null) setupByUser[uid] = Map<String, dynamic>.from(row as Map);
      }

      final list = <Map<String, dynamic>>[];
      for (final row in (usersData as List)) {
        final uid = row['user_id']?.toString();
        if (uid == null) continue;
        final setup = setupByUser[uid];
        list.add({
          'user_id': uid,
          'display_name': row['display_name']?.toString() ?? 'Unknown',
          'role': setup?['role']?.toString(),
          'security': setup?['security'] is int ? setup!['security'] as int : null,
        });
      }
      list.sort((a, b) => (a['display_name'] ?? '').toString().compareTo((b['display_name'] ?? '').toString()));
      return list;
    } catch (e) {
      print('⚠️ Error fetching selected user details: $e');
      return [];
    }
  }

  Future<void> _sendMessage() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate recipients
    if (_selectedUserIds.isEmpty &&
        _selectedRoles.isEmpty &&
        _selectedSecurityLevels.isEmpty) {
      setState(() {
        _statusMessage = '❌ Please add at least one recipient';
      });
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = '❌ Please enter a message';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Sending message...';
    });

    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Generate a temporary message ID for image uploads
      final tempMessageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
      
      // If template was selected, get template images
      final templateId = _selectedTemplateId;
      List<String> templateImagePaths = [];
      if (templateId != null) {
        try {
          final templateData = await SupabaseService.client
              .from('text_message_template')
              .select('image_urls')
              .eq('id', templateId)
              .maybeSingle();
          
          if (templateData != null && templateData['image_urls'] != null) {
            final templateImages = templateData['image_urls'] as List?;
            if (templateImages != null) {
              templateImagePaths = templateImages
                  .map((url) => url?.toString() ?? '')
                  .where((url) => url.isNotEmpty)
                  .toList();
            }
          }
        } catch (e) {
          print('⚠️ Error loading template images: $e');
        }
      }
      
      // Upload new images first (if any)
      await _uploadImages(user.id, tempMessageId);
      
      // Combine template images with newly uploaded images
      final allImagePaths = <String>[...templateImagePaths, ..._uploadedImagePaths];

      // Build final message with images placed according to placement option
      final baseMessage = _messageController.text.trim();
      final finalMessage = _buildMessageWithImages(baseMessage, allImagePaths);

      // Create messages for each recipient type/combination
      // Note: The backend will expand recipients, but we need to create separate messages
      // for different recipient types (user, role, security)
      final createdMessages = <Map<String, dynamic>>[];

      // Create messages for individual users
      for (final userId in _selectedUserIds) {
        final messageData = <String, dynamic>{
          'owner_user_id': user.id,
          'created_by': user.id,
          'message': finalMessage,
          'date_created': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'is_sent': false,
          'recipient_type': 'user',
          'recipient_user_id': userId,
          'is_important': _isImportant,
          'is_active': true,
        };

        if (allImagePaths.isNotEmpty) {
          messageData['image_urls'] = allImagePaths;
        }

        final result = await DatabaseService.create('text_messages', messageData);
        if (result != null) {
          createdMessages.add(result);
        }
      }

      // Create messages for roles
      for (final role in _selectedRoles) {
        final messageData = <String, dynamic>{
          'owner_user_id': user.id,
          'created_by': user.id,
          'message': finalMessage,
          'date_created': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'is_sent': false,
          'recipient_type': 'role',
          'recipient_role': role,
          'is_important': _isImportant,
          'is_active': true,
        };

        if (allImagePaths.isNotEmpty) {
          messageData['image_urls'] = allImagePaths;
        }

        final result = await DatabaseService.create('text_messages', messageData);
        if (result != null) {
          createdMessages.add(result);
        }
      }

      // Create messages for security levels
      for (final securityLevel in _selectedSecurityLevels) {
        final messageData = <String, dynamic>{
          'owner_user_id': user.id,
          'created_by': user.id,
          'message': finalMessage,
          'date_created': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'is_sent': false,
          'recipient_type': 'security',
          'recipient_security': securityLevel,
          'is_important': _isImportant,
          'is_active': true,
        };

        if (allImagePaths.isNotEmpty) {
          messageData['image_urls'] = allImagePaths;
        }

        final result = await DatabaseService.create('text_messages', messageData);
        if (result != null) {
          createdMessages.add(result);
        }
      }

      // Record template usage if template was used
      if (templateId != null && createdMessages.isNotEmpty) {
        try {
          for (final message in createdMessages) {
            await SupabaseService.client
                .from('text_message_template_usage')
                .insert({
              'template_id': templateId,
              'text_message_id': message['id'],
              'used_by': user.id,
              'used_at': DateTime.now().toIso8601String(),
            });
          }

          // Update template usage count
          final templateData = await SupabaseService.client
              .from('text_message_template')
              .select('usage_count')
              .eq('id', templateId)
              .maybeSingle();
          
          final currentCount = (templateData?['usage_count'] as int?) ?? 0;
          
          await SupabaseService.client
              .from('text_message_template')
              .update({
            'usage_count': currentCount + createdMessages.length,
            'last_used_date': DateTime.now().toIso8601String(),
          })
              .eq('id', templateId);
        } catch (e) {
          print('⚠️ Error recording template usage: $e');
        }
      }

      setState(() {
        _statusMessage = '✅ ${createdMessages.length} message(s) created successfully! The backend will process and send them.';
      });

      // Clear form after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _resetForm();
        }
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'New Message Screen - Send Message',
        type: 'Database',
        description: 'Failed to send message: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error sending message: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _resetForm() {
    _messageController.clear();
    _selectedTemplateId = null;
    _selectedImages.clear();
    _uploadedImagePaths.clear();
    _selectedUserIds.clear();
    _selectedRoles.clear();
    _selectedSecurityLevels.clear();
    _isImportant = false;
    _imagePlacement = 'bottom';
    _currentStep = 0;
    _statusMessage = '';
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Message', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: const [ScreenInfoIcon(screenName: 'new_message_screen.dart')],
      ),
      body: Column(
        children: [
          // Step indicator
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStepIndicator(0, 'Step 1: Message'),
                _buildStepIndicator(1, 'Step 2: Recipients'),
                _buildStepIndicator(2, 'Step 3: Important'),
                _buildStepIndicator(3, 'Step 4: Send'),
              ],
            ),
          ),

          // Status message
          if (_statusMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              color: _statusMessage.contains('✅')
                  ? Colors.green.shade50
                  : _statusMessage.contains('❌')
                      ? Colors.red.shade50
                      : Colors.blue.shade50,
              child: Text(
                _statusMessage,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),

          // Content area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: _buildStepContent(),
              ),
            ),
          ),

          // Navigation buttons
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: _currentStep == 0
                ? _buildStep1Buttons()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 0)
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _currentStep--);
                          },
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Previous'),
                        )
                      else
                        const SizedBox.shrink(),
                      const Spacer(),
                      if (_currentStep < 3)
                        ElevatedButton.icon(
                          onPressed: _canProceedToNextStep()
                              ? () {
                                  setState(() => _currentStep++);
                                }
                              : null,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Next'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0081FB),
                            foregroundColor: Colors.white,
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: (_isLoading || _isUploadingImages) ? null : _sendMessage,
                          icon: (_isLoading || _isUploadingImages)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send),
                          label: Text(
                            _isUploadingImages
                                ? 'Uploading Images...'
                                : _isLoading
                                    ? 'Sending...'
                                    : 'Send Message',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;
    
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? Colors.green
                  : isActive
                      ? const Color(0xFF0081FB)
                      : Colors.grey[300],
            ),
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 24)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? const Color(0xFF0081FB) : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Message();
      case 1:
        return _buildStep2Recipients();
      case 2:
        return _buildStep3Important();
      case 3:
        return _buildStep4Review();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1Message() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 1: Create Message',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),

        // Template selection
        DropdownButtonFormField<String>(
          value: _selectedTemplateId,
          decoration: const InputDecoration(
            labelText: 'Select Template (Optional)',
            border: OutlineInputBorder(),
            helperText: 'Choose a template to pre-fill the message',
          ),
          items: _isLoadingTemplates
              ? [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Loading templates...'),
                  )
                ]
              : _templates.isEmpty
                  ? [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('No templates available'),
                      )
                    ]
                  : [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('None'),
                      ),
                      ..._templates.map((template) {
                        return DropdownMenuItem(
                          value: template['id']?.toString(),
                          child: Text(
                            '${template['template_name']}${template['category'] != null ? ' (${template['category']})' : ''}',
                          ),
                        );
                      }),
                    ],
          onChanged: _isLoadingTemplates ? null : _onTemplateSelected,
        ),
        const SizedBox(height: 20),

        // Message text field
        TextFormField(
          key: _messageFieldKey,
          controller: _messageController,
          decoration: InputDecoration(
            labelText: 'Message *',
            border: const OutlineInputBorder(),
            helperText: 'Click on an image tile below to insert it at the cursor position.',
            suffixIcon: IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Click on an image tile below to insert it at the cursor position in your message.',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Click on an image tile below to insert it at the cursor position in your message.'),
                  ),
                );
              },
            ),
          ),
          maxLines: 8,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Message is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),

        // Image selection and preview section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Images (Optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_selectedImages.length < 5)
                      TextButton.icon(
                        onPressed: _isLoading || _isUploadingImages ? null : _pickImages,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: const Text('Add Images'),
                      ),
                  ],
                ),
                
                if (_selectedImages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Click on an image to insert it at the cursor position:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        final image = _selectedImages[index];
                        final hasMarker = _imageMarkers.containsKey(index);
                        return GestureDetector(
                          onTap: () => _insertImageMarker(index),
                          child: Container(
                            width: 48,
                            height: 48,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: hasMarker ? Colors.green : Colors.grey,
                                width: hasMarker ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                kIsWeb
                                    ? FutureBuilder<Uint8List>(
                                        future: image.readAsBytes(),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData) {
                                            return Image.memory(
                                              snapshot.data!,
                                              fit: BoxFit.cover,
                                            );
                                          } else if (snapshot.hasError) {
                                            return Container(
                                              color: Colors.grey[300],
                                              child: const Icon(Icons.image_not_supported),
                                            );
                                          } else {
                                            return Container(
                                              color: Colors.grey[300],
                                              child: const CircularProgressIndicator(),
                                            );
                                          }
                                        },
                                      )
                                    : Image.file(
                                        File(image.path),
                                        fit: BoxFit.cover,
                                      ),
                                if (hasMarker)
                                  Positioned(
                                    top: 1,
                                    left: 1,
                                    child: Container(
                                      padding: const EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 1,
                                  right: 1,
                                  child: GestureDetector(
                                    onTap: () => _removeImage(index),
                                    child: CircleAvatar(
                                      radius: 8,
                                      backgroundColor: Colors.red,
                                      child: const Icon(
                                        Icons.close,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_selectedImages.length} image(s) selected (max 5)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No images selected. Click "Add Images" to add images to your message.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Recipients() {
    final totalRecipients = _selectedUserIds.length +
        _selectedRoles.length +
        _selectedSecurityLevels.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 2: Add Recipients',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  'Total Recipients: $totalRecipients',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildRecipientChip('Users', _selectedUserIds.length),
                    _buildRecipientChip('Roles', _selectedRoles.length),
                    _buildRecipientChip('Security', _selectedSecurityLevels.length),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _openRecipientSelection,
          icon: const Icon(Icons.people),
          label: Text(totalRecipients > 0
              ? 'Edit Recipients ($totalRecipients selected)'
              : 'Select Recipients'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0081FB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 20),
        if (totalRecipients > 0) ...[
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            'Selected Recipients:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_selectedUserIds.isNotEmpty) ...[
            const Text('Users:', style: TextStyle(fontWeight: FontWeight.w500)),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchSelectedUserDetails(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(left: 16, top: 8),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final details = snapshot.data ?? [];
                if (details.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _selectedUserIds.map((id) => Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4),
                      child: Text('• $id'),
                    )).toList(),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: details.map((u) {
                    final name = u['display_name']?.toString() ?? 'Unknown';
                    final role = u['role']?.toString();
                    final security = u['security'] as int?;
                    final parts = <String>[name];
                    if (role != null && role.isNotEmpty) parts.add('Role: $role');
                    if (security != null) parts.add('Security: $security');
                    return Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4),
                      child: Text('• ${parts.join(' • ')}'),
                    );
                  }).toList(),
                );
              },
            ),
          ],
          if (_selectedRoles.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Roles:', style: TextStyle(fontWeight: FontWeight.w500)),
            ..._selectedRoles.map((role) => Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text('• $role'),
                )),
          ],
          if (_selectedSecurityLevels.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Security Levels:', style: TextStyle(fontWeight: FontWeight.w500)),
            ..._selectedSecurityLevels.map((level) => Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text('• Level $level'),
                )),
          ],
        ] else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No recipients selected. Click "Select Recipients" to add recipients.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStep3Important() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 3: Mark as Important',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  title: const Text(
                    'Mark as Important',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Important messages require acknowledgment before users can continue using the app. They will also trigger app notifications.',
                  ),
                  value: _isImportant,
                  onChanged: (value) {
                    setState(() {
                      _isImportant = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (_isImportant) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This message will block users until they read it.',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep4Review() {
    final totalRecipients = _selectedUserIds.length +
        _selectedRoles.length +
        _selectedSecurityLevels.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 4: Review & Send',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Message Preview:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _messageController.text.isEmpty
                        ? '(No message text)'
                        : _messageController.text,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Recipients:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('Total: $totalRecipients'),
                if (_selectedUserIds.isNotEmpty)
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchSelectedUserDetails(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final details = snapshot.data ?? [];
                      if (details.isEmpty) {
                        return Text('• ${_selectedUserIds.length} user(s)');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ${_selectedUserIds.length} user(s):'),
                          ...details.map((u) {
                            final name = u['display_name']?.toString() ?? 'Unknown';
                            final role = u['role']?.toString();
                            final security = u['security'] as int?;
                            final parts = <String>[name];
                            if (role != null && role.isNotEmpty) parts.add('Role: $role');
                            if (security != null) parts.add('Security: $security');
                            return Padding(
                              padding: const EdgeInsets.only(left: 12, top: 2),
                              child: Text(
                                '  - ${parts.join(' • ')}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                if (_selectedRoles.isNotEmpty)
                  Text('• ${_selectedRoles.length} role(s): ${_selectedRoles.join(", ")}'),
                if (_selectedSecurityLevels.isNotEmpty)
                  Text('• ${_selectedSecurityLevels.length} security level(s): ${_selectedSecurityLevels.join(", ")}'),
                const SizedBox(height: 16),
                const Text(
                  'Options:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _isImportant ? Icons.priority_high : Icons.info_outline,
                      color: _isImportant ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(_isImportant ? 'Marked as Important' : 'Not Important'),
                  ],
                ),
                if (_selectedImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.image, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text('${_selectedImages.length} image(s) - ${_imagePlacement == 'top' ? 'Top' : _imagePlacement == 'bottom' ? 'Bottom' : 'At marker'}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecipientChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: $count',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Build buttons for Step 1: Preview, Save as Template, Next
  Widget _buildStep1Buttons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        OutlinedButton.icon(
          onPressed: _messageController.text.trim().isEmpty ? null : _showPreview,
          icon: const Icon(Icons.preview),
          label: const Text('Preview'),
        ),
        OutlinedButton.icon(
          onPressed: _messageController.text.trim().isEmpty ? null : _saveAsTemplate,
          icon: const Icon(Icons.save),
          label: const Text('Save as Template'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            side: const BorderSide(color: Colors.orange),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _canProceedToNextStep()
              ? () {
                  setState(() => _currentStep++);
                }
              : null,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Next'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0081FB),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  /// Show preview of message with images
  void _showPreview() {
    // Build preview message with image placeholders
    String previewText = _messageController.text;
    final imagePlaceholders = <String, Widget>{};
    
    // Replace markers with image placeholders for preview
    for (int i = 0; i < _selectedImages.length; i++) {
      final marker = '{{IMAGE_$i}}';
      if (previewText.contains(marker)) {
        imagePlaceholders[marker] = Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(8),
            color: Colors.blue.shade50,
          ),
          child: Column(
            children: [
              kIsWeb
                  ? FutureBuilder<Uint8List>(
                      future: _selectedImages[i].readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Image.memory(
                            snapshot.data!,
                            width: 200,
                            height: 200,
                            fit: BoxFit.contain,
                          );
                        } else if (snapshot.hasError) {
                          return Container(
                            width: 200,
                            height: 200,
                            color: Colors.grey[300],
                            child: const Icon(Icons.image_not_supported),
                          );
                        } else {
                          return Container(
                            width: 200,
                            height: 200,
                            color: Colors.grey[300],
                            child: const CircularProgressIndicator(),
                          );
                        }
                      },
                    )
                  : Image.file(
                      File(_selectedImages[i].path),
                      width: 200,
                      height: 200,
                      fit: BoxFit.contain,
                    ),
            ],
          ),
        );
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Preview'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Message Preview:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Show message with image placeholders
              ..._buildPreviewContent(previewText, imagePlaceholders),
              if (_selectedImages.isNotEmpty && _imageMarkers.isEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Note: Images will be appended at the end of the message.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
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
        ],
      ),
    );
  }

  /// Build preview content with images inserted at marker positions
  List<Widget> _buildPreviewContent(String text, Map<String, Widget> imagePlaceholders) {
    if (imagePlaceholders.isEmpty) {
      return [
        Text(text.isEmpty ? '(No message text)' : text),
      ];
    }

    final widgets = <Widget>[];
    int lastIndex = 0;
    
    // Sort markers by position in text
    final sortedMarkers = imagePlaceholders.keys.toList()
      ..sort((a, b) => text.indexOf(a).compareTo(text.indexOf(b)));

    for (final marker in sortedMarkers) {
      final markerIndex = text.indexOf(marker, lastIndex);
      if (markerIndex == -1) continue;

      // Add text before marker
      if (markerIndex > lastIndex) {
        widgets.add(Text(text.substring(lastIndex, markerIndex)));
      }

      // Add image placeholder
      widgets.add(imagePlaceholders[marker]!);

      lastIndex = markerIndex + marker.length;
    }

    // Add remaining text
    if (lastIndex < text.length) {
      widgets.add(Text(text.substring(lastIndex)));
    }

    return widgets;
  }

  /// Save current message as template
  Future<void> _saveAsTemplate() async {
    // Navigate to message_template_screen with pre-populated data
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MessageTemplateScreen(
          prePopulatedData: {
            'message': _messageController.text,
            'is_important': _isImportant,
            'images': _selectedImages,
            'image_markers': _imageMarkers,
          },
        ),
      ),
    );

    // If template was created successfully, show message
    if (result != null && result['success'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Template saved successfully! You can continue with sending the message.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}
