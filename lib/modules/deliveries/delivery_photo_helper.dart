/// Delivery Photo Helper
/// 
/// Handles uploading photos for delivery dockets and receiver signatures

import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../../config/supabase_config.dart';
import '../errors/error_log_service.dart';

class DeliveryPhotoHelper {
  // Storage bucket names
  static const String _docketBucketName = 'delivery-docket-photos';
  static const String _signatureBucketName = 'receiver-signature-photos';

  /// Pick an image from gallery or camera
  static Future<XFile?> pickImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      return image;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Photo Helper - Pick Image',
        type: 'File Picker',
        description: 'Failed to pick image: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Upload docket photo to Supabase Storage
  static Future<String?> uploadDocketPhoto({
    required XFile imageFile,
    required String deliveryId,
  }) async {
    try {
      if (kIsWeb) {
        throw Exception('Photo upload is not supported on web. Please use mobile or desktop app.');
      }

      final file = File(imageFile.path);
      
      if (!await file.exists()) {
        throw Exception('Image file does not exist');
      }
      
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }
      
      final fileName = _generateDocketFileName(deliveryId);
      
      await SupabaseService.client.storage
          .from(_docketBucketName)
          .upload(fileName, file);

      final publicUrl = SupabaseService.client.storage
          .from(_docketBucketName)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Photo Helper - Upload Docket Photo',
        type: 'Storage',
        description: 'Failed to upload docket photo: $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Upload receiver signature to Supabase Storage
  static Future<String?> uploadSignature({
    required XFile imageFile,
    required String deliveryId,
  }) async {
    try {
      if (kIsWeb) {
        throw Exception('Signature upload is not supported on web. Please use mobile or desktop app.');
      }

      final file = File(imageFile.path);
      
      if (!await file.exists()) {
        throw Exception('Signature file does not exist');
      }
      
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('Signature file is empty');
      }
      
      final fileName = _generateSignatureFileName(deliveryId);
      
      await SupabaseService.client.storage
          .from(_signatureBucketName)
          .upload(fileName, file);

      final publicUrl = SupabaseService.client.storage
          .from(_signatureBucketName)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Delivery Photo Helper - Upload Signature',
        type: 'Storage',
        description: 'Failed to upload signature: $e',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Generate unique file name for docket photo
  static String _generateDocketFileName(String deliveryId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'docket_${deliveryId}_$timestamp.jpg';
  }

  /// Generate unique file name for signature
  static String _generateSignatureFileName(String deliveryId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'signature_${deliveryId}_$timestamp.png';
  }
}

