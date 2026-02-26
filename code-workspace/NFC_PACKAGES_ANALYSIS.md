# Flutter NFC Packages Analysis & Migration Guide

## Available NFC Packages for Flutter

### 1. **nfc_manager** (Currently Used - v4.1.1)
- **GitHub**: https://github.com/okadan/flutter-nfc-manager
- **Pros**:
  - Cross-platform (Android & iOS)
  - Active maintenance
  - Good documentation
  - Supports multiple tag technologies
- **Cons**:
  - v4.x uses Pigeon for communication, making NDEF data access difficult
  - NDEF payload not easily accessible through public API
  - Complex internal structure (TagPigeon, NdefPigeon) requires reflection
- **iOS Support**: ✅ Yes (iOS 11+)
- **Android Support**: ✅ Yes (API 19+)

### 2. **flutter_nfc_kit** (Recommended Alternative)
- **GitHub**: https://github.com/nfcim/flutter_nfc_kit
- **Pros**:
  - **Direct NDEF access** - `readNDEFRecords()` method returns NDEFMessage directly
  - Cleaner API for NDEF operations
  - Better documentation for NDEF reading
  - Cross-platform (Android & iOS)
  - Supports reading metadata, NDEF records, and transceiving
- **Cons**:
  - Less popular than nfc_manager
  - iOS can only read NDEF (cannot write)
- **iOS Support**: ✅ Yes (iOS 13+)
- **Android Support**: ✅ Yes (API 19+)
- **Latest Version**: ^2.3.0

### 3. **nfc_in_flutter**
- **GitHub**: https://github.com/Baseflow/flutter-nfc-in-flutter
- **Pros**:
  - Part of Baseflow ecosystem
  - Good documentation
- **Cons**:
  - Less actively maintained
  - Limited NDEF support
- **iOS Support**: ⚠️ Limited
- **Android Support**: ✅ Yes

### 4. **nfc_flutter**
- **Status**: ⚠️ Deprecated/Unmaintained
- **Not Recommended**: Package appears to be abandoned

## Recommendation: Switch to `flutter_nfc_kit`

**Why `flutter_nfc_kit`?**
1. **Direct NDEF Access**: The main issue with `nfc_manager` v4.x is that NDEF data is buried in Pigeon-generated classes. `flutter_nfc_kit` provides direct access via `readNDEFRecords()`.
2. **Your Use Case**: You need to read NDEF text records (like "SP0679"), which `flutter_nfc_kit` handles perfectly.
3. **iOS Compatibility**: Works on iOS 13+ (iPhone 7 and later).
4. **Simpler Code**: No need for complex reflection or platform channels.

## Migration Plan: nfc_manager → flutter_nfc_kit

### Step 1: Update Dependencies

```yaml
# pubspec.yaml
dependencies:
  # Remove: nfc_manager: ^4.1.1
  # Add:
  flutter_nfc_kit: ^2.3.0
```

### Step 2: iOS Setup

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the Runner target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "Near Field Communication Tag Reading"
6. Update `ios/Runner/Info.plist`:

```xml
<key>NFCReaderUsageDescription</key>
<string>This app uses NFC to read plant codes from NFC tags.</string>
```

7. Ensure `ios/Podfile` has:
```ruby
platform :ios, '13.0'
```

### Step 3: Android Setup

Your existing Android setup should work, but verify:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="false" />
```

### Step 4: Rewrite NfcHelper

The new implementation will be much simpler:

```dart
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'dart:typed_data';

class NfcHelper {
  static Future<bool> isAvailable() async {
    try {
      // flutter_nfc_kit doesn't have a direct availability check
      // We'll handle errors during polling instead
      return true; // Assume available, handle errors in startScanning
    } catch (e) {
      return false;
    }
  }

  static Future<bool> startScanning({
    required Function(String tagId) onTagDiscovered,
    Function(String error)? onError,
  }) async {
    try {
      // Poll for NFC tag
      NFCTag tag = await FlutterNfcKit.poll();
      
      // Check if NDEF is available
      if (tag.ndefAvailable) {
        // Read NDEF records directly
        NDEFMessage? message = await FlutterNfcKit.readNDEFRecords();
        
        if (message != null && message.records.isNotEmpty) {
          // Extract text from NDEF records
          for (var record in message.records) {
            if (record.type == NDEFType.text || record.type == NDEFType.wellknown) {
              // Get payload
              Uint8List payload = record.payload;
              
              // Parse NDEF text record
              // Format: [status byte][language code][text data]
              if (payload.length > 1) {
                int status = payload[0];
                int langLength = status & 0x3F; // Lower 6 bits
                
                if (payload.length > langLength + 1) {
                  // Extract text (skip status byte and language code)
                  List<int> textBytes = payload.sublist(1 + langLength);
                  String text = String.fromCharCodes(textBytes);
                  
                  // Extract plant code
                  String? plantCode = _extractPlantCode(text);
                  if (plantCode != null) {
                    onTagDiscovered(plantCode);
                    await FlutterNfcKit.finish();
                    return true;
                  }
                }
              }
            }
          }
        }
      }
      
      // If no NDEF, try to get tag ID
      if (tag.id != null && tag.id!.isNotEmpty) {
        String tagId = _bytesToHex(tag.id!);
        String? plantCode = _extractPlantCode(tagId);
        if (plantCode != null) {
          onTagDiscovered(plantCode);
          await FlutterNfcKit.finish();
          return true;
        }
      }
      
      onError?.call('Could not extract plant code from NFC tag');
      await FlutterNfcKit.finish();
      return false;
      
    } catch (e) {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}
      
      onError?.call('NFC Error: ${e.toString()}');
      return false;
    }
  }

  static Future<void> stopScanning() async {
    try {
      await FlutterNfcKit.finish();
    } catch (e) {
      // Ignore errors when stopping
    }
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  static String? _extractPlantCode(String? data) {
    if (data == null || data.isEmpty) return null;
    
    // Remove common prefixes/suffixes
    String cleaned = data.trim().toUpperCase();
    
    // Direct match: SP1234
    if (cleaned.startsWith('SP') && cleaned.length >= 4) {
      final match = RegExp(r'SP(\d{4,})').firstMatch(cleaned);
      if (match != null) {
        return 'SP${match.group(1)}';
      }
    }
    
    // Extract 4+ digits and prepend SP
    final digitMatch = RegExp(r'(\d{4,})').firstMatch(cleaned);
    if (digitMatch != null) {
      return 'SP${digitMatch.group(1)}';
    }
    
    // Try to find SP pattern anywhere
    final spMatch = RegExp(r'SP(\d{4,})', caseSensitive: false).firstMatch(cleaned);
    if (spMatch != null) {
      return 'SP${spMatch.group(1)}';
    }
    
    return null;
  }
}
```

### Step 5: Update Asset Check Screen

The `asset_check_screen.dart` should work with minimal changes since the API is similar. The main difference is that `flutter_nfc_kit` uses a polling model (call `poll()` and then `finish()`) rather than a session-based model.

For continuous scanning, you'll need to call `startScanning()` in a loop:

```dart
// In asset_check_screen.dart
Future<void> _startNfcScanning() async {
  _isScanning = true;
  
  while (_isScanning) {
    await NfcHelper.startScanning(
      onTagDiscovered: (tagId) {
        _handleNfcTag(tagId);
        // Continue scanning after processing
      },
      onError: (error) {
        // Show error but continue scanning
        _showError(error);
      },
    );
    
    // Small delay before next scan
    await Future.delayed(Duration(milliseconds: 500));
  }
}
```

## Alternative: Custom Platform Channel Solution

If you want to stick with native Android/iOS code directly:

### Android (Kotlin)
- Use `NfcAdapter` and `Ndef.get(tag)` directly
- Read NDEF message via `ndef.ndefMessage`
- Extract payload from first record

### iOS (Swift)
- Use `CoreNFC` framework
- `NFCNDEFReaderSession` for reading NDEF
- Extract payload from `NFCNDEFMessage`

**Pros**: Full control, direct access
**Cons**: More code to maintain, platform-specific logic

## Recommendation

**Switch to `flutter_nfc_kit`** - It solves your NDEF access problem with minimal code changes and works on both platforms.

