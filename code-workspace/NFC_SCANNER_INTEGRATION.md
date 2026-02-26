# NFC Scanner Integration Guide

## Overview

The Asset Check screen includes NFC tag reading functionality using the `nfc_manager` package. This allows the app to read NFC tags directly when the device is held near a tag.

## How It Works

### NFC Tag Reading

When "Start Scan" is tapped:
1. The app checks if NFC is available on the device
2. Starts an NFC scanning session
3. Waits for the device to be held near an NFC tag
4. Reads the tag data and extracts the plant code
5. Processes the scan automatically
6. Continues scanning for the next tag

### Tag Data Extraction

The NFC helper tries multiple methods to extract the plant code from NFC tags:

1. **NDEF Records**: Reads text data from NDEF (NFC Data Exchange Format) records
2. **Tag Identifier**: Extracts data from the tag's unique identifier
3. **Multiple Tag Types**: Supports NFC-A, NFC-B, and NFC-F (FeliCa) tag types

### Code Format Detection

The helper automatically detects and processes:
- **Full format**: "SP1234" (6 characters)
- **Digits only**: "1234" (4 digits, auto-prepends "SP")
- **Hex encoded**: Attempts to decode hexadecimal tag IDs

## Requirements

### Android

1. **NFC Hardware**: Device must have NFC capability
2. **Permissions**: Already added to `AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.NFC" />
   <uses-feature android:name="android.hardware.nfc" android:required="false" />
   ```
3. **NFC Enabled**: User must enable NFC in device settings
4. **Screen On**: NFC scanning requires the screen to be on (Android requirement)

### iOS

1. **NFC Hardware**: iPhone 7 or later (with NFC capability)
2. **Capabilities**: NFC Tag Reading must be enabled in Xcode
3. **Foreground Only**: iOS only supports NFC scanning when app is in foreground
4. **Info.plist**: Add NFC usage description (if not already present)

## Usage

### Starting NFC Scan

1. Open Asset Check screen
2. Select stock location
3. Tap "Start Scan"
4. Hold device near an NFC tag
5. Tag is automatically read and processed

### Manual Entry (Fallback)

If NFC is not available or a tag is missing:
1. Tap "Manual Entry" button (visible when scanning is active)
2. Enter 4-digit code (SP prefix added automatically)
3. Tap "Add"

## NFC Tag Configuration

### Recommended Tag Format

For best compatibility, configure your NFC tags to store data in one of these formats:

1. **NDEF Text Record**: Store "SP1234" as plain text
2. **NDEF URI Record**: Store as URI (e.g., `dwce://SP1234`)
3. **Tag ID**: Some tags encode the number in the tag's unique ID

### Writing Tags

You can use NFC writing apps or tools to program tags with:
- Format: "SP1234" (SP followed by 4 digits)
- Or: "1234" (4 digits only, app will prepend SP)

## Troubleshooting

### Issue: "NFC is not available on this device"

**Solutions:**
- Check if device has NFC hardware
- Enable NFC in device settings
- Restart the app after enabling NFC
- Use Manual Entry as fallback

### Issue: Tags not being read

**Possible causes:**
1. **Tag too far**: Hold device closer to tag (usually 1-4 cm)
2. **Screen off**: Keep screen on while scanning
3. **Tag format**: Tag may not contain data in expected format
4. **Tag type**: Some tag types may not be supported

**Solutions:**
- Hold device steady near tag for 1-2 seconds
- Ensure screen is on and app is in foreground
- Check tag contains "SP1234" format or 4 digits
- Try reprogramming tag with NDEF text record

### Issue: Wrong data extracted from tag

**Solution:**
- The helper tries multiple extraction methods
- If your tags use a specific format, you may need to customize `_extractPlantCode()` in `nfc_helper.dart`
- Check what data your tags actually contain using an NFC reader app

### Issue: Scanning stops after one tag

**Solution:**
- NFC scanning continues automatically after each successful scan
- If it stops, tap "Start Scan" again
- Some devices may require the screen to stay on

## Customization

### Adjusting Tag Data Extraction

If your NFC tags store data in a specific format, modify `_extractPlantCode()` in `nfc_helper.dart`:

```dart
static String? _extractPlantCode(String? data) {
  if (data == null || data.isEmpty) return null;

  // Add your custom extraction logic here
  // Example: Extract from specific position in hex string
  // Example: Parse from JSON if tag stores JSON data
  // Example: Decode from base64 if encoded
  
  // Current implementation handles:
  // - Direct SP1234 format
  // - 4-digit extraction
  // - Hex decoding (basic)
}
```

### Handling Different Tag Types

The helper supports:
- **NFC-A** (most common)
- **NFC-B**
- **NFC-F** (FeliCa)

If you need support for other types, add them in `startScanning()` method.

## Testing

### Without NFC Tags

1. Enable debug scanner: Set `_showDebugScanner = true` in `asset_check_screen.dart`
2. Use Manual Entry: Tap "Manual Entry" button
3. Test with NFC tags: Use actual NFC tags for full testing

### With NFC Tags

1. Ensure NFC is enabled on device
2. Start scanning in the app
3. Hold device near tag
4. Verify tag is read and processed
5. Check scanned items list updates

## Technical Details

### Package Used

- **nfc_manager**: ^3.3.0
  - Cross-platform NFC support
  - Handles multiple tag types
  - Supports NDEF reading/writing

### Scanning Session

- Starts when "Start Scan" is tapped
- Continues until "Stop Scan" is tapped
- Automatically processes each tag discovered
- Handles errors gracefully

### Error Handling

- Checks NFC availability before starting
- Logs errors to `errors_log` table
- Shows user-friendly error messages
- Falls back to Manual Entry if NFC unavailable

## Notes

- NFC scanning requires the app to be in the foreground
- Screen must be on for NFC to work (Android)
- Some devices may have NFC disabled by default
- Tag reading distance is typically 1-4 cm
- Scanning continues automatically after each tag

