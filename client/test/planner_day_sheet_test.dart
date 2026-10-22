import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';

const _days = [
  {'date': '2026-10-22', 'label': '10/22'},
  {'date': '2026-10-23', 'label': '10/23'},
  {'date': '2026-10-24', 'label': '10/24'},
];

BoardItem _task(String id, String start, String end, {bool readOnly = false}) =>
    {
      'id': id,
      'title': id,
      'start': start,
      'end': end,
      'readOnly': readOnly,
      'event': {'type': readOnly ? 'source' : 'detail', 'id': id},
      if (!readOnly)
        'moveEvent': {
          'type': 'move',
          'taskId': id,
          'expectedTasks': {
            id: {'revisionToken': 'revision-1'},
          },
        },
    };

const _candidate = <String, Object?>{
  'id': '整理笔记',
  'title': '整理笔记',
  'durationMinutes': 10,
  'event': {'type': 'detail', 'id': '整理笔记'},
  'moveEvent': {
    'type': 'move',
    'taskId': '整理笔记',
    'expectedTasks': {
      '整理笔记': {'revisionToken': 'candidate-1'},
    },
  },
};

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _mount(
  WidgetTester tester, {
  List<BoardItem> blocks = const [],
  List<BoardItem> candidates = const [_candidate],
  ValueChanged<Object?>? onEvent,
  Future<BoardItem> Function(BoardItem)? onPreview,
  bool enabled = true,
  bool reduced = false,
  bool settle = true,
  Size size = const Size(390, 860),
  TextScaler scaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: scaler,
          disableAnimations: reduced,
        ),
        child: Scaffold(
          body: PlannerBoard(
            days: _days,
            candidates: candidates,
            blocks: blocks,
            bottomInset: 70,
            enabled: enabled,
            options: const {
              'dashboard': true,
              'continuousDates': true,
              'initialDate': '2026-10-22',
              'today': '2026-10-22',
              'startMinute': 420,
              'endMinute': 1440,
            },
            onEvent: onEvent ?? (_) {},
            onPreview: onPreview,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_key('planner-day:2026-10-22'));
  await tester.pumpAndSettle();
  expect(_key('planner-day-sheet'), findsOneWidget);
}

Future<void> _drop(WidgetTester tester, int index) async {
  final gesture = await tester.startGesture(
    tester.getCenter(_key('planner-day-card:整理笔记')),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await gesture.moveTo(tester.getCenter(_key('planner-day-slot:$index')));
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  double opacity(WidgetTester tester) =>
      tester.widget<FadeTransition>(_key('planner-day-fade')).opacity.value;

  testWidgets(
    'day sheet enters gently and retains content until exit finishes',
    (tester) async {
      await _mount(tester);
      await tester.tap(_key('planner-day:2026-10-22'));
      await tester.pump();
      expect(opacity(tester), 0);
      final initial = tester.getRect(_key('planner-day-sheet'));
      await tester.pump(const Duration(milliseconds: 80));
      expect(opacity(tester), inExclusiveRange(0, 1));
      expect(
        tester.getRect(_key('planner-day-sheet')).top,
        lessThan(initial.top),
      );
      expect(
        tester.widget<ScaleTransition>(_key('planner-day-scale')).scale.value,
        inExclusiveRange(.98, 1),
      );
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
      final settled = tester.getRect(_key('planner-day-sheet'));
      await tester.tap(find.byTooltip('关闭当日任务'));
      await tester.pump();
      expect(_key('planner-day-sheet'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 70));
      expect(opacity(tester), inExclusiveRange(0, 1));
      expect(
        tester.getRect(_key('planner-day-sheet')).top,
        greaterThan(settled.top),
      );
      expect(_key('planner-day-card:整理笔记').hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(_key('planner-day-sheet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back interrupts entrance and repeated dismissal cannot leak to the route',
    (tester) async {
      await _mount(tester);
      await tester.tap(_key('planner-day:2026-10-22'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_key('planner-day-sheet'), findsNothing);
      expect(find.byType(PlannerBoard), findsOneWidget);
      await _open(tester);
      expect(opacity(tester), 1);
      await tester.tapAt(const Offset(5, 250));
      await tester.pumpAndSettle();
      expect(_key('planner-day-sheet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion opens and closes the sheet in one frame', (
    tester,
  ) async {
    await _mount(tester, reduced: true);
    await tester.tap(_key('planner-day:2026-10-22'));
    await tester.pump();
    expect(opacity(tester), 1);
    expect(
      tester.widget<SlideTransition>(_key('planner-day-slide')).position.value,
      Offset.zero,
    );
    await tester.tap(find.byTooltip('关闭当日任务'));
    await tester.pump();
    expect(_key('planner-day-sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing reduced motion completes the running transition without replay',
    (tester) async {
      await _mount(tester);
      await tester.tap(_key('planner-day:2026-10-22'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _mount(tester, reduced: true);
      expect(opacity(tester), 1);
      await _mount(tester, reduced: false, settle: false);
      expect(opacity(tester), 1);
      await tester.tap(find.byTooltip('关闭当日任务'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await _mount(tester, reduced: true);
      expect(_key('planner-day-sheet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date header opens sorted equal cards with two time rows on the left',
    (tester) async {
      await _mount(
        tester,
        blocks: [
          _task('报销', '2026-10-22T11:00:00', '2026-10-22T11:03:00'),
          _task(
            '课程',
            '2026-10-22T08:00:00',
            '2026-10-22T09:35:00',
            readOnly: true,
          ),
          _task('跨日', '2026-10-21T23:30:00', '2026-10-22T00:15:00'),
          _task('明天', '2026-10-23T09:00:00', '2026-10-23T10:00:00'),
        ],
      );
      await _open(tester);
      expect(_key('planner-day-card:明天'), findsNothing);
      final course = tester.getRect(_key('planner-day-card:课程'));
      final short = tester.getRect(_key('planner-day-card:报销'));
      expect(course.height, short.height);
      expect(short.top - course.bottom, 8);
      final times = _key('planner-day-times:课程');
      final start = find.descendant(of: times, matching: find.text('08:00'));
      final end = find.descendant(of: times, matching: find.text('09:35'));
      final title = find.descendant(
        of: _key('planner-day-card:课程'),
        matching: find.text('课程'),
      );
      expect(tester.getRect(start).bottom, lessThan(tester.getRect(end).top));
      expect(tester.getRect(times).right, lessThan(tester.getRect(title).left));
      expect(find.text('前日 23:30'), findsOneWidget);
      expect(find.textContaining('空闲'), findsNothing);
      await tester.tap(find.byTooltip('关闭当日任务'));
      await tester.pumpAndSettle();
      expect(_key('planner-day-sheet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drag is a cancellable preview and confirmation keeps revision checks',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        onEvent: events.add,
        blocks: [
          _task(
            '课程',
            '2026-10-22T08:00:00',
            '2026-10-22T09:35:00',
            readOnly: true,
          ),
        ],
      );
      await _open(tester);
      await _drop(tester, 1);
      expect(events, isEmpty);
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('结束于 09:45'), findsOneWidget);
      expect(find.text('待安排 0'), findsOneWidget);
      await tester.tap(_key('planner-day-confirm'));
      expect(events, hasLength(1));
      expect(events.single, containsPair('start', '2026-10-22T09:35:00.000'));
      expect(events.single, containsPair('end', '2026-10-22T09:45:00.000'));
      expect(events.single, containsPair('preserveDuration', true));
      expect(
        (events.single as Map)['expectedTasks'],
        _candidate['moveEvent'] is Map
            ? (_candidate['moveEvent'] as Map)['expectedTasks']
            : null,
      );
      await tester.tap(find.byTooltip('取消本次安排'));
      await tester.pumpAndSettle();
      expect(_key('planner-day-editor'), findsNothing);
      expect(find.text('待安排 1'), findsOneWidget);
      expect(events, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overlap blocks confirmation and next-free suggestion preserves other times',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        onEvent: events.add,
        blocks: [
          _task(
            '课程',
            '2026-10-22T08:00:00',
            '2026-10-22T09:35:00',
            readOnly: true,
          ),
          _task('回复消息', '2026-10-22T09:40:00', '2026-10-22T09:45:00'),
        ],
      );
      await _open(tester);
      await _drop(tester, 1);
      expect(find.text('与「回复消息」时间重叠'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_key('planner-day-confirm')).onPressed,
        isNull,
      );
      await tester.tap(find.text('移至 09:45'));
      await tester.pumpAndSettle();
      expect(find.text('结束于 09:55'), findsOneWidget);
      await tester.tap(_key('planner-day-confirm'));
      expect((events.single as Map)['start'], '2026-10-22T09:45:00.000');
      expect((events.single as Map)['taskId'], '整理笔记');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty day accepts drop and edited duration reaches the service event',
    (tester) async {
      final events = <Object?>[];
      await _mount(tester, onEvent: events.add);
      await _open(tester);
      await _drop(tester, 0);
      await tester.tap(_key('planner-day-duration'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('确定'));
      await tester.pump();
      expect(find.text('请输入1至10080分钟'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('结束于 09:03'), findsOneWidget);
      await tester.tap(_key('planner-day-confirm'));
      expect((events.single as Map)['end'], '2026-10-22T09:03:00.000');
      expect((events.single as Map)['preserveDuration'], false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late validation cannot authorize a different draft', (
    tester,
  ) async {
    final requests = <Completer<BoardItem>>[];
    await _mount(
      tester,
      onPreview: (_) {
        final result = Completer<BoardItem>();
        requests.add(result);
        return result.future;
      },
      blocks: [_task('任务', '2026-10-22T10:00:00', '2026-10-22T10:05:00')],
    );
    await _open(tester);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    final tree = tester
        .binding
        .renderViews
        .single
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!
        .toStringDeep();
    expect(tree, isNot(contains('2026年10月22日 今天')));
    final toggle = tester.getSemantics(_key('planner-day-candidates-toggle'));
    expect(toggle.label, contains('待安排 1'));
    expect(toggle.label, isNot(contains('当日任务')));
    expect(toggle.rect.height, lessThan(60));
    semantics.dispose();
    await tester.tapAt(tester.getCenter(_key('planner-day-card:任务')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester.widget<FilledButton>(_key('planner-day-confirm')).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('取消本次安排'));
    await tester.pump();
    await tester.tap(find.text('待安排 1'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(_key('planner-day-card:整理笔记')));
    await tester.pump(const Duration(milliseconds: 250));
    requests.first.complete({'valid': true});
    await tester.pump();
    expect(
      tester.widget<FilledButton>(_key('planner-day-confirm')).onPressed,
      isNull,
    );
    requests.last.complete({
      'valid': false,
      'conflicts': ['安排时间已过去'],
    });
    await tester.pumpAndSettle();
    expect(find.text('安排时间已过去'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_key('planner-day-confirm')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact phone and large text keep editor usable', (
    tester,
  ) async {
    await _mount(
      tester,
      size: const Size(360, 720),
      scaler: const TextScaler.linear(1.4),
    );
    await _open(tester);
    await _drop(tester, 0);
    expect(_key('planner-day-confirm').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_key('planner-day-sheet'), findsNothing);
  });

  testWidgets(
    'inactive retained sheet does not intercept another workspace back navigation',
    (tester) async {
      await _mount(tester);
      await _open(tester);
      await _mount(tester, enabled: false);
      expect(_key('planner-day-sheet'), findsOneWidget);
      final route = ModalRoute.of(tester.element(find.byType(PlannerBoard)))!;
      expect(route.popDisposition, RoutePopDisposition.bubble);
      await _mount(tester, enabled: true);
      expect(route.popDisposition, RoutePopDisposition.doNotPop);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_key('planner-day-sheet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
