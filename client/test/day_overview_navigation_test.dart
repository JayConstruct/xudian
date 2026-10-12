import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/daily_widgets.dart';
import 'package:task_app/core/ui/temporal_input.dart';
import 'package:task_app/core/ui/ui_component.dart';

void main() {
  for (final scenario in [(320.0, 2.0), (900.0, 1.5)]) {
    testWidgets(
      'date strip, day navigation, Chinese picker and today entry at ${scenario.$1}/${scenario.$2}',
      (tester) async {
        tester.view.physicalSize = Size(scenario.$1, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final selected = ValueNotifier('2026-10-01');
        addTearDown(selected.dispose);
        final changes = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scenario.$2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ValueListenableBuilder(
                  valueListenable: selected,
                  builder: (_, date, _) => defaultUiComponent(
                    'ui.dayOverview@1',
                    {
                      'date': date,
                      'selectedDate': date,
                      'todayDate': '2026-10-01',
                      'summary': '真实日期',
                      'days': [
                        for (var i = 1; i <= 7; i++)
                          {'date': '2026-10-0$i', 'label': '周$i'},
                      ],
                    },
                    {},
                    {
                      'change': (value) {
                        changes.add(value as String);
                        selected.value = value;
                      },
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('后一天'));
        await tester.pumpAndSettle();
        expect(selected.value, '2026-10-02');
        await tester.tap(find.byTooltip('前一天'));
        await tester.pumpAndSettle();
        expect(selected.value, '2026-10-01');
        final third = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '2026-10-03',
        );
        await tester.tap(third);
        await tester.pumpAndSettle();
        expect(selected.value, '2026-10-03');
        final button = find.widgetWithText(TextButton, '2026年10月3日 周六');
        expect(
          tester.getSize(find.byTooltip('前一天')).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        final picker = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(picker.initialDate, DateTime(2026, 10, 3));
        expect(
          Localizations.localeOf(tester.element(find.byType(DatePickerDialog)))
              .languageCode,
          'zh',
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(selected.value, '2026-10-03');
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text('15').last);
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
        expect(selected.value, '2026-10-15');
        await tester.tap(find.text('回到今天'));
        await tester.pumpAndSettle();
        expect(selected.value, '2026-10-01');
        expect(changes, [
          '2026-10-02',
          '2026-10-01',
          '2026-10-03',
          '2026-10-15',
          '2026-10-01',
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'a date header can hide the repeated heading without losing date controls',
    (tester) async {
      final changes = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: defaultUiComponent(
              'ui.dayOverview@1',
              {
                'date': '2026-10-03',
                'selectedDate': '2026-10-03',
                'todayDate': '2026-10-01',
                'dateHeading': false,
              },
              {},
              {'change': changes.add},
            ),
          ),
        ),
      );
      expect(find.text('2026年10月3日 周六'), findsNothing);
      expect(find.text('10月3日 周六'), findsNothing);
      expect(find.text('选择日期'), findsOneWidget);
      await tester.tap(find.text('选择日期'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .initialDate,
        DateTime(2026, 10, 3),
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      await tester.tap(find.byTooltip('后一天'));
      await tester.tap(find.text('回到今天'));
      expect(changes, ['2026-10-04', '2026-10-01']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'workspace date controls stay in its header while the strip shows useful counts',
    (tester) async {
      final changes = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: defaultUiComponent(
              'ui.dayOverview@1',
              {
                'date': '2026-10-03',
                'selectedDate': '2026-10-03',
                'todayDate': '2026-10-01',
                'dateHeading': false,
                'dateControls': false,
                'days': [
                  {
                    'date': '2026-10-01',
                    'label': '周四',
                    'pending': 2,
                    'completed': 1,
                  },
                  {
                    'date': '2026-10-03',
                    'label': '周六',
                    'pending': 3,
                    'completed': 0,
                  },
                ],
              },
              {},
              {'change': changes.add},
            ),
          ),
        ),
      );
      expect(find.text('选择日期'), findsNothing);
      expect(find.byTooltip('前一天'), findsNothing);
      expect(find.byTooltip('后一天'), findsNothing);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('2 待办'), findsOneWidget);
      expect(find.text('1 已完成'), findsOneWidget);
      final selected = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '2026-10-03',
      );
      expect(tester.widget<Semantics>(selected).properties.selected, true);
      await tester.tap(selected);
      await tester.tap(find.text('回到今天'));
      expect(changes, ['2026-10-03', '2026-10-01']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'year boundaries disable navigation; invalid dates remain passive',
    (tester) async {
      Future<void> show(String date) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayOverview(
              date: date,
              todayDate: '0000-01-01',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await show('0001-01-01');
      expect(
        tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
        isNull,
      );
      await show('9999-12-31');
      expect(
        tester.widget<IconButton>(find.byType(IconButton).last).onPressed,
        isNull,
      );
      await show('0000-01-01');
      expect(find.byType(IconButton), findsNothing);
      expect(find.text('回到今天'), findsNothing);
      expect(find.text('0000-01-01'), findsOneWidget);
      expect(
        parseInputDate('0000-01-01'),
        isNotNull,
      ); // legacy parser compatibility
      expect(tester.takeException(), isNull);
    },
  );
}
