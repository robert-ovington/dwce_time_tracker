/// MOBILE ENTRY POINT (Android / iOS)
///
/// Use this for smaller APK/IPA builds that exclude desktop-only screens
/// (e.g. New Message, Message Log, Message Template). Build with:
///
///   flutter build apk -t lib/main_mobile.dart
///   flutter build ios -t lib/main_mobile.dart
///
/// For web/Windows use the default: flutter run / flutter build web / flutter build windows

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/location/location_service.dart';
import 'package:dwce_time_tracker/modules/messaging/messaging_service.dart';
import 'package:dwce_time_tracker/app_config.dart';
import 'package:flutter/services.dart';
import 'package:dwce_time_tracker/screens/login_screen.dart';
import 'package:dwce_time_tracker/screens/main_menu_screen_mobile.dart';

// Conditional import for web
import 'web_supabase_expose_stub.dart'
    if (dart.library.html) 'web_supabase_expose.dart' as web_expose;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On Android, auto-hide system navigation bar for more screen space
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  try {
    String? supabaseUrl;
    String? supabaseAnonKey;

    if (kIsWeb) {
      try {
        print('🔍 Attempting to load config.json...');
        final response = await http.get(Uri.parse('config.json'));
        print('🔍 config.json response status: ${response.statusCode}');
        if (response.statusCode == 200) {
          print('🔍 config.json body: ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}...');
          final config = jsonDecode(response.body) as Map<String, dynamic>;
          supabaseUrl = config['SUPABASE_URL'] as String?;
          supabaseAnonKey = config['SUPABASE_ANON_KEY'] as String?;
          if (supabaseUrl != null && supabaseAnonKey != null) {
            print('✅ Loaded config from config.json');
          } else {
            print('⚠️ config.json loaded but values are null');
          }
        } else {
          print('⚠️ config.json returned status ${response.statusCode}');
        }
      } catch (e, stackTrace) {
        print('⚠️ Could not load config.json: $e');
        print('⚠️ Stack trace: $stackTrace');
      }
    }

    if (supabaseUrl == null || supabaseAnonKey == null) {
      try {
        await dotenv.load(fileName: '.env');
        print('✅ Loaded .env file');
        supabaseUrl = supabaseUrl ?? dotenv.env['SUPABASE_URL'];
        supabaseAnonKey = supabaseAnonKey ?? dotenv.env['SUPABASE_ANON_KEY'];
      } catch (e) {
        if (kIsWeb) {
          print('⚠️ Could not load .env file during hot reload');
          try {
            supabaseUrl = supabaseUrl ?? dotenv.env['SUPABASE_URL'];
            supabaseAnonKey = supabaseAnonKey ?? dotenv.env['SUPABASE_ANON_KEY'];
            if (supabaseUrl != null && supabaseAnonKey != null) {
              print('✅ Using existing dotenv values from previous load');
            }
          } catch (e2) {
            print('⚠️ Dotenv not initialized - .env file required');
          }
        } else {
          rethrow;
        }
      }
    }

    if (supabaseUrl == null || supabaseUrl.isEmpty ||
        supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
      throw Exception(
        'Missing Supabase credentials.\n'
        'Please ensure SUPABASE_URL and SUPABASE_ANON_KEY are set in your .env file.'
      );
    }

    print('🔍 Using Supabase URL: $supabaseUrl');
    print('🔍 Anon key length: ${supabaseAnonKey.length} characters');

    await SupabaseService.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    if (kIsWeb) {
      web_expose.exposeSupabaseUrlToWindow(supabaseUrl, supabaseAnonKey);
    }

    await LocationService.initialize();
    await MessagingService.initialize();

    runApp(
      AppConfig(
        postLoginScreenBuilder: () => const MainMenuScreen(),
        child: const MyApp(),
      ),
    );
  } catch (e, stackTrace) {
    print('❌ Fatal error during app initialization: $e');
    print('Stack trace: $stackTrace');
    runApp(ErrorApp(error: e.toString()));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DWCE Time Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String error;

  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DWCE Time Tracker - Error',
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade700),
                const SizedBox(height: 24),
                Text(
                  'Application Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: SelectableText(
                    error,
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
