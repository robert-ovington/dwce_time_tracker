# Web App Troubleshooting Guide

## Issue: "Loading DWCE Time Tracker..." Screen Stuck

If you see the loading screen but the app never loads, follow these steps:

### Step 1: Check Browser Console

1. Open the browser console:
   - **Chrome/Edge:** Press `F12` or `Ctrl+Shift+I`
   - **Firefox:** Press `F12` or `Ctrl+Shift+K`

2. Look for errors in the **Console** tab (red text)

3. Common errors you might see:
   - `Failed to load .env file`
   - `Supabase initialization error`
   - `TypeError: Cannot read property...`
   - `CORS error`

### Step 2: Verify .env File

1. Check that `.env` file exists in project root (not in `build/web`)
2. Verify it contains:
   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   ```
3. **Important:** No quotes around values, no spaces around `=`

### Step 3: Check if .env is in Assets

1. Verify `pubspec.yaml` includes:
   ```yaml
   flutter:
     assets:
       - .env
   ```

2. Rebuild if you added it:
   ```bash
   flutter clean
   flutter pub get
   flutter build web --release
   ```

### Step 4: Test .env Loading

1. After building, check if `.env` is in `build/web/assets/`
2. Open `http://localhost:8000/assets/.env` in browser
3. You should see your environment variables

### Step 5: Check Supabase Configuration

1. Verify Supabase URL and key are correct
2. Test Supabase connection:
   - Go to Supabase Dashboard
   - Check if project is active
   - Verify API keys are correct

### Step 6: Check CORS Settings

1. Go to Supabase Dashboard → Settings → API
2. Add to "Allowed CORS origins":
   - `http://localhost:8000` (for local testing)
   - Your production domain (for deployment)

---

## Common Errors and Solutions

### Error: "Failed to load .env file"

**Solution:**
1. Ensure `.env` is in project root
2. Rebuild: `flutter clean && flutter build web --release`
3. Check `build/web/assets/.env` exists after build

### Error: "Supabase initialization error"

**Solution:**
1. Check `.env` file has correct values
2. Verify no extra quotes or spaces
3. Test Supabase connection manually

### Error: "CORS policy" or "Access-Control-Allow-Origin"

**Solution:**
1. Add your domain to Supabase CORS settings
2. For local: `http://localhost:8000`
3. For production: your full domain URL

### Error: Blank white screen

**Solution:**
1. Check browser console for JavaScript errors
2. Verify all files loaded (check Network tab)
3. Try different browser
4. Clear browser cache

### Error: "TypeError" or JavaScript errors

**Solution:**
1. Check browser console for full error
2. Verify Flutter version compatibility
3. Try rebuilding: `flutter clean && flutter build web --release`

---

## Debug Steps

### 1. Enable Verbose Logging

Add to `lib/main.dart` before `runApp`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Enable debug mode
  if (kDebugMode) {
    print('🔍 Debug mode enabled');
  }
  
  try {
    await dotenv.load();
    print('✅ .env file loaded');
    print('📋 SUPABASE_URL: ${dotenv.env['SUPABASE_URL']?.substring(0, 20)}...');
    
    // ... rest of code
  } catch (e) {
    print('❌ Error: $e');
    rethrow;
  }
}
```

### 2. Check Network Tab

1. Open DevTools → Network tab
2. Reload page
3. Check for failed requests (red)
4. Look for:
   - `main.dart.js` - should be 200 OK
   - `.env` - should be 200 OK
   - Supabase API calls - check status

### 3. Test with Hardcoded Values (Temporary)

If `.env` isn't working, temporarily hardcode values in `main.dart`:

```dart
await SupabaseService.initialize(
  url: 'https://your-project.supabase.co',
  anonKey: 'your-anon-key-here',
);
```

**⚠️ Remove hardcoded values before deploying!**

---

## Quick Fixes

### Fix 1: Rebuild Everything

```bash
flutter clean
flutter pub get
flutter build web --release
```

### Fix 2: Check .env Format

Ensure `.env` file format is correct:
```env
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Wrong:**
```env
SUPABASE_URL="https://xxxxx.supabase.co"  # No quotes
SUPABASE_URL = https://xxxxx.supabase.co  # No spaces
```

### Fix 3: Verify Build Output

After building, check:
- `build/web/main.dart.js` exists
- `build/web/assets/.env` exists
- `build/web/index.html` exists

### Fix 4: Test in Different Browser

Sometimes browser extensions or cache cause issues:
- Try incognito/private mode
- Try different browser
- Clear browser cache

---

## Still Not Working?

1. **Check Flutter Version:**
   ```bash
   flutter --version
   ```
   Should be 3.1.0 or higher

2. **Check Dependencies:**
   ```bash
   flutter pub get
   flutter pub upgrade
   ```

3. **Run in Development Mode:**
   ```bash
   flutter run -d chrome
   ```
   This gives better error messages

4. **Check for Platform-Specific Code:**
   - Some packages don't work on web
   - Check for `kIsWeb` guards in code
   - Look for mobile-only packages

5. **Get Help:**
   - Share browser console errors
   - Share Flutter version
   - Share `.env` file format (without actual keys)
   - Share build output

---

## Prevention

To avoid issues in the future:

1. ✅ Always test locally before deploying
2. ✅ Check browser console regularly
3. ✅ Keep `.env` file secure (never commit)
4. ✅ Use proper error handling
5. ✅ Test in multiple browsers
6. ✅ Verify CORS settings before deployment

---

## Success Indicators

When everything works, you should see:

1. ✅ Loading screen disappears
2. ✅ Login screen appears
3. ✅ No errors in browser console
4. ✅ Network tab shows successful requests
5. ✅ Supabase connection works

---

**Need more help?** Check the browser console and share the specific error message.
