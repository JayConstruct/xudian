import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/ui/temporal_input.dart';
import 'package:task_app/core/ui/input_validation.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';

Widget temporalTestApp({required Widget home, ThemeData? theme}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  theme: theme,
  home: home,
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('date selection uses the shared $brightness surface', (
      tester,
    ) async {
      final theme = AppDesign.theme(brightness);
      final changes = <Object?>[];
      await tester.pumpWidget(
        temporalTestApp(
          theme: theme,
          home: Scaffold(
            body: TemporalInput(
              kind: TemporalInputKind.date,
              label: '日期',
              value: '2026-10-08',
              minDate: '2026-10-01',
              maxDate: '2026-10-31',
              onChanged: changes.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('选择日期'));
      await tester.pumpAndSettle();
      final picker = tester.element(find.byType(DatePickerDialog));
      final style = DatePickerTheme.of(picker);
      expect(style.backgroundColor, theme.colorScheme.surface);
      expect(style.shape, isA<RoundedSuperellipseBorder>());
      expect(
        style.dayBackgroundColor!.resolve({WidgetState.selected}),
        theme.colorScheme.primaryContainer,
      );
      expect(
        style.dayForegroundColor!.resolve({WidgetState.selected}),
        theme.colorScheme.onPrimaryContainer,
      );
      expect(
        style.dayForegroundColor!.resolve({WidgetState.disabled}),
        isNot(style.dayForegroundColor!.resolve({})),
      );
      expect(find.text('选择日期'), findsWidgets);
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(changes, ['2026-10-15']);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'civil dates, time, ranges and numeric limits reject invalid values',
    () {
      expect(parseInputDate('2026-02-30'), isNull);
      expect(parseInputDate('2028-02-29'), DateTime(2028, 2, 29));
      expect(
        validateTemporalInput(
          TemporalInputKind.date,
          '2026-10-08',
          maxDate: '2026-10-07',
        ),
        isNotNull,
      );
      expect(validateTemporalInput(TemporalInputKind.time, '24:00'), isNotNull);
      expect(validateTemporalInput(TemporalInputKind.time, '23:59'), isNull);
      expect(
        validateTemporalInput(TemporalInputKind.dateTime, '2026-10-08T09:30'),
        isNull,
      );
      expect(
        validateTemporalInput(TemporalInputKind.dateTime, '2026-02-30T09:30'),
        isNotNull,
      );
      expect(
        validateTemporalInput(TemporalInputKind.dateRange, {
          'start': '2026-10-10',
          'end': '2026-10-08',
        }),
        isNotNull,
      );
      expect(
        validateTemporalInput(TemporalInputKind.dateRange, {
          'start': '2026-12-31',
          'end': '2027-01-02',
        }),
        isNull,
      );
      expect(validateNumberInput('NaN'), isNotNull);
      expect(validateNumberInput('1.5', integer: true), isNotNull);
      expect(validateNumberInput('101', max: 100), isNotNull);
      expect(validateNumberInput('40.5', min: 0, max: 100), isNull);
    },
  );

  testWidgets('date manual editing, selection, cancellation and clear agree', (
    tester,
  ) async {
    final controller = TextEditingController(text: '2026-10-08');
    addTearDown(controller.dispose);
    Object? value = '2026-10-08';
    final changes = <Object?>[];
    await tester.pumpWidget(
      temporalTestApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TemporalInput(
              kind: TemporalInputKind.date,
              label: '计划日',
              controller: controller,
              value: value,
              minDate: '2026-01-01',
              maxDate: '2026-12-31',
              onChanged: (next) => setState(() {
                value = next;
                changes.add(next);
              }),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '2026-02-30');
    await tester.pump();
    expect(find.text('请输入有效 YYYY-MM-DD 日期'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2026-10-08');
    await tester.tap(find.byTooltip('选择计划日'));
    await tester.pumpAndSettle();
    var labels = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    );
    await tester.tap(find.text(labels.cancelButtonLabel));
    await tester.pumpAndSettle();
    expect(controller.text, '2026-10-08');
    final count = changes.length;
    await tester.tap(find.byTooltip('选择计划日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    labels = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    );
    await tester.tap(find.text(labels.okButtonLabel));
    await tester.pumpAndSettle();
    expect(value, '2026-10-15');
    expect(changes.length, count + 1);
    await tester.tap(find.byTooltip('清除计划日'));
    await tester.pumpAndSettle();
    expect(value, isNull);
    expect(controller.text, isEmpty);
  });

  testWidgets('date-time selection is atomic when time step is cancelled', (
    tester,
  ) async {
    final controller = TextEditingController(text: '2026-10-08T09:30');
    addTearDown(controller.dispose);
    final changes = <Object?>[];
    await tester.pumpWidget(
      temporalTestApp(
        home: Scaffold(
          body: TemporalInput(
            kind: TemporalInputKind.dateTime,
            label: '日期时间',
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('选择日期时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    var labels = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    );
    await tester.tap(find.text(labels.okButtonLabel));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.text, '2026-10-08T09:30');
    expect(changes, isEmpty);
  });

  testWidgets(
    '24-hour wheels reopen the current value and only confirm commits',
    (tester) async {
      final controller = TextEditingController(text: '23:59');
      addTearDown(controller.dispose);
      final changes = <Object?>[];
      await tester.pumpWidget(
        temporalTestApp(
          home: Scaffold(
            body: TemporalInput(
              kind: TemporalInputKind.time,
              label: '时间',
              controller: controller,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.byTooltip('选择时间'));
        await tester.pumpAndSettle();
      }

      await open();
      final wheels = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      expect(wheels[0].scrollController!.selectedItem, 23);
      expect(wheels[1].scrollController!.selectedItem, 59);
      await tester.drag(
        find.byKey(const ValueKey('time-wheel-小时')),
        const Offset(0, 48),
      );
      await tester.pumpAndSettle();
      expect(wheels[0].scrollController!.selectedItem, lessThan(23));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.text, '23:59');
      expect(changes, isEmpty);
      await open();
      final current = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      expect(current[0].scrollController!.selectedItem, 23);
      current[0].scrollController!.jumpToItem(0);
      current[1].scrollController!.jumpToItem(5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(controller.text, '00:05');
      expect(changes.single, '00:05');
      await open();
      final reopened = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      expect(reopened[0].scrollController!.selectedItem, 0);
      expect(reopened[1].scrollController!.selectedItem, 5);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'range uses two dates, preserves cancelled and stale values, and clears',
    (tester) async {
      Object? value = {'start': '2026-09-30', 'end': '2026-10-02'};
      final changes = <Object?>[];
      var current = true;
      await tester.pumpWidget(
        temporalTestApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => TemporalInput(
                kind: TemporalInputKind.dateRange,
                label: '日期范围',
                value: value,
                isCurrent: () => current,
                onChanged: (next) => setState(() {
                  value = next;
                  changes.add(next);
                }),
              ),
            ),
          ),
        ),
      );
      expect(find.text('开始日期'), findsOneWidget);
      expect(find.text('结束日期'), findsOneWidget);
      await tester.tap(find.byTooltip('选择结束日期'));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsNothing);
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.firstDate, DateTime(2026, 9, 30));
      expect(picker.initialDate, DateTime(2026, 10, 2));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      await tester.tap(find.byTooltip('选择结束日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(changes.single, {'start': '2026-09-30', 'end': '2026-10-15'});
      await tester.tap(find.byTooltip('选择开始日期'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate,
        DateTime(2026, 10, 15),
      );
      current = false;
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(changes, hasLength(1));
      current = true;
      await tester.tap(find.byTooltip('清除开始日期'));
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(find.text('2026-10-15'), findsNothing);
      await tester.tap(find.byTooltip('选择开始日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(value, {'start': '2026-10-15', 'end': '2026-10-15'});
    },
  );

  testWidgets(
    'host typed form shares pickers and preserves legacy return types',
    (tester) async {
      Object? result;
      await tester.pumpWidget(
        temporalTestApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog(
                  context: context,
                  builder: (_) => const HostFormDialog(
                    title: '表单',
                    fields: [
                      {
                        'key': 'date',
                        'label': '计划日',
                        'type': 'date',
                        'value': '2026-10-08',
                      },
                      {
                        'key': 'time',
                        'label': '时间',
                        'type': 'time',
                        'value': '09:30',
                      },
                      {
                        'key': 'range',
                        'label': '区间',
                        'type': 'dateRange',
                        'value': {'start': '2026-09-30', 'end': '2026-10-02'},
                      },
                      {
                        'key': 'tags',
                        'label': '标签',
                        'type': 'multiSelect',
                        'value': ['学习'],
                        'required': true,
                        'options': [
                          {'value': '学习', 'label': '学习'},
                          {'value': '工作', 'label': '工作'},
                        ],
                      },
                    ],
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('清除计划日'));
      await tester.ensureVisible(find.widgetWithText(FilterChip, '工作'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '工作'));
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(result, {
        'date': '',
        'time': '09:30',
        'range': {'start': '2026-09-30', 'end': '2026-10-02'},
        'tags': ['学习', '工作'],
      });
    },
  );
  for (final config in [
    (size: const Size(320, 640), scale: 2.0),
    (size: const Size(390, 844), scale: 1.5),
    (size: const Size(1280, 900), scale: 1.5),
  ]) {
    testWidgets(
      'native pickers fit ${config.size.width}px at ${config.scale}x',
      (tester) async {
        tester.view.physicalSize = config.size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final kind in [
          TemporalInputKind.date,
          TemporalInputKind.time,
          TemporalInputKind.dateRange,
        ]) {
          final controller = kind == TemporalInputKind.dateRange
              ? null
              : TextEditingController(
                  text: kind == TemporalInputKind.time ? '09:30' : '2026-10-08',
                );
          await tester.pumpWidget(
            temporalTestApp(
              theme: ThemeData(brightness: Brightness.dark),
              home: Scaffold(
                body: TemporalInput(
                  kind: kind,
                  label: '选择演示',
                  controller: controller,
                  value: kind == TemporalInputKind.dateRange
                      ? {'start': '2026-12-31', 'end': '2027-01-02'}
                      : null,
                  onChanged: (_) {},
                ),
              ),
            ),
          );
          await tester.tap(
            find.byTooltip(
              kind == TemporalInputKind.dateRange ? '选择开始日期' : '选择选择演示',
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (kind == TemporalInputKind.time) {
            expect(find.byType(CupertinoPicker), findsNWidgets(2));
          } else {
            expect(find.byType(DatePickerDialog), findsOneWidget);
            expect(find.text('取消'), findsOneWidget);
          }
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          controller?.dispose();
        }
      },
    );
  }
}
