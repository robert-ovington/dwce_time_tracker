# Web Front End Setup Guide

This guide will help you set up and deploy the DWCE Time Tracker web application.

## 📋 Prerequisites

1. **Flutter SDK** (3.1.0 or higher)
   - Download from: https://flutter.dev/docs/get-started/install
   - Verify installation: `flutter doctor`

2. **Chrome Browser** (for testing)
   - Required for Flutter web development

3. **Supabase Account**
   - Your Supabase project URL and anon key

---

## 🚀 Quick Start

### Step 1: Verify Web Support

Check that Flutter web is enabled:

```bash
flutter config --enable-web
flutter doctor
```

You should see `Chrome` listed under available devices.

### Step 2: Configure Environment Variables

Ensure your `.env` file in the project root contains:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

**Important:** Never commit your `.env` file to version control. It should already be in `.gitignore`.

### Step 3: Install Dependencies

```bash
flutter pub get
```

### Step 4: Run Locally

#### Option A: Run in Chrome (Recommended for Development)

```bash
flutter run -d chrome
```

This will:
- Build the web app
- Launch Chrome automatically
- Enable hot reload for development

#### Option B: Run on Custom Port

```bash
flutter run -d web-server --web-hostname localhost --web-port 3000
```

Then open: `http://localhost:3000`

#### Option C: Build and Serve Manually

```bash
# Build for web
flutter build web

# Serve the build (requires a local web server)
# Option 1: Using Python
cd build/web
python -m http.server 8000

# Option 2: Using Node.js http-server
npx http-server build/web -p 8000

# Option 3: Using PHP
php -S localhost:8000 -t build/web
```

Then open: `http://localhost:8000`

---

## 🏗️ Building for Production

### Build Command

```bash
flutter build web --release
```

This creates an optimized production build in `build/web/`.

### Build Options

```bash
# Build with specific base href (for subdirectory deployment)
flutter build web --release --base-href /time-tracker/

# Build with custom web renderer
flutter build web --release --web-renderer canvaskit
# or
flutter build web --release --web-renderer html
```

**Renderer Options:**
- **canvaskit** (default): Better performance, larger bundle size (~2MB)
- **html**: Smaller bundle size, slightly lower performance

---

## 🌐 Deployment Options

### Option 1: Firebase Hosting (Recommended)

Firebase Hosting is free, fast, and integrates well with Flutter.

#### Setup:

1. **Install Firebase CLI:**
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

2. **Initialize Firebase in your project:**
   ```bash
   firebase init hosting
   ```
   
   Select:
   - Public directory: `build/web`
   - Single-page app: `Yes`
   - Auto-build: `No` (we'll build manually)

3. **Create `firebase.json`** (if not created):
   ```json
   {
     "hosting": {
       "public": "build/web",
       "ignore": [
         "firebase.json",
         "**/.*",
         "**/node_modules/**"
       ],
       "rewrites": [
         {
           "source": "**",
           "destination": "/index.html"
         }
       ],
       "headers": [
         {
           "source": "**/*.@(js|css|wasm|woff|woff2)",
           "headers": [
             {
               "key": "Cache-Control",
               "value": "max-age=31536000"
             }
           ]
         }
       ]
     }
   }
   ```

4. **Build and Deploy:**
   ```bash
   flutter build web --release
   firebase deploy --only hosting
   ```

5. **Your app will be live at:**
   ```
   https://your-project-id.web.app
   ```

#### Continuous Deployment:

Create `.github/workflows/deploy.yml` for GitHub Actions:

```yaml
name: Deploy to Firebase

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter build web --release
      - uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: '${{ secrets.GITHUB_TOKEN }}'
          firebaseServiceAccount: '${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'
          channelId: live
          projectId: your-project-id
```

---

### Option 2: Netlify

Netlify offers free hosting with automatic deployments.

#### Setup:

1. **Install Netlify CLI:**
   ```bash
   npm install -g netlify-cli
   netlify login
   ```

2. **Create `netlify.toml` in project root:**
   ```toml
   [build]
     command = "flutter build web --release"
     publish = "build/web"

   [[redirects]]
     from = "/*"
     to = "/index.html"
     status = 200
   ```

3. **Deploy:**
   ```bash
   flutter build web --release
   netlify deploy --prod
   ```

   Or connect your GitHub repo to Netlify for automatic deployments.

---

### Option 3: Vercel

Vercel provides excellent performance and easy deployment.

#### Setup:

1. **Install Vercel CLI:**
   ```bash
   npm install -g vercel
   vercel login
   ```

2. **Create `vercel.json` in project root:**
   ```json
   {
     "buildCommand": "flutter build web --release",
     "outputDirectory": "build/web",
     "rewrites": [
       {
         "source": "/(.*)",
         "destination": "/index.html"
       }
     ]
   }
   ```

3. **Deploy:**
   ```bash
   flutter build web --release
   vercel --prod
   ```

---

### Option 4: GitHub Pages

Free hosting for static sites.

#### Setup:

1. **Create `.github/workflows/deploy.yml`:**
   ```yaml
   name: Deploy to GitHub Pages

   on:
     push:
       branches: [ main ]

   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v3
         - uses: subosito/flutter-action@v2
           with:
             flutter-version: '3.24.0'
         - run: flutter pub get
         - run: flutter build web --release --base-href /dwce_time_tracker/
         - uses: peaceiris/actions-gh-pages@v3
           with:
             github_token: ${{ secrets.GITHUB_TOKEN }}
             publish_dir: ./build/web
   ```

2. **Enable GitHub Pages:**
   - Go to Settings → Pages
   - Source: `gh-pages` branch
   - Your app will be at: `https://username.github.io/dwce_time_tracker/`

---

### Option 5: Traditional Web Hosting (cPanel, Apache, Nginx)

For traditional hosting providers:

1. **Build the app:**
   ```bash
   flutter build web --release
   ```

2. **Upload contents of `build/web/` to your web server:**
   - Via FTP/SFTP
   - Via cPanel File Manager
   - Via SSH/SCP

3. **Configure your web server:**

   **Apache (.htaccess):**
   ```apache
   RewriteEngine On
   RewriteBase /
   RewriteRule ^index\.html$ - [L]
   RewriteCond %{REQUEST_FILENAME} !-f
   RewriteCond %{REQUEST_FILENAME} !-d
   RewriteRule . /index.html [L]
   ```

   **Nginx:**
   ```nginx
   location / {
     try_files $uri $uri/ /index.html;
   }
   ```

---

## 🔧 Configuration

### Environment Variables for Web

The web app uses `flutter_dotenv` to load environment variables from `.env`.

**Important:** For production deployments, you have two options:

#### Option A: Build-time Environment Variables (Recommended)

1. Create different `.env` files:
   - `.env.development` (for local dev)
   - `.env.production` (for production)

2. Update your build script:
   ```bash
   # Copy production env before building
   cp .env.production .env
   flutter build web --release
   ```

3. **Note:** `.env` files are bundled into the web app, so they're visible in the browser. Only use the `anon` key (never the `service_role` key).

#### Option B: Runtime Configuration

For more security, you can load config from a separate config file:

1. Create `web/config.js`:
   ```javascript
   window.flutterConfig = {
     SUPABASE_URL: "https://your-project.supabase.co",
     SUPABASE_ANON_KEY: "your-anon-key"
   };
   ```

2. Update `web/index.html` to load it:
   ```html
   <script src="config.js"></script>
   ```

3. Modify your Dart code to read from `window.flutterConfig` instead of `.env`.

---

## 🐛 Troubleshooting

### Issue: "Flutter web is not enabled"

**Solution:**
```bash
flutter config --enable-web
flutter doctor
```

### Issue: "Environment variables not loading"

**Solution:**
1. Ensure `.env` file exists in project root
2. Check that `.env` is listed in `pubspec.yaml` assets:
   ```yaml
   flutter:
     assets:
       - .env
   ```
3. Verify `flutter_dotenv` is loaded before Supabase initialization

### Issue: "Blank white screen"

**Solution:**
1. Check browser console for errors (F12)
2. Verify Supabase credentials are correct
3. Check CORS settings in Supabase dashboard
4. Ensure you're using the `anon` key, not `service_role`

### Issue: "CORS errors"

**Solution:**
1. Go to Supabase Dashboard → Settings → API
2. Add your web domain to "Allowed CORS origins"
3. For local development, add: `http://localhost:3000`

### Issue: "Build fails"

**Solution:**
1. Clean build:
   ```bash
   flutter clean
   flutter pub get
   flutter build web --release
   ```

2. Check for platform-specific code that doesn't work on web:
   - Some packages (like `sqflite`) don't work on web
   - Use `kIsWeb` checks for platform-specific code

### Issue: "App works locally but not deployed"

**Solution:**
1. Check that all assets are included in `build/web`
2. Verify base href matches your deployment path
3. Check web server configuration (SPA routing)
4. Verify environment variables are loaded correctly

---

## 📱 Progressive Web App (PWA)

Your app is already configured as a PWA with:
- ✅ `manifest.json` for app metadata
- ✅ Icons for home screen installation
- ✅ Offline support (via Supabase caching)

### Testing PWA Features:

1. **Install on device:**
   - Chrome: Click install icon in address bar
   - Edge: Click install icon in address bar
   - Mobile: "Add to Home Screen" option

2. **Test offline:**
   - Open DevTools → Network tab
   - Enable "Offline" mode
   - App should still function (with cached data)

---

## 🔒 Security Considerations

1. **Never expose service_role key:**
   - Only use `anon` key in web app
   - Service role key should only be used server-side

2. **Row Level Security (RLS):**
   - Ensure all Supabase tables have proper RLS policies
   - Test that users can only access their own data

3. **Environment Variables:**
   - `.env` files are bundled into web builds
   - Consider using runtime configuration for sensitive data

4. **HTTPS:**
   - Always deploy with HTTPS enabled
   - Most hosting providers enable this automatically

---

## 📊 Performance Optimization

### Build Optimizations:

```bash
# Use HTML renderer for smaller bundle
flutter build web --release --web-renderer html

# Or use canvaskit for better performance
flutter build web --release --web-renderer canvaskit
```

### Code Splitting:

Flutter web automatically splits code. For manual optimization:

1. Use `deferred` imports for large modules
2. Lazy load routes/screens
3. Optimize images and assets

### Caching:

Configure your hosting provider to cache static assets:
- JS/CSS files: 1 year
- Images: 1 year
- HTML: No cache (always fetch latest)

---

## 🧪 Testing

### Run Tests:

```bash
flutter test
```

### Test on Different Browsers:

- **Chrome:** `flutter run -d chrome`
- **Edge:** `flutter run -d edge`
- **Firefox:** Install Flutter web support, then `flutter run -d web-server`

### Test Responsive Design:

Use Chrome DevTools device emulation or test on actual devices.

---

## 📚 Additional Resources

- [Flutter Web Documentation](https://flutter.dev/docs/get-started/web)
- [Supabase Flutter Guide](https://supabase.com/docs/guides/getting-started/quickstarts/flutter)
- [Firebase Hosting](https://firebase.google.com/docs/hosting)
- [Netlify Documentation](https://docs.netlify.com/)

---

## ✅ Checklist

Before deploying to production:

- [ ] Environment variables configured
- [ ] Build completes without errors
- [ ] App loads and functions correctly
- [ ] Authentication works
- [ ] All screens are accessible
- [ ] Responsive design tested
- [ ] CORS configured in Supabase
- [ ] HTTPS enabled
- [ ] PWA features tested
- [ ] Error handling tested
- [ ] Performance optimized
- [ ] Analytics/monitoring set up (optional)

---

## 🎉 You're Ready!

Your Flutter web app is now set up and ready to deploy. Choose a hosting option above and follow the steps to get your app live!

For questions or issues, check the troubleshooting section or refer to the Flutter/Supabase documentation.
