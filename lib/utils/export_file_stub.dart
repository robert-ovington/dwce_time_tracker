/// Cross-platform file export helper (stub).
///
/// Real implementations:
/// - Web: triggers browser download
/// - IO: writes to app documents directory
Future<String?> saveTextFile({
  required String filename,
  required String contents,
  required String mimeType,
}) async {
  // Not supported on this platform.
  return null;
}

