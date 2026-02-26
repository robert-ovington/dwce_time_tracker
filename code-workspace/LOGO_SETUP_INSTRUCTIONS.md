# Logo Setup Instructions

## Step 1: Add Your Logo File

1. **Create the logo directory** (if it doesn't exist):
   ```
   assets/logo/
   ```

2. **Place your logo file** in the `assets/logo/` directory:
   - Recommended file name: `walsh_logo.png`
   - Supported formats: `.png`, `.jpg`, `.jpeg`, `.gif`
   - Recommended size: 400-600px width (height will scale proportionally)

3. **File location should be:**
   ```
   dwce_time_tracker/
   └── assets/
       └── logo/
           └── walsh_logo.png
   ```

## Step 2: Update the Logo Path (if needed)

If your logo file has a different name, update the path in `lib/screens/login_screen.dart`:

**Current code (line ~211):**
```dart
Image.asset(
  'assets/logo/walsh_logo.png', // Change this to match your file name
  height: 120,
  fit: BoxFit.contain,
  ...
)
```

**Example if your file is named `company_logo.png`:**
```dart
Image.asset(
  'assets/logo/company_logo.png',
  height: 120,
  fit: BoxFit.contain,
  ...
)
```

## Step 3: Verify pubspec.yaml

The `pubspec.yaml` file already includes the logo directory:
```yaml
flutter:
  assets:
    - assets/logo/
```

**No changes needed** unless you want to add more asset directories.

## Step 4: Hot Restart

After adding the logo file:
1. **Stop the app** (if running)
2. **Run `flutter pub get`** (to refresh assets)
3. **Hot restart** the app (not just hot reload)

## Fallback Display

If the logo file is not found, the app will display:
- A business icon
- "Login" text

This ensures the login screen still works even if the logo hasn't been added yet.

## Logo Recommendations

- **Format**: PNG with transparent background (recommended)
- **Size**: 400-600px width
- **Aspect Ratio**: Maintain original proportions
- **File Size**: Keep under 500KB for faster loading

## Troubleshooting

**Logo not showing?**
1. Check file name matches exactly (case-sensitive)
2. Verify file is in `assets/logo/` directory
3. Run `flutter clean` then `flutter pub get`
4. Hot restart (not hot reload)

**Logo too large/small?**
- Adjust the `height: 120` value in `login_screen.dart`
- The width will scale automatically to maintain aspect ratio

