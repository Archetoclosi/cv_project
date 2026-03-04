# Sensor Streaming Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the auto-started, string-status SensorLogger with a manually controlled logger that has a proper connection state machine and a rebuilt SensorSheet with mode toggle (debug builds only), persisted IP, and a pulsing connecting indicator.

**Architecture:** `SensorLogger` in `main.dart` gains a `ValueNotifier<SensorConnectionState>` for reactive UI, two explicit start methods (`startDebug` / `connect`), and uses `WebSocketChannel.ready` for the connecting→connected/failed transition. `SensorSheet` rebuilds around `ValueListenableBuilder` and reads/writes IP via `SharedPreferences`.

**Tech Stack:** Flutter, `web_socket_channel ^3.0.3` (already in pubspec), `shared_preferences ^2.3.0` (already in pubspec), `AnimationController` for pulsing dot.

---

## Task 1: Refactor `SensorLogger` in `main.dart`

**Files:**
- Modify: `lib/main.dart`

### Step 1: Replace `SensorMode` enum with `SensorConnectionState`

In `lib/main.dart`, replace:
```dart
enum SensorMode { debug, websocket, both }
```
with:
```dart
enum SensorConnectionState { disconnected, connecting, connected, failed }
```

### Step 2: Rewrite `SensorLogger` class

Replace the entire `SensorLogger` class with this:

```dart
class SensorLogger {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  Timer? _timer;
  WebSocketChannel? _ws;

  AccelerometerEvent? _accel;
  GyroscopeEvent? _gyro;
  MagnetometerEvent? _mag;

  final connectionState =
      ValueNotifier<SensorConnectionState>(SensorConnectionState.disconnected);

  bool get isRunning => _timer != null;

  /// Start in debug (print) mode. Only meaningful in debug builds.
  void startDebug({int hz = 5}) {
    if (_timer != null) return;
    connectionState.value = SensorConnectionState.connected;
    _startSensors(hz, websocket: false);
  }

  /// Connect via WebSocket, then start sensors on success.
  Future<void> connect({required String wsUrl, int hz = 5}) async {
    if (_timer != null) return;
    connectionState.value = SensorConnectionState.connecting;
    try {
      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _ws!.ready;
      // Listen for runtime disconnects
      _ws!.stream.listen(
        (_) {},
        onError: (_) {
          connectionState.value = SensorConnectionState.failed;
          _ws = null;
          _stopTimerAndSensors();
        },
        onDone: () {
          if (connectionState.value == SensorConnectionState.connected) {
            connectionState.value = SensorConnectionState.disconnected;
          }
          _ws = null;
          _stopTimerAndSensors();
        },
        cancelOnError: true,
      );
      connectionState.value = SensorConnectionState.connected;
      _startSensors(hz, websocket: true);
    } catch (e) {
      debugPrint('WS connect error: $e');
      _ws = null;
      connectionState.value = SensorConnectionState.failed;
    }
  }

  Future<void> stop() async {
    connectionState.value = SensorConnectionState.disconnected;
    _stopTimerAndSensors();
    await _ws?.sink.close();
    _ws = null;
  }

  void _stopTimerAndSensors() {
    _timer?.cancel();
    _timer = null;
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _magSub = null;
    _accel = null;
    _gyro = null;
    _mag = null;
  }

  void _startSensors(int hz, {required bool websocket}) {
    final sensorPeriod = Duration(milliseconds: (1000 / (hz * 2)).round());

    _accelSub = accelerometerEventStream(samplingPeriod: sensorPeriod)
        .listen((e) => _accel = e, onError: (_) {});
    _gyroSub = gyroscopeEventStream(samplingPeriod: sensorPeriod)
        .listen((e) => _gyro = e, onError: (_) {});
    _magSub = magnetometerEventStream(samplingPeriod: sensorPeriod)
        .listen((e) => _mag = e, onError: (_) {});

    _timer = Timer.periodic(Duration(milliseconds: (1000 / hz).round()), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final a = _accel;
      final g = _gyro;
      final m = _mag;

      final line = 'SENSOR|$now'
          '|A:${a != null ? '${a.x.toStringAsFixed(2)},${a.y.toStringAsFixed(2)},${a.z.toStringAsFixed(2)}' : ',,'}'
          '|G:${g != null ? '${g.x.toStringAsFixed(2)},${g.y.toStringAsFixed(2)},${g.z.toStringAsFixed(2)}' : ',,'}'
          '|M:${m != null ? '${m.x.toStringAsFixed(2)},${m.y.toStringAsFixed(2)},${m.z.toStringAsFixed(2)}' : ',,'}';

      if (websocket && _ws != null) {
        try {
          _ws!.sink.add(line);
        } catch (_) {
          connectionState.value = SensorConnectionState.failed;
          _ws = null;
          _stopTimerAndSensors();
        }
      } else {
        debugPrint(line);
      }
    });
  }
}
```

### Step 3: Remove auto-start from `main()`

In `main()`, delete:
```dart
/// Avvio sensor logger (accel + gyro + mag)
sensorLogger.start(hz: 5, mode: SensorMode.websocket);
```

### Step 4: Verify no `SensorMode` references remain

Run:
```bash
grep -r "SensorMode\|connectionStatus\|\.start(" lib/
```
Expected: only matches inside `sensor_sheet.dart` (which we'll fix in Task 2). If `main.dart` shows any, fix them.

### Step 5: Check analysis

Run:
```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 0 errors (pre-existing infos are OK). Fix any errors before continuing.

### Step 6: Commit

```bash
git add lib/main.dart
git commit -m "refactor: rewrite SensorLogger with ConnectionState ValueNotifier"
```

---

## Task 2: Rebuild `SensorSheet`

**Files:**
- Modify: `lib/widgets/sensor_sheet.dart`

### Step 1: Replace the entire file

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

const _prefKeyHost = 'sensor_ws_host';
const _defaultHost = '192.168.1.100:8765';

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

class _SensorSheetState extends State<SensorSheet>
    with SingleTickerProviderStateMixin {
  // true = WebSocket, false = debug print (only relevant in debug builds)
  bool _wsMode = true;
  late final TextEditingController _hostController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: _defaultHost);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hostController.text = prefs.getString(_prefKeyHost) ?? _defaultHost;
      _prefsLoaded = true;
    });
  }

  Future<void> _saveHost() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyHost, _hostController.text.trim());
  }

  Future<void> _connect() async {
    await _saveHost();
    final url = 'ws://${_hostController.text.trim()}';
    await sensorLogger.connect(wsUrl: url, hz: 5);
  }

  void _startDebug() {
    sensorLogger.startDebug(hz: 5);
  }

  Future<void> _stop() async {
    await sensorLogger.stop();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + bottomPadding),
      child: ValueListenableBuilder<SensorConnectionState>(
        valueListenable: sensorLogger.connectionState,
        builder: (context, state, _) {
          final running = sensorLogger.isRunning;
          return Column(
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

              // Mode toggle — debug builds only
              if (kDebugMode && !running) ...[
                _SectionLabel('Mode'),
                const SizedBox(height: 8),
                _ModeToggle(
                  wsMode: _wsMode,
                  onChanged: (v) => setState(() => _wsMode = v),
                ),
                const SizedBox(height: 16),
              ],

              // IP field — only for WebSocket mode and when not running
              if (_wsMode && !running) ...[
                _SectionLabel('Host'),
                const SizedBox(height: 8),
                _HostField(
                  controller: _hostController,
                  enabled: _prefsLoaded,
                ),
                const SizedBox(height: 16),
              ],

              // Status row
              _InfoRow(
                label: 'Status',
                child: _StatusIndicator(
                  state: state,
                  pulseAnim: _pulseAnim,
                  wsMode: _wsMode,
                ),
              ),

              const SizedBox(height: 24),

              // Connect / Disconnect button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: state == SensorConnectionState.connecting
                      ? null
                      : () {
                          if (running) {
                            _stop();
                          } else if (_wsMode) {
                            _connect();
                          } else {
                            _startDebug();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: running ? Colors.red : primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    state == SensorConnectionState.connecting
                        ? 'Connecting…'
                        : running
                            ? 'Disconnect'
                            : 'Connect',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 13,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool wsMode;
  final ValueChanged<bool> onChanged;
  const _ModeToggle({required this.wsMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('Print (cable)')),
        ButtonSegment(value: true, label: Text('WebSocket (WiFi)')),
      ],
      selected: {wsMode},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).primaryColor;
          }
          return Colors.white12;
        }),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        side: WidgetStateProperty.all(BorderSide.none),
      ),
    );
  }
}

class _HostField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  const _HostField({required this.controller, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.url,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: _defaultHost,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        filled: true,
        fillColor: Colors.white10,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final SensorConnectionState state;
  final Animation<double> pulseAnim;
  final bool wsMode;

  const _StatusIndicator({
    required this.state,
    required this.pulseAnim,
    required this.wsMode,
  });

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      SensorConnectionState.connected =>
        (Colors.green, wsMode ? 'Connected' : 'Debug (cable)'),
      SensorConnectionState.connecting => (Colors.amber, 'Connecting…'),
      SensorConnectionState.failed => (Colors.red, 'Failed'),
      SensorConnectionState.disconnected => (Colors.grey, 'Disconnected'),
    };

    Widget dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    if (state == SensorConnectionState.connecting) {
      dot = FadeTransition(opacity: pulseAnim, child: dot);
    }

    return Row(
      children: [
        dot,
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _InfoRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}
```

### Step 2: Check analysis

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 0 errors. Fix any before continuing.

### Step 3: Manual smoke test

- Run `flutter run`
- Open SensorSheet from chat list header button
- In debug build: verify mode toggle appears, switch between Print/WebSocket
- Connect in WebSocket mode: status should go amber (pulsing) → green (or red if no server)
- Disconnect: status should go grey
- Reconnect: cycle works again
- Restart app: verify saved IP is pre-filled

### Step 4: Commit

```bash
git add lib/widgets/sensor_sheet.dart
git commit -m "feat: rebuild SensorSheet with mode toggle, persisted IP, connection state"
```

---

## Task 3: Clean up uncommitted changes in `main.dart`

**Files:**
- Modify: `lib/main.dart` (the `SensorMode.websocket` call currently uncommitted in git)

This is already handled by Task 1. Verify with:

```bash
git status
```
Expected: clean working tree (or only `.gitignore` left).

### Step 1: Commit `.gitignore` if still unstaged

```bash
git add .gitignore
git commit -m "chore: ignore .venv directory"
```

---

## Done

Run a final check:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
git log --oneline -5
```

Expected log:
```
chore: ignore .venv directory
feat: rebuild SensorSheet with mode toggle, persisted IP, connection state
refactor: rewrite SensorLogger with ConnectionState ValueNotifier
docs: add sensor streaming refactor design doc
...
```
