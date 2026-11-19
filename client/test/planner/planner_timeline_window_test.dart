import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/planner_timeline_window.dart';

List<TimelineItem> dates(DateTime start, [int count = 21]) => List.generate(
  count,
  (index) => {
    'date': PlannerTimelineWindow.stamp(start.add(Duration(days: index))),
  },
);

void main() {
  test('cached dates need no query until approaching a data edge', () {
    final today = DateTime.utc(2026, 10, 20);
    final cache = PlannerTimelineWindow(today)
      ..seed(dates(today.subtract(const Duration(days: 7))), const [], today);
    expect(cache.requestStart(today, 3), isNull);
    expect(cache.requestStart(today.add(const Duration(days: 2)), 3), isNull);
    expect(
      cache.requestStart(today.add(const Duration(days: 8)), 3),
      isNotNull,
    );
    expect(cache.isLoaded(today), isTrue);
    expect(cache.isLoaded(today.add(const Duration(days: 30))), isFalse);
    expect(cache.days, hasLength(63));
  });

  test('ranges merge cross-midnight blocks once and replace loaded days', () {
    final today = DateTime.utc(2026, 10, 20);
    final cache = PlannerTimelineWindow(today);
    const block = <String, Object?>{
      'id': 'overnight',
      'start': '2026-10-20T23:00:00',
      'end': '2026-10-21T01:00:00',
    };
    cache.seed(dates(today), [block], today);
    expect(cache.blocks, [block]);
    cache.seed(dates(today), const [], today);
    expect(cache.blocks, isEmpty);
    expect(cache.isLoaded(today), isTrue);
  });

  test(
    'rendered columns and cached days stay bounded during long browsing',
    () {
      final today = DateTime.utc(2026, 10, 20);
      final cache = PlannerTimelineWindow(today);
      for (var index = 0; index < 120; index++) {
        final visible = today.add(Duration(days: index * 14));
        cache.recenter(visible, 3);
        cache.seed(
          dates(visible.subtract(const Duration(days: 7))),
          const [],
          visible,
        );
        expect(cache.loadedDayCount, lessThanOrEqualTo(84));
        expect(cache.days, hasLength(63));
        expect(cache.isLoaded(visible), isTrue);
      }
      expect(cache.isLoaded(today), isFalse);
      expect(cache.requestStart(today, 3), isNotNull);
    },
  );

  test('recycling is unnecessary inside the central window', () {
    final today = DateTime.utc(2026, 10, 20);
    final cache = PlannerTimelineWindow(today);
    final previous = cache.days;
    expect(cache.recenter(today.add(const Duration(days: 7)), 3), isFalse);
    expect(identical(cache.days, previous), isTrue);
    expect(cache.recenter(today.add(const Duration(days: 30)), 3), isTrue);
    expect(
      cache.origin.add(const Duration(days: 30)),
      today.add(const Duration(days: 30)),
    );
  });

  test(
    'date windows cross leap days and stay inside supported year bounds',
    () {
      final leap = DateTime.utc(2028, 2, 29);
      final cache = PlannerTimelineWindow(leap);
      expect(cache.days.any((entry) => entry['date'] == '2028-02-29'), isTrue);
      final first = PlannerTimelineWindow(DateTime.utc(1));
      final last = PlannerTimelineWindow(DateTime.utc(9999, 12, 31));
      expect(first.days.first['date'], '0001-01-01');
      expect(last.days.last['date'], '9999-12-31');
    },
  );
}
