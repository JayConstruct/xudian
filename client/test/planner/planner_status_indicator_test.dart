import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_status_indicator.dart';

const _indicatorKey = ValueKey('status-indicator');
const _textKey = ValueKey('status-child-text');

Future<void> _mount(
  WidgetTester tester, {
  required bool completed,
  bool reduced = false,
  VoidCallback? onTap,
  double badgeSize = 16,
  bool badgeAtBottom = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: Center(
          child: PlannerStatusIndicator(
            key: _indicatorKey,
            completed: completed,
            color: const Color(0xFF276EAA),
            badgeSize: badgeSize,
            badgeAtBottom: badgeAtBottom,
            child: SizedBox(
              width: 180,
              height: 64,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('阅读任务 09:00–10:00', key: _textKey),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

double _progress(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(_indicatorKey),
      matching: find.byType(CustomPaint),
    ),
  );
  final progress =
      (paint.foregroundPainter as dynamic).progress as Animation<double>;
  return progress.value;
}

void main() {
  testWidgets(
    'a narrow marker leaves the leading time label untouched when only 3dp remain',
    (tester) async {
      const boundaryKey = ValueKey('status-narrow-pixel-boundary');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: const PlannerStatusIndicator(
                  completed: true,
                  color: Color(0xFF0055CC),
                  railWidth: 2,
                  leadingLabelWidth: 94,
                  child: SizedBox(
                    width: 100,
                    height: 80,
                    child: ColoredBox(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          expect(image.width, 100);
          expect(image.height, 80);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var edgePixels = 0;
          String? obscuredPixel;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final offset = (y * image.width + x) * 4;
              final white =
                  bytes.getUint8(offset) == 255 &&
                  bytes.getUint8(offset + 1) == 255 &&
                  bytes.getUint8(offset + 2) == 255 &&
                  bytes.getUint8(offset + 3) == 255;
              if (white) continue;
              if (x >= 96) {
                edgePixels++;
              } else {
                obscuredPixel ??=
                    '($x, $y), rgba=${List.generate(4, (channel) => bytes.getUint8(offset + channel))}';
              }
            }
          }
          expect(
            edgePixels,
            greaterThan(0),
            reason: 'The narrow completed marker must remain visible at the right edge.',
          );
          expect(
            obscuredPixel,
            isNull,
            reason: 'The marker must not cover the leading label or any other content left of x=96.',
          );
        } finally {
          image.dispose();
        }
      });
    },
  );

  testWidgets(
    'intermediate marker pixels stay out of the title region while the rail becomes a corner badge',
    (tester) async {
      const boundaryKey = ValueKey('status-pixel-boundary');
      Widget scene(bool completed) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: PlannerStatusIndicator(
                completed: completed,
                color: const Color(0xFF0055CC),
                child: const SizedBox(
                  width: 100,
                  height: 80,
                  child: ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(scene(false));
      await tester.pumpWidget(scene(true));
      await tester.pump();
      for (var frame = 1; frame <= 8; frame++) {
        await tester.pump(const Duration(milliseconds: 35));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            expect(image.width, 100);
            expect(image.height, 80);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            var paintedPixels = 0;
            String? obscuredPixel;
            for (var y = 0; y < image.height; y++) {
              for (var x = 0; x < image.width; x++) {
                final offset = (y * image.width + x) * 4;
                final white =
                    bytes.getUint8(offset) == 255 &&
                    bytes.getUint8(offset + 1) == 255 &&
                    bytes.getUint8(offset + 2) == 255 &&
                    bytes.getUint8(offset + 3) == 255;
                if (white) continue;
                paintedPixels++;
                final inRail = x >= 97;
                final inCorner = x >= 81 && y >= 3 && y < 20;
                if (!inRail && !inCorner) {
                  obscuredPixel ??= '($x, $y) at ${frame * 35}ms';
                }
              }
            }
            expect(
              paintedPixels,
              greaterThan(0),
              reason: 'The sampled frame must include a painted marker.',
            );
            expect(
              obscuredPixel,
              isNull,
              reason: 'Marker pixels must stay within the right 3dp rail or the free top corner.',
            );
          } finally {
            image.dispose();
          }
        });
      }
    },
  );

  testWidgets(
    'initial completed and pending states render their targets without entrance animation',
    (tester) async {
      await _mount(tester, completed: true);
      expect(_progress(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 140));
      expect(_progress(tester), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, completed: false);
      expect(_progress(tester), 0);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'completion reverses continuously midway and keeps the child text rectangle unchanged',
    (tester) async {
      await _mount(tester, completed: false);
      final state = tester.state(find.byKey(_indicatorKey));
      final textRect = tester.getRect(find.byKey(_textKey));
      final indicatorRect = tester.getRect(find.byKey(_indicatorKey));
      await _mount(tester, completed: true);
      expect(tester.state(find.byKey(_indicatorKey)), same(state));
      expect(_progress(tester), 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      final halfway = _progress(tester);
      expect(halfway, greaterThan(0));
      expect(halfway, lessThan(1));
      expect(tester.getRect(find.byKey(_textKey)), textRect);
      expect(tester.getRect(find.byKey(_indicatorKey)), indicatorRect);

      await _mount(tester, completed: false);
      expect(tester.state(find.byKey(_indicatorKey)), same(state));
      expect(_progress(tester), closeTo(halfway, .0001));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      expect(_progress(tester), lessThan(halfway));
      await tester.pump(const Duration(milliseconds: 280));
      expect(_progress(tester), 0);
      expect(tester.getRect(find.byKey(_textKey)), textRect);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'enabling reduced motion during a transition immediately reaches the current target',
    (tester) async {
      await _mount(tester, completed: false);
      final state = tester.state(find.byKey(_indicatorKey));
      await _mount(tester, completed: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(_progress(tester), inExclusiveRange(0, 1));
      await _mount(tester, completed: true, reduced: true);
      expect(tester.state(find.byKey(_indicatorKey)), same(state));
      expect(_progress(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
      await _mount(tester, completed: false, reduced: true);
      expect(_progress(tester), 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'foreground status paint keeps text placement and passes card and corner taps to its child',
    (tester) async {
      var taps = 0;
      await _mount(tester, completed: false, onTap: () => taps++);
      final textRect = tester.getRect(find.byKey(_textKey));
      await tester.tapAt(
        tester.getTopRight(find.byKey(_indicatorKey)) + const Offset(-3, 3),
      );
      expect(taps, 1);
      await _mount(tester, completed: true, onTap: () => taps++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 280));
      await tester.tapAt(
        tester.getTopRight(find.byKey(_indicatorKey)) + const Offset(-3, 3),
      );
      expect(taps, 2);
      await _mount(
        tester,
        completed: true,
        onTap: () => taps++,
        badgeSize: 10,
        badgeAtBottom: true,
      );
      expect(tester.getRect(find.byKey(_textKey)), textRect);
      await tester.tapAt(
        tester.getBottomRight(find.byKey(_indicatorKey)) + const Offset(-3, -3),
      );
      expect(taps, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing an active transition cancels its ticker', (
    tester,
  ) async {
    await _mount(tester, completed: false);
    await _mount(tester, completed: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(_progress(tester), inExclusiveRange(0, 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
