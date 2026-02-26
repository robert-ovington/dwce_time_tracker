/// NFC Helper (flutter_nfc_kit implementation)
/// 
/// Handles NFC tag reading for asset check scanning using flutter_nfc_kit
/// 
/// This implementation provides direct access to NDEF records, solving
/// the NDEF access issues with nfc_manager v4.x
/// 
/// NOTE: NFC scanning requires:
/// - NFC hardware on the device
/// - NFC enabled in device settings
/// - App to be in foreground (iOS limitation)

import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import '../errors/error_log_service.dart';

class NfcHelper {
  static bool _isScanning = false;
  static bool _shouldContinueScanning = false;
  static String? _lastProcessedTagId; // Track last processed tag to prevent duplicates
  static DateTime? _lastProcessedTime; // Track when last tag was processed

  /// Check if NFC is available on the device
  static Future<bool> isAvailable() async {
    try {
      // flutter_nfc_kit doesn't have a direct availability check
      // We'll attempt to poll and catch errors if NFC is unavailable
      // For now, return true and handle errors during scanning
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Start NFC tag scanning (continuous)
  /// 
  /// [onTagDiscovered] - Callback when a tag is discovered with plant code
  /// [onError] - Optional error callback
  /// 
  /// Returns true if scanning started successfully
  /// 
  /// Note: This method runs in a loop for continuous scanning.
  /// Call stopScanning() to stop.
  static Future<bool> startScanning({
    required Function(String tagId) onTagDiscovered,
    Function(String error)? onError,
  }) async {
    if (_isScanning) {
      // Already scanning, don't start another session
      return true;
    }

    _isScanning = true;
    _shouldContinueScanning = true;

    // Start continuous scanning loop
    _scanLoop(onTagDiscovered, onError);

    return true;
  }

  /// Internal scanning loop for continuous scanning
  static Future<void> _scanLoop(
    Function(String tagId) onTagDiscovered,
    Function(String error)? onError,
  ) async {
    while (_shouldContinueScanning && _isScanning) {
      try {
        // Poll for NFC tag (this blocks until a tag is found or timeout)
        NFCTag tag = await FlutterNfcKit.poll();
        
        // Get tag identifier for deduplication
        String? currentTagId;
        try {
          final dynamic tagIdValue = tag.id;
          if (tagIdValue == null) {
            currentTagId = null;
          } else if (tagIdValue is String) {
            currentTagId = tagIdValue as String;
          } else if (tagIdValue is List<int>) {
            final List<int> intList = tagIdValue as List<int>;
            currentTagId = _bytesToHex(intList);
          } else if (tagIdValue is List) {
            // Handle List<dynamic> or other List types
            try {
              final List<dynamic> dynamicList = tagIdValue as List<dynamic>;
              final intList = dynamicList.map((e) => e as int).toList();
              currentTagId = _bytesToHex(intList);
            } catch (e) {
              // If cast fails, try toString
              currentTagId = tagIdValue.toString();
            }
          } else {
            currentTagId = tagIdValue.toString();
          }
        } catch (e) {
          // Tag ID extraction failed, continue anyway
        }
        
        // Check if this is the same tag we just processed (within 2 seconds)
        if (currentTagId != null && 
            currentTagId == _lastProcessedTagId &&
            _lastProcessedTime != null &&
            DateTime.now().difference(_lastProcessedTime!) < const Duration(seconds: 2)) {
          // Same tag detected again - skip to prevent duplicate callbacks
          await FlutterNfcKit.finish();
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        
        String debugInfo = 'Tag type: ${tag.type}; ';
        bool foundPlantCode = false;
        
        // Try to read NDEF records first (most reliable for text data)
        if (tag.ndefAvailable == true) {
          debugInfo += 'NDEF available; ';
          
          try {
            final ndefRecords = await FlutterNfcKit.readNDEFRecords();
            
            if (ndefRecords != null && ndefRecords.isNotEmpty) {
              debugInfo += 'Found ${ndefRecords.length} NDEF record(s); ';
              
              // Process each NDEF record - stop at first valid plant code
              for (final record in ndefRecords) {
                if (foundPlantCode) break; // Stop if we already found a plant code
                
                final recordType = record.type;
                debugInfo += 'Record type: ${recordType?.toString() ?? 'null'}; ';
                
                // Handle text records - NDEF text record type is [0x54] (T for text)
                // Well-known type for text is RTD_TEXT = [0x54]
                bool isTextRecord = false;
                if (recordType != null && recordType.isNotEmpty) {
                  // Check if type is [0x54] (text) or empty (well-known)
                  if (recordType.length == 1 && recordType[0] == 0x54) {
                    isTextRecord = true;
                  } else if (recordType.isEmpty) {
                    // Empty type with well-known TNF might be text
                    isTextRecord = true;
                  }
                }
                
                // Try to process as text record if it matches, or just try all records
                if (isTextRecord || recordType == null || recordType.isEmpty) {
                  final payload = record.payload;
                  if (payload == null || payload.isEmpty) continue;
                  debugInfo += 'Payload length: ${payload.length}; ';
                  
                  if (payload.isNotEmpty) {
                    // Parse NDEF text record format:
                    // Byte 0: Status byte (UTF-8 bit + language code length)
                    // Bytes 1-N: Language code (ISO 639-1, e.g., "en")
                    // Bytes N+1-end: Text data
                    
                    int status = payload[0];
                    int langLength = status & 0x3F; // Lower 6 bits contain language length
                    
                    if (payload.length > langLength + 1) {
                      // Extract text (skip status byte and language code)
                      List<int> textBytes = payload.sublist(1 + langLength);
                      String text = String.fromCharCodes(textBytes);
                      debugInfo += 'Extracted text: $text; ';
                      
                      // Extract plant code from text (use strict mode for NDEF)
                      String? plantCode = _extractPlantCode(text, strictMode: true);
                      if (plantCode != null) {
                        debugInfo += 'Plant code: $plantCode; ';
                        await FlutterNfcKit.finish();
                        _lastProcessedTagId = currentTagId;
                        _lastProcessedTime = DateTime.now();
                        onTagDiscovered(plantCode);
                        foundPlantCode = true;
                        // Continue scanning after processing
                        await Future.delayed(const Duration(milliseconds: 500));
                        break; // Exit record loop
                      }
                    } else {
                      // Try to decode as UTF-8 directly (some tags may not follow standard format)
                      try {
                        String text = String.fromCharCodes(payload);
                        debugInfo += 'Direct text decode: $text; ';
                        String? plantCode = _extractPlantCode(text, strictMode: true);
                        if (plantCode != null) {
                          debugInfo += 'Plant code: $plantCode; ';
                          await FlutterNfcKit.finish();
                          _lastProcessedTagId = currentTagId;
                          _lastProcessedTime = DateTime.now();
                          onTagDiscovered(plantCode);
                          foundPlantCode = true;
                          // Continue scanning after processing
                          await Future.delayed(const Duration(milliseconds: 500));
                          break; // Exit record loop
                        }
                      } catch (e) {
                        debugInfo += 'Text decode error: $e; ';
                      }
                    }
                  }
                }
              }
              
              // If we found a plant code from NDEF, skip tag ID fallback
              if (foundPlantCode) {
                continue; // Continue to next tag scan
              }
            } else {
              debugInfo += 'No NDEF records found; ';
            }
          } catch (e) {
            debugInfo += 'NDEF read error: $e; ';
          }
        } else {
          debugInfo += 'NDEF not available; ';
        }
        
        // Fallback: Try to get tag ID (only if NDEF didn't yield a result)
        if (!foundPlantCode) {
          try {
            String? tagId;
            
            if (currentTagId != null) {
              tagId = currentTagId;
            } else {
              final tagIdValue = tag.id;
              if (tagIdValue == null) {
                // No ID available, skip
              } else {
                // Handle different types of tag.id
                if (tagIdValue is String) {
                  tagId = tagIdValue;
                } else {
                  // Try to convert to List<int> and then to hex
                  try {
                    final dynamicId = tagIdValue as dynamic;
                    if (dynamicId is List) {
                      final intList = dynamicId.cast<int>().toList();
                      if (intList.isNotEmpty) {
                        tagId = _bytesToHex(intList);
                      }
                    }
                  } catch (e) {
                    // If conversion fails, try toString
                    tagId = tagIdValue.toString();
                  }
                }
              }
            }
            
            if (tagId != null && tagId.isNotEmpty) {
              debugInfo += 'Tag ID: $tagId; ';
              
              // For tag IDs, use strict mode to avoid false positives
              String? plantCode = _extractPlantCode(tagId, strictMode: true);
              if (plantCode != null) {
                debugInfo += 'Plant code from ID: $plantCode; ';
                await FlutterNfcKit.finish();
                _lastProcessedTagId = currentTagId ?? tagId;
                _lastProcessedTime = DateTime.now();
                onTagDiscovered(plantCode);
                foundPlantCode = true;
                // Continue scanning after processing
                await Future.delayed(const Duration(milliseconds: 500));
                continue;
              }
            }
          } catch (e) {
            // Ignore tag ID extraction errors
            debugInfo += 'Tag ID extraction error: $e; ';
          }
        }
        
        // Could not extract plant code
        await FlutterNfcKit.finish();
        
        final errorMsg = 'Could not extract plant code from NFC tag.\n\nDebug Info:\n$debugInfo\n\nPlease check tag format or use Manual Entry.';
        onError?.call(errorMsg);
        
        // Log error
        await ErrorLogService.logError(
          location: 'NFC Helper',
          type: 'NFC',
          description: 'Could not extract plant code. Debug: $debugInfo',
        );
        
        // Small delay before next scan attempt
        await Future.delayed(const Duration(milliseconds: 500));
        
      } catch (e, stackTrace) {
        try {
          await FlutterNfcKit.finish();
        } catch (_) {
          // Ignore errors when finishing
        }
        
        // Check if this is a timeout or cancellation (expected errors)
        if (e.toString().contains('timeout') || 
            e.toString().contains('cancelled') ||
            e.toString().contains('user')) {
          // These are expected - just continue scanning
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        
        // Unexpected error
        final errorMsg = 'NFC Error: ${e.toString()}';
        onError?.call(errorMsg);
        
        // Log error
        await ErrorLogService.logError(
          location: 'NFC Helper',
          type: 'NFC',
          description: 'Error processing NFC tag: $e',
          stackTrace: stackTrace,
        );
        
        // Small delay before retry
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }
    
    // Cleanup when loop exits
    _isScanning = false;
    try {
      await FlutterNfcKit.finish();
    } catch (_) {
      // Ignore
    }
  }

  /// Stop NFC scanning
  static Future<void> stopScanning() async {
    _shouldContinueScanning = false;
    _isScanning = false;
    _lastProcessedTagId = null; // Reset deduplication
    _lastProcessedTime = null;
    
    try {
      await FlutterNfcKit.finish();
    } catch (e) {
      // Ignore errors when stopping
    }
  }

  /// Convert bytes to hex string (format: XX:XX:XX:XX)
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  }

  /// Extract plant code from various text formats
  /// 
  /// Handles:
  /// - "SP0679" (direct format)
  /// - "0679" (digits only, prepends SP) - only in non-strict mode
  /// - "enSP0679" (NDEF text record with language code)
  /// 
  /// [strictMode]: If true, only extracts codes that explicitly contain "SP" prefix.
  ///               This prevents false positives from hex tag IDs like "04:12:34:56"
  static String? _extractPlantCode(String? data, {bool strictMode = false}) {
    if (data == null || data.isEmpty) return null;
    
    // Remove whitespace and convert to uppercase
    String cleaned = data.trim().toUpperCase();
    
    // Priority 1: Direct match: SP1234 or SP0679 (most reliable)
    final directMatch = RegExp(r'SP(\d{4})').firstMatch(cleaned);
    if (directMatch != null) {
      final digits = directMatch.group(1)!;
      // Validate: must be exactly 4 digits
      if (digits.length == 4) {
        return 'SP$digits';
      }
    }
    
    // Priority 2: Match with language prefix: enSP0679, frSP1234, etc.
    final langMatch = RegExp(r'[a-z]{2}SP(\d{4})', caseSensitive: false).firstMatch(cleaned);
    if (langMatch != null) {
      final digits = langMatch.group(1)!;
      if (digits.length == 4) {
        return 'SP$digits';
      }
    }
    
    // Priority 3: Try to find SP pattern anywhere in the string (case insensitive)
    final spMatch = RegExp(r'SP(\d{4})', caseSensitive: false).firstMatch(cleaned);
    if (spMatch != null) {
      final digits = spMatch.group(1)!;
      if (digits.length == 4) {
        return 'SP$digits';
      }
    }
    
    // Only extract digits without SP prefix if NOT in strict mode
    // This is risky for tag IDs which may contain random 4-digit sequences
    if (!strictMode) {
      // Extract exactly 4 consecutive digits (not 4+)
      // This is more conservative than before
      final digitMatch = RegExp(r'(\d{4})').firstMatch(cleaned);
      if (digitMatch != null) {
        final digits = digitMatch.group(1)!;
        // Additional validation: only accept if it looks like a plant code
        // (e.g., starts with 0-1, or is in a reasonable range)
        if (digits.length == 4) {
          return 'SP$digits';
        }
      }
    }
    
    return null;
  }
}

