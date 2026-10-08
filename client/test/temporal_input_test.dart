import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/temporal_input.dart';
import 'package:task_app/core/ui/input_validation.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';

void main() {
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
      MaterialApp(
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
      MaterialApp(
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
    expect(find.byType(TimePickerDialog), findsOneWidget);
    labels = MaterialLocalizations.of(
      tester.element(find.byType(TimePickerDialog)),
    );
    await tester.tap(find.text(labels.cancelButtonLabel));
    await tester.pumpAndSettle();
    expect(controller.text, '2026-10-08T09:30');
    expect(changes, isEmpty);
  });

  testWidgets('cross-month range confirms an object and ignores stale result', (
    tester,
  ) async {
    Object? value = {'start': '2026-09-30', 'end': '2026-10-02'};
    final changes = <Object?>[];
    var current = true;
    await tester.pumpWidget(
      MaterialApp(
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
    await tester.tap(find.byTooltip('选择日期范围'));
    await tester.pumpAndSettle();
    final labels = MaterialLocalizations.of(
      tester.element(find.byType(DateRangePickerDialog)),
    );
    await tester.tap(find.text(labels.saveButtonLabel));
    await tester.pumpAndSettle();
    expect(changes.single, {'start': '2026-09-30', 'end': '2026-10-02'});
    await tester.tap(find.byTooltip('选择日期范围'));
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.text(labels.saveButtonLabel));
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
  });

  testWidgets(
    'host typed form shares pickers and preserves legacy return types',
    (tester) async {
      Object? result;
      await tester.pumpWidget(
        MaterialApp(
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
            MaterialApp(
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
          await tester.tap(find.byTooltip('选择选择演示'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (kind == TemporalInputKind.dateRange) {
            final labels = MaterialLocalizations.of(
              tester.element(find.byType(DateRangePickerDialog)),
            );
            await tester.tap(find.byTooltip(labels.inputDateModeButtonLabel));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.byTooltip(labels.calendarModeButtonLabel));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(
              find.byTooltip(
                MaterialLocalizations.of(
                  tester.element(find.byType(DateRangePickerDialog)),
                ).closeButtonTooltip,
              ),
            );
          } else {
            final dialog = kind == TemporalInputKind.time
                ? find.byType(TimePickerDialog)
                : find.byType(DatePickerDialog);
            await tester.tap(
              find.text(
                MaterialLocalizations.of(tester.element(dialog))
                    .cancelButtonLabel,
              ),
            );
          }
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
