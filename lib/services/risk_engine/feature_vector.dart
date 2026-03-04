/// Input contract for the Risk Engine.
/// All values are expected to be already extracted and normalized
/// over a sliding window (recommended: ~2 seconds).
class FeatureVector {
  // ─── YOLO / Vision ────────────────────────────────────────────────────────

  /// A `cell phone` class was detected in at least one frame of the window.
  final bool phoneDetected;

  /// Max detection confidence for `cell phone` in the window. [0.0 – 1.0]
  final double phoneConfidence;

  /// Fraction of window frames where a phone was detected. [0.0 – 1.0]
  /// 0.0 = never seen, 1.0 = present in every frame.
  final double phonePersistence;

  /// Bounding box area of the phone as a fraction of the total frame area. [0.0 – 1.0]
  /// Larger = phone is closer / more prominent.
  final double phoneAreaRatio;

  /// Horizontal position of the phone bbox center, normalized. [0.0 – 1.0]
  /// 0.5 = dead center (more suspicious).
  final double phoneCenterX;

  /// Vertical position of the phone bbox center, normalized. [0.0 – 1.0]
  final double phoneCenterY;

  /// At least one human face was detected in the window.
  final bool faceDetected;

  /// Number of distinct faces detected (max across frames in the window).
  final int faceCount;

  // ─── IMU ──────────────────────────────────────────────────────────────────

  /// Mean magnitude of the accelerometer vector over the window. [m/s²]
  /// Values near 9.8 = device at rest.
  final double accelMagnitudeMean;

  /// Std-dev of the accelerometer magnitude over the window. [m/s²]
  /// Low value = device is stationary.
  final double accelMagnitudeStd;

  /// Mean magnitude of the gyroscope vector over the window. [rad/s]
  final double gyroMagnitudeMean;

  /// Std-dev of the gyroscope magnitude over the window. [rad/s]
  final double gyroMagnitudeStd;

  /// Device tilt angle with respect to vertical. [degrees, 0 – 180]
  /// ~0° = screen facing up (flat on table)
  /// ~90° = screen vertical (normal use / photo taking)
  /// ~45-75° = typical camera-pointing angle (suspicious)
  final double tiltAngle;

  /// Std-dev of the magnetometer magnitude over the window.
  /// Spikes may indicate a nearby electronic device.
  final double magMagnitudeStd;

  // ─── Derived / Composite (computed in constructor) ────────────────────────

  /// True if the device appears stationary during the window.
  /// Defined as: accelMagnitudeStd < 0.3 && gyroMagnitudeStd < 0.05
  late final bool isStationary;

  /// True if tilt is in the typical range for pointing a phone at a screen.
  /// Defined as: tiltAngle ∈ [30°, 75°]
  late final bool tiltInPhotoRange;

  /// Combined signal: phone visible AND device stationary.
  late final bool phoneAndStationary;

  /// Combined signal: phone visible AND tilt in photo range.
  late final bool phoneAndTilt;

  /// Weighted persistence signal: confidence × persistence.
  /// Reduces noise from fleeting detections.
  late final double phoneStrength;

  FeatureVector({
    required this.phoneDetected,
    required this.phoneConfidence,
    required this.phonePersistence,
    required this.phoneAreaRatio,
    required this.phoneCenterX,
    required this.phoneCenterY,
    required this.faceDetected,
    required this.faceCount,
    required this.accelMagnitudeMean,
    required this.accelMagnitudeStd,
    required this.gyroMagnitudeMean,
    required this.gyroMagnitudeStd,
    required this.tiltAngle,
    required this.magMagnitudeStd,
  }) {
    isStationary = accelMagnitudeStd < 0.3 && gyroMagnitudeStd < 0.05;
    tiltInPhotoRange = tiltAngle >= 30.0 && tiltAngle <= 75.0;
    phoneAndStationary = phoneDetected && isStationary;
    phoneAndTilt = phoneDetected && tiltInPhotoRange;
    phoneStrength = phoneConfidence * phonePersistence;
  }

  /// Convenience factory for testing / simulation.
  factory FeatureVector.zero() => FeatureVector(
        phoneDetected: false,
        phoneConfidence: 0.0,
        phonePersistence: 0.0,
        phoneAreaRatio: 0.0,
        phoneCenterX: 0.5,
        phoneCenterY: 0.5,
        faceDetected: false,
        faceCount: 0,
        accelMagnitudeMean: 9.8,
        accelMagnitudeStd: 0.05,
        gyroMagnitudeMean: 0.0,
        gyroMagnitudeStd: 0.01,
        tiltAngle: 90.0,
        magMagnitudeStd: 0.1,
      );

  @override
  String toString() =>
      'FeatureVector(phoneDetected=$phoneDetected, phoneStrength=${phoneStrength.toStringAsFixed(2)}, '
      'isStationary=$isStationary, tiltInPhotoRange=$tiltInPhotoRange, '
      'tiltAngle=${tiltAngle.toStringAsFixed(1)}°, faceDetected=$faceDetected)';
}
