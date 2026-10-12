import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/ui/daily_widgets.dart';
import 'package:task_app/core/ui/ui_component.dart';

void main() {
  testWidgets(
    'narrow large-text agenda uses full-width cards and readable centered dates',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(Brightness.dark),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    DayOverview(
                      date: '2026-10-10',
                      dateHeading: false,
                      dateControls: false,
                      days: [
                        for (final day in [8, 9, 10, 11, 12])
                          {
                            'date': '2026-10-${day.toString().padLeft(2, '0')}',
                            'label': '周日',
                            'pending': 1,
                          },
                      ],
                      onChanged: (_) {},
                    ),
                    const AgendaItem(
                      title: '高等数学',
                      subtitle: '教学楼 A101',
                      startTime: '08:00',
                      endTime: '09:35',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selected = tester.getRect(
        find.byKey(const ValueKey('daily-date:2026-10-10')),
      );
      expect(selected.left, greaterThanOrEqualTo(20));
      expect(selected.right, lessThanOrEqualTo(300));
      expect(
        tester.getSize(find.text('10')).height,
        lessThanOrEqualTo(tester.getSize(find.text('8')).height + 1),
        reason: 'Two-digit date remains on one line',
      );
      expect(
        tester.getRect(find.text('08:00 – 09:35')).bottom,
        lessThan(tester.getRect(find.text('高等数学')).top),
      );
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(AgendaItem),
                matching: find.byType(Material),
              ),
            )
            .width,
        greaterThan(200),
        reason: 'Course body receives the card width, not a narrow remainder beside the time',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'date strip centers selection on date/order changes and keeps manual scroll on count refresh',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final options = ValueNotifier((date: '2026-10-10', start: 8, count: 1));
      addTearDown(options.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ValueListenableBuilder(
                  valueListenable: options,
                  builder: (_, value, _) => DayOverview(
                    date: value.date,
                    dateHeading: false,
                    dateControls: false,
                    days: [
                      for (var day = value.start; day < value.start + 5; day++)
                        {
                          'date': '2026-10-${day.toString().padLeft(2, '0')}',
                          'pending': value.count,
                        },
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      void selectedIsVisible() {
        final rect = tester.getRect(
          find.byKey(ValueKey('daily-date:${options.value.date}')),
        );
        expect(rect.left, greaterThanOrEqualTo(20));
        expect(rect.right, lessThanOrEqualTo(300));
      }

      selectedIsVisible();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(0);
      await tester.pump();
      options.value = (date: '2026-10-10', start: 8, count: 2);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, 0);
      options.value = (date: '2026-10-11', start: 9, count: 2);
      await tester.pumpAndSettle();
      selectedIsVisible();
      final before = scroll.position.pixels;
      options.value = (date: '2026-10-11', start: 8, count: 2);
      await tester.pumpAndSettle();
      selectedIsVisible();
      expect(
        scroll.position.pixels,
        greaterThan(before),
        reason: 'Reordering dates recenters the same selected civil date',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final highContrast in [false, true]) {
    testWidgets(
      'date cells retain identity, readable colors and every change event with high contrast $highContrast',
      (tester) async {
        final selected = ValueNotifier('2026-10-10');
        addTearDown(selected.dispose);
        final events = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme(Brightness.light),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
                child: ValueListenableBuilder(
                  valueListenable: selected,
                  builder: (_, date, _) => DayOverview(
                    date: date,
                    selectedDate: date,
                    dateControls: false,
                    dateHeading: false,
                    onChanged: events.add,
                    days: [
                      for (final day in [8, 9, 10, 11, 12])
                        {
                          'date': '2026-10-${day.toString().padLeft(2, '0')}',
                          'label': '日期',
                          'pending': 1,
                        },
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final target = find.byKey(const ValueKey('daily-date:2026-10-11'));
        final original = tester.element(target);
        Color background() =>
            (tester
                        .widget<Container>(
                          find.descendant(
                            of: target,
                            matching: find.byType(Container),
                          ),
                        )
                        .decoration!
                    as BoxDecoration)
                .color!;
        final initial = background();
        selected.value = '2026-10-11';
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        final primary = AppDesign.theme(Brightness.light).colorScheme.primary;
        expect(background(), isNot(initial));
        if (highContrast) {
          expect(background(), primary);
        } else {
          expect(background(), isNot(primary));
        }
        for (final day in [10, 11, 12]) {
          await tester.tap(find.byKey(ValueKey('daily-date:2026-10-$day')));
        }
        expect(events, ['2026-10-10', '2026-10-11', '2026-10-12']);
        selected.value = '2026-10-12';
        await tester.pump(const Duration(milliseconds: 30));
        selected.value = '2026-10-11';
        await tester.pumpAndSettle();
        expect(tester.element(target), same(original));
        expect(background(), primary);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final config in [
    (width: 320.0, scale: 2.0, brightness: Brightness.light),
    (width: 390.0, scale: 1.0, brightness: Brightness.light),
    (width: 1100.0, scale: 1.5, brightness: Brightness.dark),
  ]) {
    testWidgets(
      'daily components keep information and actions at ${config.width}/${config.scale}/${config.brightness}',
      (tester) async {
        tester.view.physicalSize = Size(config.width, 1100);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var courses = 0, opened = 0, added = 0;
        bool? completed;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme(config.brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    defaultUiComponent(
                      'ui.dayOverview@1',
                      {
                        'date': '2026-10-01',
                        'summary': '3 节课程 · 2 项待办',
                        'days': [
                          for (final date in [
                            '2026-09-29',
                            '2026-09-30',
                            '2026-10-01',
                            '2026-10-02',
                            '2026-10-03',
                          ])
                            {
                              'date': date,
                              'label':
                                  '周${['日', '一', '二', '三', '四', '五', '六'][DateTime.parse(date).weekday % 7]}',
                              'pending': 12,
                              'completed': 2,
                            },
                        ],
                      },
                      {},
                      {},
                    ),
                    defaultUiComponent(
                      'ui.sectionHeader@1',
                      {
                        'title': '今日课程',
                        'count': '50+',
                        'actionLabel': '添加任务',
                        'actionIcon': 'add',
                      },
                      {},
                      {'press': (_) => added++},
                    ),
                    defaultUiComponent(
                      'ui.agendaItem@1',
                      {
                        'title': '高等数学与非常长的课程标题',
                        'subtitle': '教学楼 A302 · 张老师',
                        'startTime': '08:00',
                        'endTime': '09:35',
                        'color': '#447BC4',
                        'badge': '即将开始',
                      },
                      {},
                      {'press': (_) => courses++},
                    ),
                    const SizedBox(height: 16),
                    defaultUiComponent(
                      'ui.taskItem@1',
                      {
                        'title': '完成英语阅读练习与课堂笔记',
                        'subtitle': '今天 18:00 · 学习',
                        'completed': false,
                      },
                      {'details': const Text('扩展字段仍可展示')},
                      {
                        'change': (value) => completed = value as bool,
                        'open': (_) => opened++,
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.text('10月1日 周四'), findsOneWidget);
        expect(find.byType(DayOverview), findsOneWidget);
        expect(find.byType(AgendaItem), findsOneWidget);
        expect(find.text('扩展字段仍可展示'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('添加任务'));
        await tester.tap(find.byTooltip('添加任务'));
        expect(added, 1);
        await tester.ensureVisible(find.text('高等数学与非常长的课程标题'));
        await tester.tap(find.text('高等数学与非常长的课程标题'));
        expect(courses, 1);
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        expect(completed, true);
        expect(opened, 0);
        await tester.tap(find.text('完成英语阅读练习与课堂笔记'));
        expect(opened, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
