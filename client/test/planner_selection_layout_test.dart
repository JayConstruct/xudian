import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';

const _days = <BoardItem>[
  {'date': '2026-10-15', 'label': '周四 10/15'},
  {'date': '2026-10-16', 'label': '周五 10/16'},
];

BoardItem _task(String id, {bool course = false, bool fixed = false}) => {
  'id': id,
  'title': id,
  'location': '教学楼 301 教室',
  'start': '2026-10-15T08:15:00',
  'end': '2026-10-15T09:45:00',
  'event': {'type': 'details', 'id': id},
  'moveEvent': {'type': 'move'},
  'editTimeEvent': {'type': 'editTime'},
  if (course) 'readOnly': true,
  if (fixed) 'fixed': true,
};

Future<void> _mount(
  WidgetTester tester, {
  required List<BoardItem> blocks,
  ValueChanged<Object?>? onEvent,
  VoidCallback? onOutside,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextButton(
              key: const ValueKey('outside-planner'),
              onPressed: onOutside ?? () {},
              child: const Text('外部操作'),
            ),
            Expanded(
              child: PlannerBoard(
                key: UniqueKey(),
                days: _days,
                blocks: blocks,
                bottomInset: 72,
                options: const {
                  'dashboard': true,
                  'startMinute': 480,
                  'endMinute': 720,
                  'initialMinute': 480,
                },
                onEvent: onEvent ?? (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _block(String id) => find.byKey(ValueKey('block:$id:2026-10-15'));

Finder _textInBlock(String id, String text) =>
    find.descendant(of: _block(id), matching: find.text(text));

final _panel = find.byKey(const ValueKey('planner-selection-panel'));

void main() {
  for (final course in [false, true]) {
    testWidgets(
      '${course ? 'course' : 'task'} selection preserves title and location geometry',
      (tester) async {
        final id = course ? '高等数学课程' : '完成项目任务';
        await _mount(tester, blocks: [_task(id, course: course)]);
        final title = _textInBlock(id, id);
        final location = _textInBlock(id, '教学楼 301 教室');
        final titleRect = tester.getRect(title);
        final locationRect = tester.getRect(location);
        final titleStyle = tester.widget<Text>(title).style;
        final locationStyle = tester.widget<Text>(location).style;

        await tester.tap(title);
        await tester.pumpAndSettle();

        expect(_panel, findsOneWidget);
        expect(tester.getRect(title), titleRect);
        expect(tester.getRect(location), locationRect);
        expect(tester.widget<Text>(title).style, titleStyle);
        expect(tester.widget<Text>(location).style, locationStyle);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('courses reserve title width while fixed tasks retain lock', (
    tester,
  ) async {
    await _mount(
      tester,
      blocks: [
        _task('课程', course: true),
        {
          ..._task('固定任务', fixed: true),
          'start': '2026-10-16T08:15:00',
          'end': '2026-10-16T09:45:00',
        },
      ],
    );
    expect(find.byIcon(Icons.school_outlined), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid, date header and outside actions dismiss selection', (
    tester,
  ) async {
    var outsideCalls = 0;
    await _mount(
      tester,
      blocks: [_task('选中任务')],
      onOutside: () => outsideCalls++,
    );
    Future<void> select() async {
      await tester.tap(_textInBlock('选中任务', '选中任务'));
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
    }

    await select();
    final grid = tester.getRect(find.byType(DragTarget<BoardItem>));
    await tester.tapAt(Offset(grid.right - 24, grid.top + 30));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);

    await select();
    await tester.tap(find.text('周五'));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);

    await select();
    await tester.tap(find.byKey(const ValueKey('outside-planner')));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(outsideCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel actions keep selection and a different card replaces it', (
    tester,
  ) async {
    final events = <Object?>[];
    await _mount(
      tester,
      blocks: [
        _task('第一任务'),
        {
          ..._task('第二任务'),
          'start': '2026-10-16T08:15:00',
          'end': '2026-10-16T09:45:00',
        },
      ],
      onEvent: events.add,
    );
    await tester.tap(_textInBlock('第一任务', '第一任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: _panel, matching: find.text('编辑时间')));
    await tester.pumpAndSettle();
    expect(events.last, {'type': 'editTime', 'id': '第一任务'});
    expect(_panel, findsOneWidget);
    await tester.tap(find.descendant(of: _panel, matching: find.text('查看详情')));
    await tester.pumpAndSettle();
    expect(events.last, {'type': 'details', 'id': '第一任务'});
    expect(_panel, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('block:第二任务:2026-10-16')),
        matching: find.text('第二任务'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _panel, matching: find.text('第二任务')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _panel, matching: find.text('第一任务')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
