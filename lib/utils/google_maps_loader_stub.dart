/// Stub implementation for non-web platforms
/// This file is used when dart:html and dart:js are not available

import 'dart:async';

/// Load Google Maps API on web platforms
/// Returns a Future that completes when the API is ready to use
/// On non-web platforms, this is a no-op
Future<void> loadGoogleMapsApiImpl() async {
  // No-op on non-web platforms
  return;
}
