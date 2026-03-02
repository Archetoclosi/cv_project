import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_screen.dart';
import 'theme/app_colors.dart';

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

/// Istanza globale del logger
final SensorLogger sensorLogger = SensorLogger();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  /// Avvio logger giroscopio
  //sensorLogger.start(hz: 25);

  runApp(const MyApp());
}

/// APP PRINCIPALE
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        primaryColor: const Color(0xFFB77EF1),
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white),
          titleLarge: TextStyle(color: Colors.white),
          titleMedium: TextStyle(color: Colors.white),
          titleSmall: TextStyle(color: Colors.white),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB77EF1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: child!,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthScreen(),
        '/chats': (context) => const ChatListScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: args['chatId'] as String,
              contactName: args['contactName'] as String,
              contactColor: AppColors.primary,
            ),
          );
        }
        return null;
      },
    );
  }
}
