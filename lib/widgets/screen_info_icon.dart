import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An icon button (ⓘ) for the AppBar that shows a popup with the screen name when tapped.
class ScreenInfoIcon extends StatelessWidget {
  const ScreenInfoIcon({super.key, required this.screenName});

  final String screenName;

  static void showInfoDialog(BuildContext context, String screenName) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Flexible(child: Text('Information')),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(screenName),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: screenName));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline),
      tooltip: 'Information',
      onPressed: () => showInfoDialog(context, screenName),
    );
  }
}
