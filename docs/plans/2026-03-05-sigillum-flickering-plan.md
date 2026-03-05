# Sigillum Flickering Anti-Screenshot Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Sigillum" photo mode that combines one-time viewing with a 60Hz noise-pattern overlay to disrupt camera capture.

**Architecture:** New `FlickerShield` widget overlays pre-generated noise textures at ~60Hz (randomized ±10Hz) with 0.3 opacity, invisible to the human eye but disruptive for camera sensors. Sigillum photos are stored with `oneTime: true` + `sigillum: true` in Firestore.

**Tech Stack:** Flutter (AnimationController, CustomPainter, RepaintBoundary), Firestore

---

### Task 1: FlickerShield Widget — Noise Painter

**Files:**
- Create: `lib/widgets/flicker_shield.dart`
- Create: `test/flicker_shield_test.dart`

**Step 1: Write the failing test**

In `test/flicker_shield_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ping/widgets/flicker_shield.dart';

void main() {
  group('FlickerShield', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlickerShield(
            child: Text('protected'),
          ),
        ),
      );

      expect(find.text('protected'), findsOneWidget);
    });

    testWidgets('contains a RepaintBoundary for the overlay', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlickerShield(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );

      expect(find.byType(RepaintBoundary), findsWidgets);
    });

    testWidgets('contains a CustomPaint for the noise overlay', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlickerShield(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('overlay has opacity 0.3', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlickerShield(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );

      // Find the Opacity widget wrapping the noise overlay
      final opacityWidget = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacityWidget.any((w) => (w.opacity - 0.3).abs() < 0.01), isTrue);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/flicker_shield_test.dart`
Expected: FAIL — `flicker_shield.dart` does not exist

**Step 3: Write the FlickerShield widget**

In `lib/widgets/flicker_shield.dart`:

```dart
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Overlays a high-frequency noise pattern on [child] to disrupt camera capture.
///
/// The noise flickers at ~60 Hz (randomised ±10 Hz) with opacity 0.3.
/// Imperceptible to the human eye; disruptive for camera sensors.
class FlickerShield extends StatefulWidget {
  final Widget child;

  const FlickerShield({super.key, required this.child});

  @override
  State<FlickerShield> createState() => _FlickerShieldState();
}

class _FlickerShieldState extends State<FlickerShield>
    with SingleTickerProviderStateMixin {
  static const int _noiseVariants = 4;
  static const int _gridCols = 24;
  static const int _gridRows = 36;
  static const double _overlayOpacity = 0.3;
  static const double _baseFrequencyHz = 60.0;
  static const double _frequencyJitterHz = 10.0;
  static const double _minFrequencyHz = 50.0;

  late final Ticker _ticker;
  final _random = Random();

  /// Pre-generated noise seeds — each produces a different pattern.
  late final List<int> _noiseSeeds;

  int _currentVariant = 0;
  Duration _lastToggle = Duration.zero;
  late Duration _currentInterval;
  bool _showNoise = false;

  @override
  void initState() {
    super.initState();
    _noiseSeeds = List.generate(_noiseVariants, (_) => _random.nextInt(1 << 32));
    _currentInterval = _randomInterval();
    _ticker = createTicker(_onTick)..start();
  }

  Duration _randomInterval() {
    final hz = max(
      _minFrequencyHz,
      _baseFrequencyHz + (_random.nextDouble() * 2 - 1) * _frequencyJitterHz,
    );
    return Duration(microseconds: (1e6 / hz).round());
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastToggle >= _currentInterval) {
      _lastToggle = elapsed;
      _showNoise = !_showNoise;
      if (_showNoise) {
        _currentVariant = (_currentVariant + 1) % _noiseVariants;
      }
      // Re-randomise interval every cycle to prevent adaptation
      _currentInterval = _randomInterval();
      // Only rebuild the overlay via the ValueListenableBuilder approach
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showNoise)
          RepaintBoundary(
            child: Opacity(
              opacity: _overlayOpacity,
              child: CustomPaint(
                painter: _NoisePainter(
                  seed: _noiseSeeds[_currentVariant],
                  cols: _gridCols,
                  rows: _gridRows,
                ),
                size: Size.infinite,
              ),
            ),
          ),
      ],
    );
  }
}

class _NoisePainter extends CustomPainter {
  final int seed;
  final int cols;
  final int rows;

  _NoisePainter({required this.seed, required this.cols, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        paint.color = Color.fromARGB(
          255,
          rng.nextInt(256),
          rng.nextInt(256),
          rng.nextInt(256),
        );
        canvas.drawRect(
          Rect.fromLTWH(c * cellW, r * cellH, cellW + 1, cellH + 1),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NoisePainter old) => old.seed != seed;
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/flicker_shield_test.dart`
Expected: All 4 tests PASS

**Step 5: Run analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No new errors

**Step 6: Commit**

```bash
git add lib/widgets/flicker_shield.dart test/flicker_shield_test.dart
git commit -m "feat: add FlickerShield widget with noise overlay at 60Hz"
```

---

### Task 2: ChatService — Add `sigillum` Parameter

**Files:**
- Modify: `lib/services/chat_service.dart:17-36` (sendImage method)

**Step 1: Modify `sendImage` to accept `sigillum` parameter**

In `lib/services/chat_service.dart`, update `sendImage`:

```dart
  Future<void> sendImage(
    String chatId,
    String senderId,
    Uint8List imageBytes, {
    bool oneTime = false,
    bool sigillum = false,
  }) async {
    final cloudinary = CloudinaryService();
    final url = await cloudinary.uploadImage(imageBytes);

    if (url == null) return;

    await _db.collection('chats').doc(chatId).collection('messages').add({
      'imageUrl': url,
      'senderId': senderId,
      'type': 'image',
      'oneTime': oneTime || sigillum,
      'sigillum': sigillum,
      'viewedOnce': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
```

Key: `sigillum: true` automatically sets `oneTime: true` via the `||`.

**Step 2: Run analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No new errors

**Step 3: Commit**

```bash
git add lib/services/chat_service.dart
git commit -m "feat: add sigillum parameter to sendImage"
```

---

### Task 3: ChatScreen — Sigillum Send Button

**Files:**
- Modify: `lib/screens/chat_screen.dart:656-699` (bottom sheet with send options)

**Step 1: Add Sigillum button to the bottom sheet**

In `lib/screens/chat_screen.dart`, inside the `showModalBottomSheet` builder (after the "Invia foto one time" ListTile at line ~681), add a third ListTile:

```dart
                        ListTile(
                          leading: Text(
                            '\u{1F441}',
                            style: TextStyle(fontSize: 24),
                          ),
                          title: const Text(
                            'Invia foto con Sigillum',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _pickAndSendImage(oneTime: false, sigillum: true);
                          },
                        ),
```

**Step 2: Update `_pickAndSendImage` to accept `sigillum`**

In `lib/screens/chat_screen.dart`, modify `_pickAndSendImage` (line ~65):

```dart
  Future<void> _pickAndSendImage({
    required bool oneTime,
    bool sigillum = false,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    try {
      setState(() => _isUploadingImage = true);
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      await _chatService.sendImage(
        widget.chatId,
        _myId,
        bytes,
        oneTime: oneTime,
        sigillum: sigillum,
      );
    } catch (e) {
      debugPrint('Errore invio immagine: $e');
    } finally {
      setState(() => _isUploadingImage = false);
    }
  }
```

**Step 3: Run analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No new errors

**Step 4: Commit**

```bash
git add lib/screens/chat_screen.dart
git commit -m "feat: add Sigillum send button in attachment menu"
```

---

### Task 4: ChatScreen — Sigillum Placeholder & FlickerShield in Full-Screen

**Files:**
- Modify: `lib/screens/chat_screen.dart:439-508` (_buildImageBubbleContent)
- Modify: `lib/screens/chat_screen.dart:741-800` (FullScreenImage)

**Step 1: Add import for FlickerShield**

At the top of `lib/screens/chat_screen.dart`, add:

```dart
import '../widgets/flicker_shield.dart';
```

**Step 2: Update `_buildImageBubbleContent` to handle Sigillum placeholders**

In `_buildImageBubbleContent`, after extracting `oneTime` and `viewedOnce` (line ~448-449), also extract `sigillum`:

```dart
    final sigillum = data['sigillum'] as bool? ?? false;
```

Then update the one-time placeholder section. Replace the existing one-time `if` block (lines ~464-507) with logic that differentiates Sigillum:

```dart
    if (oneTime || sigillum) {
      if (viewedOnce) {
        return _buildImagePlaceholder(
          isMe,
          time,
          showTimestamp,
          label: sigillum ? 'Foto Sigillum visualizzata' : 'Foto one time visualizzata',
          icon: sigillum ? Icons.visibility : Icons.lock,
        );
      }

      final placeholder = _buildImagePlaceholder(
        isMe,
        time,
        showTimestamp,
        label: sigillum ? '\u{1F441} Foto Sigillum' : 'Foto one time',
        icon: sigillum ? Icons.visibility : Icons.lock,
      );

      if (isMe) {
        return placeholder;
      }

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenImage(
                imageUrl: imageUrl,
                chatId: widget.chatId,
                messageId: messageId,
                oneTime: true,
                isMe: isMe,
                sigillum: sigillum,
              ),
            ),
          );
        },
        child: placeholder,
      );
    }
```

**Step 3: Update `FullScreenImage` to accept `sigillum` and wrap with `FlickerShield`**

In `lib/screens/chat_screen.dart`, update the `FullScreenImage` widget:

Add `sigillum` field:

```dart
class FullScreenImage extends StatefulWidget {
  final String imageUrl;
  final String chatId;
  final String messageId;
  final bool oneTime;
  final bool isMe;
  final bool sigillum;

  const FullScreenImage({
    super.key,
    required this.imageUrl,
    required this.chatId,
    required this.messageId,
    required this.oneTime,
    required this.isMe,
    this.sigillum = false,
  });

  @override
  State<FullScreenImage> createState() => _FullScreenImageState();
}
```

Then in the `build` method of `_FullScreenImageState`, wrap content with FlickerShield when sigillum:

```dart
  @override
  Widget build(BuildContext context) {
    Widget content = Center(child: Image.network(widget.imageUrl));

    if (widget.sigillum) {
      content = FlickerShield(child: content);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        panEnabled: true,
        boundaryMargin: EdgeInsets.zero,
        minScale: 1.0,
        maxScale: 4.0,
        clipBehavior: Clip.hardEdge,
        child: Center(child: content),
      ),
    );
  }
```

**Step 4: Run analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No new errors

**Step 5: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/screens/chat_screen.dart
git commit -m "feat: Sigillum placeholder in chat and FlickerShield in full-screen view"
```

---

### Task 5: Manual Smoke Test

**Steps:**
1. Run: `flutter run`
2. Open a chat, tap attachment icon
3. Verify three options: "Invia foto", "Invia foto one time", "Invia foto con Sigillum" (with eye emoji)
4. Send a Sigillum photo
5. Verify sender sees placeholder with eye icon and "Foto Sigillum" text
6. Switch to recipient — verify they see the placeholder and can tap it
7. Verify full-screen opens with the noise flickering overlay active
8. Close the photo — verify placeholder changes to "Foto Sigillum visualizzata"
9. Verify the photo cannot be opened again by either party
