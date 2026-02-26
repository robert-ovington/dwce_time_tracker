/// MODULE 2: Authentication Service
/// 
/// This module handles user authentication (sign up, sign in, sign out)
/// 
/// PREREQUISITES:
/// - Module 1 (Supabase Config) must be initialized
/// - In Supabase Dashboard: Go to Authentication > Settings
///   - Enable Email provider
///   - Configure email templates if needed
/// 
/// TESTING:
/// 1. Test sign up: Call AuthService.signUp('test@example.com', 'password123')
/// 2. Test sign in: Call AuthService.signIn('test@example.com', 'password123')
/// 3. Test sign out: Call AuthService.signOut()
/// 4. Check current user: Call AuthService.getCurrentUser()

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../config/supabase_config.dart';
// Conditional import for web-only functionality
import 'auth_service_stub.dart' if (dart.library.html) 'dart:html' as html;

class AuthService {
  // Sign up a new user with email and password
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await SupabaseService.client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );
      
      if (response.user != null) {
        print('✅ User signed up successfully: ${response.user!.email}');
      }
      
      return response;
    } catch (e) {
      print('❌ Sign up error: $e');
      rethrow;
    }
  }

  // Sign in with email and password
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // Debug: Print Supabase client URL
      final supabaseUrl = SupabaseService.supabaseUrl;
      if (supabaseUrl != null) {
        print('🔍 Attempting sign in to: $supabaseUrl/auth/v1/token');
      }
      print('🔍 Email: $email');
      
      final response = await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        print('✅ User signed in successfully: ${response.user!.email}');
      }
      
      return response;
    } catch (e, stackTrace) {
      print('❌ Sign in error: $e');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Stack trace: $stackTrace');
      
      // Try to extract more details from the error
      if (e.toString().contains('<!DOCTYPE')) {
        print('⚠️ ERROR: Received HTML instead of JSON - this usually means:');
        print('   1. CORS is blocking the request');
        print('   2. The Supabase URL is incorrect');
        print('   3. The request is being redirected to an error page');
        final supabaseUrl = SupabaseService.supabaseUrl;
        if (supabaseUrl != null) {
          print('🔍 Supabase URL being used: $supabaseUrl');
        }
        print('💡 SOLUTION: Check Supabase Dashboard → Settings → API → Additional Allowed Origins');
        print('   Add: https://dwce-time-tracker.web.app');
        print('   Add: https://dwce-time-tracker.firebaseapp.com');
      }
      
      rethrow;
    }
  }

  // Sign out current user
  static Future<void> signOut() async {
    try {
      await SupabaseService.client.auth.signOut();
      print('✅ User signed out successfully');
    } catch (e) {
      print('❌ Sign out error: $e');
      rethrow;
    }
  }

  // Get current user
  static User? getCurrentUser() {
    return SupabaseService.currentUser;
  }

  // Check if user is logged in
  static bool isLoggedIn() {
    return SupabaseService.isLoggedIn;
  }

  // Listen to auth state changes
  static Stream<AuthState> get authStateChanges {
    return SupabaseService.client.auth.onAuthStateChange;
  }

  // Reset password (sends email)
  static Future<void> resetPassword(String email) async {
    try {
      await SupabaseService.client.auth.resetPasswordForEmail(email);
      print('✅ Password reset email sent to: $email');
    } catch (e) {
      print('❌ Password reset error: $e');
      rethrow;
    }
  }

  // Update password (used after clicking reset link)
  // Note: This requires an active session. If called after clicking reset link,
  // the session should be automatically established by Supabase from the URL tokens.
  static Future<UserResponse> updatePassword(String newPassword) async {
    try {
      // Check if we have a session
      final session = SupabaseService.client.auth.currentSession;
      if (session == null) {
        throw Exception(
          'No active session. Please click the password reset link from your email first, '
          'then try again. The link will establish a session automatically.',
        );
      }

      final response = await SupabaseService.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      print('✅ Password updated successfully');
      return response;
    } catch (e) {
      print('❌ Update password error: $e');
      rethrow;
    }
  }

  // Verify OTP for password recovery (for PKCE flow)
  static Future<bool> verifyRecoveryOtp({
    required String email,
    required String token,
  }) async {
    try {
      final response = await SupabaseService.client.auth.verifyOTP(
        type: OtpType.recovery,
        email: email,
        token: token,
      );
      
      if (response.session != null) {
        print('✅ Recovery session established via OTP');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Verify recovery OTP error: $e');
      return false;
    }
  }

  // Verify the recovery token and set session (for web - extracts from URL)
  static Future<bool> verifyRecoveryToken({String? email}) async {
    try {
      // Check if we already have a session
      var session = SupabaseService.client.auth.currentSession;
      if (session != null) {
        print('✅ Recovery session already established');
        return true;
      }

      // Extract tokens from URL (for web only)
      // Supabase can put tokens in either hash (#access_token=...) or query params (?code=...)
      if (kIsWeb) {
        try {
          // ignore: undefined_prefixed_name
          final url = html.window.location.href;
          final uri = Uri.parse(url);
          
          // Check hash first (standard OAuth flow)
          String? accessToken;
          String? refreshToken;
          String? type;
          
          if (uri.fragment.isNotEmpty) {
            // Tokens in hash fragment
            final hashParams = Uri.splitQueryString(uri.fragment);
            accessToken = hashParams['access_token'];
            refreshToken = hashParams['refresh_token'];
            type = hashParams['type'];
            print('🔍 Checking URL hash - type: $type');
          }
          
          // Also check query parameters (PKCE flow uses ?code=...)
          // Note: type=recovery might not always be in the URL
          print('🔍 Checking query parameters: ${uri.queryParameters}');
          if (accessToken == null) {
            final code = uri.queryParameters['code'];
            final recoveryType = uri.queryParameters['type'];
            
            print('🔍 Code from query: $code, Type: $recoveryType');
            
            // Check if we have a code - it might be a recovery code even without type parameter
            if (code != null && (recoveryType == 'recovery' || recoveryType == null)) {
              print('🔍 Found code in query params: $code (type: ${recoveryType ?? "unknown"})');
              
              // If type is null, it's likely a recovery code (password reset links usually only have code)
              // Try automatic handling first (wait a bit for Supabase to process)
              await Future.delayed(const Duration(milliseconds: 1500));
              
              var session = SupabaseService.client.auth.currentSession;
              if (session != null) {
                print('✅ Session established by Supabase (PKCE flow)');
                // Clear the URL for security
                // ignore: undefined_prefixed_name
                html.window.history.replaceState({}, '', html.window.location.pathname);
                return true;
              }
              
              // If automatic handling failed (code verifier missing), try manual OTP verification
              // We need the email - use provided email or return false if not provided
              if (email == null || email.isEmpty) {
                print('❌ PKCE auto-handling failed and no email provided for recovery');
                return false;
              }
              final userEmail = email;
              print('⚠️ PKCE auto-handling failed (code verifier missing), trying manual OTP verification with email: $userEmail');
              
              // The code from PKCE flow is an authorization code, not an OTP token
              // We can't verify it without the code verifier in local storage
              // Try using it as an OTP token anyway (might work in some configurations)
              try {
                print('💡 Attempting to use PKCE code as OTP token...');
                final otpSuccess = await verifyRecoveryOtp(
                  email: userEmail,
                  token: code,
                );
                
                if (otpSuccess) {
                  // Clear the URL for security
                  html.window.history.replaceState({}, '', html.window.location.pathname);
                  return true;
                }
              } catch (e) {
                print('❌ Manual OTP verification failed: $e');
                print('💡 SOLUTION: Disable PKCE for password recovery in Supabase:');
                print('   1. Go to Supabase Dashboard → Authentication → URL Configuration');
                print('   2. Under "Password Reset", disable PKCE or use non-PKCE flow');
                print('   3. Or request a new reset email and use it immediately');
                print('');
                print('   The PKCE code verifier is missing from browser storage.');
                print('   This happens when the reset link is opened in a different browser/session.');
              }
            }
          }
          
          // If we have tokens from hash, try to set session
          if (accessToken != null && refreshToken != null && type == 'recovery') {
            print('🔍 Found tokens in hash - attempting to set session');
            try {
              final response = await SupabaseService.client.auth.setSession(refreshToken);
              
              if (response.session != null) {
                print('✅ Recovery session established from URL tokens');
                // Clear the URL for security
                // ignore: undefined_prefixed_name
                html.window.history.replaceState({}, '', html.window.location.pathname);
                return true;
              } else {
                print('⚠️ Session was not created from refresh token');
              }
            } catch (e) {
              print('⚠️ Error setting session from refresh token: $e');
            }
          }
          
          // Final check - maybe Supabase already processed it
          final session = SupabaseService.client.auth.currentSession;
          if (session != null) {
            print('✅ Session found (may have been set automatically)');
            return true;
          }
          
          print('⚠️ No tokens found in URL hash or query params. URL: ${uri.toString()}');
        } catch (e) {
          // Error extracting from URL
          print('⚠️ Could not extract from URL: $e');
        }
      } else {
        print('⚠️ Password reset token extraction only works on web');
      }

      // Final check
      session = SupabaseService.client.auth.currentSession;
      if (session != null) {
        print('✅ Recovery session found');
        return true;
      } else {
        print('⚠️ No session found. Make sure you clicked the reset link from your email.');
        return false;
      }
    } catch (e) {
      print('❌ Verify recovery token error: $e');
      return false;
    }
  }
}

