# Migration Steps: nfc_manager → flutter_nfc_kit

## Quick Migration Guide

### Step 1: Update pubspec.yaml

```yaml
dependencies:
  # Remove this line:
  # nfc_manager: ^4.1.1
  
  # Add this line:
  flutter_nfc_kit: ^2.3.0
```

Then run:
```bash
flutter pub get
```

### Step 2: iOS Setup

1. **Open Xcode**:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. **Add NFC Capability**:
   - Select "Runner" target
   - Go to "Signing & Capabilities" tab
   - Click "+ Capability"
   - Add "Near Field Communication Tag Reading"

3. **Update Info.plist**:
   Edit `ios/Runner/Info.plist` and add:
   ```xml
   <key>NFCReaderUsageDescription</key>
   <string>This app uses NFC to read plant codes from NFC tags.</string>
   ```

4. **Verify Podfile**:
   Ensure `ios/Podfile` has:
   ```ruby
   platform :ios, '13.0'
   ```

5. **Update pods**:
   ```bash
   cd ios
   pod install
   cd ..
   ```

### Step 3: Android Setup

Your existing Android setup should work. Verify `android/app/src/main/AndroidManifest.xml` has:

```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="false" />
```

### Step 4: Replace nfc_helper.dart

1. **Backup current file**:
   ```bash
   cp lib/modules/asset_check/nfc_helper.dart lib/modules/asset_check/nfc_helper_old.dart
   ```

2. **Replace with new implementation**:
   ```bash
   cp lib/modules/asset_check/nfc_helper_new.dart lib/modules/asset_check/nfc_helper.dart
   ```

3. **Remove old file** (optional):
   ```bash
   rm lib/modules/asset_check/nfc_helper_old.dart
   ```

### Step 5: Remove Platform Channel Code (Optional)

Since `flutter_nfc_kit` handles NDEF reading natively, you can remove the platform channel code:

1. **Remove from MainActivity.kt**:
   - Remove the `readNdefFromCurrentTag` method handler
   - Remove the `readMifareUltralight` method handler
   - Keep `currentTag` storage if you want, but it's not needed

2. **Remove from nfc_helper.dart**:
   - Remove the `_nfcChannel` constant
   - Remove any platform channel calls

### Step 6: Test

1. **Build and run**:
   ```bash
   flutter run
   ```

2. **Test NFC scanning**:
   - Open Asset Check screen
   - Tap "Start Scan"
   - Hold device near NFC tag with "SP0679" or similar
   - Verify tag is read correctly

### Step 7: Clean Up (Optional)

1. **Remove unused files**:
   ```bash
   rm lib/modules/asset_check/nfc_helper_new.dart
   ```

2. **Remove nfc_manager references**:
   - Check for any other files importing `nfc_manager`
   - Update documentation if needed

## Expected Behavior

### Before (nfc_manager):
- ❌ Could not access NDEF payload
- ❌ Complex reflection code needed
- ❌ Platform channel workarounds required

### After (flutter_nfc_kit):
- ✅ Direct NDEF access via `readNDEFRecords()`
- ✅ Simple, clean API
- ✅ No platform channels needed
- ✅ Works on both iOS and Android

## Troubleshooting

### iOS Issues

**Error: "NFCReaderSessionInvalidationError"**
- Ensure NFC capability is added in Xcode
- Check Info.plist has NFCReaderUsageDescription
- Verify iOS deployment target is 13.0+

**Error: "NFC is not available"**
- iOS only supports NFC on iPhone 7 and later
- NFC only works when app is in foreground

### Android Issues

**Error: "NFC not available"**
- Check NFC is enabled in device settings
- Verify device has NFC hardware
- Check AndroidManifest.xml permissions

**Error: "Tag not found"**
- Ensure tag is NDEF formatted
- Try holding device closer to tag
- Some tags may need to be formatted first

## Rollback Plan

If you need to rollback:

1. Restore old nfc_helper.dart:
   ```bash
   cp lib/modules/asset_check/nfc_helper_old.dart lib/modules/asset_check/nfc_helper.dart
   ```

2. Restore pubspec.yaml:
   ```yaml
   dependencies:
     nfc_manager: ^4.1.1
     # Remove: flutter_nfc_kit: ^2.3.0
   ```

3. Run:
   ```bash
   flutter pub get
   ```

