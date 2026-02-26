/// Google Maps API Loader
/// 
/// Utility to lazily load the Google Maps JavaScript API on web platforms
/// Only loads when needed, reducing unnecessary API calls

import 'dart:async';
import 'google_maps_loader_stub.dart'
    if (dart.library.html) 'google_maps_loader_web.dart';

/// Load Google Maps API on web platforms
/// Returns a Future that completes when the API is ready to use
/// On non-web platforms, this is a no-op
Future<void> loadGoogleMapsApi() => loadGoogleMapsApiImpl();
