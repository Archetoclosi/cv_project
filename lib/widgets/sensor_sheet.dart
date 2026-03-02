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
