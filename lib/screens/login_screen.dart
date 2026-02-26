import 'package:dwce_time_tracker/app_config.dart';
import 'package:dwce_time_tracker/config/supabase_config.dart';
import 'package:dwce_time_tracker/modules/auth/auth_service.dart';
import 'package:dwce_time_tracker/modules/database/database_service.dart';
import 'package:dwce_time_tracker/modules/errors/error_log_service.dart';
import 'package:dwce_time_tracker/modules/location/location_service.dart';
import 'package:dwce_time_tracker/modules/messaging/messaging_service.dart';
import 'package:dwce_time_tracker/modules/users/user_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Login Screen
///
/// Based on the design from https://portal.fit2trade.com/
/// Clean, centered login form with email and password fields.
/// Post-login screen is provided by AppConfig (set by main.dart or main_mobile.dart).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true; // Enabled by default
  String? _errorMessage;

  // Secure storage for credentials
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Load saved credentials if "Remember me" was previously checked
  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (rememberMe) {
        final savedEmail = prefs.getString('saved_email');
        final savedPassword = await _storage.read(key: 'saved_password');

        if (savedEmail != null && savedPassword != null) {
          setState(() {
            _emailController.text = savedEmail;
            _passwordController.text = savedPassword;
            _rememberMe = true;
          });
        }
      }
    } catch (e, stackTrace) {
      print('Error loading saved credentials: $e');
      await ErrorLogService.logError(
        location: 'Login Screen - Load Saved Credentials',
        type: 'Storage',
        description: 'Failed to load saved credentials: $e',
        stackTrace: stackTrace,
      );
    }
  }

  // Save credentials securely
  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool('remember_me', true);
        await prefs.setString('saved_email', _emailController.text.trim());
        await _storage.write(
          key: 'saved_password',
          value: _passwordController.text,
        );
      } else {
        await prefs.setBool('remember_me', false);
        await prefs.remove('saved_email');
        await _storage.delete(key: 'saved_password');
      }
    } catch (e, stackTrace) {
      print('Error saving credentials: $e');
      await ErrorLogService.logError(
        location: 'Login Screen - Save Credentials',
        type: 'Storage',
        description: 'Failed to save credentials: $e',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Save credentials if "Remember me" is checked
      await _saveCredentials();

      if (mounted) {
        // Block navigation until user has responded to the location permission dialog
        // (Not Now or Grant Permission), so the message stays visible and Main Menu is not shown until then.
        final locationEnabled = await LocationService.ensureLocationEnabled(context);
        if (locationEnabled) {
          print('✅ Location services enabled and permission granted');
          LocationService.warmUpLocation();
        } else {
          print('⚠️ Location services not enabled or permission denied');
        }

        if (!mounted) return;
        // Check for important messages before navigating
        await MessagingService.showImportantMessagesDialog(context);

        if (!mounted) return;
        final postLogin = AppConfig.of(context).postLoginScreenBuilder;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => postLogin()),
        );
      }
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Login Screen - Handle Login',
        type: 'Authentication',
        description:
            'Login failed for email ${_emailController.text.trim()}: $e',
        stackTrace: stackTrace,
      );
      setState(() {
        _errorMessage = 'Invalid email or password. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      // Show dialog to enter email
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Forgot Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Enter your email address to receive a password reset link.'),
              const SizedBox(height: 16),
              TextField(
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) async {
                  Navigator.of(context).pop();
                  await _sendPasswordReset(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final emailController = TextEditingController();
                Navigator.of(context).pop();
                // Show another dialog with text field
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Forgot Password'),
                    content: TextField(
                      controller: emailController,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _sendPasswordReset(emailController.text.trim());
                        },
                        child: const Text('Send Reset Link'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Send Reset Link'),
            ),
          ],
        ),
      );
    } else {
      await _sendPasswordReset(email);
    }
  }

  Future<void> _sendPasswordReset(String email) async {
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address')),
      );
      return;
    }

    try {
      await AuthService.resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset link sent to $email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      await ErrorLogService.logError(
        location: 'Login Screen - Forgot Password',
        type: 'Authentication',
        description: 'Failed to send password reset email to $email: $e',
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Form(
                    key: _formKey,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // When fonts/assets fail on web, constraints can be NaN; clamp to finite bounds.
                        final maxW = (constraints.maxWidth.isNaN || !constraints.maxWidth.isFinite)
                            ? 400.0
                            : constraints.maxWidth.clamp(1.0, 400.0);
                        final maxH = (constraints.maxHeight.isNaN ||
                                !constraints.maxHeight.isFinite ||
                                constraints.maxHeight == double.infinity)
                            ? 800.0
                            : constraints.maxHeight.clamp(1.0, 2000.0);
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxW,
                            minHeight: 0,
                            maxHeight: maxH,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                        // Company Logo (fixed-height container avoids NaN when image/fonts fail to load on web)
                        SizedBox(
                          height: 120,
                          child: Image.asset(
                            'assets/logo/walsh_logo.png',
                            height: 120,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.business,
                                      size: 80,
                                      color: Colors.blue,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Login',
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Email Field (fixed height avoids NaN when fonts/assets fail on web)
                        SizedBox(
                          height: 56,
                          child: TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: Icon(Icons.email_outlined),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field (fixed height avoids NaN when fonts/assets fail on web)
                        SizedBox(
                          height: 56,
                          child: TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleLogin(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.lock_outlined),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Remember Me Checkbox
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: _isLoading
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _rememberMe = value ?? false;
                                      });
                                    },
                            ),
                            const Text('Remember me'),
                          ],
                        ),
                        // Forgot Password Link
                        TextButton(
                          onPressed:
                              _isLoading ? null : _handleForgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                        const SizedBox(height: 8),

                        // Error Message
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        // Login Button
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF0081FB), // #0081FB
                              foregroundColor: const Color(
                                  0xFFFEFE00), // #FEFE00 (yellow text)
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                              Color(0xFFFEFE00)), // #FEFE00
                                    ),
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Build version info
                        FutureBuilder<String>(
                          future: _loadBuildInfo(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 16.0),
                                child: Text(
                                  snapshot.data!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),  // Column
                  );    // return ConstrainedBox
                    },
                  ),    // LayoutBuilder
                ),      // Form
              ),        // Padding
            ),          // Card
          ),            // ConstrainedBox(maxWidth)
        ),              // SingleChildScrollView
      ),                // Center
    ),                  // Container
    ),                  // SafeArea
    );                  // Scaffold
  }

  // Load build info: on web from build_info.txt; on mobile from package_info_plus
  Future<String> _loadBuildInfo() async {
    if (!kIsWeb) {
      try {
        final info = await PackageInfo.fromPlatform();
        final version = info.version;
        final buildNumber = info.buildNumber;
        if (version.isNotEmpty || buildNumber.isNotEmpty) {
          return 'Build: $version ($buildNumber)';
        }
      } catch (e) {
        // Silently fail - version info is optional
      }
      return 'Build: Unknown';
    }
    try {
      final response = await http.get(Uri.parse('build_info.txt?t=${DateTime.now().millisecondsSinceEpoch}'));
      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        String buildDate = 'Unknown';
        for (final line in lines) {
          if (line.startsWith('Build Date:')) {
            buildDate = line.replaceFirst('Build Date:', '').trim();
            break;
          }
        }
        return 'Build: $buildDate';
      }
    } catch (e) {
      // Silently fail - version info is optional
    }
    return 'Build: Unknown';
  }
}

