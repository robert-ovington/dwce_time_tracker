import 'package:flutter/material.dart';

/// Provides app-wide config (e.g. post-login screen) so entry points (main.dart
/// vs main_mobile.dart) can supply different menus without passing through every widget.
class AppConfig extends InheritedWidget {
  const AppConfig({
    super.key,
    required this.postLoginScreenBuilder,
    required super.child,
  });

  final Widget Function() postLoginScreenBuilder;

  static AppConfig? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppConfig>();
  }

  static AppConfig of(BuildContext context) {
    final c = maybeOf(context);
    assert(c != null, 'AppConfig not found. Wrap app in AppConfig.');
    return c!;
  }

  @override
  bool updateShouldNotify(AppConfig oldWidget) {
    return postLoginScreenBuilder != oldWidget.postLoginScreenBuilder;
  }
}
