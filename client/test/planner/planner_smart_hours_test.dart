import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';

void main() {
  final range = find.byKey(const ValueKey('planner-hour-range'));
  final grid = find.byKey(const ValueKey('planner-vertical'));
  const days = [
    {'date': '2026-11-24'},
    {'date': '2026-11-25'},
  ];
  const blocks = [
    {
      'id': 'a',
      'title': '上午任务',
      'moveEvent': {'type': 'move'},
      'start': '2026-11-24T09:00:00',
      'end': '2026-11-24T12:00:00',
    },
    {
      'id': 'b',
      'title': '夜间任务',
      'start': '2026-11-25T21:30:00',
      'end': '2026-11-26T00:15:00',
    },
  ];
  Future<void> mount(
    WidgetTester tester, {
    Key? boardKey,
    bool empty = false,
    ValueChanged<Object?>? onDrop,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerBoard(
            key: boardKey,
            days: days,
            blocks: empty ? const [] : blocks,
            onEvent: onDrop ?? (_) {},
            options: const {
              'dashboard': true,
              'continuousDates': true,
              'smartHours': true,
              'visibleDays': 1,
              'initialDate': '2026-11-24',
              'initialMinute': 480,
              'pixelsPerMinute': 2,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final top in [true, false]) {
    testWidgets(
      'a deliberate ${top ? 'top' : 'bottom'} pull unlocks this session only',
      (tester) async {
        final haptics = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await mount(tester);
        String bounds() => tester.widget<Text>(range).data!;
        expect(bounds(), '08:00–13:00');
        final scroll = tester.widget<SingleChildScrollView>(grid).controller!;
        scroll.jumpTo(top ? 0 : scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final before = scroll.offset;
        final dy = top ? 1.0 : -1.0;
        Future<TestGesture> pull() async {
          // Start inside the range so touch slop is consumed before the edge.
          scroll.jumpTo(before + 32 * dy);
          final finger = await tester.startGesture(tester.getCenter(grid));
          await finger.moveBy(Offset(0, 22 * dy));
          await finger.moveBy(Offset(0, scroll.offset - before));
          await tester.pump();
          expect(scroll.offset, before);
          await finger.moveBy(Offset(0, 48 * dy));
          await tester.pump(const Duration(milliseconds: 180));
          expect(bounds(), '08:00–13:00');
          expect(
            tester
                .widget<CircularProgressIndicator>(
                  find.byType(CircularProgressIndicator),
                )
                .value,
            closeTo(48 / 72, .001),
          );
          return finger;
        }

        final short = await pull();
        expect(find.text(top ? '继续下拉，显示全天' : '继续上拉，显示全天'), findsOneWidget);
        await short.up();
        await tester.pumpAndSettle();
        expect(bounds(), '08:00–13:00');
        expect(haptics, isEmpty);
        final long = await pull();
        await long.moveBy(Offset(0, 23 * dy));
        await tester.pump();
        expect(bounds(), '08:00–13:00');
        expect(haptics, isEmpty);
        await long.moveBy(Offset(0, dy));
        await tester.pumpAndSettle();
        expect(bounds(), '00:00–24:00');
        expect(scroll.offset, closeTo(before + 480 * 2, .1));
        await long.up();
        expect(
          haptics.where((e) => e == 'HapticFeedbackType.lightImpact'),
          hasLength(1),
        );
        await mount(tester, boardKey: const ValueKey('reopened'));
        expect(bounds(), '00:00–24:00');
        await tester.pumpWidget(const SizedBox.shrink());
        await mount(tester, empty: true);
        expect(bounds(), startsWith('08:00–'));
        expect(bounds(), isNot('00:00–24:00'));
      },
    );
  }
  testWidgets(
    'a held task can reveal the day and drop in a previously hidden hour',
    (tester) async {
      final drops = <Object?>[];
      await mount(tester, onDrop: drops.add);
      final scroll = tester.widget<SingleChildScrollView>(grid).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final view = tester.getRect(grid);
      final finger = await tester.startGesture(
        tester.getCenter(find.text('上午任务').hitTestable()),
      );
      await tester.pump(const Duration(milliseconds: 550));
      final y = view.bottom - 92;
      await finger.moveTo(Offset(view.center.dx, y));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(range).data, '08:00–13:00');
      await finger.moveBy(const Offset(0, 48));
      await tester.pump();
      expect(find.text('继续向下拖，显示全天'), findsOneWidget);
      await finger.moveBy(const Offset(0, 23));
      await tester.pump();
      expect(tester.widget<Text>(range).data, '08:00–13:00');
      await finger.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(tester.widget<Text>(range).data, '00:00–24:00');
      await finger.moveTo(Offset(view.center.dx, view.bottom - 4));
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      await finger.up();
      await tester.pumpAndSettle();
      expect(drops, hasLength(1));
      final event = drops.single as Map;
      expect(event['start'] as String, startsWith('2026-11-24'));
      expect(
        int.parse((event['start'] as String).substring(11, 13)),
        greaterThanOrEqualTo(13),
      );
    },
  );

  testWidgets(
    'swiping a second date into view includes its late cross-midnight task and preserves screen time',
    (tester) async {
      await mount(tester);
      final scroll = tester.widget<SingleChildScrollView>(grid).controller!;
      scroll.jumpTo(60);
      await tester.pumpAndSettle();
      await tester.dragFrom(tester.getCenter(grid), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(range).data, endsWith('–24:00'));
      final start =
          int.parse(tester.widget<Text>(range).data!.substring(0, 2)) * 60;
      expect(start + scroll.offset / 2, closeTo(510, .01));
    },
  );
}
