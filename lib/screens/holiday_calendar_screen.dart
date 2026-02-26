/// Holiday Calendar – placeholder; can be extended to show company holidays or leave.

import 'package:flutter/material.dart';
import '../widgets/screen_info_icon.dart';

class HolidayCalendarScreen extends StatelessWidget {
  const HolidayCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Holiday Calendar'),
        actions: const [ScreenInfoIcon(screenName: 'holiday_calendar_screen.dart')],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_month, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Holiday calendar',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Company holidays and leave can be shown here when configured.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
