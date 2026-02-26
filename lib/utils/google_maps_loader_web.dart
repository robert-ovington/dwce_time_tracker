/// Web-specific implementation of Google Maps API Loader
/// This file is only used on web platforms where dart:html and dart:js are available

// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

/// Load Google Maps API on web platforms
/// Returns a Future that completes when the API is ready to use
Future<void> loadGoogleMapsApiImpl() async {
  // Check if already loaded
  if (js.context.hasProperty('google') && 
      js.context['google'] != null &&
      js.context['google']['maps'] != null) {
    print('✅ Google Maps API already loaded');
    return;
  }
  
  // Call the JavaScript function defined in web/index.html
  if (!js.context.hasProperty('loadGoogleMapsApi')) {
    throw Exception('loadGoogleMapsApi function not found in window. Make sure web/index.html is loaded.');
  }
  
  try {
    // Call the function which returns a Promise
    // We'll use a polling approach since we can't easily convert JS Promise to Dart Future
    // without dart:js_util
    js.context.callMethod('loadGoogleMapsApi', []);
    
    // Poll for Google Maps to be loaded (the JS promise handles the actual loading)
    final maxWait = Duration(seconds: 30);
    final startTime = DateTime.now();
    const pollInterval = Duration(milliseconds: 100);
    
    while (DateTime.now().difference(startTime) < maxWait) {
      await Future.delayed(pollInterval);
      if (js.context.hasProperty('google') && 
          js.context['google'] != null &&
          js.context['google']['maps'] != null) {
        print('✅ Google Maps API loaded successfully');
        return;
      }
    }
    
    // Timeout - check one more time
    if (js.context.hasProperty('google') && 
        js.context['google'] != null &&
        js.context['google']['maps'] != null) {
      print('✅ Google Maps API loaded successfully');
      return;
    }
    
    throw TimeoutException('Timeout waiting for Google Maps API to load', maxWait);
  } catch (e) {
    print('❌ Exception loading Google Maps API: $e');
    rethrow;
  }
}
