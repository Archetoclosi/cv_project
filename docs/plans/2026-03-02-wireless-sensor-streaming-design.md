# Wireless Sensor Streaming Design

## Goal
Add WebSocket-based wireless transport to SensorLogger so sensor data can be streamed to a Mac without a USB cable. Preserve the existing debugPrint method. Add a sensor control bottom sheet to the app UI.

## Phase 1: WebSocket Transport

### SensorLogger API Changes
New enum and parameters on `start()`:

```dart
enum SensorMode { debug, websocket, both }

sensorLogger.start(
  hz: 5,
  mode: SensorMode.websocket,
  wsUrl: 'ws://192.168.1.100:8765',
);
```

- `debug` — debugPrint only (current behavior, default)
- `websocket` — sends over WebSocket only (works in release builds)
- `both` — debugPrint + WebSocket simultaneously

### Connection Behavior
- `start()` opens WS connection before starting the timer
- Connection failure → falls back to debugPrint + logs warning
- Connection drop mid-stream → lines go to debugPrint as fallback
- No reconnect logic (restart to reconnect)
- `stop()` closes WS connection + cancels sensors/timer

### Data Format
Same `SENSOR|<unix_ms>|A:<x>,<y>,<z>|G:<x>,<y>,<z>|M:<x>,<y>,<z>` line — identical whether cable or WiFi.

### New Dependency
- `web_socket_channel` (official Dart team package)

### IP Configuration
- Hardcoded for now
- Future: editable from UI

### Mac-Side Receiver
`tools/sensor_receiver.py` — ~15 lines of Python:
- WebSocket server on port 8765
- Prints incoming lines to terminal
- Dependency: `websockets` (pip install)

## Phase 2: Sensor Bottom Sheet

### Navigation
Icon button in `ChatListScreen` header bar (next to What's New and logout buttons). Tapping opens a bottom sheet.

### UI (bottom sheet)
- Same dark glassmorphic style as `WhatsNewSheet`
- **Connection status indicator** — colored dot + text: "Connected" (green) / "Disconnected" (red) / "Connecting..." (yellow)
- **Start/Stop button** — toggles `sensorLogger.start()` / `sensorLogger.stop()`
- **IP display** — shows hardcoded IP (locked, not editable for now)
- **Mode display** — shows current mode (locked to websocket for now)

### File
`lib/widgets/sensor_sheet.dart` — follows WhatsNewSheet pattern.

## Future (not in scope)
- Editable IP text field
- Mode selector in UI
- Auto-reconnect on disconnect
- QR code discovery
