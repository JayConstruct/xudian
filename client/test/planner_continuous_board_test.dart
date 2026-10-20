import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_scroll_behavior.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/module_host/planner_board.dart';

List<BoardItem> _days(String first) => List.generate(21, (index) {
  final date = DateTime.parse(first).add(Duration(days: index));
  return {'date': date.toIso8601String().substring(0, 10)};
});

const _options = <String, Object?>{
  'dashboard': true,
  'continuousDates': true,
  'visibleDays': 3,
  'today': '2026-10-20',
  'now': '2026-10-20T10:20:00',
  'initialDate': '2026-10-19',
  'scrollRequest': 0,
  'startMinute': 480,
  'endMinute': 1080,
  'pixelsPerMinute': 1.1,
  'rangeEvent': {'type': 'period'},
  'todayEvent': {'type': 'today'},
  'viewportEvent': {'type': 'timelineViewport'},
};

const _candidates = <BoardItem>[
  {
    'id': 'reading',
    'title': '阅读论文',
    'overdue': true,
    'durationMinutes': 60,
    'event': {'type': 'detail'},
    'moveEvent': {'type': 'move'},
  },
  {
    'id': 'shopping',
    'title': '采购清单',
    'durationMinutes': 30,
    'event': {'type': 'detail'},
    'moveEvent': {'type': 'move'},
  },
  {
    'id': 'notes',
    'title': '整理笔记',
    'durationMinutes': 150,
    'event': {'type': 'detail'},
    'moveEvent': {'type': 'move'},
  },
];

Future<void> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 900),
  double scale = 1,
  List<BoardItem>? days,
  List<BoardItem>? blocks,
  BoardItem options = _options,
  ValueChanged<Object?>? onEvent,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppDesign.theme(Brightness.light),
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: PlannerBoard(
          days: days ?? _days('2026-10-12'),
          candidates: _candidates,
          blocks:
              blocks ??
              const [
                {
                  'id': 'class',
                  'title': '专业课程',
                  'start': '2026-10-20T09:50:00',
                  'end': '2026-10-20T11:25:00',
                  'readOnly': true,
                },
              ],
          options: options,
          onEvent: onEvent ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder _key(String value) => find.byKey(ValueKey(value));
ScrollController _horizontal(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(_key('planner-horizontal'))
    .controller!;

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('compact timeline geometry at $width px and ${scale}x', (
        tester,
      ) async {
        await _mount(tester, size: Size(width, 900), scale: scale);
        final columnWidth = (width - 48) / 3;
        expect(
          tester.getSize(_key('planner-day:2026-10-20')).width,
          closeTo(columnWidth, .01),
        );
        expect(
          tester.getRect(_key('planner-day:2026-10-20')).left,
          closeTo(48 + columnWidth, .01),
        );
        expect(
          tester.getSize(_key('planner-candidate-region')).height,
          lessThanOrEqualTo(scale == 1 ? 44 : 60),
        );
        expect(_key('planner-candidates-popup'), findsNothing);
        expect(_key('planner-range-rail'), findsNothing);
        expect(find.byTooltip('上一时段'), findsNothing);
        expect(find.byTooltip('下一时段'), findsNothing);
        expect(_key('planner-return-today'), findsNothing);
        expect(find.text('10月19–21日'), findsOneWidget);
        final gridTop = tester.getTopLeft(_key('planner-vertical')).dy;
        expect(gridTop, lessThanOrEqualTo(scale == 1 ? 128 : 176));
        expect(_key('planner-now-line'), findsOneWidget);
        expect(_key('planner-now-label'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('swiping days updates visible dates and offers return to today', (
    tester,
  ) async {
    final events = <Object?>[];
    await _mount(tester, onEvent: events.add);
    final headerTop = tester.getTopLeft(_key('planner-day:2026-10-20')).dy;
    final gridTop = tester.getTopLeft(_key('planner-vertical')).dy;
    await tester.drag(_key('planner-horizontal'), const Offset(-342, 0));
    await tester.pumpAndSettle();
    expect(find.text('10月22–24日'), findsOneWidget);
    expect(_key('planner-return-today'), findsOneWidget);
    expect(tester.getTopLeft(_key('planner-day:2026-10-22')).dy, headerTop);
    expect(tester.getTopLeft(_key('planner-vertical')).dy, gridTop);
    expect(_key('planner-now-label'), findsNothing);
    expect(events.whereType<Map>().last, {
      'type': 'timelineViewport',
      'startDate': '2026-10-22',
      'visibleDays': 3,
    });
    await tester.tap(_key('planner-return-today'));
    expect(events.last, {'type': 'today'});
    await tester.tap(_key('planner-date-picker'));
    expect(events.last, {'type': 'period'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'swiping the compact date header scrolls the same days as the grid',
    (tester) async {
      final events = <Object?>[];
      await _mount(tester, onEvent: events.add);
      await tester.drag(_key('planner-date-header'), const Offset(-342, 0));
      await tester.pumpAndSettle();
      expect(find.text('10月22–24日'), findsOneWidget);
      expect(_horizontal(tester).offset, closeTo(10 * 114, .01));
      expect(
        events.whereType<Map>().where(
          (event) => event['type'] == 'timelineViewport',
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'window refresh preserves absolute date, vertical reading and sub-day travel',
    (tester) async {
      final first = ValueNotifier('2026-10-12');
      addTearDown(first.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: first,
              builder: (context, start, _) => PlannerBoard(
                days: _days(start),
                options: _options,
                onEvent: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final horizontal = _horizontal(tester);
      final width = (800 - 48) / 3;
      horizontal.jumpTo(10.25 * width);
      final vertical = tester
          .widget<SingleChildScrollView>(_key('planner-vertical'))
          .controller!;
      vertical.jumpTo(100);
      await tester.pump();
      final before = tester.getRect(_key('planner-day:2026-10-22'));
      first.value = '2026-10-15';
      await tester.pump();
      await tester.pump();
      expect(horizontal.offset, closeTo(7.25 * width, .01));
      expect(
        tester.getRect(_key('planner-day:2026-10-22')).left,
        closeTo(before.left, .01),
      );
      expect(vertical.offset, 100);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('automatic time bounds retain the clock time being read', (
    tester,
  ) async {
    final shifted = ValueNotifier(false);
    addTearDown(shifted.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: shifted,
            builder: (context, changed, _) => PlannerBoard(
              days: _days('2026-10-12'),
              options: {
                ..._options,
                'startMinute': changed ? 540 : 480,
                'endMinute': 1440,
                'displayHoursLabel': changed
                    ? '自动 09:00–24:00'
                    : '自动 08:00–24:00',
              },
              onEvent: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final vertical = tester
        .widget<SingleChildScrollView>(_key('planner-vertical'))
        .controller!;
    vertical.jumpTo(240);
    await tester.pump();
    final minute = 480 + vertical.offset / 1.1;
    shifted.value = true;
    await tester.pump();
    await tester.pump();
    expect(540 + vertical.offset / 1.1, closeTo(minute, .01));
    expect(find.text('10月19–21日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaving a focused task restores the continuous date and time viewport',
    (tester) async {
      await _mount(tester, size: const Size(390, 700));
      final vertical = tester
          .widget<SingleChildScrollView>(_key('planner-vertical'))
          .controller!;
      vertical.jumpTo(60);
      await tester.pump();
      await tester.tap(find.text('专业课程').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('放大该时段'));
      await tester.pumpAndSettle();
      expect(find.text('返回时间表'), findsOneWidget);
      await tester.tap(find.text('返回时间表'));
      await tester.pumpAndSettle();
      expect(find.text('10月19–21日'), findsOneWidget);
      expect(
        tester.getRect(_key('planner-day:2026-10-19')).left,
        closeTo(48, .01),
      );
      expect(vertical.offset, closeTo(60, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit date jump supersedes retained viewport and crosses a year',
    (tester) async {
      final state = ValueNotifier(false);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: state,
              builder: (context, jumped, _) => PlannerBoard(
                days: _days(jumped ? '2026-12-24' : '2026-10-12'),
                options: {
                  ..._options,
                  if (jumped) 'initialDate': '2026-12-31',
                  'scrollRequest': jumped ? 1 : 0,
                },
                onEvent: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      state.value = true;
      await tester.pump();
      await tester.pump();
      expect(find.text('2026/12/31–2027/1/2'), findsOneWidget);
      expect(_key('planner-return-today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outside-hour tasks use an inline action and ignore offscreen preload days',
    (tester) async {
      const outside = <BoardItem>[
        {
          'id': 'late',
          'title': '夜间任务',
          'start': '2026-10-20T23:00:00',
          'end': '2026-10-20T23:30:00',
        },
        {
          'id': 'future',
          'title': '远期任务',
          'start': '2026-10-25T23:00:00',
          'end': '2026-10-25T23:30:00',
        },
      ];
      await _mount(tester, blocks: outside);
      expect(_key('planner-outside-indicator'), findsOneWidget);
      expect(
        tester.getTopLeft(_key('planner-vertical')).dy,
        lessThanOrEqualTo(128),
      );
      expect(find.byTooltip('显示时段外的安排（1）'), findsOneWidget);
      await tester.tap(_key('planner-outside-indicator'));
      await tester.pumpAndSettle();
      expect(find.text('夜间任务'), findsOneWidget);
      expect(find.text('远期任务'), findsNothing);
      await tester.tapAt(const Offset(10, 20));
      await tester.pumpAndSettle();
      _horizontal(tester).jumpTo(10 * 114);
      await tester.pump();
      expect(_key('planner-outside-indicator'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'candidate expansion overlays rather than displacing the date header or grid',
    (tester) async {
      await _mount(tester);
      final header = tester.getRect(_key('planner-day:2026-10-20'));
      final grid = tester.getRect(_key('planner-vertical'));
      await tester.tap(_key('planner-toggle-candidates'));
      await tester.pumpAndSettle();
      expect(_key('planner-candidates-popup'), findsOneWidget);
      expect(tester.getRect(_key('planner-day:2026-10-20')), header);
      expect(tester.getRect(_key('planner-vertical')), grid);
      expect(find.text('长按拖入时间表'), findsOneWidget);
      await tester.tap(find.byTooltip('收起待安排'));
      await tester.pumpAndSettle();
      expect(_key('planner-candidates-popup'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending popover preserves drag-to-schedule and closes after dropping',
    (tester) async {
      final events = <Object?>[];
      await _mount(tester, onEvent: events.add);
      await tester.tap(_key('planner-toggle-candidates'));
      await tester.pumpAndSettle();
      final source = find
          .descendant(
            of: _key('planner-candidates-expanded'),
            matching: find.byType(LongPressDraggable<BoardItem>),
          )
          .first;
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 600));
      final viewport = tester.getRect(_key('planner-vertical'));
      await gesture.moveTo(Offset(48 + 114 * 1.5, viewport.top + 220));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();
      final moves = events.whereType<Map>().where(
        (event) => event['type'] == 'move',
      );
      expect(moves, hasLength(1));
      expect(moves.single['start'], startsWith('2026-10-20T'));
      expect(_key('planner-candidates-popup'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
