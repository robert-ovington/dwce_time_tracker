// Stub file for non-web platforms
// This file is used when dart:html is not available

class HttpRequest {
  static Future<String> getString(String url) async {
    throw UnimplementedError('HttpRequest not available on this platform');
  }
}
