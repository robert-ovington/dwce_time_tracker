import 'dart:io' show Platform;

/// Used on Android, iOS, Windows, macOS, Linux.
/// isMobile is true only on Android and iOS.

bool get isMobile => Platform.isAndroid || Platform.isIOS;
