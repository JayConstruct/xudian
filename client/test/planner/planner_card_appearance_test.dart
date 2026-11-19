import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';
import 'package:task_app/core/module_host/planner_card_appearance.dart';
import 'package:task_app/core/module_host/planner_status_indicator.dart';

const _appearance = <String, Object?>{
  'borderStyle': 'dashed',
  'titleDecoration': 'lineThrough',
  'cornerIcon': 'slash',
  'badgeText': '已取消',
};
const _cancelled = <String, Object?>{
  'id': 'writing',
  'title': '写作提纲',
  'color': '#858B95',
  'start': '2026-10-15T09:00:00',
  'end': '2026-10-15T10:00:00',
  'appearance': _appearance,
  'sourceLabel': '已取消',
  'selectionNote': '原安排已保留，此时段可重新安排',
  'selectionLayout': 'inlineActions',
  'event': {'type': 'detail', 'id': 'writing'},
  'actions': [
    {
      'label': '恢复任务',
      'icon': 'undo',
      'event': {'type': 'restoreTask', 'id': 'writing'},
    },
  ],
};

void main() {
  testWidgets(
    'dashed outline has gaps and corner marks leave both time labels untouched',
    (tester) async {
      const boundaryKey = ValueKey('appearance-pixels');
      for (final width in [140.0, 72.0, 1.0]) {
        final leading = width == 140 ? 34.0 : 68.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: PlannerCardDecoration(
                    appearance: PlannerCardAppearance.of(_cancelled),
                    color: const Color(0xFF606670),
                    surface: Colors.white,
                    textStyle: const TextStyle(fontSize: 9),
                    textDirection: TextDirection.ltr,
                    textScaler: TextScaler.linear(2),
                    leadingLabelWidth: leading,
                    child: SizedBox(
                      width: width,
                      height: 90,
                      child: const ColoredBox(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          bool ink(int x, int y) {
            final offset = (y * image.width + x) * 4;
            return bytes.getUint8(offset) != 255 ||
                bytes.getUint8(offset + 1) != 255 ||
                bytes.getUint8(offset + 2) != 255;
          }

          // Interior to the outline, this entire leading column is reserved for
          // the original start and end labels even when no badge can fit.
          for (var y = 4; y < 86; y++) {
            for (var x = 4; x < math.min(leading - 2, image.width - 4); x++) {
              expect(
                ink(x, y),
                false,
                reason: 'width=$width; decoration covered ($x,$y)',
              );
            }
          }
          if (width == 140) {
            final edge = [for (var x = 15; x < 125; x++) ink(x, 1)];
            expect(edge, contains(true));
            expect(
              edge,
              contains(false),
              reason: 'Dashed outline must retain visible gaps.',
            );
            expect(
              [
                for (var y = 4; y < 19; y++)
                  for (var x = 121; x < 137; x++) ink(x, y),
              ],
              contains(true),
              reason: 'Corner slash must be visible.',
            );
          }
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final size in [const Size(411, 900), const Size(320, 900)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'cancelled block stays at its original bounds and offers inline restore at $size $brightness with large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final events = <Object?>[];
          final active = <String, Object?>{..._cancelled}
            ..remove('appearance')
            ..remove('actions')
            ..remove('selectionNote');
          final scene = ValueNotifier<BoardItem>(active);
          addTearDown(scene.dispose);
          await tester.pumpWidget(
            ValueListenableBuilder<BoardItem>(
              valueListenable: scene,
              builder: (context, task, _) => MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(1.8),
                  ),
                  child: Scaffold(
                    body: PlannerBoard(
                      days: const [
                        {'date': '2026-10-15', 'label': '10/15'},
                        {'date': '2026-10-16', 'label': '10/16'},
                        {'date': '2026-10-17', 'label': '10/17'},
                      ],
                      blocks: [
                        task,
                        const {
                          'id': 'completed',
                          'title': '整理笔记',
                          'completed': true,
                          'statusIndicator': 'edgeToCorner',
                          'start': '2026-10-16T09:00:00',
                          'end': '2026-10-16T10:00:00',
                        },
                      ],
                      options: const {
                        'dashboard': true,
                        'continuousDates': true,
                        'visibleDays': 3,
                        'initialDate': '2026-10-15',
                        'startMinute': 480,
                        'endMinute': 720,
                        'initialMinute': 480,
                        'pixelsPerMinute': 2,
                      },
                      onEvent: events.add,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final block = find.byKey(const ValueKey('block:writing:2026-10-15'));
          final title = find.descendant(of: block, matching: find.text('写作提纲'));
          final start = find.descendant(
            of: block,
            matching: find.text('09:00'),
          );
          final end = find.descendant(of: block, matching: find.text('10:00'));
          final bounds = tester.getRect(block),
              titleBounds = tester.getRect(title),
              startBounds = tester.getRect(start),
              endBounds = tester.getRect(end);
          scene.value = _cancelled;
          await tester.pumpAndSettle();
          expect(tester.getRect(block), bounds);
          expect(tester.getRect(title), titleBounds);
          expect(tester.getRect(start), startBounds);
          expect(tester.getRect(end), endBounds);
          expect(
            tester.widget<Text>(title).style!.decoration,
            TextDecoration.lineThrough,
          );
          expect(
            tester.widget<Text>(start).style!.decoration,
            isNot(TextDecoration.lineThrough),
          );
          expect(find.byType(PlannerCardDecoration), findsOneWidget);
          expect(find.byType(PlannerStatusIndicator), findsOneWidget);
          await tester.tap(title);
          await tester.pumpAndSettle();
          expect(find.text('已取消'), findsOneWidget);
          expect(find.text('原安排已保留，此时段可重新安排'), findsOneWidget);
          final restore = find.text('恢复任务'), details = find.text('查看详情');
          expect(
            (tester.getCenter(restore).dy - tester.getCenter(details).dy).abs(),
            lessThan(10),
          );
          expect(find.text('编辑时间'), findsNothing);
          expect(find.byTooltip('拖动调整时长'), findsNothing);
          await tester.tap(restore);
          await tester.pumpAndSettle();
          expect(events.single, {'type': 'restoreTask', 'id': 'writing'});
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
