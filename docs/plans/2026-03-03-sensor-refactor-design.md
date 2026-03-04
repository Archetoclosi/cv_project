# Sensor Streaming Refactor — Design

Date: 2026-03-03

## Goal

Give the user full control of sensor streaming from the app side:
- Choose transmission mode before connecting
- Explicit connect/disconnect (no auto-start on launch)
- Proper connection status (disconnected / connecting / connected / failed)
- IP persisted across sessions
- Python receiver works untethered from `flutter run`

## Section 1 — SensorLogger

### Changes to `lib/main.dart`

**New enum:**
```dart
enum SensorConnectionState { disconnected, connecting, connected, failed }
```

**SensorMode simplified** — remove `both`; keep only `debug` and `websocket`.

**SensorLogger gets:**
- `ValueNotifier<SensorConnectionState> connectionState` — UI listens to this reactively
- `start()` becomes two-phase for WebSocket: sets `connecting`, attempts connect, transitions to `connected` or `failed`
- `stop()` resets state to `disconnected`, closes WS channel
- Auto-start in `main()` removed — user connects manually from SensorSheet

## Section 2 — SensorSheet UI

Rebuilt as a `ValueListenableBuilder` on `sensorLogger.connectionState`.

### Release builds (always WebSocket)
- IP field (pre-filled from SharedPreferences key `sensor_ws_host`, editable)
- Status row: colored dot + label
- Connect / Disconnect button

### Debug builds (`kDebugMode == true`)
- Segmented toggle above IP field: **Print (cable)** | **WebSocket (WiFi)**
- When "Print" selected: IP field hidden, no connection state shown
- When "WebSocket" selected: same UI as release builds

### Status dot colors
| State | Color | Animation |
|---|---|---|
| disconnected | grey | none |
| connecting | amber | pulsing |
| connected | green | none |
| failed | red | none |

### IP persistence
On connect tap: save typed IP to `SharedPreferences` before opening WS channel.

## Section 3 — Python receiver

`tools/sensor_receiver.py` — **no changes needed.**

The script is a plain WebSocket server on `0.0.0.0:8765`. It already works untethered from `flutter run` because WebSocket data arrives independently over the network.

The untethering is achieved on the app side:
- **Release build**: only WebSocket mode available → Python script is always the receiver
- **Debug build, Print mode**: data goes to the `flutter run` terminal → Python script not involved
- **Debug build, WebSocket mode**: same as release

## Out of scope
- iOS USB tunneling (no iproxy equivalent for device→host direction)
- Android `adb reverse` USB tunneling (WiFi WebSocket is sufficient)
- QR code IP discovery
