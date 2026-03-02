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

/// LOGGER GIROSCOPIO (servizio semplice)
class SensorLogger {
  StreamSubscription<GyroscopeEvent>? _sub;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void start({int hz = 25}) {
    final minIntervalMs = (1000 / hz).round();

    _sub = gyroscopeEvents.listen((e) {
      final now = DateTime.now();
      if (now.difference(_last).inMilliseconds < minIntervalMs) return;
      _last = now;

      debugPrint(
        'GYRO ts=${now.toIso8601String()} '
        'x=${e.x.toStringAsFixed(4)} '
        'y=${e.y.toStringAsFixed(4)} '
        'z=${e.z.toStringAsFixed(4)} rad/s',
      );
    }, onError: (err) {
      debugPrint('Gyro error: $err');
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
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
