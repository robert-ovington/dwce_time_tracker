import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';

/// Coming Soon Screen
/// 
/// Placeholder screen for features that are not yet implemented.
/// Displays a friendly message indicating the feature is coming soon.
class ComingSoonScreen extends StatelessWidget {
  final String featureName;
  
  const ComingSoonScreen({
    super.key,
    this.featureName = 'This feature',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          featureName,
          style: const TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0081FB),
        foregroundColor: Colors.black,
        actions: [ScreenInfoIcon(screenName: 'coming_soon_screen.dart')],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.construction,
                size: 80,
                color: Colors.orange.shade400,
              ),
              const SizedBox(height: 24),
              Text(
                'Coming Soon',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$featureName is currently under development.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Please check back later.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
