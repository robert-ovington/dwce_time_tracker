/// Scan Feedback Helper
/// 
/// Provides audio and vibration feedback for successful/unsuccessful scans
/// 
/// NOTE: Audio files should be placed in assets/audio/ directory:
/// - success_single.wav (single beep for successful scan)
/// - success_double.wav (double beep when ready for next scan)
/// - error.wav (error sound for unsuccessful scan)
/// 
/// If audio files are not available, only vibration feedback will be used.

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

class ScanFeedbackHelper {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _audioInitialized = false;

  /// Initialize audio player (call once at app startup)
  static Future<void> initialize() async {
    if (_audioInitialized) return;
    try {
      // Preload audio files if available
      // TODO: Uncomment and update paths when audio files are added
      // await _audioPlayer.setSource(AssetSource('audio/success_single.wav'));
      _audioInitialized = true;
    } catch (e) {
      // Audio files not available - continue without audio
      print('⚠️ Audio files not available, using vibration only');
    }
  }

  /// Play success feedback (single beep + vibration)
  static Future<void> playSuccessSingle() async {
    try {
      // Vibration feedback
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(duration: 100);
      }

      // Audio feedback
      // TODO: Uncomment when audio files are added
      // try {
      //   await _audioPlayer.play(AssetSource('audio/success_single.wav'));
      // } catch (e) {
      //   // Audio file not found - continue without audio
      // }

      // Haptic feedback (alternative to vibration package)
      HapticFeedback.lightImpact();
    } catch (e) {
      // Fallback to haptic feedback only
      HapticFeedback.lightImpact();
    }
  }

  /// Play ready for next scan feedback (double beep)
  static Future<void> playSuccessDouble() async {
    try {
      // Audio feedback
      // TODO: Uncomment when audio files are added
      // try {
      //   await _audioPlayer.play(AssetSource('audio/success_double.wav'));
      // } catch (e) {
      //   // Audio file not found - continue without audio
      // }
    } catch (e) {
      // Audio not available - silent
    }
  }

  /// Play error feedback (error sound + vibration pattern)
  static Future<void> playError() async {
    try {
      // Vibration pattern (short-long-short)
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(pattern: [0, 100, 200, 100, 200, 100]);
      }

      // Audio feedback
      // TODO: Uncomment when audio files are added
      // try {
      //   await _audioPlayer.play(AssetSource('audio/error.wav'));
      // } catch (e) {
      //   // Audio file not found - continue without audio
      // }

      // Haptic feedback (alternative)
      HapticFeedback.heavyImpact();
    } catch (e) {
      // Fallback to haptic feedback only
      HapticFeedback.heavyImpact();
    }
  }

  /// Dispose audio player (call when app closes)
  static Future<void> dispose() async {
    await _audioPlayer.dispose();
    _audioInitialized = false;
  }
}

