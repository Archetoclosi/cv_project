# Wireless Sensor Streaming Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add WebSocket transport to SensorLogger with mode switching (debug/websocket/both), a Python receiver script, and a sensor control bottom sheet in the app.

**Architecture:** SensorLogger gets a `SensorMode` enum and optional WS connection. The timer callback routes the formatted line to debugPrint and/or WebSocket based on mode. A new `SensorSheet` bottom sheet (matching WhatsNewSheet style) provides start/stop and connection status. A tiny Python WS server on the Mac receives and prints the data.

**Tech Stack:** Flutter, `sensors_plus ^7.0.0`, `web_socket_channel ^3.0.3`, Python `websockets`

---

### Task 1: Add web_socket_channel dependency

**Files:**
- Modify: `pubspec.yaml:47` (after `package_info_plus`)

**Step 1: Add dependency**

Add after line 47 (`package_info_plus: ^8.0.0`):

```yaml
  web_socket_channel: ^3.0.3
```

**Step 2: Install**

Run: `flutter pub get`
Expected: Resolving dependencies... Done.

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: add web_socket_channel for wireless sensor streaming"
```

---

### Task 2: Add SensorMode enum and WebSocket support to SensorLogger

**Files:**
- Modify: `lib/main.dart:1-78` (imports + SensorLogger class)

**Step 1: Add imports**

Add after line 5 (`import 'package:sensors_plus/sensors_plus.dart';`):

```dart
import 'package:web_socket_channel/web_socket_channel.dart';
```

**Step 2: Add SensorMode enum**

Add before the SensorLogger class (before line 13):

```dart
enum SensorMode { debug, websocket, both }
```

**Step 3: Replace SensorLogger class**

Replace lines 13-75 (the entire SensorLogger class) with:

```dart
/// Sensor logger: accelerometer + gyroscope + magnetometer
/// Outputs structured lines via debugPrint and/or WebSocket at configurable Hz.
/// Format: SENSOR|<unix_ms>|A:<x>,<y>,<z>|G:<x>,<y>,<z>|M:<x>,<y>,<z>
class SensorLogger {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  Timer? _timer;
  WebSocketChannel? _ws;
  SensorMode _mode = SensorMode.debug;

  // Latest buffered values (null until first event arrives)
  AccelerometerEvent? _accel;
  GyroscopeEvent? _gyro;
  MagnetometerEvent? _mag;

  /// Whether the logger is currently running.
  bool get isRunning => _timer != null;

  /// Current connection status for UI.
  /// Returns 'connected', 'disconnected', or 'debug'.
  String get connectionStatus {
    if (_mode == SensorMode.debug) return 'debug';
    if (_ws != null) return 'connected';
    return 'disconnected';
  }

  void start({
    int hz = 25,
    SensorMode mode = SensorMode.debug,
    String wsUrl = 'ws://192.168.1.100:8765',
  }) {
    if (_timer != null) return; // already running
    _mode = mode;

    // Open WebSocket if needed
    if (mode == SensorMode.websocket || mode == SensorMode.both) {
      try {
        _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      } catch (e) {
        debugPrint('WS connect error: $e — falling back to debug mode');
        _mode = SensorMode.debug;
        _ws = null;
      }
    }

    // Sensor sampling at 2x target Hz to ensure fresh data each tick
    final sensorPeriod = Duration(milliseconds: (1000 / (hz * 2)).round());

    _accelSub = accelerometerEventStream(samplingPeriod: sensorPeriod)
        .listen((e) => _accel = e, onError: (e) => debugPrint('Accel error: $e'));

    _gyroSub = gyroscopeEventStream(samplingPeriod: sensorPeriod)
        .listen((e) => _gyro = e, onError: (e) => debugPrint('Gyro error: $e'));

    _magSub = magnetometerEventStream(samplingPeriod: sensorPeriod)
        .listen((e) => _mag = e, onError: (e) => debugPrint('Mag error: $e'));

    // Timer emits combined line at target Hz
    _timer = Timer.periodic(Duration(milliseconds: (1000 / hz).round()), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final a = _accel;
      final g = _gyro;
      final m = _mag;

      final accelStr = a != null
          ? 'A:${a.x.toStringAsFixed(2)},${a.y.toStringAsFixed(2)},${a.z.toStringAsFixed(2)}'
          : 'A:,,';
      final gyroStr = g != null
          ? 'G:${g.x.toStringAsFixed(2)},${g.y.toStringAsFixed(2)},${g.z.toStringAsFixed(2)}'
          : 'G:,,';
      final magStr = m != null
          ? 'M:${m.x.toStringAsFixed(2)},${m.y.toStringAsFixed(2)},${m.z.toStringAsFixed(2)}'
          : 'M:,,';

      final line = 'SENSOR|$now|$accelStr|$gyroStr|$magStr';

      // Route to debugPrint and/or WebSocket
      if (_mode == SensorMode.debug || _mode == SensorMode.both) {
        debugPrint(line);
      }
      if ((_mode == SensorMode.websocket || _mode == SensorMode.both) && _ws != null) {
        try {
          _ws!.sink.add(line);
        } catch (e) {
          debugPrint('WS send error: $e — falling back to debug');
          _ws = null;
          _mode = SensorMode.debug;
        }
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _magSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _magSub = null;
    _accel = null;
    _gyro = null;
    _mag = null;
    await _ws?.sink.close();
    _ws = null;
  }
}
```

**Step 4: Update the start call in main()**

Change line 90 from:
```dart
  sensorLogger.start(hz: 5);
```
to:
```dart
  sensorLogger.start(hz: 5, mode: SensorMode.debug);
```

**Step 5: Run flutter analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No new errors.

**Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "feat: add SensorMode enum and WebSocket transport to SensorLogger"
```

---

### Task 3: Create Python receiver script

**Files:**
- Create: `tools/sensor_receiver.py`

**Step 1: Create the script**

```python
#!/usr/bin/env python3
"""Minimal WebSocket server that receives and prints sensor data from the Flutter app."""

import asyncio
import websockets

async def handler(websocket):
    print(f"[+] Phone connected from {websocket.remote_address}")
    try:
        async for message in websocket:
            print(message)
    except websockets.exceptions.ConnectionClosed:
        print("[-] Phone disconnected")

async def main():
    print("Sensor receiver listening on ws://0.0.0.0:8765")
    async with websockets.serve(handler, "0.0.0.0", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
```

**Step 2: Commit**

```bash
git add tools/sensor_receiver.py
git commit -m "feat: add Python WebSocket receiver script"
```

---

### Task 4: Create SensorSheet bottom sheet widget

**Files:**
- Create: `lib/widgets/sensor_sheet.dart`

**Step 1: Create the widget**

Follow WhatsNewSheet style exactly (same Container decoration, padding, button style). The sheet contains:
- Title "Sensors"
- Connection status row (colored dot + text)
- IP display row (locked text)
- Mode display row (locked text)
- Start/Stop button

```dart
import 'package:flutter/material.dart';
import '../main.dart';

class SensorSheet extends StatefulWidget {
  const SensorSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SensorSheet(),
    );
  }

  @override
  State<SensorSheet> createState() => _SensorSheetState();
}

class _SensorSheetState extends State<SensorSheet> {
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final running = sensorLogger.isRunning;
    final status = sensorLogger.connectionStatus;

    Color statusColor;
    String statusText;
    switch (status) {
      case 'connected':
        statusColor = Colors.green;
        statusText = 'Connected';
        break;
      case 'debug':
        statusColor = Colors.blue;
        statusText = 'Debug (cable)';
        break;
      default:
        statusColor = Colors.red;
        statusText = 'Disconnected';
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sensors',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // Connection status
          _InfoRow(
            label: 'Status',
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          // IP display
          _InfoRow(
            label: 'IP',
            child: Text(
              '192.168.1.100:8765',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 15,
              ),
            ),
          ),

          // Mode display
          _InfoRow(
            label: 'Mode',
            child: Text(
              'WebSocket',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 15,
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Start/Stop button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  if (running) {
                    sensorLogger.stop();
                  } else {
                    sensorLogger.start(
                      hz: 5,
                      mode: SensorMode.websocket,
                      wsUrl: 'ws://192.168.1.100:8765',
                    );
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: running ? Colors.red : primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                running ? 'Stop' : 'Start',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _InfoRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 15,
            ),
          ),
          child,
        ],
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/widgets/sensor_sheet.dart
git commit -m "feat: add SensorSheet bottom sheet widget"
```

---

### Task 5: Add sensor button to ChatListScreen header

**Files:**
- Modify: `lib/screens/chat_list_screen.dart:7,96-101`

**Step 1: Add import**

Add after line 7 (`import '../widgets/whats_new_sheet.dart';`):

```dart
import '../widgets/sensor_sheet.dart';
```

**Step 2: Add icon button**

In `_buildHeader`, inside the `Row(children: [...])` at line 96, add a new `IconButton` before the What's New button (before line 97):

```dart
              IconButton(
                icon: const Icon(Icons.sensors, color: Colors.white),
                tooltip: 'Sensors',
                onPressed: () => SensorSheet.show(context),
              ),
```

**Step 3: Run flutter analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No new errors.

**Step 4: Commit**

```bash
git add lib/screens/chat_list_screen.dart
git commit -m "feat: add sensor button to chat list header"
```

---

### Task 6: Test on device

**Step 1: Start Python receiver on Mac**

```bash
pip install websockets
python tools/sensor_receiver.py
```
Expected: `Sensor receiver listening on ws://0.0.0.0:8765`

**Step 2: Update hardcoded IP if needed**

Check your Mac's local IP (`ifconfig en0 | grep inet`). If it's not `192.168.1.100`, update the IP in:
- `lib/main.dart` — the `start()` call in `main()`
- `lib/widgets/sensor_sheet.dart` — the `start()` call and display text

**Step 3: Run app on device**

Run: `flutter run` on physical iOS device.

**Step 4: Test via bottom sheet**

- Open the app → Chat list
- Tap the sensor icon in the header
- Tap "Start" in the bottom sheet
- Verify: status dot turns green, Mac terminal shows SENSOR| lines
- Tap "Stop" → data stops

**Step 5: Test via code (debug mode)**

Change `main()` to use `SensorMode.debug` and verify debugPrint output still works.

**Step 6: Commit any IP fixes**

```bash
git add -A
git commit -m "test: verify wireless sensor streaming on device"
```

---

### Task 7: Update memory files

**Files:**
- Modify: `~/.claude/projects/.../memory/state.md`
- Modify: `~/.claude/projects/.../memory/milestones.md`
- Modify: `~/.claude/projects/.../memory/claude.md`

**Step 1:** Update state.md — mark wireless tasks as done.
**Step 2:** Update milestones.md — add and check off wireless milestones.
**Step 3:** Update claude.md — add SensorSheet and tools/sensor_receiver.py to file tree.
