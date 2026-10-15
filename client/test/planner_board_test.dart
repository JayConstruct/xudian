import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';

const _days = [
  {'date': '2026-10-15', 'label': '周四 10/15'},
  {'date': '2026-10-16', 'label': '周五 10/16'},
  {'date': '2026-10-17', 'label': '周六 10/17'},
  {'date': '2026-10-18', 'label': '周日 10/18'},
  {'date': '2026-10-19', 'label': '周一 10/19'},
];

Future<void> _mount(
  WidgetTester tester, {
  List<BoardItem> candidates = const [],
  List<BoardItem> blocks = const [],
  List<BoardItem> previewBlocks = const [],
  BoardItem options = const {},
  ValueChanged<Object?>? onEvent,
  TextScaler scaler = TextScaler.noScaling,
  BoardItem? selectEvent,
  List<Object?> selectedIds = const [],
  Future<BoardItem> Function(BoardItem)? onPreview,
  bool enabled = true,
  Object? previewIdentity,
  List<BoardItem> days = _days,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(800, 600), textScaler: scaler),
        child: Scaffold(
          body: PlannerBoard(
            days: days,
            candidates: candidates,
            blocks: blocks,
            previewBlocks: previewBlocks,
            options: options,
            onEvent: onEvent ?? (_) {},
            selectEvent: selectEvent,
            selectedIds: selectedIds,
            onPreview: onPreview,
            enabled: enabled,
            previewIdentity: previewIdentity,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

BoardItem _block(
  String id,
  String start,
  String end, {
  bool readOnly = false,
}) => {
  'id': id,
  'title': id,
  'start': start,
  'end': end,
  'event': {'action': 'detail', 'id': id},
  'moveEvent': {'action': 'move'},
  if (readOnly) 'readOnly': true,
};

Future<TestGesture> _dragTo(
  WidgetTester tester,
  Finder source,
  Offset point,
) async {
  final gesture = await tester.startGesture(tester.getCenter(source));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(point - const Offset(0, 2));
  await tester.pump();
  await gesture.moveTo(point);
  await tester.pump(const Duration(milliseconds: 40));
  return gesture;
}

Offset _gridPoint(WidgetTester tester, int day, int minute) {
  final rect = tester.getRect(find.byType(DragTarget<BoardItem>));
  final board = tester.widget<PlannerBoard>(find.byType(PlannerBoard));
  return Offset(
    rect.left +
        rect.width / (board.days.isEmpty ? 5 : board.days.length) * day +
        35,
    rect.top + minute,
  );
}

List<BoardItem> _month() => List.generate(28, (index) {
  final date = DateTime.utc(
    2026,
    10,
    15 + index,
  ).toIso8601String().substring(0, 10);
  return {'date': date, 'label': date.substring(5)};
});

void main() {
  testWidgets(
    'drag proposals prefer explicit actual duration over wall clock difference',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          {
            ..._block('dst', '2026-10-15T09:00:00', '2026-10-15T11:00:00'),
            'durationMinutes': 60.5,
          },
        ],
        onEvent: events.add,
      );
      final gesture = await _dragTo(
        tester,
        find.text('dst'),
        _gridPoint(tester, 1, 10 * 60),
      );
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['start'], '2026-10-16T10:00:00.000');
      expect((events.single as Map)['end'], '2026-10-16T11:00:30.000');
    },
  );

  testWidgets(
    '28 day board bounds mounted task widgets and reveals both dates and times on scroll',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final days = _month();
      final blocks = [
        for (var day = 0; day < 28; day++)
          for (var hour = 0; hour < 24; hour++)
            _block(
              'day${day}hour$hour',
              '${days[day]['date']}T${hour.toString().padLeft(2, '0')}:00:00',
              '${days[day]['date']}T${hour.toString().padLeft(2, '0')}:10:00',
            ),
      ];
      await _mount(tester, days: days, blocks: blocks);
      int cards() => find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.startsWith('block:'),
          )
          .evaluate()
          .length;
      int taskWidgets() => find
          .byWidgetPredicate((widget) {
            final key = widget.key;
            if (key is! ValueKey<String>) return false;
            return [
              'block:',
              'occupancy:',
              'resize-position:',
            ].any(key.value.startsWith);
          })
          .evaluate()
          .length;
      expect(blocks, hasLength(672));
      expect(cards(), inExclusiveRange(1, 80));
      final initialCards = cards(), initialWidgets = taskWidgets();
      expect(initialWidgets, lessThan(240));
      expect(
        find.byKey(ValueKey('block:day20hour20:${days[20]['date']}')),
        findsNothing,
      );
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      horizontal.jumpTo(20 * 112);
      vertical.jumpTo(20 * 60);
      await tester.pump();
      await tester.pump();
      expect(find.text('day20hour20'), findsOneWidget);
      expect(find.text('day0hour9'), findsNothing);
      expect(cards(), lessThan(80));
      expect(taskWidgets(), lessThan(240));
      debugPrint(
        'PlannerBoard 672 tasks / 28 days: mounted cards $initialCards → ${cards()}, task surfaces $initialWidgets → ${taskWidgets()}',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dense collision group keeps isolated tasks separately selectable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(
        tester,
        blocks: [
          _block('拥挤A', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
          _block('拥挤B', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
          _block('孤立任务', '2026-10-15T14:00:00', '2026-10-15T14:30:00'),
        ],
      );
      expect(find.text('2项安排 · 选择'), findsOneWidget);
      expect(find.text('孤立任务'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('block:孤立任务:2026-10-15')))
            .width,
        greaterThan(90),
      );
      await tester.tap(find.text('2项安排 · 选择'));
      await tester.pumpAndSettle();
      expect(find.text('拥挤A'), findsOneWidget);
      expect(find.text('拥挤B'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('孤立任务'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long cross midnight occupations retain true bands and reachable labels inside viewport',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        days: _month(),
        options: const {'initialMinute': 720},
        blocks: [_block('长跨天', '2026-10-14T23:45:00', '2026-10-18T02:00:00')],
        onEvent: events.add,
      );
      final band = find.byKey(const ValueKey('occupancy:长跨天:2026-10-15'));
      expect(tester.getSize(band).height, 1440);
      final label = find.byKey(const ValueKey('block:长跨天:2026-10-15'));
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      expect(tester.getRect(label).overlaps(viewport), isTrue);
      await tester.tap(label);
      expect(events.single, {'action': 'detail', 'id': '长跨天'});
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      horizontal.jumpTo(3 * 112);
      vertical.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:长跨天:2026-10-18')))
            .height,
        120,
      );
      expect(
        find.byKey(const ValueKey('occupancy:长跨天:2026-10-15')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'virtualized drag and resize sources stay mounted through edge scrolling until release',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <Object?>[];
      final blocks = [
        _block('source', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      ];
      await _mount(tester, days: _month(), blocks: blocks, onEvent: events.add);
      final source = find.byKey(const ValueKey('block:source:2026-10-15'));
      final element = tester.element(source);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      var gesture = await _dragTo(
        tester,
        find.text('source'),
        Offset(viewport.right - 5, viewport.center.dy),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(tester.element(source), same(element));
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(events, hasLength(1));
      expect((events.single as Map)['id'], 'source');
      expect(source, findsNothing);
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      horizontal.jumpTo(0);
      await tester.pump();
      await tester.pump();
      events.clear();
      final handle = find.byKey(const ValueKey('resize:source:2026-10-15'));
      final handleElement = tester.element(handle);
      gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveTo(Offset(viewport.right - 5, viewport.center.dy));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(tester.element(handle), same(handleElement));
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(events, hasLength(1));
      expect((events.single as Map)['intent'], 'resize');
      expect((events.single as Map)['start'], '2026-10-15T09:00:00.000');
      expect(handle, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'valid preview with overdue still states explicit confirmation is required',
    (tester) async {
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'due',
            'title': '截止任务',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        onPreview: (_) async => {
          'valid': true,
          'previewLabel': '移动 · 1项',
          'overdue': [
            {'taskId': 'due', 'title': '截止任务'},
          ],
        },
      );
      final gesture = await _dragTo(
        tester,
        find.text('截止任务'),
        _gridPoint(tester, 0, 9 * 60),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('安排超过截止，落下后需明确确认'), findsWidgets);
      await gesture.cancel();
      await tester.pump();
    },
  );

  testWidgets(
    'late preview after pointer cancellation or widget disposal cannot restore overlays',
    (tester) async {
      const candidates = [
        {
          'id': 'late',
          'title': '取消后预览',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      final pending = <Completer<BoardItem>>[];
      Future<BoardItem> preview(BoardItem _) {
        final c = Completer<BoardItem>();
        pending.add(c);
        return c.future;
      }

      await _mount(tester, candidates: candidates, onPreview: preview);
      var gesture = await _dragTo(
        tester,
        find.text('取消后预览'),
        _gridPoint(tester, 0, 9 * 60),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(pending, hasLength(1));
      await gesture.cancel();
      await tester.pump();
      pending[0].complete({'previewLabel': '已取消的回复'});
      await tester.pump();
      await tester.pump();
      expect(find.text('已取消的回复'), findsNothing);
      gesture = await _dragTo(
        tester,
        find.text('取消后预览'),
        _gridPoint(tester, 0, 10 * 60),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(pending, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      pending[1].complete({'previewLabel': '已销毁的回复'});
      await gesture.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canceling duration adjustment commits nothing and stops its scroll timer',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          _block('cancel-size', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
        ],
        onEvent: events.add,
      );
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('resize:cancel-size:2026-10-15')),
        ),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      final offset = vertical.offset;
      await tester.pump(const Duration(milliseconds: 800));
      expect(vertical.offset, offset);
      expect(events, isEmpty);
      expect(find.textContaining('调整时长'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edge auto scroll moves both axes, keeps fine mode and stops on drop or cancel',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <Object?>[];
      const candidates = [
        {
          'id': 'edge',
          'title': '边缘任务',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      await _mount(tester, candidates: candidates, onEvent: events.add);
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final viewport = tester.getRect(
        find.byKey(const ValueKey('planner-vertical')),
      );
      final initialY = vertical.offset;
      var gesture = await _dragTo(
        tester,
        find.text('边缘任务'),
        viewport.bottomRight - const Offset(10, 12),
      );
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(horizontal.offset, greaterThan(0));
      expect(vertical.offset, greaterThan(initialY));
      expect(find.textContaining('1分钟细调'), findsWidgets);
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['snapMinutes'], 1);
      final x = horizontal.offset, y = vertical.offset;
      await tester.pump(const Duration(milliseconds: 400));
      expect(horizontal.offset, x);
      expect(vertical.offset, y);
      events.clear();
      gesture = await _dragTo(
        tester,
        find.text('边缘任务'),
        viewport.topLeft + const Offset(55, 8),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.cancel();
      await tester.pump();
      final canceledX = horizontal.offset, canceledY = vertical.offset;
      await tester.pump(const Duration(milliseconds: 800));
      expect(horizontal.offset, canceledX);
      expect(vertical.offset, canceledY);
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('edge auto scroll respects both maximum extents', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(
      tester,
      candidates: const [
        {
          'id': 'bound',
          'title': '边界任务',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ],
    );
    final horizontal = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('planner-horizontal')),
        )
        .controller!;
    final vertical = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('planner-vertical')),
        )
        .controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    vertical.jumpTo(vertical.position.maxScrollExtent);
    await tester.pump();
    final rect = tester.getRect(find.byKey(const ValueKey('planner-vertical')));
    final gesture = await _dragTo(
      tester,
      find.text('边界任务'),
      rect.bottomRight - const Offset(4, 4),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(horizontal.offset, horizontal.position.maxScrollExtent);
    expect(vertical.offset, vertical.position.maxScrollExtent);
    await gesture.cancel();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duration handle changes only end and protects minimum positive duration',
    (tester) async {
      final events = <Object?>[];
      final blocks = [
        _block('resize', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
      ];
      await _mount(tester, blocks: blocks, onEvent: events.add);
      var handle = find.byKey(const ValueKey('resize:resize:2026-10-15'));
      var gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(find.textContaining('调整时长'), findsWidgets);
      await gesture.up();
      await tester.pump();
      expect(events.single, {
        'action': 'move',
        'id': 'resize',
        'start': '2026-10-15T09:00:00.000',
        'end': '2026-10-15T10:30:00.000',
        'intent': 'resize',
        'snapMinutes': 15,
      });
      events.clear();
      gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['end'], '2026-10-15T09:01:00.000');
    },
  );

  testWidgets(
    'cross midnight resize is one operation and fixed or read only sources have no handle',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        options: const {'initialMinute': 0},
        blocks: [
          _block('night', '2026-10-15T23:45:00', '2026-10-16T00:30:00'),
          {
            ..._block('fixed', '2026-10-15T01:00:00', '2026-10-15T02:00:00'),
            'fixed': true,
          },
          _block(
            'course',
            '2026-10-15T03:00:00',
            '2026-10-15T04:00:00',
            readOnly: true,
          ),
        ],
        onEvent: events.add,
      );
      expect(
        find.byKey(const ValueKey('resize:night:2026-10-15')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('resize:fixed:2026-10-15')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('resize:course:2026-10-15')),
        findsNothing,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('resize:night:2026-10-16'))),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(events, hasLength(1));
      expect((events.single as Map)['start'], '2026-10-15T23:45:00.000');
      expect((events.single as Map)['end'], '2026-10-16T01:00:00.000');
      expect((events.single as Map)['intent'], 'resize');
    },
  );

  testWidgets(
    'local swap previews both origins while keeping each tasks duration',
    (tester) async {
      await _mount(
        tester,
        blocks: [
          _block('a', '2026-10-15T09:00:00', '2026-10-15T09:30:00'),
          _block('b', '2026-10-16T10:00:00', '2026-10-16T11:30:00'),
        ],
      );
      final gesture = await _dragTo(
        tester,
        find.text('a'),
        _gridPoint(tester, 1, 10 * 60 + 45),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final a = find.byKey(const ValueKey('local:a:2026-10-16'));
      final b = find.byKey(const ValueKey('local:b:2026-10-15'));
      expect(tester.getSize(a).height, 30);
      expect(tester.getSize(b).height, 90);
      expect(
        tester.getTopLeft(a).dy,
        tester
            .getTopLeft(find.byKey(const ValueKey('occupancy:b:2026-10-16')))
            .dy,
      );
      expect(
        tester.getTopLeft(b).dy,
        tester
            .getTopLeft(find.byKey(const ValueKey('occupancy:a:2026-10-15')))
            .dy,
      );
      expect(find.text('交换几何预览 · 15分钟吸附'), findsOneWidget);
      await gesture.cancel();
      await tester.pump();
    },
  );

  testWidgets(
    'releasing during target transition cannot swap the previously hovered task',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'source',
            'title': '过渡任务',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        blocks: [
          _block('a', '2026-10-16T09:00:00', '2026-10-16T10:00:00'),
          _block('b', '2026-10-17T09:00:00', '2026-10-17T10:00:00'),
        ],
        onEvent: events.add,
      );
      final gesture = await _dragTo(
        tester,
        find.text('过渡任务'),
        _gridPoint(tester, 1, 9 * 60 + 30),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('交换 · 待校验'), findsOneWidget);
      await gesture.moveTo(_gridPoint(tester, 2, 9 * 60 + 30));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['intent'], 'move');
      expect((events.single as Map).containsKey('targetId'), isFalse);
    },
  );

  testWidgets(
    'preview requests debounce and ignore out of order replies, cancellation and view changes',
    (tester) async {
      final requests = <BoardItem>[];
      final pending = <Completer<BoardItem>>[];
      final events = <Object?>[];
      const candidates = [
        {
          'id': 'async',
          'title': '异步任务',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      Future<BoardItem> preview(BoardItem event) {
        requests.add(event);
        final completer = Completer<BoardItem>();
        pending.add(completer);
        return completer.future;
      }

      await _mount(
        tester,
        candidates: candidates,
        onPreview: preview,
        onEvent: events.add,
        previewIdentity: 'v1',
      );
      final gesture = await _dragTo(
        tester,
        find.text('异步任务'),
        _gridPoint(tester, 0, 9 * 60),
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 2));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(requests, hasLength(1));
      await gesture.moveTo(_gridPoint(tester, 0, 10 * 60));
      await tester.pump(const Duration(milliseconds: 200));
      expect(requests, hasLength(2));
      pending[1].complete({
        'valid': false,
        'previewLabel': '服务校验结果',
        'conflicts': ['与课程冲突'],
        'previewBlocks': [
          _block('service', '2026-10-16T10:00:00', '2026-10-16T10:30:00'),
        ],
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('与课程冲突'), findsWidgets);
      expect(
        find.byKey(const ValueKey('service:service:2026-10-16')),
        findsOneWidget,
      );
      pending[0].complete({'previewLabel': '过时结果'});
      await tester.pump();
      expect(find.text('过时结果'), findsNothing);
      await _mount(
        tester,
        candidates: candidates,
        onPreview: preview,
        onEvent: events.add,
        previewIdentity: 'v2',
      );
      await gesture.moveTo(_gridPoint(tester, 1, 10 * 60));
      await tester.pump(const Duration(milliseconds: 220));
      await gesture.up();
      await tester.pump();
      expect(events, isEmpty);
      expect(requests, hasLength(2));
      expect(find.text('服务校验结果'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending preview and edge timers are harmless after disable and disposal',
    (tester) async {
      final completer = Completer<BoardItem>();
      var calls = 0;
      const candidates = [
        {
          'id': 'dispose',
          'title': '生命周期任务',
          'durationMinutes': 30,
          'moveEvent': {'action': 'move'},
        },
      ];
      Future<BoardItem> preview(BoardItem _) {
        calls++;
        return completer.future;
      }

      await _mount(tester, candidates: candidates, onPreview: preview);
      final gesture = await _dragTo(
        tester,
        find.text('生命周期任务'),
        _gridPoint(tester, 0, 9 * 60),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, 1);
      await _mount(
        tester,
        candidates: candidates,
        onPreview: preview,
        enabled: false,
      );
      completer.complete({'previewLabel': '禁用后的结果'});
      await tester.pump();
      expect(find.text('禁用后的结果'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'target dwell distinguishes center swap from edge insertion and preserves raw ids',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'source',
            'title': '拖动源',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        blocks: [
          _block('target', '2026-10-16T09:00:00', '2026-10-16T10:30:00'),
        ],
        onEvent: events.add,
      );
      var gesture = await _dragTo(
        tester,
        find.text('拖动源'),
        _gridPoint(tester, 1, 9 * 60 + 45),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('交换 · 待校验'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect((events.last as Map)['intent'], 'swap');
      expect((events.last as Map)['targetId'], 'target');
      gesture = await _dragTo(
        tester,
        find.text('拖动源'),
        _gridPoint(tester, 1, 9 * 60),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('插入 · 待校验'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect((events.last as Map)['intent'], 'insert');
      expect((events.last as Map)['targetId'], 'target');
    },
  );

  testWidgets(
    '100 overlapping blocks retain true stripes and accessible choice without negative widths',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: List.generate(
          100,
          (i) => _block('密集$i', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
        ),
        onEvent: events.add,
      );
      expect(tester.takeException(), isNull);
      final stripe = find.byKey(
        const ValueKey('dense-occupancy:密集0:2026-10-15'),
      );
      expect(tester.getSize(stripe).width, greaterThan(0));
      // One painter carries all exact-length bands; aggregation has a separate
      // minimum-height selection label and does not create 100 band widgets.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.startsWith('occupancy:密集'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('100项安排 · 选择'));
      await tester.pumpAndSettle();
      expect(find.text('密集0'), findsOneWidget);
      await tester.tap(find.text('密集0'));
      await tester.pumpAndSettle();
      expect(events.single, {'action': 'detail', 'id': '密集0'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320 wide board scrolls dates at 1.5 text scale and preserves candidate identity',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <Object?>[];
      await _mount(
        tester,
        scaler: const TextScaler.linear(1.5),
        candidates: const [
          {
            'id': 'raw-task',
            'title': '待选任务',
            'selected': true,
            'selectEvent': {'type': 'select', 'id': 'candidate:raw-task'},
          },
        ],
        onEvent: events.add,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      await tester.tap(find.byType(Checkbox));
      expect(events.single, {
        'type': 'select',
        'id': 'candidate:raw-task',
        'selected': false,
        'value': false,
      });
      events.clear();
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byKey(const ValueKey('planner-horizontal')),
        const Offset(-230, 0),
      );
      await tester.pumpAndSettle();
      expect(horizontal.offset, greaterThan(0));
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      final before = vertical.offset;
      await tester.drag(
        find.byKey(const ValueKey('planner-vertical')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(vertical.offset, greaterThan(before));
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deadline summary never changes execution placement; short occupancy stays true length',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          {
            ..._block('短任务', '2026-10-15T09:00:00', '2026-10-15T09:05:00'),
            'deadlineSummary': '截10/19',
          },
          _block('长任务', '2026-10-15T10:00:00', '2026-10-15T11:30:00'),
        ],
        onEvent: events.add,
      );
      final short = find.byKey(const ValueKey('occupancy:短任务:2026-10-15'));
      final long = find.byKey(const ValueKey('occupancy:长任务:2026-10-15'));
      expect(tester.getSize(short).height, 5);
      expect(tester.getSize(long).height, 90);
      expect(tester.getTopLeft(long).dy - tester.getTopLeft(short).dy, 60);
      final summary = tester.widget<Text>(find.text('截10/19'));
      final context = tester.element(find.text('截10/19'));
      expect(summary.style!.color, Theme.of(context).colorScheme.error);
      await tester.tap(find.text('短任务'));
      expect(events.single, {'action': 'detail', 'id': '短任务'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'candidate long press proposes another day with duration and 15 minute snapping',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'raw-task',
            'title': '候选任务',
            'durationMinutes': 30,
            'deadlineSummary': '截10/15',
            'moveEvent': {'action': 'move'},
          },
        ],
        onEvent: events.add,
      );
      final gesture = await _dragTo(
        tester,
        find.text('候选任务'),
        _gridPoint(tester, 1, 9 * 60 + 8),
      );
      expect(find.textContaining('15分钟吸附'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      final event = events.single as Map;
      expect(event['id'], 'raw-task');
      expect(event['start'], '2026-10-16T09:15:00.000');
      expect(event['end'], '2026-10-16T09:45:00.000');
      expect(event['snapMinutes'], 15);
      expect(event['intent'], 'move');
      expect(event.containsKey('deadlineSummary'), isFalse);
      expect(find.text('候选任务'), findsOneWidget);
    },
  );

  testWidgets(
    'stationary dwell enters one minute mode without shifting the candidate time',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        candidates: const [
          {
            'id': 'fine',
            'title': '细调任务',
            'durationMinutes': 30,
            'moveEvent': {'action': 'move'},
          },
        ],
        onEvent: events.add,
      );
      final point = _gridPoint(tester, 0, 9 * 60 + 7);
      final gesture = await _dragTo(tester, find.text('细调任务'), point);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('1分钟细调'), findsOneWidget);
      expect(find.text('10/15 09:00 → 10/15 09:30'), findsOneWidget);
      await gesture.moveBy(const Offset(0, 3));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect((events.single as Map)['start'], '2026-10-15T09:03:00.000');
      expect((events.single as Map)['snapMinutes'], 1);
    },
  );

  testWidgets(
    'courses and fixed tasks expose details and cannot initiate a drag',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        blocks: [
          _block(
            '只读课程',
            '2026-10-15T09:00:00',
            '2026-10-15T10:00:00',
            readOnly: true,
          ),
          {
            ..._block('固定任务', '2026-10-15T10:00:00', '2026-10-15T11:00:00'),
            'fixed': true,
          },
        ],
        onEvent: events.add,
      );
      expect(find.byType(LongPressDraggable<BoardItem>), findsNothing);
      await tester.tap(find.text('只读课程'));
      expect(events.single, {'action': 'detail', 'id': '只读课程'});
    },
  );

  testWidgets(
    'cross midnight segments share an id and caller previews retain both swap locations',
    (tester) async {
      await _mount(
        tester,
        blocks: [_block('跨夜', '2026-10-15T23:45:00', '2026-10-16T00:30:00')],
        previewBlocks: [
          _block('first', '2026-10-15T09:00:00', '2026-10-15T10:00:00'),
          _block('second', '2026-10-16T10:00:00', '2026-10-16T10:30:00'),
        ],
      );
      expect(
        find.byKey(const ValueKey('occupancy:跨夜:2026-10-15')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('preview:first:2026-10-15')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('preview:second:2026-10-16')),
        findsOneWidget,
      );
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-vertical')),
          )
          .controller!;
      vertical.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:跨夜:2026-10-16')))
            .height,
        30,
      );
      vertical.jumpTo(vertical.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('occupancy:跨夜:2026-10-15')))
            .height,
        15,
      );
    },
  );

  testWidgets('outside range entry preserves access to hidden occupations', (
    tester,
  ) async {
    final events = <Object?>[];
    await _mount(
      tester,
      blocks: [_block('隐藏安排', '2026-10-15T06:00:00', '2026-10-15T07:00:00')],
      options: const {'startMinute': 480, 'endMinute': 1080},
      onEvent: events.add,
    );
    expect(
      find.byKey(const ValueKey('occupancy:隐藏安排:2026-10-15')),
      findsNothing,
    );
    await tester.tap(find.text('显示范围外有 1 项安排 · 查看'));
    await tester.pumpAndSettle();
    expect(find.text('10/15 06:00 → 10/15 07:00'), findsOneWidget);
    await tester.tap(find.text('隐藏安排'));
    await tester.pumpAndSettle();
    expect(events.single, {'action': 'detail', 'id': '隐藏安排'});
  });

  testWidgets(
    'large text keeps two candidate rows and selection is a separate event',
    (tester) async {
      final events = <Object?>[];
      await _mount(
        tester,
        scaler: const TextScaler.linear(2),
        candidates: const [
          {
            'id': 'one',
            'title': '无截止',
            'event': {'action': 'detail'},
          },
          {'id': 'two', 'title': '第二行', 'deadlineSummary': '截10/16'},
          {'id': 'three', 'title': '第三列'},
        ],
        selectEvent: const {'action': 'select'},
        selectedIds: const ['one'],
        onEvent: events.add,
      );
      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      expect(checkboxes.first.value, isTrue);
      await tester.tap(find.byType(Checkbox).first);
      expect(events.single, {
        'action': 'select',
        'id': 'one',
        'selected': false,
        'value': false,
      });
      expect(
        tester.getTopLeft(find.text('无截止')).dy,
        lessThan(tester.getTopLeft(find.text('第二行')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
