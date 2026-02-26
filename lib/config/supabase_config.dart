/// MODULE 1: Supabase Configuration
/// 
/// This module handles the connection to your Supabase project.
/// 
/// SETUP INSTRUCTIONS:
/// 1. Make sure you have added supabase_flutter to your pubspec.yaml dependencies
/// 2. Replace 'YOUR_SUPABASE_URL' and 'YOUR_SUPABASE_ANON_KEY' with your actual values
///    (You mentioned these are already in your pubspec.yaml - you can move them here or keep them there)
/// 3. Call SupabaseService.initialize() in your main() function before runApp()
/// 
/// TESTING:
/// Run the app and check the console for "Supabase initialized successfully" message

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Store the URL for debugging purposes
  static String? _supabaseUrl;
  
  // Get the Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;
  
  // Get the Supabase URL (for debugging)
  static String? get supabaseUrl => _supabaseUrl;

  // Initialize Supabase connection
  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    try {
      // Ensure URL doesn't have trailing slash
      final cleanUrl = url.trim().replaceAll(RegExp(r'/$'), '');
      
      // Store the URL for later use
      _supabaseUrl = cleanUrl;
      
      print('🔍 Initializing Supabase with URL: $cleanUrl');
      
      await Supabase.initialize(
        url: cleanUrl,
        anonKey: anonKey,
      );
      print('✅ Supabase initialized successfully');
    } catch (e) {
      print('❌ Error initializing Supabase: $e');
      rethrow;
    }
  }

  // Check if Supabase is initialized
  static bool get isInitialized => Supabase.instance.client != null; // ignore: unnecessary_null_comparison

  // Get current user (null if not logged in)
  static User? get currentUser => client.auth.currentUser;

  // Check if user is logged in
  static bool get isLoggedIn => currentUser != null;
}

