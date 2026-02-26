/// Message Image Upload Helper
/// 
/// Handles uploading images to Supabase Storage for messages
/// Images are stored in the 'message-images' bucket

import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../../config/supabase_config.dart';
import '../errors/error_log_service.dart';

class MessageImageHelper {
  static const String _bucketName = 'message-images';
  static const int _maxFileSize = 10 * 1024 * 1024; // 10MB
  static const List<String> _allowedMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  ];

  /// Pick an image from gallery or camera
  static Future<XFile?> pickImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85, // Compress to 85% quality
        maxWidth: 1920, // Max width
        maxHeight: 1920, // Max height
      );
      return image;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Message Image Helper - Pick Image',
        type: 'File Picker',
        description: 'Failed to pick image: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Pick multiple images
  static Future<List<XFile>> pickMultipleImages({
    ImageSource source = ImageSource.gallery,
    int maxImages = 5,
  }) async {
    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      
      // Limit to maxImages
      return images.take(maxImages).toList();
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Message Image Helper - Pick Multiple Images',
        type: 'File Picker',
        description: 'Failed to pick images: $e',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Upload image to Supabase Storage
  /// Returns the storage path (not full URL) to store in image_urls array
  /// Path format: {user_id}/{message_id}_{timestamp}_{index}.{ext}
  static Future<String?> uploadImage({
    required XFile imageFile,
    required String userId,
    required String messageId,
    required int imageIndex,
  }) async {
    try {
      // Read file as bytes (works on both web and mobile)
      final bytes = await imageFile.readAsBytes();
      
      if (bytes.isEmpty) {
        throw Exception('Image file is empty');
      }
      
      final fileSize = bytes.length;
      if (fileSize > _maxFileSize) {
        throw Exception('Image file size (${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB) exceeds maximum allowed size (10MB)');
      }

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Get extension from name (preferred) or path (mobile only)
      String extension = 'jpg'; // default
      if (imageFile.name.isNotEmpty) {
        final parts = imageFile.name.split('.');
        if (parts.length > 1) {
          extension = parts.last.toLowerCase();
        }
      } else if (!kIsWeb) {
        // On mobile, we can use path
        try {
          final pathParts = imageFile.path.split('.');
          if (pathParts.length > 1) {
            extension = pathParts.last.toLowerCase();
          }
        } catch (e) {
          // If path access fails, use default
          extension = 'jpg';
        }
      }
      
      final storageFileName = '${messageId}_${timestamp}_$imageIndex.$extension';
      final storagePath = '$userId/$storageFileName';

      // Upload to Supabase Storage
      // On web we must use uploadBinary (upload() calls .path on the argument)
      if (kIsWeb) {
        await SupabaseService.client.storage
            .from(_bucketName)
            .uploadBinary(storagePath, bytes);
      } else {
        // For mobile, use File object
        final file = File(imageFile.path);
        await SupabaseService.client.storage
            .from(_bucketName)
            .upload(storagePath, file);
      }

      // Return the storage path (will be used to construct URLs)
      return storagePath;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Message Image Helper - Upload Image',
        type: 'Storage',
        description: 'Failed to upload image to bucket "$_bucketName": $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Get public URL for an image from storage path
  /// Note: For private buckets, you may need to use signed URLs instead
  static String getImageUrl(String storagePath) {
    return SupabaseService.client.storage
        .from(_bucketName)
        .getPublicUrl(storagePath);
  }

  /// Get signed URL for private image (valid for 1 hour)
  /// Use this for private buckets
  static Future<String?> getSignedImageUrl(String storagePath) async {
    try {
      final response = await SupabaseService.client.storage
          .from(_bucketName)
          .createSignedUrl(storagePath, 3600); // Valid for 1 hour
      
      return response;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Message Image Helper - Get Signed URL',
        type: 'Storage',
        description: 'Failed to get signed URL for $storagePath: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Delete image from storage
  static Future<bool> deleteImage(String storagePath) async {
    try {
      await SupabaseService.client.storage
          .from(_bucketName)
          .remove([storagePath]);
      return true;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Message Image Helper - Delete Image',
        type: 'Storage',
        description: 'Failed to delete image $storagePath: $e',
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Validate image file before upload
  static Future<String?> validateImage(XFile imageFile) async {
    try {
      // Use readAsBytes() which works on both web and mobile
      final bytes = await imageFile.readAsBytes();
      
      if (bytes.isEmpty) {
        return 'Image file is empty';
      }
      
      final fileSize = bytes.length;
      if (fileSize > _maxFileSize) {
        return 'Image file size (${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB) exceeds maximum allowed size (10MB)';
      }

      // Check MIME type - use name (preferred) or path (mobile only)
      String extension = 'jpg'; // default
      if (imageFile.name.isNotEmpty) {
        final parts = imageFile.name.split('.');
        if (parts.length > 1) {
          extension = parts.last.toLowerCase();
        }
      } else if (!kIsWeb) {
        // On mobile, we can use path
        try {
          final pathParts = imageFile.path.split('.');
          if (pathParts.length > 1) {
            extension = pathParts.last.toLowerCase();
          }
        } catch (e) {
          // If path access fails, use default
          extension = 'jpg';
        }
      }
      final mimeType = _getMimeType(extension);
      if (!_allowedMimeTypes.contains(mimeType)) {
        return 'Image format not supported. Allowed: JPEG, PNG, GIF, WebP';
      }

      return null; // Valid
    } catch (e) {
      return 'Error validating image: $e';
    }
  }

  /// Get MIME type from file extension
  static String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'unknown';
    }
  }

  /// Format file size for display
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
