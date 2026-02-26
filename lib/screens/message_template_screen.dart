/// Message Template Screen
/// 
/// CRUD interface for managing message templates.
/// Users can create, edit, delete, and view their message templates.

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../config/supabase_config.dart';
import '../modules/auth/auth_service.dart';
import '../modules/database/database_service.dart';
import '../modules/errors/error_log_service.dart';
import '../modules/messaging/message_image_helper.dart';

class MessageTemplateScreen extends StatefulWidget {
  final Map<String, dynamic>? prePopulatedData;
  
  const MessageTemplateScreen({super.key, this.prePopulatedData});

  @override
  State<MessageTemplateScreen> createState() => _MessageTemplateScreenState();
}

class _MessageTemplateScreenState extends State<MessageTemplateScreen> {
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = true;
  String _statusMessage = '';
  String? _selectedCategory;
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    
    // If pre-populated data is provided, open the create dialog automatically
    if (widget.prePopulatedData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEditDialog(null, prePopulatedData: widget.prePopulatedData);
      });
    }
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    try {
      final user = AuthService.getCurrentUser();
      if (user == null) {
        throw Exception('User not authenticated');
      }

      dynamic query = SupabaseService.client
          .from('text_message_template')
          .select('*')
          .eq('is_active', true)
          .order('template_name');

      // Filter by category if selected
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        query = query.eq('category', _selectedCategory);
      }

      final response = await query;
      final templates = List<Map<String, dynamic>>.from(response as Iterable<dynamic>);

      // Extract unique categories
      final categories = <String>{};
      for (final template in templates) {
        final category = template['category']?.toString();
        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
      }

      setState(() {
        _templates = templates;
        _categories = categories.toList()..sort();
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Message Template Screen - Load Templates',
        type: 'Database',
        description: 'Failed to load templates: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error loading templates: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTemplate(String templateId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: const Text('Are you sure you want to delete this template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Soft delete by setting is_active to false
      await SupabaseService.client
          .from('text_message_template')
          .update({'is_active': false})
          .eq('id', templateId);

      setState(() {
        _statusMessage = '✅ Template deleted successfully';
      });

      _loadTemplates();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Message Template Screen - Delete Template',
        type: 'Database',
        description: 'Failed to delete template: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _statusMessage = '❌ Error deleting template: $e';
      });
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic>? template, {Map<String, dynamic>? prePopulatedData}) async {
    final isEdit = template != null;
    final prePopulated = prePopulatedData ?? {};
    
    final nameController = TextEditingController(
      text: template?['template_name']?.toString() ?? prePopulated['template_name']?.toString() ?? '',
    );
    final messageController = TextEditingController(
      text: template?['message']?.toString() ?? prePopulated['message']?.toString() ?? '',
    );
    final categoryController = TextEditingController(
      text: template?['category']?.toString() ?? prePopulated['category']?.toString() ?? '',
    );
    final tagsController = TextEditingController(
      text: template != null
          ? ((template['tags'] as List?)?.map((t) => t.toString()).join(', ') ?? '')
          : (prePopulated['tags']?.toString() ?? ''),
    );
    bool isImportant = template?['is_important'] == true || prePopulated['is_important'] == true;
    
    // Load existing image URLs from template
    List<String> existingImagePaths = [];
    if (template?['image_urls'] != null && template!['image_urls'] is List) {
      existingImagePaths = (template['image_urls'] as List)
          .map((url) => url?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .toList();
    }
    
    // Selected new images to upload (from pre-populated data or new selection)
    List<XFile> selectedNewImages = [];
    if (prePopulated['images'] != null && prePopulated['images'] is List) {
      selectedNewImages = List<XFile>.from(prePopulated['images'] as List);
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Template' : 'New Template'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Template Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message *',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 6,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                    helperText: 'Optional category for organizing templates',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    border: OutlineInputBorder(),
                    helperText: 'Comma-separated tags (e.g., urgent, reminder, announcement)',
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Mark as Important'),
                  value: isImportant,
                  onChanged: (value) {
                    setDialogState(() {
                      isImportant = value ?? false;
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // Image selection section
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
                              'Template Images (Optional)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (selectedNewImages.length + existingImagePaths.length < 5)
                              TextButton.icon(
                                onPressed: () async {
                                  final images = await MessageImageHelper.pickMultipleImages(
                                    maxImages: 5 - selectedNewImages.length - existingImagePaths.length,
                                  );
                                  setDialogState(() {
                                    selectedNewImages.addAll(images);
                                  });
                                },
                                icon: const Icon(Icons.add_photo_alternate, size: 18),
                                label: const Text('Add', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                        if (existingImagePaths.isNotEmpty || selectedNewImages.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: existingImagePaths.length + selectedNewImages.length,
                              itemBuilder: (context, index) {
                                if (index < existingImagePaths.length) {
                                  // Existing image from template
                                  final imagePath = existingImagePaths[index];
                                  return FutureBuilder<String?>(
                                    future: MessageImageHelper.getSignedImageUrl(imagePath),
                                    builder: (context, snapshot) {
                                      return Container(
                                        width: 100,
                                        margin: const EdgeInsets.only(right: 8),
                                        child: Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: snapshot.hasData
                                                  ? Image.network(
                                                      snapshot.data!,
                                                      width: 100,
                                                      height: 100,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error, stackTrace) {
                                                        return Container(
                                                          color: Colors.grey.shade200,
                                                          child: const Icon(Icons.broken_image),
                                                        );
                                                      },
                                                    )
                                                  : Container(
                                                      color: Colors.grey.shade200,
                                                      child: const Center(
                                                        child: CircularProgressIndicator(),
                                                      ),
                                                    ),
                                            ),
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: CircleAvatar(
                                                radius: 12,
                                                backgroundColor: Colors.red,
                                                child: IconButton(
                                                  padding: EdgeInsets.zero,
                                                  icon: const Icon(
                                                    Icons.close,
                                                    size: 14,
                                                    color: Colors.white,
                                                  ),
                                                  onPressed: () {
                                                    setDialogState(() {
                                                      existingImagePaths.removeAt(index);
                                                    });
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                } else {
                                  // New selected image
                                  final newImageIndex = index - existingImagePaths.length;
                                  final image = selectedNewImages[newImageIndex];
                                  return Container(
                                    width: 100,
                                    margin: const EdgeInsets.only(right: 8),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(
                                            File(image.path),
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: CircleAvatar(
                                            radius: 12,
                                            backgroundColor: Colors.red,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.close,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                              onPressed: () {
                                                setDialogState(() {
                                                  selectedNewImages.removeAt(newImageIndex);
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop({'success': false}),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty ||
                    messageController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Template name and message are required'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  final user = AuthService.getCurrentUser();
                  if (user == null) {
                    throw Exception('User not authenticated');
                  }

                  // Upload new images if any
                  final uploadedImagePaths = <String>[];
                  final templateId = isEdit ? (template!['id']?.toString() ?? '') : 'temp_${DateTime.now().millisecondsSinceEpoch}';
                  
                  for (int i = 0; i < selectedNewImages.length; i++) {
                    try {
                      final storagePath = await MessageImageHelper.uploadImage(
                        imageFile: selectedNewImages[i],
                        userId: user.id,
                        messageId: templateId,
                        imageIndex: existingImagePaths.length + i,
                      );
                      if (storagePath != null) {
                        uploadedImagePaths.add(storagePath);
                      }
                    } catch (e) {
                      print('⚠️ Error uploading template image: $e');
                      // Continue with other images
                    }
                  }

                  // Combine existing and new image paths
                  final allImagePaths = [...existingImagePaths, ...uploadedImagePaths];

                  // Parse tags
                  final tags = tagsController.text
                      .split(',')
                      .map((t) => t.trim())
                      .where((t) => t.isNotEmpty)
                      .toList();

                  final templateData = <String, dynamic>{
                    'owner_user_id': user.id,
                    'template_name': nameController.text.trim(),
                    'message': messageController.text.trim(),
                    'category': categoryController.text.trim().isEmpty
                        ? null
                        : categoryController.text.trim(),
                    'tags': tags.isEmpty ? null : tags,
                    'is_important': isImportant,
                    'is_active': true,
                  };

                  // Add image URLs if any
                  if (allImagePaths.isNotEmpty) {
                    templateData['image_urls'] = allImagePaths;
                  }

                  if (isEdit) {
                    // Update existing template
                    await DatabaseService.update(
                      'text_message_template',
                      template!['id']?.toString() ?? '',
                      templateData,
                    );
                  } else {
                    // Create new template
                    await DatabaseService.create('text_message_template', templateData);
                  }

                  Navigator.of(context).pop({'success': true, 'isEdit': isEdit});
                  _loadTemplates();
                  setState(() {
                    _statusMessage = isEdit
                        ? '✅ Template updated successfully'
                        : '✅ Template created successfully';
                  });
                  
                  // If this was called from new_message_screen, also pop this screen
                  if (prePopulatedData != null && !isEdit) {
                    Navigator.of(context).pop({'success': true});
                  }
                } catch (e, stackTrace) {
                  await ErrorLogService.logError(
                    location: 'Message Template Screen - Save Template',
                    type: 'Database',
                    description: 'Failed to save template: $e',
                    stackTrace: stackTrace,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(isEdit ? 'Update' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Templates', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [
          const ScreenInfoIcon(screenName: 'message_template_screen.dart'),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadTemplates,
          ),
        ],
      ),
      body: Column(
        children: [
          // Category filter
          if (_categories.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  const Text('Filter by Category: '),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      hint: const Text('All Categories'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All Categories'),
                        ),
                        ..._categories.map((category) {
                          return DropdownMenuItem<String>(
                            value: category,
                            child: Text(category),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCategory = value;
                        });
                        _loadTemplates();
                      },
                    ),
                  ),
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
                  : Colors.red.shade50,
              child: Text(
                _statusMessage,
                style: const TextStyle(fontSize: 14),
              ),
            ),

          // Templates list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _templates.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.description, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No templates found',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => _showEditDialog(null),
                              icon: const Icon(Icons.add),
                              label: const Text('Create Template'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTemplates,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8.0),
                          itemCount: _templates.length,
                          itemBuilder: (context, index) {
                            final template = _templates[index];
                            final tags = template['tags'] as List? ?? [];
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8.0),
                              child: ListTile(
                                leading: template['is_important'] == true
                                    ? const Icon(Icons.priority_high, color: Colors.red)
                                    : const Icon(Icons.description),
                                title: Text(
                                  template['template_name']?.toString() ?? 'Unnamed',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (template['category'] != null)
                                      Text(
                                        'Category: ${template['category']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (template['message'] != null)
                                      Text(
                                        template['message'].toString().length > 100
                                            ? '${template['message'].toString().substring(0, 100)}...'
                                            : template['message'].toString(),
                                        style: const TextStyle(fontSize: 12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (tags.isNotEmpty)
                                      Wrap(
                                        spacing: 4,
                                        children: tags.map((tag) {
                                          return Chip(
                                            label: Text(
                                              tag.toString(),
                                              style: const TextStyle(fontSize: 10),
                                            ),
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          );
                                        }).toList(),
                                      ),
                                    if (template['usage_count'] != null)
                                      Text(
                                        'Used ${template['usage_count']} time(s)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    if (template['last_used_date'] != null)
                                      Text(
                                        'Last used: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(template['last_used_date'].toString()))}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    // Show image indicator
                                    if (template['image_urls'] != null && 
                                        template['image_urls'] is List && 
                                        (template['image_urls'] as List).isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.image, size: 14, color: Colors.blue),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${(template['image_urls'] as List).length} image(s)',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      tooltip: 'Edit',
                                      onPressed: () => _showEditDialog(template),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteTemplate(
                                        template['id']?.toString() ?? '',
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(null),
        child: const Icon(Icons.add),
        tooltip: 'New Template',
      ),
    );
  }
}
