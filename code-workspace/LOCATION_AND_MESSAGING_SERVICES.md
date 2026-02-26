# Location and Messaging Services

## Overview

Two centralized services have been created to manage GPS/location permissions and messaging/notifications throughout the app.

## 1. Location Service

**File:** `lib/modules/location/location_service.dart`

### Features

- **Centralized GPS Management**: Single service for all location-related functionality
- **Automatic Permission Checking**: Checks location status on app initialization and after login
- **User-Friendly Prompts**: Dialog boxes to guide users to enable location services
- **Permission Management**: Handles all location permission states (denied, granted, permanently denied)

### Usage

#### Initialization
The service is automatically initialized in `main.dart` when the app starts.

#### After Login
Location is checked after successful login (non-blocking) and prompts the user if needed:

```dart
// Already implemented in login_screen.dart
LocationService.ensureLocationEnabled(context).then((enabled) {
  if (enabled) {
    print('✅ Location services enabled');
  }
});
```

#### In Your Screens
Replace individual GPS checks with the centralized service:

```dart
import 'package:dwce_time_tracker/modules/location/location_service.dart';

// Check location status
final status = await LocationService.checkLocationStatus();
if (status['hasPermission'] as bool) {
  // Get current position
  final position = await LocationService.getCurrentPosition();
  if (position != null) {
    // Use position.latitude, position.longitude
  }
}

// Or ensure location is enabled (shows dialogs if needed)
final enabled = await LocationService.ensureLocationEnabled(context);
if (enabled) {
  // Location is ready to use
}
```

### Methods

- `initialize()` - Called automatically on app startup
- `checkLocationStatus()` - Check current location service and permission status
- `requestPermission()` - Request location permission
- `getCurrentPosition()` - Get current GPS position (if permission granted)
- `ensureLocationEnabled(context)` - Check and prompt for location if needed
- `showLocationServiceDialog(context)` - Show dialog to enable location services
- `showPermissionDialog(context)` - Show dialog to request permission
- `openAppSettings()` - Open app settings (for permanently denied permissions)
- `openLocationSettings()` - Open device location settings

### Integration Points

1. **App Initialization** (`main.dart`): Service is initialized automatically
2. **After Login** (`login_screen.dart`): Location is checked and user is prompted if needed
3. **In Screens**: Use `LocationService` instead of direct `Geolocator` calls

## 2. Messaging Service

**File:** `lib/modules/messaging/messaging_service.dart`

### Features

- **Message Management**: Send, receive, and manage in-app messages
- **Notification Preferences**: User can enable/disable notifications
- **Unread Message Tracking**: Track unread message counts
- **Extensible**: Ready for push notification integration

### Database Schema Required

The service expects a `messages` table in your Supabase database. Create it with:

```sql
CREATE TABLE public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  sender_id UUID NOT NULL REFERENCES auth.users(id),
  recipient_id UUID NOT NULL REFERENCES auth.users(id),
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  read_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_messages_recipient_id ON public.messages(recipient_id);
CREATE INDEX idx_messages_is_read ON public.messages(is_read);
CREATE INDEX idx_messages_created_at ON public.messages(created_at DESC);

-- RLS Policies (adjust based on your security needs)
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own messages"
  ON public.messages FOR SELECT
  USING (auth.uid() = recipient_id OR auth.uid() = sender_id);

CREATE POLICY "Users can send messages"
  ON public.messages FOR INSERT
  WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update their received messages"
  ON public.messages FOR UPDATE
  USING (auth.uid() = recipient_id);
```

### Usage

#### Initialization
The service is automatically initialized in `main.dart`.

#### Check Notification Settings
```dart
import 'package:dwce_time_tracker/modules/messaging/messaging_service.dart';

// Check if notifications are enabled
if (MessagingService.notificationsEnabled) {
  // Notifications are enabled
}

// Show notification settings dialog
await MessagingService.showNotificationSettingsDialog(context);
```

#### Get Messages
```dart
// Get all messages
final messages = await MessagingService.getMessages();

// Get unread messages only
final unreadMessages = await MessagingService.getMessages(unreadOnly: true);

// Get unread count
final unreadCount = await MessagingService.getUnreadMessageCount();
```

#### Send Message
```dart
final result = await MessagingService.sendMessage(
  recipientId: 'user-uuid',
  subject: 'Message Subject',
  body: 'Message body text',
);
```

#### Mark as Read
```dart
await MessagingService.markMessageAsRead(messageId);
```

### Methods

- `initialize()` - Called automatically on app startup
- `setNotificationsEnabled(bool)` - Enable/disable notifications
- `requestNotificationPermission()` - Request notification permission (placeholder)
- `showNotificationPermissionDialog(context)` - Show dialog to request permission
- `getUnreadMessageCount()` - Get count of unread messages
- `getMessages({limit, unreadOnly})` - Get messages for current user
- `sendMessage({recipientId, subject, body})` - Send a message
- `markMessageAsRead(messageId)` - Mark message as read
- `deleteMessage(messageId)` - Delete a message
- `checkForNewMessages()` - Check for new messages (for periodic checks)
- `showNotificationSettingsDialog(context)` - Show notification settings UI

## Adding Push Notifications (Future Enhancement)

To add actual push notifications, you'll need to:

### 1. Add Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  flutter_local_notifications: ^16.0.0  # For local notifications
  firebase_messaging: ^14.7.0  # For push notifications (optional)
```

### 2. Platform Configuration

#### Android
- Add Firebase configuration files
- Configure notification channels in `AndroidManifest.xml`

#### iOS
- Configure push notification capabilities in Xcode
- Add notification permissions to `Info.plist`

### 3. Update MessagingService

Replace the placeholder `requestNotificationPermission()` and `_sendNotification()` methods with actual implementation using the notification packages.

## Integration Checklist

- [x] Location service created and initialized
- [x] Location checked after login
- [x] Messaging service created and initialized
- [ ] Create `messages` table in Supabase database
- [ ] Add notification packages (if push notifications needed)
- [ ] Create messages screen UI (optional)
- [ ] Add notification badge to main menu (optional)
- [ ] Implement periodic message checking (optional)

## Next Steps

1. **Create Messages Table**: Run the SQL script above in your Supabase database
2. **Add Messages Screen**: Create a UI screen to display messages (similar to email inbox)
3. **Add Notification Badge**: Show unread count badge in main menu
4. **Implement Push Notifications**: Add actual notification packages and configure platforms
5. **Update Screens**: Replace direct GPS calls with `LocationService` in existing screens

## Example: Creating a Messages Screen

```dart
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final messages = await MessagingService.getMessages();
    setState(() {
      _messages = messages;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => MessagingService.showNotificationSettingsDialog(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ListTile(
                  leading: message['is_read'] == false
                      ? const Icon(Icons.mail, color: Colors.blue)
                      : const Icon(Icons.mail_outline),
                  title: Text(message['subject'] ?? ''),
                  subtitle: Text(message['body'] ?? ''),
                  trailing: Text(
                    DateFormat('MMM d').format(
                      DateTime.parse(message['created_at'] ?? DateTime.now().toIso8601String()),
                    ),
                  ),
                  onTap: () async {
                    await MessagingService.markMessageAsRead(message['id']);
                    _loadMessages();
                  },
                );
              },
            ),
    );
  }
}
```
