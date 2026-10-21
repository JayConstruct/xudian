import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';

const _days = [
  {'date': '2026-10-15', 'label': '10/15'},
  {'date': '2026-10-16', 'label': '10/16'},
  {'date': '2026-10-17', 'label': '10/17'},
  {'date': '2026-10-18', 'label': '10/18'},
  {'date': '2026-10-19', 'label': '10/19'},
];
const _candidates = [
  {
    'id': 'motion',
    'title': '跟手任务',
    'durationMinutes': 30,
    'moveEvent': {'action': 'move'},
  },
];
const _regionKey = ValueKey('planner-candidate-region');
const _toggleKey = ValueKey('planner-toggle-candidates');
const _speed = 14 / .032 * 40 / 44;

Future<void> _show(
  WidgetTester tester, {
  bool reduced = false,
  bool dashboard = false,
  bool timeline = false,
  bool enabled = true,
  ValueChanged<Object?>? onEvent,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: PlannerBoard(
            days: _days,
            candidates: _candidates,
            enabled: enabled,
            options: {
              'dashboard': dashboard,
              'continuousDates': timeline,
              'initialDate': '2026-10-15',
              'initialMinute': 480,
            },
            onEvent: onEvent ?? (event) {},
          ),
        ),
      ),
    ),
  );
}

ScrollController _controller(WidgetTester tester, String name) {
  final widget = tester.widget(find.byKey(ValueKey(name)));
  return widget is SingleChildScrollView
      ? widget.controller!
      : (widget as ScrollView).controller!;
}

Rect _viewport(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('planner-vertical')));

Future<TestGesture> _drag(WidgetTester tester, Offset target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('跟手任务').hitTestable().last),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(target - const Offset(0, 2));
  await tester.pump();
  await gesture.moveTo(target);
  await tester.pump();
  return gesture;
}

double _rotation(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(
        of: find.byKey(_toggleKey),
        matching: find.byType(RotationTransition),
      ),
    )
    .turns
    .value;

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.physicalSize = const Size(360, 850);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets(
    'edge scrolling advances each frame and keeps the header linked',
    (tester) async {
      await _show(tester);
      await tester.pumpAndSettle();
      final horizontal = _controller(tester, 'planner-horizontal');
      final vertical = _controller(tester, 'planner-vertical');
      final header = _controller(tester, 'planner-date-header');
      final gesture = await _drag(
        tester,
        _viewport(tester).bottomRight - const Offset(4, 4),
      );
      final horizontalStart = horizontal.offset;
      final verticalStart = vertical.offset;
      for (var frame = 1; frame <= 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          horizontal.offset - horizontalStart,
          closeTo(_speed * .016 * frame, .001),
        );
        expect(
          vertical.offset - verticalStart,
          closeTo(_speed * .016 * frame, .001),
        );
        expect(header.offset, closeTo(horizontal.offset, .001));
      }
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('delayed frames integrate the same elapsed-time distance', (
    tester,
  ) async {
    await _show(tester);
    await tester.pumpAndSettle();
    final vertical = _controller(tester, 'planner-vertical');
    final viewport = _viewport(tester);
    final gesture = await _drag(
      tester,
      Offset(viewport.center.dx, viewport.bottom - 4),
    );
    final start = vertical.offset;
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final regularDistance = vertical.offset - start;
    await tester.pump(const Duration(milliseconds: 160));
    expect(regularDistance, closeTo(_speed * .160, .001));
    expect(vertical.offset - start, closeTo(regularDistance * 2, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'edge ramp and center preserve proportional velocity and no drift',
    (tester) async {
      await _show(tester);
      await tester.pumpAndSettle();
      final vertical = _controller(tester, 'planner-vertical');
      final viewport = _viewport(tester);
      final gesture = await _drag(
        tester,
        Offset(viewport.center.dx, viewport.bottom - 22),
      );
      final start = vertical.offset;
      await tester.pump(const Duration(milliseconds: 160));
      expect(vertical.offset - start, closeTo(437.5 * .5 * .160, .001));
      await gesture.moveTo(viewport.center);
      await tester.pump();
      final centered = vertical.offset;
      await tester.pump(const Duration(milliseconds: 160));
      expect(vertical.offset, centered);
      await gesture.cancel();
      await tester.pumpAndSettle();
    },
  );

  for (final maximum in [false, true]) {
    testWidgets(
      'edge scrolling clamps both ${maximum ? 'maximum' : 'minimum'} extents',
      (tester) async {
        await _show(tester);
        await tester.pumpAndSettle();
        final horizontal = _controller(tester, 'planner-horizontal');
        final vertical = _controller(tester, 'planner-vertical');
        horizontal.jumpTo(
          maximum ? horizontal.position.maxScrollExtent - 1 : 1,
        );
        vertical.jumpTo(maximum ? vertical.position.maxScrollExtent - 1 : 1);
        await tester.pump();
        final viewport = _viewport(tester);
        final gesture = await _drag(
          tester,
          maximum
              ? viewport.bottomRight - const Offset(4, 4)
              : viewport.topLeft + const Offset(52, 4),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(
          horizontal.offset,
          maximum ? horizontal.position.maxScrollExtent : 0,
        );
        expect(
          vertical.offset,
          maximum ? vertical.position.maxScrollExtent : 0,
        );
        await gesture.cancel();
        await tester.pumpAndSettle();
      },
    );
  }

  for (final ending in ['leave', 'cancel', 'drop', 'disable', 'dispose']) {
    testWidgets('$ending stops frame callbacks without stale scrolling', (
      tester,
    ) async {
      final events = <Object?>[];
      await _show(tester, onEvent: events.add);
      await tester.pumpAndSettle();
      final horizontal = _controller(tester, 'planner-horizontal');
      final vertical = _controller(tester, 'planner-vertical');
      final gesture = await _drag(
        tester,
        _viewport(tester).bottomRight - const Offset(4, 4),
      );
      await tester.pump(const Duration(milliseconds: 48));
      if (ending == 'leave') {
        await gesture.moveTo(const Offset(20, 20));
      } else if (ending == 'cancel') {
        await gesture.cancel();
      } else if (ending == 'drop') {
        await gesture.up();
      } else if (ending == 'disable') {
        await _show(tester, enabled: false, onEvent: events.add);
      } else {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pumpAndSettle();
      final horizontalStopped = ending == 'dispose' ? null : horizontal.offset;
      final verticalStopped = ending == 'dispose' ? null : vertical.offset;
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 1));
      if (ending != 'dispose') {
        expect(horizontal.offset, horizontalStopped);
        expect(vertical.offset, verticalStopped);
      }
      expect(events, hasLength(ending == 'drop' ? 1 : 0));
      if (ending == 'leave') {
        await gesture.moveTo(
          _viewport(tester).bottomRight - const Offset(4, 4),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          vertical.offset - verticalStopped!,
          closeTo(_speed * .016, .001),
        );
      }
      if (ending != 'cancel' && ending != 'drop') await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion preserves functional scrolling and fine snap', (
    tester,
  ) async {
    final events = <Object?>[];
    await _show(tester, reduced: true, onEvent: events.add);
    await tester.pumpAndSettle();
    final vertical = _controller(tester, 'planner-vertical');
    final gesture = await _drag(
      tester,
      _viewport(tester).bottomRight - const Offset(4, 4),
    );
    final start = vertical.offset;
    await tester.pump(const Duration(milliseconds: 700));
    expect(vertical.offset - start, closeTo(_speed * .700, .001));
    expect(find.textContaining('1分钟细调'), findsWidgets);
    await gesture.up();
    await tester.pumpAndSettle();
    expect((events.single as Map)['snapMinutes'], 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('timeline edge scrolling keeps the existing linked controllers', (
    tester,
  ) async {
    await _show(tester, dashboard: true, timeline: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    final horizontal = _controller(tester, 'planner-horizontal');
    final header = _controller(tester, 'planner-date-header');
    final viewport = _viewport(tester);
    final gesture = await _drag(
      tester,
      Offset(viewport.right - 4, viewport.center.dy),
    );
    final start = horizontal.offset;
    await tester.pump(const Duration(milliseconds: 16));
    expect(horizontal.offset - start, closeTo(_speed * .016, .001));
    expect(header.offset, closeTo(horizontal.offset, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'normal candidate collapse retains intermediate rotation and size',
    (tester) async {
      await _show(tester, dashboard: true);
      await tester.pumpAndSettle();
      final height = tester.getSize(find.byKey(_regionKey)).height;
      await tester.tap(find.byKey(_toggleKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester.getSize(find.byKey(_regionKey)).height,
        inExclusiveRange(0, height),
      );
      expect(_rotation(tester), inExclusiveRange(-.25, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_regionKey)).height, 0);
      expect(_rotation(tester), -.25);
    },
  );

  testWidgets('disableAnimations collapses and expands in one frame', (
    tester,
  ) async {
    await _show(tester, reduced: true, dashboard: true);
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byKey(_regionKey)).height;
    await tester.tap(find.byKey(_toggleKey));
    await tester.pump();
    expect(tester.getSize(find.byKey(_regionKey)).height, 0);
    expect(_rotation(tester), -.25);
    await tester.tap(find.byKey(_toggleKey));
    await tester.pump();
    expect(tester.getSize(find.byKey(_regionKey)).height, height);
    expect(_rotation(tester), 0);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final expanding in [false, true]) {
    testWidgets(
      'enabling reduced motion finishes an in-flight ${expanding ? 'expansion' : 'collapse'}',
      (tester) async {
        await _show(tester, dashboard: true);
        await tester.pumpAndSettle();
        final height = tester.getSize(find.byKey(_regionKey)).height;
        if (expanding) {
          await tester.tap(find.byKey(_toggleKey));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(_toggleKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          tester.getSize(find.byKey(_regionKey)).height,
          inExclusiveRange(0, height),
        );
        expect(_rotation(tester), inExclusiveRange(-.25, 0));
        await _show(tester, reduced: true, dashboard: true);
        expect(
          tester.getSize(find.byKey(_regionKey)).height,
          expanding ? height : 0,
        );
        expect(_rotation(tester), expanding ? 0 : -.25);
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getSize(find.byKey(_regionKey)).height,
          expanding ? height : 0,
        );
        expect(_rotation(tester), expanding ? 0 : -.25);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
}
