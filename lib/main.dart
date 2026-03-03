import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_screen.dart';
import 'theme/app_colors.dart';

enum SensorConnectionState { disconnected, connecting, connected, failed }

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
    if (isRunning ||
        connectionState.value == SensorConnectionState.connecting ||
        connectionState.value == SensorConnectionState.connected) return;
    connectionState.value = SensorConnectionState.connected;
    _startSensors(hz, websocket: false);
  }

  /// Connect via WebSocket, then start sensors on success.
  Future<void> connect({required String wsUrl, int hz = 5}) async {
    if (connectionState.value == SensorConnectionState.connecting ||
        connectionState.value == SensorConnectionState.connected) return;
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
        .listen((e) => _accel = e, onError: (e) => debugPrint('Accel error: $e'));
    _gyroSub = gyroscopeEventStream(samplingPeriod: sensorPeriod)
        .listen((e) => _gyro = e, onError: (e) => debugPrint('Gyro error: $e'));
    _magSub = magnetometerEventStream(samplingPeriod: sensorPeriod)
        .listen((e) => _mag = e, onError: (e) => debugPrint('Mag error: $e'));

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
          Future.microtask(_stopTimerAndSensors);
        }
      } else {
        debugPrint(line);
      }
    });
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
