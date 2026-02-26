/// Stub used on web where dart:io is not available.
/// On web, we consider the app as "not mobile" (web/desktop behavior).

bool get isMobile => false;
