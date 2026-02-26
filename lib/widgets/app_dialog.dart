import 'package:flutter/material.dart';

/// Shows a dialog with content centered, max height 60% of screen, and vertically scrollable.
/// Use for popups that may overflow on small screens (e.g. phone).
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget>? actions,
  bool scrollable = true,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
      return AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: scrollable
              ? SingleChildScrollView(
                  child: content,
                )
              : content,
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actions: actions,
      );
    },
  );
}
