# Sensor Streaming Design

## Goal
Read accelerometer, magnetometer, and gyroscope in realtime on iOS. Stream formatted data to the PC console via `debugPrint` + `flutter run` for ML pipeline consumption and debug visibility.

## Approach
Expand existing `SensorLogger` class in `main.dart` (Approach A).

## Data Format
One line per sample, pipe-delimited:
```
SENSOR|<unix_timestamp_ms>|<accel_x>,<accel_y>,<accel_z>|<gyro_x>,<gyro_y>,<gyro_z>|<mag_x>,<mag_y>,<mag_z>
```
- 4 decimal places for all values
- Units: accel = m/s², gyro = rad/s, mag = µT
- `SENSOR|` prefix for grep filtering

## Architecture
- 3 `StreamSubscription`s listen to accelerometer, gyroscope, magnetometer via `sensors_plus`
- Each stores its latest event in a buffer variable
- A periodic `Timer` at the configured Hz (default 25) emits the combined line
- `start(hz)` / `stop()` interface unchanged

## PC Consumption
```bash
flutter run 2>&1 | grep "SENSOR|"
flutter run 2>&1 | grep "SENSOR|" > sensor_data.txt
```

## Constraints
- No new dependencies (sensors_plus already in pubspec)
- No new files (expand existing class)
- No UI changes
- Debug builds only (debugPrint)
