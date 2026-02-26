# MacBook Pro Setup Guide: Building DWCE Time Tracker for iPhone

This guide walks you through setting up a MacBook Pro to compile the **dwce_time_tracker** Flutter project and produce an installable app for iPhone (simulator, device, or App Store–ready archive).

---

## Prerequisites

- A MacBook Pro (or any Mac) running a recent macOS (e.g. Sonoma or later).
- An Apple ID (free) for running on your own device; an Apple Developer account ($99/year) if you need TestFlight or App Store distribution.
- The project already runs and builds on your Windows PC.

---

## Part 1: Software to Install on Your MacBook

### Step 1.1: Xcode (required for iOS builds)

1. Open **App Store** on your Mac.
2. Search for **Xcode** and click **Get** / **Install** (it’s large, ~12 GB+).
3. After installation, open **Xcode** once.
4. Accept the license agreement.
5. In the menu bar: **Xcode → Settings → Locations**. Ensure **Command Line Tools** is set to your Xcode version (e.g. “Xcode 16.x”).

### Step 1.2: Xcode Command Line Tools (if not already installed)

If you use the terminal before installing full Xcode, macOS may prompt you to install Command Line Tools. You can also install them explicitly:

```bash
xcode-select --install
```

Choose **Install** in the dialog. Full Xcode (Step 1.1) includes these; having both is fine.

### Step 1.3: Homebrew (recommended for installing other tools)

1. Open **Terminal** (Applications → Utilities → Terminal, or Spotlight: `Cmd+Space` → “Terminal”).
2. Install Homebrew from [https://brew.sh](https://brew.sh):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

3. Follow the on-screen instructions. At the end, it may ask you to add Homebrew to your `PATH` (e.g. run two `echo` commands it prints).

### Step 1.4: Git (if not already present)

macOS often includes Git. Check:

```bash
git --version
```

If not installed, install via Homebrew:

```bash
brew install git
```

### Step 1.5: Flutter SDK

1. **Download Flutter** for macOS from: [https://docs.flutter.dev/get-started/install/macos](https://docs.flutter.dev/get-started/install/macos)  
   - Or use the direct download: [https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_*.zip](https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_stable.zip) (Apple Silicon) or the **x64** zip for Intel Macs.

2. **Unzip** the archive to a folder, e.g. your home directory:
   - Example: `~/development/flutter` (avoid paths with spaces or special characters).

3. **Add Flutter to your PATH** by editing your shell config:
   - For **zsh** (default on recent macOS): `nano ~/.zshrc`  
   - For **bash**: `nano ~/.bash_profile`  
   Add this line (adjust the path to where you unzipped Flutter):

   ```bash
   export PATH="$PATH:$HOME/development/flutter/bin"
   ```

   Save (in nano: `Ctrl+O`, Enter, then `Ctrl+X`).

4. **Reload your shell** (or open a new Terminal window):

   ```bash
   source ~/.zshrc
   # or: source ~/.bash_profile
   ```

5. **Run the Flutter doctor** to check the setup:

   ```bash
   flutter doctor
   ```

   Fix any reported issues. For iOS you want:
   - [✓] Flutter
   - [✓] Xcode
   - [✓] CocoaPods (Flutter doctor will suggest installing it if missing)

### Step 1.6: CocoaPods (iOS dependency manager)

Flutter’s iOS build uses CocoaPods. Install with:

```bash
sudo gem install cocoapods
```

If you use a Ruby version manager (rbenv, rvm) or get permission errors, you can use:

```bash
brew install cocoapods
```

Run once more:

```bash
flutter doctor
```

and ensure the iOS toolchain and CocoaPods are OK.

---

## Part 2: Syncing the Project from Your PC to Your MacBook

The project is not in a Git repo on your PC, so you have three practical options.

### Option A: Put the project in Git, then clone on the Mac (recommended)

1. **On your PC:**  
   - Initialize a Git repo in the project folder (if not already):
     ```bash
     cd c:\Users\robie\dwce_time_tracker
     git init
     ```
   - Create a `.gitignore` (you already have one; ensure `.env` and secrets are ignored).
   - Create a repository on **GitHub**, **GitLab**, or **Bitbucket** (e.g. `your-username/dwce_time_tracker`).
   - Add the remote and push:
     ```bash
     git add .
     git commit -m "Initial commit"
     git remote add origin https://github.com/your-username/dwce_time_tracker.git
     git push -u origin main
     ```
     (Use `master` if your default branch is `master`.)

2. **On your MacBook:**  
   - Open Terminal and go to a folder where you keep projects, e.g. `cd ~/projects`.
   - Clone the repo:
     ```bash
     git clone https://github.com/your-username/dwce_time_tracker.git
     cd dwce_time_tracker
     ```
   - **Copy the `.env` file from your PC to the Mac** (e.g. USB drive, email yourself, or secure cloud). Place it in the project root:
     ```bash
     # After copying .env into the project folder:
     ls -la .env
     ```
   - Do **not** commit `.env` to Git; it contains secrets and is in `.gitignore`.

**Ongoing workflow:** On PC: `git add .` → `git commit -m "message"` → `git push`. On Mac: `git pull` in the project folder, then build.

---

### Option B: Cloud folder sync (OneDrive, Dropbox, Google Drive)

1. **On your PC:**  
   - Move or copy the project folder into a synced folder (e.g. OneDrive → `OneDrive/dwce_time_tracker`).

2. **On your MacBook:**  
   - Install the same cloud client (OneDrive/Dropbox/Google Drive) and sign in.
   - Wait for the folder to sync.
   - Open Terminal and go to the synced project path, e.g.:
     ```bash
     cd ~/OneDrive/dwce_time_tracker
     # or
     cd ~/Dropbox/dwce_time_tracker
     ```
   - Ensure **`.env`** is present in the project root (some cloud clients skip hidden files; copy it manually if needed).

**Note:** Build artifacts (e.g. `build/`, `ios/Pods/`) can slow sync and cause conflicts. You can add them to the cloud client’s “ignore” list or use Git (Option A) for code and only sync when needed.

---

### Option C: Manual copy (USB drive or network share)

1. **On your PC:**  
   - Zip the project folder (excluding large caches if possible), or copy the whole folder to a USB drive or network share.  
   - Exclude `build/` and `ios/Pods/` if you want a smaller copy (Flutter will regenerate them).

2. **On your MacBook:**  
   - Copy the folder from the USB/share to a local path, e.g. `~/projects/dwce_time_tracker`.
   - Ensure **`.env`** is in the project root (copy it separately if it was not in the archive).

3. **For future updates:** Repeat the copy and overwrite, or switch to Git (Option A) for easier updates.

---

## Part 3: One-time project setup on the MacBook

Run these in the project directory (e.g. `~/projects/dwce_time_tracker` or your synced path).

### Step 3.1: Get Flutter dependencies

```bash
cd ~/projects/dwce_time_tracker   # or your actual path
flutter pub get
```

### Step 3.2: Install iOS CocoaPods

```bash
cd ios
pod install
cd ..
```

If you see Ruby or CocoaPods errors, ensure CocoaPods is installed (see Step 1.6) and that you’re using a compatible Ruby (Xcode’s or Homebrew’s).

### Step 3.3: Confirm `.env` is present

The app reads Supabase config from `.env` (see `lib/main.dart`). The file is in `.gitignore`, so it will not come from Git.

- Copy `.env` from your PC to the project root on the Mac (if you used Option A or C).
- It should contain at least:
  - `SUPABASE_URL=...`
  - `SUPABASE_ANON_KEY=...`
- You can use `.env.example` as a template (fill in real values; do not commit `.env`).

---

## Part 4: Commands to build and run for iPhone

All commands are run from the **project root** on your MacBook.

### List connected devices and simulators

```bash
flutter devices
```

You’ll see connected iPhones and available iOS simulators.

### Run on an iPhone simulator (no physical device)

```bash
# Default (full) app
flutter run -d "iPhone 16" -t lib/main.dart

# Mobile-only app (smaller; recommended for phones)
flutter run -t lib/main_mobile.dart -d "iPhone 16"

# Lite app
flutter run -t lib/lite_mobile.dart -d "iPhone 16"
```

Replace `"iPhone 16"` with the simulator name from `flutter devices`.

### Run on a physical iPhone (connected via USB)

1. Connect the iPhone and unlock it; tap **Trust** if asked.
2. On the Mac: **Xcode → Settings → Accounts** → add your Apple ID if needed.
3. In Xcode, open the iOS project once and set the **Team** for the **Runner** target (Signing & Capabilities) to your Apple ID team.
4. In Terminal:

   ```bash
   flutter run -t lib/main_mobile.dart -d <device_id>
   ```

   Use the device id from `flutter devices` (e.g. a long hex string or device name).

### Build an iOS release (for archive or device)

This produces the Xcode project/archive that you can then run or archive for distribution.

```bash
# Mobile app (recommended for iPhone)
flutter build ios -t lib/main_mobile.dart

# Lite app
flutter build ios -t lib/lite_mobile.dart

# Full app (all platforms)
flutter build ios -t lib/main.dart
```

After a successful build, the app is in `build/ios/iphoneos/` and the Xcode project is updated. You can open the app in Xcode to run on a device or create an archive.

### Open in Xcode (for archive / IPA / TestFlight)

1. Open the iOS project in Xcode:

   ```bash
   open ios/Runner.xcworkspace
   ```

   (Use the `.xcworkspace` file, not `.xcodeproj`, when using CocoaPods.)

2. In Xcode:
   - Select the **Runner** scheme and a **real device** (not a simulator) as the run destination.
   - **Product → Archive**.
   - When the archive is created, the **Organizer** window opens. From there you can:
     - **Distribute App** → **Ad Hoc** or **Development** to export an **IPA** for installation on registered devices.
     - **Distribute App** → **App Store Connect** for TestFlight or App Store (requires Apple Developer account).

### Export an IPA from the command line (optional)

After `flutter build ios`, you can use `xcodebuild` and `xcrun` to create an IPA; typically it’s easier to use **Product → Archive** and then **Distribute App** in Xcode. If you need a scripted IPA, you’d use the archive produced by Xcode and then export it via command line or Xcode’s export options.

---

## Quick reference: build types

| Build type   | Command |
|-------------|---------|
| Run (simulator) | `flutter run -t lib/main_mobile.dart -d "iPhone 16"` |
| Run (device)    | `flutter run -t lib/main_mobile.dart -d <device_id>` |
| Build iOS       | `flutter build ios -t lib/main_mobile.dart` |
| Open in Xcode   | `open ios/Runner.xcworkspace` |
| Create IPA/TestFlight | Xcode: **Product → Archive** → **Distribute App** |

---

## Troubleshooting

- **“No valid code signing” / signing errors:** In Xcode, open `ios/Runner.xcworkspace`, select the **Runner** target → **Signing & Capabilities**, choose your **Team** (Apple ID), and enable **Automatically manage signing**.
- **CocoaPods errors:** Run `cd ios && pod install && cd ..` again. If versions conflict, try `pod repo update` then `pod install`.
- **“.env not found” or Supabase errors:** Ensure `.env` exists in the project root on the Mac and contains `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- **Flutter not found:** Ensure `flutter/bin` is in your `PATH` and run `source ~/.zshrc` (or `~/.bash_profile`) in Terminal.
- **Xcode license / command line tools:** Open Xcode once, accept the license, and in **Xcode → Settings → Locations** set **Command Line Tools** to your Xcode version.

For more about platform-specific screens and entry points (`main.dart`, `main_mobile.dart`, `lite_mobile.dart`), see **PLATFORM_CONFIG.md** in the project root.
