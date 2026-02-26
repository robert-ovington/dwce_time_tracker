/// Platform helpers for excluding screens from mobile (Android/iOS) builds
/// while keeping them on web and Windows.
///
/// Use [isMobile] to show/hide menu items or routes:
/// - On web and Windows/macOS/Linux: isMobile = false → show all screens.
/// - On Android and iOS: isMobile = true → hide screens you want desktop-only.
///
/// Example in menu:
///   if (!isMobile && permission) _buildMenuItem('Message Log', ...),
///
/// To actually exclude code from the mobile bundle (smaller APK/IPA), use a
/// separate entry point (e.g. main_mobile.dart) that does not import
/// the desktop-only screens and use: flutter build apk -t lib/main_mobile.dart

export 'platform_utils_stub.dart'
    if (dart.library.io) 'platform_utils_io.dart';
