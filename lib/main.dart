/// MAIN ENTRY POINT
/// 
/// This file initializes your app and Supabase connection.
/// 
/// SETUP:
/// 1. Replace 'YOUR_SUPABASE_URL' and 'YOUR_SUPABASE_ANON_KEY' with your actual values
///    OR read them from your pubspec.yaml if you stored them there
/// 2. Run: flutter pub get
/// 3. Run: flutter run

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/location/location_service.dart';
import 'package:dwce_time_tracker/modules/messaging/messaging_service.dart';
import 'package:dwce_time_tracker/app_config.dart';
import 'package:dwce_time_tracker/screens/login_screen.dart';
import 'package:dwce_time_tracker/screens/main_menu_screen.dart';

// Conditional import for web
import 'web_supabase_expose_stub.dart'
    if (dart.library.html) 'web_supabase_expose.dart' as web_expose;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Try to load environment variables from .env file
    String? supabaseUrl;
    String? supabaseAnonKey;
    
    // Try to load config from config.json first (for web deployment)
    if (kIsWeb) {
      try {
        print('🔍 Attempting to load config.json...');
        final response = await http.get(Uri.parse('config.json'));
        print('🔍 config.json response status: ${response.statusCode}');
        if (response.statusCode == 200) {
          final body = response.body.trim();
          final isJson = body.isNotEmpty && !body.startsWith('<');
          if (isJson) {
            print('🔍 config.json body: ${body.length > 100 ? "${body.substring(0, 100)}..." : body}');
            final config = jsonDecode(body) as Map<String, dynamic>;
            supabaseUrl = config['SUPABASE_URL'] as String?;
            supabaseAnonKey = config['SUPABASE_ANON_KEY'] as String?;
            print('🔍 Parsed URL: ${supabaseUrl != null ? "found (${supabaseUrl.length} chars)" : "null"}');
            print('🔍 Parsed Key: ${supabaseAnonKey != null ? "found (${supabaseAnonKey.length} chars)" : "null"}');
            if (supabaseUrl != null && supabaseAnonKey != null) {
              print('✅ Loaded config from config.json');
            } else {
              print('⚠️ config.json loaded but values are null');
            }
          } else {
            print('⚠️ config.json returned non-JSON (e.g. HTML); using .env fallback');
          }
        } else {
          print('⚠️ config.json returned status ${response.statusCode}');
        }
      } catch (e, stackTrace) {
        print('⚠️ Could not load config.json: $e');
        print('⚠️ Stack trace: $stackTrace');
      }
    }
    
    // Fallback to .env file if config.json didn't work
    if (supabaseUrl == null || supabaseAnonKey == null) {
      try {
        await dotenv.load(fileName: '.env');
        print('✅ Loaded .env file');
        supabaseUrl = supabaseUrl ?? dotenv.env['SUPABASE_URL'];
        supabaseAnonKey = supabaseAnonKey ?? dotenv.env['SUPABASE_ANON_KEY'];
      } catch (e) {
        // For web, .env might not be available during hot reload
        // Try to use existing values if dotenv was previously loaded
        if (kIsWeb) {
          print('⚠️ Could not load .env file during hot reload');
          print('⚠️ Attempting to use existing dotenv values if available');
          try {
            // Try to access existing values (only works if dotenv was loaded before)
            supabaseUrl = supabaseUrl ?? dotenv.env['SUPABASE_URL'];
            supabaseAnonKey = supabaseAnonKey ?? dotenv.env['SUPABASE_ANON_KEY'];
            if (supabaseUrl != null && supabaseAnonKey != null) {
              print('✅ Using existing dotenv values from previous load');
            }
          } catch (e2) {
            // dotenv not initialized - this is expected on first run
            print('⚠️ Dotenv not initialized - .env file required');
          }
        } else {
          // For mobile, rethrow the error
          rethrow;
        }
      }
    }
    
    // Verify we have the required credentials
    if (supabaseUrl == null || supabaseUrl.isEmpty || 
        supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
      throw Exception(
        'Missing Supabase credentials.\n'
        'Please ensure SUPABASE_URL and SUPABASE_ANON_KEY are set in your .env file.\n\n'
        'For web development:\n'
        '1. Create a .env file in the project root\n'
        '2. Add: SUPABASE_URL=your_url\n'
        '3. Add: SUPABASE_ANON_KEY=your_key\n'
        '4. Restart the app (hot reload won\'t pick up new .env files)'
      );
    }
    
    // Debug: Print the URL being used (without the key for security)
    print('🔍 Using Supabase URL: $supabaseUrl');
    print('🔍 Anon key length: ${supabaseAnonKey.length} characters');
    
    // Initialize Supabase using values from .env file
    await SupabaseService.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    
    // Expose Supabase URL to window for Google Maps API key loading (web only)
    if (kIsWeb) {
      web_expose.exposeSupabaseUrlToWindow(supabaseUrl, supabaseAnonKey);
    }
    
    // Initialize location service
    await LocationService.initialize();
    
    // Initialize messaging service
    await MessagingService.initialize();
    
    runApp(
      AppConfig(
        postLoginScreenBuilder: () => const MainMenuScreen(),
        child: const MyApp(),
      ),
    );
  } catch (e, stackTrace) {
    // Log error to console
    print('❌ Fatal error during app initialization: $e');
    print('Stack trace: $stackTrace');
    
    // Run error app to display error message
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
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final padding = MediaQuery.paddingOf(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: padding.copyWith(
              bottom: math.max(padding.bottom, 17),
            ),
          ),
          child: child,
        );
      },
      home: const LoginScreen(),
    );
  }
}

/// Error display widget shown when app fails to initialize
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
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.shade700,
                ),
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Please reload the page (F5) or close and reopen the browser.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Check the browser console (F12) for more details.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
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
