import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';

void main() {
  const day = {'date': '2026-11-04', 'label': '周三'};
  const course = <String, Object?>{
    'id': 'course',
    'title': '高等数学',
    'start': '2026-11-04T09:00:00',
    'end': '2026-11-04T11:00:00',
    'readOnly': true,
    'location': '教一302',
    'teacher': '王老师',
    'selectionDetails': [
      {'label': '地点', 'value': '教一302'},
      {'label': '老师', 'value': '王老师'},
    ],
  };
  Future<void> mount(
    WidgetTester tester, {
    ValueChanged<Object?>? onEvent,
    bool enabled = true,
    Map<String, Object?> item = course,
    Map<String, Object?> options = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerBoard(
            enabled: enabled,
            days: const [day],
            blocks: [item],
            onEvent: onEvent ?? (_) {},
            options: {
              'dashboard': true,
              'startMinute': 480,
              'endMinute': 1440,
              'initialMinute': 480,
              'pixelsPerMinute': 1.1,
              'pinchZoom': {
                'event': {'type': 'pinchZoom'},
                'min': .75,
                'max': 3,
              },
              ...options,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollController vertical(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(
        find.byKey(const ValueKey('planner-vertical')),
      )
      .controller!;
  double courseHeight(WidgetTester tester) => tester
      .getSize(find.byKey(const ValueKey('block:course:2026-11-04')))
      .height;

  testWidgets('pinch scales around focal minute and sends one display event', (
    tester,
  ) async {
    final events = <Object?>[];
    await mount(tester, onEvent: events.add);
    final scroll = vertical(tester);
    scroll.jumpTo(120);
    await tester.pump();
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('planner-vertical')),
    );
    final before = courseHeight(tester);
    final minute = (scroll.offset + 180) / 1.1;
    final a = await tester.startGesture(
      origin + const Offset(200, 180),
      pointer: 1,
    );
    final b = await tester.startGesture(
      origin + const Offset(300, 180),
      pointer: 2,
    );
    await tester.pump();
    await a.moveTo(origin + const Offset(150, 180));
    await b.moveTo(origin + const Offset(350, 180));
    await tester.pump();
    await tester.pump();
    expect(courseHeight(tester), closeTo(before * 2, .1));
    expect((scroll.offset + 180) / 2.2, closeTo(minute, .1));
    expect(events, isEmpty);
    final c = await tester.startGesture(
      origin + const Offset(500, 180),
      pointer: 3,
    );
    await c.moveTo(origin + const Offset(700, 180));
    await tester.pump();
    expect(courseHeight(tester), closeTo(before * 2, .1));
    await c.up();
    await b.up();
    final stoppedOffset = scroll.offset;
    // The module temporarily disables the board while saving this completed
    // gesture. Its local display and pending focal position must remain.
    await mount(tester, onEvent: events.add, enabled: false);
    expect(courseHeight(tester), closeTo(before * 2, .1));
    expect(scroll.offset, closeTo(stoppedOffset, .1));
    await a.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(scroll.offset, closeTo(stoppedOffset, .1));
    await a.up();
    await tester.pumpAndSettle();
    expect(events, hasLength(1));
    expect(events.single, {'type': 'pinchZoom', 'pixelsPerMinute': 2.2});
    // A module acknowledgement keeps the same focal position.
    final offset = scroll.offset;
    await mount(
      tester,
      onEvent: events.add,
      options: const {'pixelsPerMinute': 2.2},
    );
    expect(vertical(tester).offset, closeTo(offset, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pinch bounds, cancellation and single-finger scrolling remain functional',
    (tester) async {
      final events = <Object?>[];
      await mount(tester, onEvent: events.add);
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('planner-vertical')),
      );
      final a = await tester.startGesture(
        origin + const Offset(200, 200),
        pointer: 1,
      );
      final b = await tester.startGesture(
        origin + const Offset(300, 200),
        pointer: 2,
      );
      await a.moveTo(origin + const Offset(50, 200));
      await b.moveTo(origin + const Offset(650, 200));
      await tester.pump();
      await b.cancel();
      await a.cancel();
      await tester.pumpAndSettle();
      expect((events.single as Map)['pixelsPerMinute'], 3);
      final offset = vertical(tester).offset;
      await tester.drag(
        find.byKey(const ValueKey('planner-vertical')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(vertical(tester).offset, greaterThan(offset));
      expect(events, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nearby fingers can spread into a pinch', (tester) async {
    final events = <Object?>[];
    await mount(tester, onEvent: events.add);
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('planner-vertical')),
    );
    final before = courseHeight(tester);
    final a = await tester.startGesture(
      origin + const Offset(200, 180),
      pointer: 1,
    );
    final b = await tester.startGesture(
      origin + const Offset(208, 180),
      pointer: 2,
    );
    await tester.pump();
    expect(courseHeight(tester), before);
    await a.moveBy(const Offset(-12, 0));
    await b.moveBy(const Offset(12, 0));
    await tester.pump();
    await tester.pump();
    expect(courseHeight(tester), greaterThan(before));
    await b.up();
    await a.up();
    await tester.pumpAndSettle();
    expect(events, hasLength(1));
    expect(find.byKey(const ValueKey('planner-selection-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final removed in [false, true]) {
    testWidgets(
      '${removed ? 'removing pinch configuration' : 'disabling the board'} cancels an active pinch',
      (tester) async {
        final events = <Object?>[];
        await mount(tester, onEvent: events.add);
        final scroll = vertical(tester);
        scroll.jumpTo(100);
        await tester.pump();
        final before = courseHeight(tester);
        final origin = tester.getTopLeft(
          find.byKey(const ValueKey('planner-vertical')),
        );
        final a = await tester.startGesture(
          origin + const Offset(200, 180),
          pointer: 1,
        );
        final b = await tester.startGesture(
          origin + const Offset(300, 180),
          pointer: 2,
        );
        await a.moveBy(const Offset(-30, 0));
        await b.moveBy(const Offset(30, 0));
        await tester.pump();
        await tester.pump();
        expect(courseHeight(tester), greaterThan(before));
        // Queue another focal adjustment, then replace the configuration
        // before its frame callback can run.
        await a.moveBy(const Offset(-10, 0));
        await mount(
          tester,
          onEvent: events.add,
          enabled: removed,
          options: removed ? {'pinchZoom': null} : const {},
        );
        expect(courseHeight(tester), closeTo(before, .1));
        expect(scroll.offset, closeTo(100, .1));
        await a.moveBy(const Offset(-20, -20));
        await b.moveBy(const Offset(20, -20));
        // Re-enabling the board must not revive the cancelled fingers.
        await mount(tester, onEvent: events.add);
        await a.moveBy(const Offset(-10, 0));
        await b.moveBy(const Offset(10, 0));
        await tester.pump();
        expect(courseHeight(tester), closeTo(before, .1));
        expect(scroll.offset, closeTo(100, .1));
        await b.up();
        await a.up();
        await tester.pumpAndSettle();
        expect(events, isEmpty);
        expect(courseHeight(tester), closeTo(before, .1));
        expect(scroll.offset, closeTo(100, .1));
        expect(tester.takeException(), isNull);
        await mount(tester, onEvent: events.add);
        await tester.drag(
          find.byKey(const ValueKey('planner-vertical')),
          const Offset(0, -80),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(100));
        final c = await tester.startGesture(
          origin + const Offset(200, 180),
          pointer: 3,
        );
        final d = await tester.startGesture(
          origin + const Offset(300, 180),
          pointer: 4,
        );
        await c.moveBy(const Offset(-20, 0));
        await d.moveBy(const Offset(20, 0));
        await tester.pump();
        await tester.pump();
        await d.up();
        await c.up();
        await tester.pumpAndSettle();
        expect(events, hasLength(1));
        expect(courseHeight(tester), greaterThan(before));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('ignored third finger does not replace a lifted pinch finger', (
    tester,
  ) async {
    final events = <Object?>[];
    await mount(tester, onEvent: events.add);
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('planner-vertical')),
    );
    final a = await tester.startGesture(
      origin + const Offset(200, 180),
      pointer: 1,
    );
    final b = await tester.startGesture(
      origin + const Offset(300, 180),
      pointer: 2,
    );
    await a.moveBy(const Offset(-20, 0));
    await b.moveBy(const Offset(20, 0));
    await tester.pump();
    await tester.pump();
    final c = await tester.startGesture(
      origin + const Offset(500, 180),
      pointer: 3,
    );
    await a.up();
    await tester.pump();
    final height = courseHeight(tester);
    final offset = vertical(tester).offset;
    await c.moveBy(const Offset(80, -30));
    await b.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(courseHeight(tester), height);
    expect(vertical(tester).offset, offset);
    await c.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(events, hasLength(1));
    final d = await tester.startGesture(
      origin + const Offset(200, 180),
      pointer: 4,
    );
    final e = await tester.startGesture(
      origin + const Offset(300, 180),
      pointer: 5,
    );
    await d.moveBy(const Offset(-10, 0));
    await e.moveBy(const Offset(10, 0));
    await tester.pump();
    await tester.pump();
    expect(courseHeight(tester), greaterThan(height));
    await e.up();
    await d.up();
    await tester.pumpAndSettle();
    expect(events, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small pinch starting on a course does not select the course', (
    tester,
  ) async {
    final events = <Object?>[];
    await mount(tester, onEvent: events.add);
    final center = tester.getCenter(
      find.byKey(const ValueKey('block:course:2026-11-04')),
    );
    final a = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 1,
    );
    final b = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await a.moveBy(const Offset(-5, 0));
    await b.moveBy(const Offset(5, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-selection-panel')), findsNothing);
    expect(events.every((e) => (e as Map)['type'] == 'pinchZoom'), isTrue);
    await tester.tap(find.text('高等数学'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('planner-selection-panel')),
      findsOneWidget,
    );
  });

  testWidgets(
    'course fields and selected detail rows follow declared options',
    (tester) async {
      await mount(tester);
      expect(find.text('教一302'), findsOneWidget);
      expect(find.text('王老师'), findsOneWidget);
      await tester.tap(find.text('高等数学'));
      await tester.pumpAndSettle();
      expect(find.text('地点 教一302'), findsOneWidget);
      expect(find.text('老师 王老师'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭选中任务'));
      await tester.pumpAndSettle();
      expect(find.text('地点 教一302'), findsNothing);
      await mount(
        tester,
        item: {
          ...course,
          'showLocation': false,
          'showTeacher': false,
          'selectionDetails': <Object?>[],
          'showSelectionGaps': false,
        },
      );
      expect(find.text('教一302'), findsNothing);
      expect(find.text('王老师'), findsNothing);
      await tester.tap(find.text('高等数学'));
      await tester.pumpAndSettle();
      expect(find.text('地点 教一302'), findsNothing);
      expect(find.text('老师 王老师'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
