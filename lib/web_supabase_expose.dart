// Web-specific implementation to expose Supabase URL to window
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void exposeSupabaseUrlToWindow(String? url, [String? anonKey]) {
  try {
    if (url != null) {
      html.window.localStorage['SUPABASE_URL'] = url;
    }
    if (anonKey != null) {
      html.window.localStorage['SUPABASE_ANON_KEY'] = anonKey;
    }
    // Also dispatch a custom event
    html.window.document.dispatchEvent(
      html.CustomEvent('supabaseReady', detail: {'url': url, 'anonKey': anonKey})
    );
    print('✅ Exposed Supabase URL and anon key to window for Google Maps');
  } catch (e) {
    print('⚠️ Could not expose Supabase URL to window: $e');
  }
}
