import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_scroll_behavior.dart';
import 'package:task_app/core/module_host/planner_board.dart';

List<BoardItem> dates(String start) => List.generate(
  21,
  (index) => {
    'date': DateTime.parse(start)
        .add(Duration(days: index))
        .toIso8601String()
        .substring(0, 10),
  },
);

const configuration = <String, Object?>{
  'dashboard': true,
  'continuousDates': true,
  'timeline': {'rangeContextKey': 'timelineRange'},
  'visibleDays': 3,
  'initialDate': '2026-10-19',
  'today': '2026-10-20',
  'now': '2026-10-20T10:00:00',
  'startMinute': 480,
  'endMinute': 1080,
  'scrollRequest': 0,
  'pixelsPerMinute': 1.1,
};

Finder keyed(String key) => find.byKey(ValueKey(key));
ScrollController horizontal(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(keyed('planner-horizontal'))
    .controller!;

Future<void> mount(
  WidgetTester tester, {
  required Future<BoardItem?> Function(String, int) load,
  ValueChanged<BoardItem>? viewport,
  ValueChanged<Object?>? event,
  List<BoardItem> blocks = const [],
  bool enabled = true,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: PlannerBoard(
          days: dates('2026-10-12'),
          blocks: blocks,
          options: configuration,
          enabled: enabled,
          onLoadRange: load,
          onViewportChanged: viewport,
          onEvent: event ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final surface in ['planner-horizontal', 'planner-date-header']) {
    testWidgets('held $surface gesture cannot be moved by its passive peer', (
      tester,
    ) async {
      await mount(
        tester,
        load: (start, count) async => {
          'days': dates(start),
          'blocks': <BoardItem>[],
        },
      );
      final controller = horizontal(tester);
      final initial = controller.offset;
      final gesture = await tester.startGesture(
        tester.getCenter(keyed(surface)),
      );
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(controller.offset, closeTo(initial + 40, .01));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          controller.offset,
          closeTo(initial + 40, .01),
          reason: 'stationary finger, frame $frame',
        );
      }
      for (var step = 0; step < 4; step++) {
        await gesture.moveBy(const Offset(-12, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, closeTo(initial + 40 + (step + 1) * 12, .01));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final source in ['planner-horizontal', 'planner-date-header']) {
    testWidgets(
      'touching the peer interrupts $source inertia without stealing its new drag',
      (tester) async {
        await mount(
          tester,
          load: (start, count) async => {
            'days': dates(start),
            'blocks': <BoardItem>[],
          },
        );
        final peer = source == 'planner-horizontal'
            ? 'planner-date-header'
            : 'planner-horizontal';
        await tester.fling(keyed(source), const Offset(-120, 0), 800);
        await tester.pump(const Duration(milliseconds: 16));
        final before = horizontal(tester).offset;
        final gesture = await tester.startGesture(
          tester.getCenter(keyed(peer)),
        );
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(horizontal(tester).offset, closeTo(before, .01));
        }
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(horizontal(tester).offset, closeTo(before - 40, .01));
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(horizontal(tester).offset, closeTo(before - 60, .01));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'display-only browsing remains available during foreground refresh',
    (tester) async {
      final viewports = <BoardItem>[];
      await mount(
        tester,
        enabled: false,
        load: (_, _) async => null,
        viewport: viewports.add,
      );
      await tester.drag(keyed('planner-horizontal'), const Offset(-114, 0));
      await tester.pumpAndSettle();
      expect(viewports.last['startDate'], '2026-10-20');
      expect(
        tester.widget<PlannerBoard>(find.byType(PlannerBoard)).enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nearby horizontal gestures are local and headers are virtualized',
    (tester) async {
      final requests = <String>[];
      final viewports = <BoardItem>[];
      final events = <Object?>[];
      await mount(
        tester,
        load: (start, count) async {
          requests.add(start);
          return {'days': dates(start), 'blocks': <BoardItem>[]};
        },
        viewport: viewports.add,
        event: events.add,
      );
      await tester.drag(keyed('planner-horizontal'), const Offset(-114, 8));
      await tester.pumpAndSettle();
      await tester.drag(keyed('planner-date-header'), const Offset(-114, 0));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(events, isEmpty);
      expect(viewports.last['startDate'], '2026-10-21');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey &&
                  '${(widget.key! as ValueKey).value}'.startsWith(
                    'planner-day:',
                  ),
            )
            .evaluate()
            .length,
        lessThan(12),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a short fast flick advances instead of snapping back', (
    tester,
  ) async {
    final viewports = <BoardItem>[];
    await mount(
      tester,
      load: (start, count) async => {
        'days': dates(start),
        'blocks': <BoardItem>[],
      },
      viewport: viewports.add,
    );
    final before = horizontal(tester).offset;
    await tester.fling(keyed('planner-horizontal'), const Offset(-40, 0), 700);
    await tester.pumpAndSettle();
    expect(
      viewports,
      isNotEmpty,
      reason: 'offset $before -> ${horizontal(tester).offset}',
    );
    expect(
      DateTime.parse(viewports.last['startDate'] as String)
          .isAfter(DateTime.utc(2026, 10, 19)),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('late background data cannot reset a newer scroll position', (
    tester,
  ) async {
    final reply = Completer<BoardItem?>();
    final requests = <String>[];
    final viewports = <BoardItem>[];
    await mount(
      tester,
      load: (start, count) {
        requests.add(start);
        return reply.future;
      },
      viewport: viewports.add,
    );
    horizontal(tester).jumpTo(39 * 114);
    await tester.pump();
    await tester.pump();
    expect(requests, hasLength(1));
    await tester.drag(keyed('planner-horizontal'), const Offset(-114, 0));
    await tester.pumpAndSettle();
    final before = horizontal(tester).offset;
    final date = viewports.last['startDate'];
    reply.complete({'days': dates(requests.single), 'blocks': <BoardItem>[]});
    await tester.pumpAndSettle();
    expect(horizontal(tester).offset, closeTo(before, .01));
    expect(viewports.last['startDate'], date);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recycling preserves absolute date and limits physical extent', (
    tester,
  ) async {
    final viewports = <BoardItem>[];
    await mount(
      tester,
      load: (start, count) async => {
        'days': dates(start),
        'blocks': <BoardItem>[],
      },
      viewport: viewports.add,
    );
    for (var index = 0; index < 12; index++) {
      final controller = horizontal(tester);
      controller.jumpTo(controller.offset + 20 * 114);
      await tester.pumpAndSettle();
      expect(
        horizontal(tester).position.maxScrollExtent,
        closeTo(60 * 114, .01),
      );
      expect(
        find.byKey(ValueKey('planner-day:${viewports.last['startDate']}')),
        findsOneWidget,
      );
      expect(
        DateTime.parse('${viewports.last['startDate']}T00:00:00Z')
            .difference(DateTime.utc(2026, 10, 19))
            .inDays,
        (index + 1) * 20,
        reason:
            'recycle $index, offset ${horizontal(tester).offset}, reported $viewports',
      );
    }
    expect(
      DateTime.parse('${viewports.last['startDate']}T00:00:00Z')
          .difference(DateTime.utc(2026, 10, 19))
          .inDays,
      240,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed ranges show a local retry without disabling horizontal scroll',
    (tester) async {
      var fail = true;
      var requests = 0;
      await mount(
        tester,
        load: (start, count) async {
          requests++;
          if (fail) throw StateError('unavailable');
          return {'days': dates(start), 'blocks': <BoardItem>[]};
        },
      );
      horizontal(tester).jumpTo(45 * 114);
      await tester.pumpAndSettle();
      expect(find.text('重试加载'), findsWidgets);
      expect(requests, 1);
      fail = false;
      await tester.tap(find.text('重试加载').hitTestable().first);
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('重试加载').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
