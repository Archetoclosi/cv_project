import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ping/widgets/flicker_shield.dart';

void main() {
  group('FlickerShield', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlickerShield(
            child: Text('protected'),
          ),
        ),
      );

      expect(find.text('protected'), findsOneWidget);
    });

    testWidgets('contains a RepaintBoundary for the overlay', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlickerShield(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );

      // Advance time so the noise overlay becomes visible
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(RepaintBoundary), findsWidgets);
    });

    testWidgets('contains a CustomPaint for the noise overlay', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlickerShield(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );

      // Advance time so the noise overlay becomes visible
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('overlay has opacity 0.3', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlickerShield(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );

      // Advance time so the noise overlay becomes visible
      await tester.pump(const Duration(milliseconds: 50));

      // Find the Opacity widget wrapping the noise overlay
      final opacityWidget = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacityWidget.any((w) => (w.opacity - 0.3).abs() < 0.01), isTrue);
    });
  });
}
