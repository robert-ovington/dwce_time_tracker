/// Photo Upload Helper
/// 
/// Handles uploading photos to Supabase Storage
/// 
/// NOTE: Update the bucket name below to match your Supabase Storage bucket
/// for asset check fault photos. Default is 'asset-check-photos'

import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../../config/supabase_config.dart';
import '../errors/error_log_service.dart';

class PhotoUploadHelper {
  // TODO: Update this bucket name to match your Supabase Storage bucket
  static const String _bucketName = 'asset-check-photos';

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
        location: 'Photo Upload Helper - Pick Image',
        type: 'File Picker',
        description: 'Failed to pick image: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Upload image to Supabase Storage
  /// Returns the public URL of the uploaded image
  static Future<String?> uploadImage({
    required XFile imageFile,
    required String fileName, // e.g., 'fault_${timestamp}_${userId}.jpg'
  }) async {
    try {
      // For web platform, photo upload is not supported in this implementation
      // Use mobile/desktop platforms for photo upload functionality
      if (kIsWeb) {
        throw Exception('Photo upload is not supported on web. Please use mobile or desktop app.');
      }

      // Use File object directly - Supabase SDK handles this correctly
      final file = File(imageFile.path);
      
      // Check if file exists and has content
      if (!await file.exists()) {
        throw Exception('Image file does not exist');
      }
      
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }
      
      // Upload to Supabase Storage using File object
      // The SDK will handle the file upload correctly
      await SupabaseService.client.storage
          .from(_bucketName)
          .upload(fileName, file);

      // Get public URL
      final publicUrl = SupabaseService.client.storage
          .from(_bucketName)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e, stackTrace) {
      // Enhanced error logging for storage upload issues
      final errorMessage = e.toString();
      await ErrorLogService.logError(
        location: 'Photo Upload Helper - Upload Image',
        type: 'Storage',
        description: 'Failed to upload image to bucket "$_bucketName": $errorMessage\n'
            'File: $fileName\n'
            'Size: ${await File(imageFile.path).length()} bytes\n'
            'Common causes: Missing storage bucket, RLS policies blocking upload, or file size limits.',
        stackTrace: stackTrace,
      );
      
      // Re-throw with more context for UI display
      throw Exception(
        'Photo upload failed: $errorMessage\n\n'
        'Please check:\n'
        '1. Storage bucket "$_bucketName" exists in Supabase\n'
        '2. Storage policies allow authenticated users to upload\n'
        '3. File size is within limits',
      );
    }
  }

  /// Generate a unique file name for fault photos
  static String generateFileName(String userId, String smallPlantNo) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'fault_${smallPlantNo}_${userId}_$timestamp.jpg';
  }
}

