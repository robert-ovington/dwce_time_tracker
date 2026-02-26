/// Location Service
/// 
/// Centralized service for managing GPS/location permissions and status.
/// Checks location services on app initialization and login.
/// Provides methods to request permissions and prompt users to enable location.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static bool _isLocationServiceEnabled = false;
  static LocationPermission _permissionStatus = LocationPermission.denied;
  static bool _hasCheckedPermissions = false;

  /// Check if location services are enabled on the device
  static bool get isLocationServiceEnabled => _isLocationServiceEnabled;

  /// Get current permission status
  static LocationPermission get permissionStatus => _permissionStatus;

  /// Check if we have location permissions
  static bool get hasLocationPermission {
    return _permissionStatus == LocationPermission.whileInUse ||
        _permissionStatus == LocationPermission.always;
  }

  /// Initialize location service - check status on app startup
  static Future<void> initialize() async {
    if (kIsWeb) {
      _isLocationServiceEnabled = false;
      _hasCheckedPermissions = true;
      return;
    }

    try {
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      _permissionStatus = await Geolocator.checkPermission();
      _hasCheckedPermissions = true;
      
      print('📍 Location Service Status:');
      print('   - Service Enabled: $_isLocationServiceEnabled');
      print('   - Permission: $_permissionStatus');
    } catch (e) {
      print('❌ Error initializing location service: $e');
      _hasCheckedPermissions = true;
    }
  }

  /// Check location status (call after login or when needed)
  static Future<Map<String, dynamic>> checkLocationStatus() async {
    if (kIsWeb) {
      return {
        'enabled': false,
        'permission': LocationPermission.denied,
        'hasPermission': false,
        'message': 'Location services not available on web',
      };
    }

    try {
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      _permissionStatus = await Geolocator.checkPermission();
      _hasCheckedPermissions = true;

      final hasPermission = _permissionStatus == LocationPermission.whileInUse ||
          _permissionStatus == LocationPermission.always;

      return {
        'enabled': _isLocationServiceEnabled,
        'permission': _permissionStatus,
        'hasPermission': hasPermission,
        'message': _getStatusMessage(_isLocationServiceEnabled, _permissionStatus),
      };
    } catch (e) {
      print('❌ Error checking location status: $e');
      return {
        'enabled': false,
        'permission': LocationPermission.denied,
        'hasPermission': false,
        'message': 'Error checking location status',
      };
    }
  }

  /// Request location permission
  static Future<LocationPermission> requestPermission() async {
    if (kIsWeb) {
      return LocationPermission.denied;
    }

    try {
      _permissionStatus = await Geolocator.requestPermission();
      return _permissionStatus;
    } catch (e) {
      print('❌ Error requesting location permission: $e');
      return LocationPermission.denied;
    }
  }

  /// Get current position (if permissions are granted)
  static Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) async {
    if (kIsWeb || !_isLocationServiceEnabled || !hasLocationPermission) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: accuracy,
          timeLimit: timeLimit ?? const Duration(seconds: 10),
        ),
      );
      return position;
    } catch (e) {
      print('❌ Error getting current position: $e');
      return null;
    }
  }

  /// Warm up location on login by requesting a fresh high-accuracy fix.
  ///
  /// This can help avoid using stale GPS data that was cached from a
  /// previous location (e.g. at home before travelling to work).
  static Future<void> warmUpLocation() async {
    if (kIsWeb) {
      return;
    }
    if (!_isLocationServiceEnabled || !hasLocationPermission) {
      return;
    }

    try {
      await getCurrentPosition(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      print('📍 Location warm-up completed.');
    } catch (e) {
      print('⚠️ Location warm-up failed: $e');
    }
  }

  /// Show dialog to prompt user to enable location services
  static Future<bool> showLocationServiceDialog(BuildContext context) async {
    if (kIsWeb) {
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.orange),
              SizedBox(width: 8),
              Text('Location Services Required'),
            ],
          ),
          content: const Text(
            'This app requires location services to track your work location. '
            'Please enable location services in your device settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final opened = await Geolocator.openLocationSettings();
                Navigator.of(context).pop(opened);
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  /// Show dialog to request location permission
  static Future<bool> showPermissionDialog(BuildContext context) async {
    if (kIsWeb) {
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue),
              SizedBox(width: 8),
              Text('Location Permission'),
            ],
          ),
          content: const Text(
            'This app uses GPS data to assist you in day to day tasks such as automatically finding which job you are working on to recording locations of emergency works, concrete deliveries or Travel Allowances. You will be required to grant these permissions to take advantage of all the features offered in this app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () async {
                final permission = await requestPermission();
                final granted = permission == LocationPermission.whileInUse ||
                    permission == LocationPermission.always;
                Navigator.of(context).pop(granted);
              },
              child: const Text('Grant Permission'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  /// Check and prompt for location if needed (call after login)
  static Future<bool> ensureLocationEnabled(BuildContext context) async {
    if (kIsWeb) {
      return false;
    }

    // Check if location service is enabled
    final status = await checkLocationStatus();
    
    final isEnabled = status['enabled'] as bool? ?? false;
    if (!isEnabled) {
      // Location service is disabled - prompt user to enable
      final opened = await showLocationServiceDialog(context);
      if (opened) {
        // Wait a bit for user to enable location
        await Future.delayed(const Duration(seconds: 1));
        // Recheck status
        final newStatus = await checkLocationStatus();
        final newIsEnabled = newStatus['enabled'] as bool? ?? false;
        if (!newIsEnabled) {
          return false;
        }
      } else {
        return false;
      }
    }

    // Check permission
    final hasPermission = status['hasPermission'] as bool? ?? false;
    if (!hasPermission) {
      // Permission not granted - request it
      final granted = await showPermissionDialog(context);
      if (!granted) {
        return false;
      }
      // Recheck status after permission request
      final newStatus = await checkLocationStatus();
      return newStatus['hasPermission'] as bool? ?? false;
    }

    return true;
  }

  /// Get status message for display
  static String _getStatusMessage(bool enabled, LocationPermission permission) {
    if (!enabled) {
      return 'Location services are disabled. Please enable them in device settings.';
    }
    
    switch (permission) {
      case LocationPermission.denied:
        return 'Location permission is denied. Please grant permission to use location features.';
      case LocationPermission.deniedForever:
        return 'Location permission is permanently denied. Please enable it in app settings.';
      case LocationPermission.whileInUse:
        return 'Location permission granted (while in use).';
      case LocationPermission.always:
        return 'Location permission granted (always).';
      case LocationPermission.unableToDetermine:
        return 'Unable to determine location permission status.';
    }
  }

  /// Open app settings (for permanently denied permissions)
  static Future<bool> openAppSettings() async {
    if (kIsWeb) {
      return false;
    }
    return await Geolocator.openAppSettings();
  }

  /// Open location settings
  static Future<bool> openLocationSettings() async {
    if (kIsWeb) {
      return false;
    }
    return await Geolocator.openLocationSettings();
  }
}
