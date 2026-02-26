/// Screen availability per platform.
///
/// Keep in sync with Supabase table `screen_platforms`. When a screen is
/// created or removed, update that table and this config (so mobile build
/// and menu stay correct).
///
/// Screens with android or ios true are included in the mobile entry point
/// (main_mobile.dart). Screens with both false are desktop/web only and
/// are not imported in the mobile build for smaller APK/IPA.

enum AppPlatform { android, ios, web, windows }

/// Per-screen platform flags. Matches Supabase screen_platforms table.
class ScreenPlatformConfig {
  const ScreenPlatformConfig({
    required this.screenId,
    this.displayName,
    this.android = true,
    this.ios = true,
    this.web = true,
    this.windows = true,
    this.lite = false,
  });

  final String screenId;
  final String? displayName;
  final bool android;
  final bool ios;
  final bool web;
  final bool windows;
  /// Bare-minimum for "lite" mobile app (basic users).
  final bool lite;

  bool isOnPlatform(AppPlatform platform) {
    switch (platform) {
      case AppPlatform.android:
        return android;
      case AppPlatform.ios:
        return ios;
      case AppPlatform.web:
        return web;
      case AppPlatform.windows:
        return windows;
    }
  }

  bool get isOnMobile => android || ios;
  bool get isOnDesktopOrWeb => web || windows;
  bool get isOnLite => lite;
}

/// Source of truth for which screens exist and on which platforms.
/// Update when adding/removing screens; keep in sync with Supabase screen_platforms.
/// [lite] = true for bare-minimum screens in the lite mobile app.
final List<ScreenPlatformConfig> kScreenPlatforms = [
  const ScreenPlatformConfig(screenId: 'messages', displayName: 'Messages', lite: true),
  const ScreenPlatformConfig(screenId: 'new_message', displayName: 'New Message', android: false, ios: false),
  const ScreenPlatformConfig(screenId: 'message_log', displayName: 'Message Log', android: false, ios: false),
  const ScreenPlatformConfig(screenId: 'message_template', displayName: 'Message Template', android: false, ios: false),
  const ScreenPlatformConfig(screenId: 'recipient_selection', displayName: 'Recipient Selection', android: false, ios: false),
  const ScreenPlatformConfig(screenId: 'clock_in_out', displayName: 'Clock In/Out', lite: true),
  const ScreenPlatformConfig(screenId: 'my_clockings', displayName: 'My Clockings', lite: true),
  const ScreenPlatformConfig(screenId: 'clock_office', displayName: 'Clock Office'),
  const ScreenPlatformConfig(screenId: 'admin_staff_attendance', displayName: 'Attendance'),
  const ScreenPlatformConfig(screenId: 'admin_staff_summary', displayName: 'Summary'),
  const ScreenPlatformConfig(screenId: 'time_tracking', displayName: 'Time Tracking', lite: true),
  const ScreenPlatformConfig(screenId: 'my_time_periods', displayName: 'My Time Periods', lite: true),
  const ScreenPlatformConfig(screenId: 'time_clocking', displayName: 'Time Clocking', lite: true),
  const ScreenPlatformConfig(screenId: 'asset_check', displayName: 'Asset Check'),
  const ScreenPlatformConfig(screenId: 'my_checks', displayName: 'My Checks'),
  const ScreenPlatformConfig(screenId: 'delivery', displayName: 'Delivery'),
  const ScreenPlatformConfig(screenId: 'admin', displayName: 'Admin'),
  const ScreenPlatformConfig(screenId: 'user_creation', displayName: 'Create User'),
  const ScreenPlatformConfig(screenId: 'user_edit', displayName: 'Edit User'),
  const ScreenPlatformConfig(screenId: 'employer_management', displayName: 'Employer'),
  const ScreenPlatformConfig(screenId: 'pay_rate_rules', displayName: 'Pay Types'),
  const ScreenPlatformConfig(screenId: 'supervisor_approval', displayName: 'Timesheet Approval'),
  const ScreenPlatformConfig(screenId: 'plant_location_report', displayName: 'Small Plant Location Report'),
  const ScreenPlatformConfig(screenId: 'fault_management_report', displayName: 'Small Plant Fault Management'),
  const ScreenPlatformConfig(screenId: 'stock_locations_management', displayName: 'Stock Locations'),
  const ScreenPlatformConfig(screenId: 'cube_details', displayName: 'Cube Details'),
  const ScreenPlatformConfig(screenId: 'coming_soon', displayName: 'Coming Soon', lite: true),
  const ScreenPlatformConfig(screenId: 'login', displayName: 'Login', lite: true),
  const ScreenPlatformConfig(screenId: 'main_menu', displayName: 'Main Menu', lite: true),
  const ScreenPlatformConfig(screenId: 'platform_config', displayName: 'Platform Config'),
];

/// Screen IDs included in the mobile build (android or ios). Used by main_mobile
/// to know which screens to import; desktop-only screens are not imported.
Set<String> get mobileScreenIds =>
    kScreenPlatforms.where((s) => s.isOnMobile).map((s) => s.screenId).toSet();

/// Screen IDs included in the lite mobile build (bare minimum for basic users).
/// Used by lite_mobile.dart; only lite=true screens are in the lite app.
Set<String> get liteScreenIds =>
    kScreenPlatforms.where((s) => s.isOnLite).map((s) => s.screenId).toSet();

bool isScreenOnPlatform(String screenId, AppPlatform platform) {
  for (final s in kScreenPlatforms) {
    if (s.screenId == screenId) return s.isOnPlatform(platform);
  }
  return false;
}
