import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/module_host/time_grid.dart';

const _title = '课程方块标题需要更多空间完整显示文字内容';
const _subtitle = '教学楼 101 · 课程教师';

Future<void> _pumpGrid(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required double rowHeight,
  required int span,
  required void Function(Object?) onEvent,
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
      home: Scaffold(
        body: TimeGrid(
          options: {
            'fillWidth': true,
            'fitColumns': true,
            'labelWidth': 42,
            'rowHeight': rowHeight,
          },
          columns: [
            for (var index = 0; index < 7; index++)
              {'id': '$index', 'title': '周${index + 1}'},
          ],
          rows: [
            for (var index = 0; index < span; index++)
              {'id': '$index', 'title': '${index + 1}'},
          ],
          blocks: [
            {
              'column': '0',
              'start': 0,
              'end': span,
              'title': _title,
              'subtitle': _subtitle,
              'event': 'detail',
            },
          ],
          onEvent: onEvent,
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _course() =>
    find.ancestor(of: find.text(_title), matching: find.byType(InkWell));

void main() {
  testWidgets('normal course content geometry', (tester) async {
    final events = <Object?>[];
    await _pumpGrid(
      tester,
      size: const Size(546, 600),
      scale: 1,
      rowHeight: 72,
      span: 2,
      onEvent: events.add,
    );

    final card = tester.getRect(_course());
    final title = tester.getRect(find.text(_title));
    final subtitle = tester.getRect(find.text(_subtitle));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(_title));
    final lineTops = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: _title.length),
        )
        .map((box) => box.top)
        .toSet();
    final titleWidget = tester.widget<Text>(find.text(_title));
    final subtitleWidget = tester.widget<Text>(find.text(_subtitle));

    expect(card.size, const Size(68, 140));
    expect(title.left - card.left, 2);
    expect(title.top - card.top, 2);
    expect(title.width, 64);
    expect(paragraph.constraints.maxHeight, 136);
    expect(titleWidget.maxLines, 4);
    expect(lineTops, hasLength(4));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(titleWidget.style!.fontSize, 12.5);
    expect(titleWidget.style!.height, 1.3);
    expect(subtitleWidget.style!.fontSize, 11);
    expect(subtitleWidget.style!.height, 1.35);
    expect(subtitleWidget.maxLines, 4);
    expect(subtitle.top, title.bottom);
    expect(subtitle.height, greaterThan(0));
    expect(subtitle.bottom, lessThanOrEqualTo(card.bottom - 2));
    expect(tester.takeException(), isNull);

    await tester.tap(_course());
    expect(events, ['detail']);
  });

  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets('compact content at ${scale}x', (tester) async {
      final events = <Object?>[];
      await _pumpGrid(
        tester,
        size: const Size(320, 600),
        scale: scale,
        rowHeight: 48,
        span: 1,
        onEvent: events.add,
      );

      final card = tester.getRect(_course());
      final title = tester.getRect(find.text(_title));
      final subtitle = tester.getRect(find.text(_subtitle));
      final paragraph = tester.renderObject<RenderParagraph>(find.text(_title));
      final titleWidget = tester.widget<Text>(find.text(_title));
      final subtitleWidget = tester.widget<Text>(find.text(_subtitle));
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: _course(), matching: find.byType(Tooltip)),
      );

      expect(card.width, closeTo((320 - 42) / 7 - 4, .001));
      expect(card.height, 44);
      expect(title.left - card.left, 2);
      expect(title.top - card.top, 2);
      expect(title.width, closeTo(card.width - 4, .001));
      expect(paragraph.constraints.maxHeight, 40);
      expect(title.height, 40);
      expect(subtitle.height, 0);
      expect(subtitle.bottom, card.bottom - 2);
      expect(titleWidget.maxLines, 4);
      expect(titleWidget.overflow, TextOverflow.ellipsis);
      expect(subtitleWidget.overflow, TextOverflow.ellipsis);
      expect(titleWidget.style!.fontSize, 12.5);
      expect(subtitleWidget.style!.fontSize, 11);
      expect(paragraph.textScaler.scale(12.5), closeTo(12.5 * scale, .001));
      expect(tooltip.message, contains(_title));
      expect(tooltip.message, contains(_subtitle));
      expect(
        find.bySemanticsLabel(RegExp('$_title，$_subtitle')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(_course());
      expect(events, ['detail']);
    });
  }
}
