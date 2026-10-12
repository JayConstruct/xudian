import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/workspace_date_title.dart';

void main() {
  testWidgets(
    'rapid date changes keep latest label semantics and accept every control event',
    (tester) async {
      final date = ValueNotifier('2026-10-10');
      addTearDown(date.dispose);
      final events = <String>[];
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: date,
                builder: (_, value, _) => WorkspaceDateTitle(
                  title: value,
                  date: value,
                  style: const TextStyle(fontSize: 24),
                  onEvent: events.add,
                ),
              ),
            ),
          ),
        );
        for (final value in [
          '2026-10-11',
          '2026-10-12',
          '2026-10-09',
          '2026-10-10',
        ]) {
          date.value = value;
          await tester.pump(const Duration(milliseconds: 30));
          await tester.tap(find.byTooltip('后一天'));
          expect(find.bySemanticsLabel(value), findsOneWidget);
          expect(find.byType(Text).evaluate().length, lessThanOrEqualTo(2));
        }
        expect(events, List.filled(4, 'date.next'));
        await tester.pumpAndSettle();
        expect(find.text('2026-10-10'), findsOneWidget);
        expect(find.text('2026-10-09'), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('reduced motion changes date without a departing visible label', (
    tester,
  ) async {
    final date = ValueNotifier('2026-10-10');
    addTearDown(date.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ValueListenableBuilder(
              valueListenable: date,
              builder: (_, value, _) => WorkspaceDateTitle(
                title: value,
                date: value,
                style: const TextStyle(fontSize: 24),
                onEvent: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    date.value = '2026-10-11';
    await tester.pumpAndSettle();
    expect(find.text('2026-10-10'), findsNothing);
    expect(find.text('2026-10-11'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'date header has accessible controls and animated changes at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final events = <String>[];
        final date = ValueNotifier('2026-10-10');
        addTearDown(date.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ValueListenableBuilder(
                    valueListenable: date,
                    builder: (_, value, _) => WorkspaceDateTitle(
                      title: value == '2026-10-10' ? '10月10日 周六' : '10月11日 周日',
                      date: value,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      onEvent: events.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('后一天'));
        await tester.tap(find.byKey(const ValueKey('workspace-date-picker')));
        expect(events, ['date.next', 'date.choose']);
        expect(
          tester.getSize(find.byTooltip('后一天')).height,
          greaterThanOrEqualTo(48),
        );
        date.value = '2026-10-11';
        await tester.pump();
        expect(find.text('10月10日 周六'), findsOneWidget);
        expect(find.text('10月11日 周日'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('10月10日 周六'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
