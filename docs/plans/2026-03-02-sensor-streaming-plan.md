# Sensor Streaming Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand the existing `SensorLogger` class to read accelerometer, magnetometer, and gyroscope, emitting structured `SENSOR|` lines via `debugPrint` at a configurable sample rate.

**Architecture:** Three `StreamSubscription`s buffer the latest event from each sensor. A periodic `Timer` at the target Hz combines all three into one pipe-delimited line and calls `debugPrint`. The existing `start()`/`stop()` interface is preserved.

**Tech Stack:** Flutter, `sensors_plus ^7.0.0` (already in pubspec), `debugPrint` output via `flutter run`.

---

### Task 1: Replace SensorLogger with expanded version

**Files:**
- Modify: `lib/main.dart:13-41` (the `SensorLogger` class)

**Step 1: Replace the SensorLogger class**

Replace lines 13-41 of `lib/main.dart` with:

```dart
/// Sensor logger: accelerometer + gyroscope + magnetometer
/// Outputs structured lines via debugPrint at configurable Hz.
/// Format: SENSOR|<unix_ms>|<ax>,<ay>,<az>|<gx>,<gy>,<gz>|<mx>,<my>,<mz>
class SensorLogger {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  Timer? _timer;

  // Latest buffered values (null until first event arrives)
  AccelerometerEvent? _accel;
  GyroscopeEvent? _gyro;
  MagnetometerEvent? _mag;

  void start({int hz = 25}) {
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
          ? '${a.x.toStringAsFixed(4)},${a.y.toStringAsFixed(4)},${a.z.toStringAsFixed(4)}'
          : ',,';
      final gyroStr = g != null
          ? '${g.x.toStringAsFixed(4)},${g.y.toStringAsFixed(4)},${g.z.toStringAsFixed(4)}'
          : ',,';
      final magStr = m != null
          ? '${m.x.toStringAsFixed(4)},${m.y.toStringAsFixed(4)},${m.z.toStringAsFixed(4)}'
          : ',,';

      debugPrint('SENSOR|$now|$accelStr|$gyroStr|$magStr');
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
  }
}
```

**Key decisions in this code:**
- Sensors sample at 2x the output Hz so the buffer always has a recent value when the timer fires.
- `sensors_plus` new API: `accelerometerEventStream()`, `gyroscopeEventStream()`, `magnetometerEventStream()` with `samplingPeriod` parameter (the old `gyroscopeEvents` getter is deprecated).
- If a sensor hasn't fired yet, the group is `,,` (empty but parseable — 3 empty fields).
- Timestamp is Unix milliseconds (integer, no decimals).

**Step 2: Run flutter analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No new errors (3 pre-existing info issues are OK).

**Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: expand SensorLogger with accel + mag + structured output"
```

---

### Task 2: Verify on physical device

**Step 1: Uncomment the start call**

In `lib/main.dart:56`, change:
```dart
//sensorLogger.start(hz: 25);
```
to:
```dart
sensorLogger.start(hz: 25);
```

**Step 2: Run on device**

Run: `flutter run` on a physical iOS device via USB cable.

**Step 3: Verify output**

In the flutter run console, you should see lines like:
```
SENSOR|1709312456123|0.0123,-9.8012,0.4321|0.0045,-0.0012,0.0034|12.3400,-45.6700,23.8900
```

Verify:
- Lines appear at roughly 25/sec
- All three sensor groups have values (not `,,`)
- Values change when you move/rotate the phone

**Step 4: Test grep piping**

In a separate terminal:
```bash
flutter logs | grep "SENSOR|"
```
Verify: Only SENSOR lines appear, clean and parseable.

**Step 5: Re-comment the start call**

Change back to:
```dart
//sensorLogger.start(hz: 25);
```

The logger stays off by default — user uncomments when needed.

**Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "test: verify sensor streaming on device, keep start commented"
```

---

### Task 3: Update memory files

**Files:**
- Modify: `~/.claude/projects/.../memory/state.md`
- Modify: `~/.claude/projects/.../memory/milestones.md`

**Step 1: Update state.md** — mark implementation tasks as done.

**Step 2: Update milestones.md** — check off completed milestones.
