// Stub file for non-web platforms
// This file provides empty implementations of web-only functionality

library auth_service_stub;

class Window {
  Location get location => Location();
  History get history => History();
}

class Location {
  String get href => '';
  String get pathname => '';
}

class History {
  void replaceState(dynamic state, String title, String? url) {
    // No-op on non-web platforms
  }
}

final window = Window();
