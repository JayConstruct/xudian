import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_board.dart';
import 'package:task_app/core/ui/content_colors.dart';

Future<void> _mount(
  WidgetTester tester, {
  List<BoardItem> candidates = const [],
  List<BoardItem> blocks = const [],
  List<Object?> selectedIds = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xff6750a4)),
      home: Scaffold(
        body: PlannerBoard(
          days: const [
            {'date': '2026-10-19', 'label': '周一 10/19'},
          ],
          candidates: candidates,
          blocks: blocks,
          selectedIds: selectedIds,
          options: const {
            'startMinute': 480,
            'endMinute': 720,
            'initialMinute': 480,
          },
          onEvent: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Material _cardMaterial(WidgetTester tester, String title) =>
    tester.element(find.text(title)).findAncestorWidgetOfExactType<Material>()!;

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(PlannerBoard))).colorScheme;

BoardItem _block(String id, String title, String colorKey) => {
  'id': id,
  'title': title,
  'colorKey': colorKey,
  'start': '2026-10-19T09:00:00',
  'end': '2026-10-19T10:00:00',
};

void main() {
  testWidgets('candidate and scheduled versions retain their identity color', (
    tester,
  ) async {
    await _mount(
      tester,
      candidates: const [
        {'id': 'candidate:42', 'title': '写课程报告', 'colorKey': 'task:42'},
      ],
    );
    final candidateColor = _cardMaterial(tester, '写课程报告').color;
    expect(
      candidateColor,
      ContentColors.surface(ContentColors.accent('task:42'), _scheme(tester)),
    );
    await _mount(tester, blocks: [_block('scheduled:42', '写课程报告', 'task:42')]);
    expect(_cardMaterial(tester, '写课程报告').color, candidateColor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('different tasks have different colored card backgrounds', (
    tester,
  ) async {
    await _mount(
      tester,
      candidates: const [
        {'id': 'one', 'title': '阅读课文', 'colorKey': 'task:one'},
        {'id': 'two', 'title': '准备实验', 'colorKey': 'task:two'},
      ],
    );
    final first = _cardMaterial(tester, '阅读课文').color;
    final second = _cardMaterial(tester, '准备实验').color;
    expect(first, isNot(second));
    expect(
      first,
      ContentColors.surface(ContentColors.accent('task:one'), _scheme(tester)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only course uses its custom color and visible hatching', (
    tester,
  ) async {
    await _mount(
      tester,
      blocks: [
        {
          ..._block('course', '高等数学', 'course:math'),
          'color': '#e05b86',
          'readOnly': true,
        },
      ],
    );
    expect(
      _cardMaterial(tester, '高等数学').color,
      ContentColors.surface(const Color(0xffe05b86), _scheme(tester)),
    );
    final texture = find.descendant(
      of: find.byWidget(_cardMaterial(tester, '高等数学')),
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter != null,
      ),
    );
    expect(texture, findsOneWidget);
    expect(tester.widget<CustomPaint>(texture).painter, isNotNull);
    expect(find.byIcon(Icons.school_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected card retains color and gains a distinct border', (
    tester,
  ) async {
    final block = _block('selected-task', '完成作业', 'task:homework');
    await _mount(tester, blocks: [block]);
    final unselectedColor = _cardMaterial(tester, '完成作业').color;
    await _mount(tester, blocks: [block], selectedIds: ['selected-task']);
    expect(_cardMaterial(tester, '完成作业').color, unselectedColor);
    final borders = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text('完成作业'),
            matching: find.byType(Container),
          ),
        )
        .map((container) => container.foregroundDecoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>();
    expect(
      borders.any(
        (border) =>
            border.isUniform &&
            border.top.width >= 2 &&
            border.top.color == _scheme(tester).primary,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
