// Web-only implementation
import 'dart:convert';
import 'dart:html' as html;

Future<String?> saveTextFile({
  required String filename,
  required String contents,
  required String mimeType,
}) async {
  final bytes = utf8.encode(contents);
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
  // Web download has no local path to return.
  return filename;
}

