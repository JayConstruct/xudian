import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/module_host/time_grid.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('course colors stay readable and selectable in $brightness', (
      tester,
    ) async {
      final events = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(brightness),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 400,
              child: TimeGrid(
                options: const {'fillWidth': true, 'rowHeight': 72},
                columns: const [
                  {
                    'id': 'mon',
                    'title': '周一',
                    'subtitle': '10/12',
                    'highlight': true,
                  },
                ],
                rows: const [
                  {'id': '1', 'title': '1', 'subtitle': '08:00'},
                  {'id': '2', 'title': '2', 'subtitle': '09:00'},
                ],
                blocks: const [
                  {
                    'column': 'mon',
                    'start': 0,
                    'end': 1,
                    'title': '浅色课程',
                    'subtitle': '教学楼 101',
                    'color': '#F5D96B',
                    'event': 'light',
                  },
                  {
                    'column': 'mon',
                    'start': 0,
                    'end': 1,
                    'title': '深色课程',
                    'subtitle': '教学楼 202',
                    'color': '#303C76',
                    'event': 'dark',
                  },
                ],
                onEvent: events.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final title in ['浅色课程', '深色课程']) {
        final text = tester.widget<Text>(find.text(title));
        final course = tester
            .widgetList<Material>(
              find.ancestor(
                of: find.text(title),
                matching: find.byType(Material),
              ),
            )
            .singleWhere((widget) => widget.shape is RoundedSuperellipseBorder);
        expect(
          contrast(text.style!.color!, course.color!),
          greaterThanOrEqualTo(4.5),
        );
        expect(course.color!.a, 1);
        await tester.tap(find.text(title));
      }
      expect(events, ['light', 'dark']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'compact courses retain full details without large-text overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(Brightness.dark),
          home: Scaffold(
            body: TimeGrid(
              options: const {
                'fillWidth': true,
                'rowHeight': 48,
                'labelWidth': 42,
                'fitColumns': true,
              },
              columns: [
                for (var i = 0; i < 7; i++) {'id': '$i', 'title': '周${i + 1}'},
              ],
              rows: const [
                {'id': '1', 'title': '1', 'subtitle': '08:00'},
              ],
              blocks: const [
                {
                  'column': '0',
                  'start': 0,
                  'end': 1,
                  'title': '课程标题非常长也保留完整提示',
                  'subtitle': '教学楼 101 · 课程教师',
                  'event': 'detail',
                },
              ],
              onEvent: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('课程标题非常长也保留完整提示'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, contains('教学楼 101 · 课程教师'));
      expect(tester.takeException(), isNull);
    },
  );
}
