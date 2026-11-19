import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';
import 'package:task_app/core/module_host/planner_status_indicator.dart';

typedef _Scene = ({List<BoardItem> blocks, bool enabled});

const _date = '2026-10-22';
BoardItem _task(
  String title,
  String start,
  String end, {
  bool completed = false,
}) => {
  'id': title,
  'title': title,
  'colorKey': title,
  'start': '${_date}T$start:00',
  'end': '${_date}T$end:00',
  'completed': completed,
  'statusIndicator': 'edgeToCorner',
  'event': {'type': 'detail', 'id': title},
  if (!completed) 'moveEvent': {'type': 'move', 'taskId': title},
};

Future<ValueNotifier<_Scene>> _mount(
  WidgetTester tester,
  List<BoardItem> blocks, {
  Size size = const Size(900, 900),
  TextScaler scaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final scene = ValueNotifier<_Scene>((blocks: blocks, enabled: true));
  addTearDown(scene.dispose);
  await tester.pumpWidget(
    ValueListenableBuilder<_Scene>(
      valueListenable: scene,
      builder: (context, value, _) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: scaler),
          child: Scaffold(
            body: PlannerBoard(
              days: const [
                {'date': _date, 'label': '10/22'},
                {'date': '2026-10-23', 'label': '10/23'},
                {'date': '2026-10-24', 'label': '10/24'},
              ],
              candidates: const [],
              blocks: value.blocks,
              enabled: value.enabled,
              options: const {
                'dashboard': true,
                'continuousDates': true,
                'initialDate': _date,
                'today': _date,
                'visibleDays': 3,
                'startMinute': 540,
                'endMinute': 900,
                'initialMinute': 540,
                'pixelsPerMinute': 1.5,
              },
              onEvent: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scene;
}

Finder _indicator(String title, {Finder? scope}) {
  final text = scope == null
      ? find.text(title)
      : find.descendant(of: scope, matching: find.text(title));
  return find.ancestor(of: text, matching: find.byType(PlannerStatusIndicator));
}

Rect _titleRect(WidgetTester tester, Finder indicator, String title) =>
    tester.getRect(find.descendant(of: indicator, matching: find.text(title)));

double _progress(WidgetTester tester, Finder indicator) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: indicator, matching: find.byType(CustomPaint)).first,
  );
  final dynamic painter = paint.foregroundPainter;
  return (painter.progress as Animation<double>).value;
}

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, .01));
  expect(actual.top, closeTo(expected.top, .01));
  expect(actual.width, closeTo(expected.width, .01));
  expect(actual.height, closeTo(expected.height, .01));
}

void main() {
  testWidgets(
    'selected timeline task retains animation state and title geometry while completing and reopening',
    (tester) async {
      const title = '稳定的一小时任务';
      final pending = _task(title, '10:00', '11:00');
      final scene = await _mount(tester, [pending]);
      final indicator = _indicator(title);
      expect(indicator, findsOneWidget);
      final state = tester.state(indicator);
      final original = _titleRect(tester, indicator, title);
      expect(_progress(tester, indicator), 0);
      await tester.tap(
        find.descendant(of: indicator, matching: find.text(title)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('planner-selection-panel')),
        findsOneWidget,
      );
      expect(tester.state(indicator), same(state));
      _expectRect(_titleRect(tester, indicator, title), original);

      scene.value = (blocks: [pending], enabled: false);
      await tester.pump();
      expect(tester.state(indicator), same(state));
      final completed = _task(title, '10:00', '11:00', completed: true);
      scene.value = (blocks: [completed], enabled: false);
      await tester.pump();
      expect(tester.state(indicator), same(state));
      await tester.pump(const Duration(milliseconds: 140));
      final halfway = _progress(tester, indicator);
      expect(halfway, inExclusiveRange(0, 1));
      final text = tester.widget<Text>(
        find.descendant(of: indicator, matching: find.text(title)),
      );
      expect(text.style?.decoration, isNot(TextDecoration.lineThrough));
      expect(
        find.descendant(
          of: indicator,
          matching: find.byIcon(Icons.check_circle_outline),
        ),
        findsNothing,
      );
      _expectRect(_titleRect(tester, indicator, title), original);

      scene.value = (blocks: [completed], enabled: true);
      await tester.pump();
      expect(tester.state(indicator), same(state));
      expect(_progress(tester, indicator), closeTo(halfway, .001));
      scene.value = (blocks: [pending], enabled: true);
      await tester.pump();
      expect(_progress(tester, indicator), closeTo(halfway, .001));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_progress(tester, indicator), inExclusiveRange(0, halfway));
      await tester.pumpAndSettle();
      expect(tester.state(indicator), same(state));
      expect(_progress(tester, indicator), 0);
      _expectRect(_titleRect(tester, indicator, title), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'minute and overlapping narrow tasks preserve title space at large text sizes',
    (tester) async {
      final pending = [
        _task('一分钟', '09:30', '09:31'),
        _task('重叠任务甲', '11:00', '11:30'),
        _task('重叠任务乙', '11:10', '11:40'),
      ];
      final scene = await _mount(
        tester,
        pending,
        size: const Size(390, 900),
        scaler: TextScaler.linear(1.8),
      );
      final geometry = <String, Rect>{};
      for (final item in pending) {
        final title = item['title'] as String;
        final indicator = _indicator(title);
        expect(indicator, findsOneWidget);
        geometry[title] = _titleRect(tester, indicator, title);
      }
      final tiny = tester.widget<PlannerStatusIndicator>(_indicator('一分钟'));
      expect(tiny.badgeAtBottom, true);
      expect(tiny.badgeSize, lessThan(16));
      expect(tester.takeException(), isNull);
      scene.value = (
        blocks: [
          for (final item in pending)
            {...item, 'completed': true}..remove('moveEvent'),
        ],
        enabled: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      for (final item in pending) {
        final title = item['title'] as String;
        final indicator = _indicator(title);
        _expectRect(_titleRect(tester, indicator, title), geometry[title]!);
        expect(_progress(tester, indicator), inExclusiveRange(0, 1));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'day list keeps marker state and text geometry across completion and reopening',
    (tester) async {
      const title = '日清单中的任务';
      final pending = _task(title, '10:00', '11:00');
      final scene = await _mount(tester, [pending], size: const Size(390, 900));
      await tester.tap(find.byKey(const ValueKey('planner-day:$_date')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('planner-day-sheet'));
      expect(sheet, findsOneWidget);
      final indicator = _indicator(title, scope: sheet);
      expect(indicator, findsOneWidget);
      final state = tester.state(indicator);
      final original = _titleRect(tester, indicator, title);
      scene.value = (
        blocks: [_task(title, '10:00', '11:00', completed: true)],
        enabled: true,
      );
      await tester.pump();
      // The board forwards its new snapshot to the separate overlay next frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(tester.state(indicator), same(state));
      final halfway = _progress(tester, indicator);
      expect(halfway, inExclusiveRange(0, 1));
      _expectRect(_titleRect(tester, indicator, title), original);
      scene.value = (blocks: [pending], enabled: true);
      await tester.pump();
      await tester.pump();
      expect(_progress(tester, indicator), closeTo(halfway, .001));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_progress(tester, indicator), inExclusiveRange(0, halfway));
      await tester.pumpAndSettle();
      expect(tester.state(indicator), same(state));
      expect(_progress(tester, indicator), 0);
      _expectRect(_titleRect(tester, indicator, title), original);
      expect(tester.takeException(), isNull);
    },
  );
}
