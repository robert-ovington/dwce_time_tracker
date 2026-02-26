# Platform & screen config

This doc explains how to keep **Supabase `screen_platforms`**, **Flutter `lib/config/platform_screens.dart`**, and the different app entry points in sync, and which commands to use for each build type.

---

## 1. Configs to maintain

| Config | Purpose |
|--------|--------|
| **Supabase table `screen_platforms`** | Source of truth for which screens are on Android, iOS, Web, Windows, and Lite. Used by admin/reporting; can be read at runtime. |
| **Flutter `lib/config/platform_screens.dart`** | Local mirror of the table. Drives which screens are imported in each entry point (full, mobile, lite). **Must stay in sync with the Supabase table.** |

When you **add or remove a screen**, update **both**:

1. Supabase: insert/update/delete row in `screen_platforms` (and set `android`, `ios`, `web`, `windows`, `lite` as needed).
2. Flutter: add/remove/update the corresponding entry in `kScreenPlatforms` in `lib/config/platform_screens.dart`.

---

## 2. Processes

### Adding a new screen

1. Implement the screen in `lib/screens/` (e.g. `my_new_screen.dart`).
2. **Supabase:** Insert a row into `screen_platforms`:
   - `screen_id`: e.g. `my_new_screen` (snake_case)
   - `display_name`: e.g. `My New Screen`
   - `android`, `ios`, `web`, `windows`, `lite`: set to `true`/`false` per platform.
3. **Flutter:** Add a `ScreenPlatformConfig` to `kScreenPlatforms` in `lib/config/platform_screens.dart` with the same flags.
4. Add the screen to the right menu(s):
   - **Full app** (`lib/screens/main_menu_screen.dart`): add menu item and import.
   - **Mobile app** (`lib/screens/main_menu_screen_mobile.dart`): add only if `android` or `ios` is true; import only if not desktop-only.
   - **Lite app** (`lib/screens/main_menu_screen_lite.dart`): add only if `lite` is true; import only lite screens.

### Removing a screen

1. **Supabase:** Delete the row (or soft-delete) for that `screen_id` in `screen_platforms`.
2. **Flutter:** Remove the entry from `kScreenPlatforms` in `lib/config/platform_screens.dart`.
3. Remove the screen from the menu(s) and delete (or stop importing) the screen file as needed.

### Changing platform flags (e.g. add to Lite)

1. **Supabase:** Update the row in `screen_platforms` (e.g. set `lite = true`).
2. **Flutter:** Update the corresponding `ScreenPlatformConfig` in `lib/config/platform_screens.dart`.
3. If the screen is now in the lite set, add it to `main_menu_screen_lite.dart` and ensure `lite_mobile.dart` can reach it (it only imports lite screens).

---

## 3. Build types and entry points

| Build | Entry point | Use case | Screens included |
|-------|-------------|----------|------------------|
| **Full (Web / Windows)** | `lib/main.dart` (default) | Web and Windows; all features. | All screens (android, ios, web, windows). |
| **Mobile (smaller APK/IPA)** | `lib/main_mobile.dart` | Android/iOS without desktop-only features (e.g. Messenger). | Only screens with `android` or `ios` true; Messenger etc. not imported. |
| **Lite (basic users)** | `lib/lite_mobile.dart` | Android/iOS with bare minimum (clock, messages, dashboard, etc.). | Only screens with `lite` true. |

---

## 4. Commands

### Full app (Web, Windows, or run anywhere)

```bash
# Run (default entry point = main.dart)
flutter run
flutter run -d chrome
flutter run -d windows

# Build
flutter build web
flutter build windows
```

### Mobile app (smaller; no Messenger etc.)

```bash
# Run
flutter run -t lib/main_mobile.dart -d <device_id>

# Build
flutter build apk -t lib/main_mobile.dart
flutter build ios -t lib/main_mobile.dart
```

### Lite app (bare minimum for basic users)

```bash
# Run
flutter run -t lib/lite_mobile.dart -d <device_id>

# Build
flutter build apk -t lib/lite_mobile.dart
flutter build ios -t lib/lite_mobile.dart
```

### List devices

```bash
flutter devices
```

---

## 5. Supabase migrations

- **Create/update table:** `supabase/migrations/20260123000000_screen_platforms.sql`
- **Add lite column (if table already exists without it):** `supabase/migrations/20260123100000_screen_platforms_lite.sql`

Apply with your usual Supabase workflow (e.g. `supabase db push` or run SQL in the dashboard).

---

## 6. Platform Config screen

**Main Menu → Administration → Platform Config** shows the current local config (`lib/config/platform_screens.dart`) in a table (Screen ID, Display Name, Android, iOS, Web, Windows, Lite). Use it to verify the app’s view of platform availability; keep it in sync with the Supabase table as above.

---

## 7. Web development – hot restart workaround

**Quick fix when you see the error:** Stop the app (**q** in terminal or Stop in IDE), then start again with `flutter run -d chrome` (or your Web Chrome launch config). Do **not** use hot restart (capital **R**) on web on Windows.

When running **Flutter web** (`flutter run -d chrome`), **hot restart** (capital **R** in the terminal) can trigger:

```text
Invalid argument(s): Uri org-dartlang-app:/web_plugin_registrant.dart must have scheme 'file:'.
```

This comes from Flutter tooling: during web hot restart it passes virtual `org-dartlang-app:` URIs to code that only accepts `file:` URIs (e.g. on Windows). It is a known tooling bug; there is no project-level fix.

**Workaround:** use a **full restart** instead of hot restart:

1. Stop the app (**q** in the terminal, or stop from the IDE).
2. Start again: `flutter run -d chrome` (or run the "Flutter (Web - Chrome)" launch config).

Use **hot reload** (lowercase **r**) for small edits when possible; it often does not hit this code path. If the error appears after upgrading Flutter, check the [Flutter issue tracker](https://github.com/flutter/flutter/issues) for a fix in a newer version.

**"Error when reading org-dartlang-app:/web_entrypoint.dart: File not found"** – The same workaround applies. The debugger reports a virtual path (`org-dartlang-app:/web_entrypoint.dart`) that cannot be resolved on Windows. Do a **full restart**: stop the app (**q**), then run again with `flutter run -d chrome`. The project has `web/web_entrypoint.dart` and a root stub `web_entrypoint.dart` for the IDE; the "file not found" is a tooling issue, not a missing file.
