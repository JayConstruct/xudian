import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/daily_widgets.dart';
import 'package:task_app/core/ui/daily_date_strip.dart';
import 'package:task_app/core/ui/temporal_input.dart';

void main() {
  for (final rtl in [false, true]) {
    testWidgets('continuous cells translate and reverse in place, RTL=$rtl', (
      tester,
    ) async {
      final selected = ValueNotifier(DateTime(2026, 10, 10));
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              body: SizedBox(
                width: 500,
                child: ValueListenableBuilder(
                  valueListenable: selected,
                  builder: (_, date, _) => DayOverview(
                    date: formatInputDate(date),
                    dateHeading: false,
                    dateControls: false,
                    onChanged: (raw) => selected.value = DateTime.parse(raw),
                    days: [
                      for (var offset = -2; offset <= 2; offset++)
                        {
                          'date': formatInputDate(
                            DateTime(date.year, date.month, date.day + offset),
                          ),
                          'label': '日期',
                          'pending': 2,
                        },
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final cell = find.byKey(const ValueKey('daily-date:2026-10-10'));
      final element = tester.element(cell);
      expect(tester.getCenter(cell).dx, 250);
      selected.value = DateTime(2026, 10, 11);
      await tester.pump();
      expect(tester.getCenter(cell).dx, 250);
      await tester.pump(const Duration(milliseconds: 60));
      final halfway = tester.getCenter(cell).dx;
      expect(halfway, rtl ? greaterThan(250) : lessThan(250));
      selected.value = DateTime(2026, 10, 10);
      await tester.pump();
      expect(tester.getCenter(cell).dx, closeTo(halfway, .01));
      await tester.pumpAndSettle();
      expect(tester.getCenter(cell).dx, 250);
      expect(tester.element(cell), same(element));
      expect(tester.takeException(), isNull);
    });
  }

  for (final rtl in [false, true]) {
    testWidgets('a horizontal release selects one declared date, RTL=$rtl', (
      tester,
    ) async {
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              body: SizedBox(
                width: 500,
                child: DayOverview(
                  date: '2026-10-10',
                  dateHeading: false,
                  dateControls: false,
                  onChanged: events.add,
                  days: [
                    for (var day = 8; day <= 12; day++)
                      {
                        'date': '2026-10-$day'
                            .replaceFirst('-8', '-08')
                            .replaceFirst('-9', '-09'),
                        'label': '日期',
                      },
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getCenter(find.byType(DailyDateStrip));
      final gesture = await tester.startGesture(origin);
      await gesture.moveBy(Offset(rtl ? 115 : -115, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(events, ['2026-10-11']);
      events.clear();
      await tester.tap(find.byKey(const ValueKey('daily-date:2026-10-08')));
      expect(events, ['2026-10-08']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion updates immediately and still accepts swipes', (
    tester,
  ) async {
    final selected = ValueNotifier('2026-10-10');
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 500,
              child: ValueListenableBuilder(
                valueListenable: selected,
                builder: (_, date, _) => DayOverview(
                  date: date,
                  dateHeading: false,
                  dateControls: false,
                  onChanged: (value) => selected.value = value,
                  days: [
                    for (final day in [8, 9, 10, 11, 12])
                      {
                        'date': '2026-10-${day.toString().padLeft(2, '0')}',
                        'label': '日期',
                      },
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    selected.value = '2026-10-11';
    await tester.pump();
    expect(
      tester.getCenter(find.byKey(const ValueKey('daily-date:2026-10-11'))).dx,
      250,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DailyDateStrip)),
    );
    await gesture.moveBy(const Offset(110, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
    expect(selected.value, '2026-10-10');
  });

  testWidgets(
    'civil bounds, count refresh and vertical scrolling stay independent',
    (tester) async {
      final counts = ValueNotifier(1);
      addTearDown(counts.dispose);
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    width: 500,
                    child: ValueListenableBuilder(
                      valueListenable: counts,
                      builder: (_, count, _) => DayOverview(
                        date: '0001-01-01',
                        dateHeading: false,
                        dateControls: false,
                        onChanged: events.add,
                        days: [
                          for (final day in ['01', '02', '03', '04', '05'])
                            {
                              'date': '0001-01-$day',
                              'label': '日期',
                              'pending': count,
                            },
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 1500),
                ],
              ),
            ),
          ),
        ),
      );
      final semantics = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '日期选择，左右滑动切换日期',
        ),
      );
      expect(semantics.properties.onDecrease, isNull);
      semantics.properties.onIncrease!();
      expect(events, ['0001-01-02']);
      events.clear();
      final strip = find.byType(DailyDateStrip);
      final gesture = await tester.startGesture(tester.getCenter(strip));
      await gesture.moveBy(const Offset(125, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        events,
        isEmpty,
        reason: 'Year 1 does not navigate into year zero',
      );
      final cell = find.byKey(const ValueKey('daily-date:0001-01-01'));
      final position = tester.getCenter(cell).dx;
      counts.value = 2;
      await tester.pump();
      expect(tester.getCenter(cell).dx, position);
      await tester.drag(strip, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        greaterThan(0),
      );
      expect(events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'enabling reduced motion finishes the current translation immediately',
    (tester) async {
      final options = ValueNotifier((date: '2026-10-10', reduced: false));
      addTearDown(options.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: options,
            builder: (_, option, _) => MediaQuery(
              data: MediaQueryData(disableAnimations: option.reduced),
              child: Scaffold(
                body: SizedBox(
                  width: 500,
                  child: DayOverview(
                    date: option.date,
                    dateHeading: false,
                    dateControls: false,
                    days: [
                      for (final day in [8, 9, 10, 11, 12])
                        {
                          'date': '2026-10-${day.toString().padLeft(2, '0')}',
                          'label': '日期',
                        },
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final cell = find.byKey(const ValueKey('daily-date:2026-10-11'));
      final original = tester.element(cell);
      options.value = (date: '2026-10-11', reduced: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getCenter(cell).dx, greaterThan(250));
      options.value = (date: '2026-10-11', reduced: true);
      await tester.pump();
      expect(tester.getCenter(cell).dx, 250);
      expect(tester.element(cell), same(original));
      expect(tester.takeException(), isNull);
    },
  );

  test('sparse, invalid and duplicate declarations never enable invented navigation', () {
    expect(
      DailyDateStrip.supports([
        {'date': '2026-10-01'},
        {'date': '2026-10-03'},
      ], '2026-10-01'),
      isFalse,
    );
    expect(
      DailyDateStrip.supports([
        {'date': '0000-12-31'},
        {'date': '0001-01-01'},
      ], '0001-01-01'),
      isFalse,
    );
    expect(
      DailyDateStrip.supports([
        {'date': '9999-12-30'},
        {'date': '9999-12-31'},
      ], '9999-12-31'),
      isTrue,
    );
    expect(
      DailyDateStrip.supports([
        {'date': '2026-10-01'},
        {'date': '2026-10-01'},
      ], '2026-10-01'),
      isFalse,
    );
  });
}
