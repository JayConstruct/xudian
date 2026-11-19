import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';

// Run with --dart-define=PLANNER_PERF_BASELINE=true to record the previous
// implementation without enforcing the new deterministic work budgets.
const _baseline = bool.fromEnvironment('PLANNER_PERF_BASELINE');

class _CountingItem extends MapBase<String, Object?> {
  _CountingItem(this.value);
  final BoardItem value;
  int timeReads = 0;
  @override
  Object? operator [](Object? key) {
    if (key == 'start' || key == 'end') timeReads++;
    return value[key];
  }

  @override
  void operator []=(String key, Object? item) => value[key] = item;
  @override
  Iterable<String> get keys => value.keys;
  @override
  void clear() => value.clear();
  @override
  Object? remove(Object? key) => value.remove(key);
}

class _CountingScaler extends TextScaler {
  final _calls = [0];
  int get calls => _calls[0];
  set calls(int value) => _calls[0] = value;
  @override
  double scale(double fontSize) {
    calls++;
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}

class _Fixture {
  _Fixture() {
    days = List.generate(28, (index) {
      final date = DateTime.utc(
        2026,
        10,
        15 + index,
      ).toIso8601String().substring(0, 10);
      return <String, Object?>{'date': date, 'label': date.substring(5)};
    });
    items = [
      for (var day = 0; day < 28; day++)
        for (var hour = 0; hour < 24; hour++)
          _CountingItem({
            'id': 'day${day}hour$hour',
            'title': 'day${day}hour$hour',
            'start':
                '${days[day]['date']}T${hour.toString().padLeft(2, '0')}:00:00',
            'end':
                '${days[day]['date']}T${hour.toString().padLeft(2, '0')}:10:00',
            'event': {'action': 'detail', 'id': 'day${day}hour$hour'},
            'moveEvent': {'action': 'move'},
          }),
    ];
    blocks = items;
  }
  late List<BoardItem> days, blocks;
  late List<_CountingItem> items;
  void reset() {
    for (final item in items) {
      item.timeReads = 0;
    }
  }

  int get reads => items.fold(0, (total, item) => total + item.timeReads);
  int get touched => items.where((item) => item.timeReads > 0).length;
}

int _mountedCards() => find
    .byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('block:');
    })
    .evaluate()
    .length;

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  BoardItem options = const {'dashboard': true, 'initialMinute': 540},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlannerBoard(
          days: fixture.days,
          blocks: fixture.blocks,
          options: options,
          onEvent: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _record(String phase, _Fixture fixture, Stopwatch watch) {
  debugPrint(
    'PlannerBoard work [$phase]: tasks=${fixture.items.length}, '
    'timeReads=${fixture.reads}, touchedTasks=${fixture.touched}, '
    'mountedCards=${_mountedCards()}, elapsedUs=${watch.elapsedMicroseconds} '
    '(elapsed is diagnostic only; Flutter widget-test time is not device FPS)',
  );
}

void main() {
  testWidgets(
    'partial display reuses cached outside counts and real display changes invalidate geometry',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _Fixture();
      const partial = <String, Object?>{
        'dashboard': true,
        'initialMinute': 540,
        'startMinute': 480,
        'endMinute': 1080,
      };
      await _mount(tester, fixture, options: partial);
      expect(find.textContaining('392 项'), findsOneWidget);
      fixture.reset();
      final watch = Stopwatch()..start();
      await _mount(tester, fixture, options: partial);
      _record('same-data partial-range rebuild', fixture, watch);
      if (!_baseline) expect(fixture.touched, lessThan(100));
      expect(find.textContaining('392 项'), findsOneWidget);

      await _mount(
        tester,
        fixture,
        options: {...partial, 'pixelsPerMinute': 2},
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('occupancy:day0hour9:2026-10-15')),
            )
            .height,
        20,
      );

      // Extending the visible start includes the previously hidden morning.
      await _mount(tester, fixture, options: {...partial, 'startMinute': 420});
      expect(find.textContaining('364 项'), findsOneWidget);

      // The identical task snapshot must be re-indexed for a new set of dates.
      fixture.days = fixture.days.skip(1).toList();
      await _mount(tester, fixture, options: partial);
      expect(
        find.byKey(const ValueKey('occupancy:day0hour9:2026-10-15')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('occupancy:day1hour9:2026-10-16')),
        findsOneWidget,
      );
      expect(find.textContaining('378 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long-block scrolling reuses text work even across row clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scaler = _CountingScaler();
    final days = [
      for (var i = 0; i < 5; i++)
        <String, Object?>{'date': '2026-10-${15 + i}', 'label': 'date$i'},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Scaffold(
            body: PlannerBoard(
              days: days,
              blocks: [
                for (var i = 0; i < 5; i++)
                  <String, Object?>{
                    'id': 'long$i',
                    'title': '长课程$i',
                    'start': '2026-10-${15 + i}T08:00:00',
                    'end': '2026-10-${15 + i}T13:00:00',
                    'location': '主教学楼第一会议室',
                    'teacher': '教师$i',
                    'readOnly': true,
                  },
              ],
              options: const {'dashboard': true, 'initialMinute': 540},
              onEvent: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cold = scaler.calls;
    scaler.calls = 0;
    final vertical = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('planner-vertical')),
        )
        .controller!;
    vertical.jumpTo(vertical.offset + 1);
    await tester.pumpAndSettle();
    debugPrint(
      'PlannerBoard text work [one pixel scroll]: '
      'coldTextScaleCalls=$cold, scrollTextScaleCalls=${scaler.calls}; '
      'scale calls observe entry to text sizing, not exact TextPainter layout count',
    );
    if (!_baseline) expect(scaler.calls, 0);

    // Cross metadata visibility boundaries inside one virtualization window.
    // The rows must remain laid out even as the shared scroll clips them away.
    final viewport = tester.getRect(
      find.byKey(const ValueKey('planner-vertical')),
    );
    final endTop = tester
        .getTopLeft(
          find.byKey(const ValueKey('block-time-end:long0:2026-10-15')),
        )
        .dy;
    final cutoff = vertical.offset + endTop - viewport.top - 5;
      final windowStart = (cutoff / 64).floor() * 64.0 + 1;
    vertical.jumpTo(windowStart);
    await tester.pumpAndSettle();
    final teacher = find.byKey(
      const ValueKey('planner-info:long0:2026-10-15:teacher'),
    );
    final teacherHeight = tester.getSize(teacher).height;
    scaler.calls = 0;
    for (var step = 2; step <= 60; step += 2) {
      vertical.jumpTo(windowStart + step);
      await tester.pump();
    }
    debugPrint(
      'PlannerBoard text work [30 scroll steps across row clipping]: '
      'textScaleCalls=${scaler.calls}',
    );
    if (!_baseline) expect(scaler.calls, 0);
    expect(tester.getSize(teacher).height, teacherHeight);
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('长课程0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '672 task scroll and unchanged host rebuild avoid whole-data time parsing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _Fixture();
      final watch = Stopwatch()..start();
      await _mount(tester, fixture);
      _record('cold mount', fixture, watch);
      expect(fixture.items, hasLength(672));
      expect(_mountedCards(), inExclusiveRange(1, 80));

      fixture.reset();
      watch.reset();
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
      await tester.pumpAndSettle();
      _record('scroll to day20/hour20', fixture, watch);
      expect(find.text('day20hour20'), findsOneWidget);
      expect(_mountedCards(), lessThan(80));
      if (!_baseline) expect(fixture.touched, lessThan(100));

      fixture.reset();
      watch.reset();
      await _mount(tester, fixture);
      _record('same-data host rebuild', fixture, watch);
      expect(find.text('day20hour20'), findsOneWidget);
      expect(horizontal.offset, 20 * 112);
      if (!_baseline) expect(fixture.touched, lessThan(100));

      // A genuine data revision must still update the visible task and geometry.
      // Keep the input immutable, as a script response is immutable once mounted.
      fixture.blocks = List<BoardItem>.of(fixture.blocks);
      final index = 20 * 24 + 20;
      fixture.blocks[index] = {
        ...fixture.items[index].value,
        'title': 'changed visible task',
        'end': '${fixture.days[20]['date']}T20:20:00',
      };
      await _mount(tester, fixture);
      expect(find.text('changed visible task'), findsOneWidget);
      expect(
        tester
            .getSize(
              find.byKey(
                ValueKey('occupancy:day20hour20:${fixture.days[20]['date']}'),
              ),
            )
            .height,
        20,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
