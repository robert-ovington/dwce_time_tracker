# Android App Flow: From Launch to Main Menu

This document describes what happens when a user opens the Android app and logs in, written in plain English.

---

## Phase 1: App Startup

When you tap the app icon on your Android phone, the following happens:

### 1. Flutter Initializes
- The app starts up and prepares the Flutter framework.
- This happens before anything appears on screen.

### 2. Load Supabase Credentials
- The app reads the `.env` file from the device to get:
  - **Supabase URL** – the address of your cloud database.
  - **Supabase Anon Key** – the password to connect to the database.
- If these are missing, the app shows an error screen and stops.

### 3. Connect to Supabase
- The app connects to Supabase (your cloud database).
- This is needed for login, user data, messages, and everything else.

### 4. Initialize Location Service
- The app prepares the location service (GPS).
- It does not request location permission yet – just gets ready.

### 5. Initialize Messaging Service
- The app prepares the messaging service.
- This sets up push notifications and message checking.

### 6. Show Login Screen
- Once everything is ready, the app shows the **Login Screen**.
- If initialization failed at any step, an error screen is shown instead.

---

## Phase 2: Login Screen

The user now sees the login form.

### 1. Check for Saved Credentials
- When the login screen opens, it checks if the user previously selected "Remember Me".
- If yes, it loads the saved email and password from secure storage.
- The password is stored encrypted (using Android's EncryptedSharedPreferences).

### 2. User Enters Credentials
- If credentials were saved, they are pre-filled.
- Otherwise, the user types their email and password.

### 3. User Taps "Login"
- The app validates the form (checks email format, password not empty).
- Shows a loading spinner.

### 4. Authenticate with Supabase
- The app sends the email and password to Supabase.
- Supabase checks if the credentials are correct.
- If wrong, an error message appears: "Invalid email or password."

### 5. Save Credentials (if Remember Me is checked)
- If login succeeds and "Remember Me" is ticked, the app saves:
  - Email in SharedPreferences (simple storage).
  - Password in FlutterSecureStorage (encrypted storage).
- Next time the user opens the app, credentials will be pre-filled.

### 6. Check Location Services
- After login, the app checks if GPS/location is enabled.
- If not enabled, it may prompt the user to turn on location.
- This runs in the background (doesn't block navigation).
- If location is enabled, the app "warms up" the GPS to get a fresh location fix.

### 7. Check for Important Messages
- Before going to the main menu, the app checks for "important" messages.
- If there are unread important messages, a dialog pops up.
- The user must read (or dismiss) all important messages before continuing.
- This blocks navigation until done.

### 8. Navigate to Main Menu
- Once important messages are handled, the app replaces the login screen with the **Main Menu Screen**.

---

## Phase 3: Main Menu Screen

The user now sees the main menu with all available features.

### 1. Show Loading Indicator
- While data loads, a spinning circle appears.

### 2. Load User Data
- The app fetches from Supabase:
  - **User Setup** – settings specific to this user (from `users_setup` table).
  - **User Data** – display name, role, security level (from `users_data` table).
  - **Menu Permissions** – which menu items this user can see (from `users_setup` table).
  - **Dashboard Enabled** – whether to show the dashboard (from user settings).
  - **Current User Email** – from the logged-in Supabase session.

### 3. Check Network Connectivity
- The app checks if the phone is online (WiFi, mobile data, etc.).
- It subscribes to connectivity changes so the UI can show "Online" or "Offline".

### 4. Check Important Messages (again)
- After the menu loads, the app checks for important messages one more time.
- If any are found, a dialog appears.
- After reading them, the app checks for new regular messages.

### 5. Start Periodic Message Checks
- The app sets a timer to check for important messages every 5 minutes.
- This keeps running while the menu is open.

### 6. Build the Menu
- The app builds the menu based on the user's permissions.
- Each menu section (Clock In, Timesheets, Administration, etc.) only appears if the user has permission.
- For example:
  - `menu_clock_in = true` → Clock In section appears.
  - `menu_administration = true` → Administration section appears.
  - `menu_messenger = true` **and** not on mobile → Messenger section appears (web/desktop only).

### 7. Hide Loading, Show Menu
- Once everything is loaded, the loading spinner disappears.
- The full menu is displayed.
- The user can now tap any menu item to navigate to that screen.

---

## Summary Flowchart

```
[App Icon Tapped]
       │
       ▼
[Initialize Flutter]
       │
       ▼
[Load .env credentials] ─── (missing) ──→ [Error Screen] ──→ STOP
       │
       (found)
       ▼
[Connect to Supabase]
       │
       ▼
[Initialize Location Service]
       │
       ▼
[Initialize Messaging Service]
       │
       ▼
[Show Login Screen]
       │
       ▼
[Load saved credentials if "Remember Me"]
       │
       ▼
[User enters email/password]
       │
       ▼
[User taps Login]
       │
       ▼
[Authenticate with Supabase] ─── (fail) ──→ [Show error message] ──→ (retry)
       │
       (success)
       ▼
[Save credentials if "Remember Me"]
       │
       ▼
[Check location services (background)]
       │
       ▼
[Show important messages dialog] ─── (user reads/dismisses) ──→
       │
       ▼
[Navigate to Main Menu Screen]
       │
       ▼
[Show loading spinner]
       │
       ▼
[Load user data, permissions, connectivity]
       │
       ▼
[Check important messages (again)]
       │
       ▼
[Build menu based on permissions]
       │
       ▼
[Show Main Menu]
       │
       ▼
[User can navigate to any feature]
```

---

## Key Files Involved

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point; initializes Supabase, location, messaging |
| `lib/main_mobile.dart` | Alternative entry point for smaller mobile builds |
| `lib/screens/login_screen.dart` | Login form, authentication, credential storage |
| `lib/screens/main_menu_screen.dart` | Main menu with permission-based visibility |
| `lib/modules/auth/auth_service.dart` | Handles Supabase authentication |
| `lib/modules/users/user_service.dart` | Fetches user data and permissions |
| `lib/modules/location/location_service.dart` | GPS and location handling |
| `lib/modules/messaging/messaging_service.dart` | Message checking and notifications |
| `lib/config/supabase_config.dart` | Supabase connection configuration |

---

## Notes

- **Remember Me** uses encrypted storage so passwords are not stored in plain text.
- **Important messages** must be read before the user can use the app (blocking dialog).
- **Menu permissions** are loaded from the database, so admins can control what each user sees.
- **Connectivity status** updates in real-time (if you lose WiFi, the menu shows "Offline").
- **5-minute message checks** ensure users don't miss important announcements.
