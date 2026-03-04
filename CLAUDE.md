# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Analyze code (3 pre-existing info-level issues are acceptable)
flutter analyze --no-fatal-infos --no-fatal-warnings

# Run app
flutter run

# Run tests
flutter test

# Install dependencies
flutter pub get

# Cloud Functions: build & deploy (requires Firebase Blaze plan)
cd functions && npm run build
firebase deploy --only functions
```

## Architecture

**Ping** is a Flutter chat app with Firebase backend (project ID: `pingcv`) and IMU/sensor streaming capabilities.

### Flutter App (`lib/`)

**Service layer** handles all Firebase/external API interactions:
- `auth_service.dart` — Firebase Auth + Firestore user profile CRUD
- `chat_service.dart` — Firestore chat/message operations + unread count clearing
- `cloudinary_service.dart` — image upload
- `changelog_service.dart` — what's new content

**Screens** are StatefulWidgets (required for StreamSubscription lifecycle management).

**Sensor streaming** is managed by the `SensorLogger` class in `main.dart`:
- State machine: `SensorConnectionState` enum (disconnected → connecting → connected/failed)
- Uses `ValueNotifier<SensorConnectionState>` for reactive UI
- Supports debug mode (console) and WebSocket mode (remote server)
- `SensorSheet` widget (`widgets/sensor_sheet.dart`) is the control UI, shown as a bottom sheet

### Firestore Data Model

```
users/{userId}          — profile: nickname, fcmToken, ...
chats/{chatId}          — chatId = "${uid1}_${uid2}" (UIDs sorted alphabetically)
  .participants[]
  .lastMessageAt
  .unreadCounts.{userId}  — incremented by Cloud Function, cleared by client on open
  messages/{messageId}
    .senderId, .text|.image, .createdAt, .type ("text"|"image")
```

### Cloud Functions (`functions/src/index.ts`)

Single function `onNewMessage` triggers on `chats/{chatId}/messages/{messageId}` onCreate:
1. Increments `unreadCounts` for recipient
2. Updates `lastMessageAt`
3. Sends FCM push notification

Push notifications use FCM Legacy HTTP API with server key from `lib/services/fcm_constants.dart`. No service account JSON is bundled in the app.

### Tools (`tools/`)

Python scripts for sensor data:
- `interpreter.py` — IMU data interpreter
- `sensor_receiver.py` — WebSocket receiver

### Key Patterns

- FCM token saved with `.set({'fcmToken': token}, SetOptions(merge: true))` — NOT `.update()` to handle first-login edge cases
- Chat IDs always constructed with UIDs sorted alphabetically: `[uid1, uid2]..sort()` then joined with `_`
- Global `navigatorKey` in `main.dart` for navigation from outside widget tree
- Global `sensorLogger` instance in `main.dart`
