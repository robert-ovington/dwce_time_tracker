# Web Front End - Quick Start Guide

## 🚀 Get Started in 5 Minutes

### 1. Verify Setup

```bash
flutter config --enable-web
flutter doctor
```

### 2. Check Environment

Ensure `.env` file exists with:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

### 3. Run Locally

```bash
flutter run -d chrome
```

That's it! Your app should open in Chrome.

---

## 📦 Build for Production

### Windows:
```bash
build_web.bat
```

### Manual:
```bash
flutter build web --release
```

Output: `build/web/` folder

---

## 🌐 Deploy Options

### Option 1: Firebase (Easiest)

1. Install Firebase CLI:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

2. Initialize:
   ```bash
   firebase init hosting
   ```
   - Public directory: `build/web`
   - Single-page app: `Yes`

3. Deploy:
   ```bash
   deploy_firebase.bat
   ```
   Or manually:
   ```bash
   flutter build web --release
   firebase deploy --only hosting
   ```

### Option 2: Netlify

1. Create `netlify.toml`:
   ```toml
   [build]
     command = "flutter build web --release"
     publish = "build/web"
   ```

2. Deploy:
   ```bash
   flutter build web --release
   netlify deploy --prod
   ```

### Option 3: Any Web Host

1. Build:
   ```bash
   flutter build web --release
   ```

2. Upload `build/web/` contents to your web server

---

## 🔧 Common Commands

```bash
# Run in Chrome
flutter run -d chrome

# Run on custom port
flutter run -d web-server --web-hostname localhost --web-port 3000

# Build for production
flutter build web --release

# Build with HTML renderer (smaller)
flutter build web --release --web-renderer html

# Clean and rebuild
flutter clean
flutter pub get
flutter build web --release
```

---

## ⚠️ Important Notes

1. **Environment Variables**: `.env` file is bundled into the web build. Only use the `anon` key, never the `service_role` key.

2. **CORS**: Add your web domain to Supabase Dashboard → Settings → API → Allowed CORS origins

3. **HTTPS**: Always use HTTPS in production (most hosts enable this automatically)

4. **Base Path**: If deploying to a subdirectory, use:
   ```bash
   flutter build web --release --base-href /your-path/
   ```

---

## 🐛 Troubleshooting

**Blank screen?**
- Check browser console (F12)
- Verify Supabase credentials
- Check CORS settings

**Build fails?**
```bash
flutter clean
flutter pub get
flutter build web --release
```

**CORS errors?**
- Add your domain to Supabase CORS settings
- For local dev: add `http://localhost:3000`

---

## 📚 Full Documentation

See `WEB_SETUP_GUIDE.md` for complete setup instructions, deployment options, and troubleshooting.

---

## ✅ Quick Checklist

- [ ] Flutter web enabled
- [ ] `.env` file configured
- [ ] App runs locally
- [ ] Build completes successfully
- [ ] CORS configured in Supabase
- [ ] Deployed to hosting provider
- [ ] HTTPS enabled
- [ ] Tested on different browsers

---

**Need help?** Check `WEB_SETUP_GUIDE.md` for detailed instructions.
