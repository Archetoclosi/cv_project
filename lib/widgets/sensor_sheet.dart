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
