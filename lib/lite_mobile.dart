/// LITE MOBILE ENTRY POINT (Android / iOS)
///
/// Bare-minimum app for basic users. Only includes screens with lite=true
/// in lib/config/platform_screens.dart (and Supabase screen_platforms.lite).
/// Build with:
///
///   flutter build apk -t lib/lite_mobile.dart
///   flutter build ios -t lib/lite_mobile.dart
///
/// See PLATFORM_CONFIG.md for full vs mobile vs lite.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/location/location_service.dart';
import 'package:dwce_time_tracker/modules/messaging/messaging_service.dart';
import 'package:dwce_time_tracker/app_config.dart';
import 'package:dwce_time_tracker/screens/login_screen.dart';
import 'package:dwce_time_tracker/screens/main_menu_screen_lite.dart';

import 'web_supabase_expose_stub.dart'
    if (dart.library.html) 'web_supabase_expose.dart' as web_expose;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    String? supabaseUrl;
    String? supabaseAnonKey;

    if (kIsWeb) {
      try {
        final response = await http.get(Uri.parse('config.json'));
        if (response.statusCode == 200) {
          final config = jsonDecode(response.body) as Map<String, dynamic>;
          supabaseUrl = config['SUPABASE_URL'] as String?;
          supabaseAnonKey = config['SUPABASE_ANON_KEY'] as String?;
        }
      } catch (e) {
        print('⚠️ Could not load config.json: $e');
      }
    }

    if (supabaseUrl == null || supabaseAnonKey == null) {
      try {
        await dotenv.load(fileName: '.env');
        supabaseUrl = supabaseUrl ?? dotenv.env['SUPABASE_URL'];
        supabaseAnonKey = supabaseAnonKey ?? dotenv.env['SUPABASE_ANON_KEY'];
      } catch (e) {
        if (kIsWeb) {
          supabaseUrl = supabaseUrl ?? dotenv.env['SUPABASE_URL'];
          supabaseAnonKey = supabaseAnonKey ?? dotenv.env['SUPABASE_ANON_KEY'];
        } else {
          rethrow;
        }
      }
    }

    if (supabaseUrl == null || supabaseUrl.isEmpty ||
        supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
      throw Exception(
        'Missing Supabase credentials. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env'
      );
    }

    await SupabaseService.initialize(url: supabaseUrl!, anonKey: supabaseAnonKey!);

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
    print('❌ Fatal error: $e');
    print('Stack trace: $stackTrace');
    runApp(ErrorApp(error: e.toString()));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DWCE Time Tracker (Lite)',
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
                Text('Application Error', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                const SizedBox(height: 16),
                SelectableText(error, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
