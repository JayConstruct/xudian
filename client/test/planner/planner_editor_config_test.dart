import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_day_sheet.dart';

void main() {
  testWidgets('module labels and duration bound drive the native editor', (
    tester,
  ) async {
    final events = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlannerDaySheet(
            date: DateTime.utc(2026, 11, 16),
            candidates: const [],
            blocks: const [
              {
                'id': 'session',
                'title': 'Workshop',
                'start': '2026-11-16T09:00:00',
                'end': '2026-11-16T09:30:00',
                'moveEvent': {'type': 'move'},
              },
            ],
            options: const {
              'editor': {
                'maxDurationMinutes': 60,
                'labels': {
                  'dayTitle': 'Sessions',
                  'durationTitle': 'Session length',
                  'confirm': 'Accept',
                  'durationError': 'Maximum {max}',
                  'apply': 'Save session',
                },
              },
            },
            enabled: true,
            canMove: (_) => true,
            onEvent: events.add,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sessions'), findsOneWidget);
    await tester.tap(find.text('Workshop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-day-duration')));
    await tester.pumpAndSettle();
    expect(find.text('Session length'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '61');
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum 60'), findsOneWidget);
    expect(events, isEmpty);
    await tester.enterText(find.byType(TextField), '45');
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Save session'), findsOneWidget);
    expect(events, isEmpty);
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();
    expect(events, hasLength(1));
    expect((events.single as Map)['end'], '2026-11-16T09:45:00.000');
  });
}
