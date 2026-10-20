import 'dart:convert';

typedef TimelineItem = Map<String, Object?>;

class PlannerTimelineWindow {
  PlannerTimelineWindow(DateTime visibleDate) {
    _setOrigin(visibleDate);
  }

  static const renderedDays = 63;
  static const cachedDays = 84;
  static const requestDays = 21;
  static final firstDate = DateTime.utc(1);
  static final lastDate = DateTime.utc(9999, 12, 31);
  final _loaded = <DateTime, List<TimelineItem>>{};
  late DateTime origin;
  late List<TimelineItem> days;
  List<TimelineItem> blocks = const [];

  int get loadedDayCount => _loaded.length;

  static DateTime dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static DateTime bounded(DateTime value, int length) {
    final last = lastDate.subtract(Duration(days: length - 1));
    if (value.isBefore(firstDate)) return firstDate;
    if (value.isAfter(last)) return last;
    return dateOnly(value);
  }

  static String stamp(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  void _setOrigin(DateTime date) {
    origin = bounded(date.subtract(const Duration(days: 30)), renderedDays);
    days = List.unmodifiable(
      List.generate(renderedDays, (index) {
        final day = origin.add(Duration(days: index));
        return <String, Object?>{'date': stamp(day)};
      }),
    );
  }

  bool recenter(DateTime visibleDate, int visibleDays) {
    final offset = dateOnly(visibleDate).difference(origin).inDays;
    if (offset >= 14 && offset <= renderedDays - visibleDays - 14) {
      return false;
    }
    final previous = origin;
    _setOrigin(visibleDate);
    if (origin == previous) return false;
    _refreshBlocks();
    return true;
  }

  bool isLoaded(DateTime date) => _loaded.containsKey(dateOnly(date));

  DateTime? requestStart(DateTime visibleDate, int visibleDays) {
    final start = bounded(
      visibleDate.subtract(const Duration(days: 4)),
      visibleDays + 8,
    );
    for (var index = 0; index < visibleDays + 8; index++) {
      if (!isLoaded(start.add(Duration(days: index)))) {
        return bounded(
          visibleDate.subtract(const Duration(days: 7)),
          requestDays,
        );
      }
    }
    return null;
  }

  void seed(
    List<TimelineItem> loadedDays,
    List<TimelineItem> loadedBlocks,
    DateTime visibleDate,
  ) {
    for (final entry in loadedDays) {
      final date = DateTime.tryParse('${entry['date']}');
      if (date == null) continue;
      final day = dateOnly(date);
      final end = day.add(const Duration(days: 1));
      _loaded.remove(day);
      _loaded[day] = List.unmodifiable(
        loadedBlocks.where((block) {
          final from = DateTime.tryParse('${block['start']}');
          final to = DateTime.tryParse('${block['end']}');
          if (from == null || to == null) return false;
          final floatingFrom = DateTime.utc(
            from.year,
            from.month,
            from.day,
            from.hour,
            from.minute,
          );
          final floatingTo = DateTime.utc(
            to.year,
            to.month,
            to.day,
            to.hour,
            to.minute,
          );
          return floatingFrom.isBefore(end) && floatingTo.isAfter(day);
        }),
      );
    }
    if (_loaded.length > cachedDays) {
      final farthest = _loaded.keys.toList()
        ..sort(
          (first, second) => second
              .difference(visibleDate)
              .abs()
              .compareTo(first.difference(visibleDate).abs()),
        );
      for (final day in farthest.take(_loaded.length - cachedDays)) {
        _loaded.remove(day);
      }
    }
    _refreshBlocks();
  }

  void _refreshBlocks() {
    final end = origin.add(const Duration(days: renderedDays));
    final unique = <String, TimelineItem>{};
    for (final entry in _loaded.entries) {
      if (entry.key.isBefore(origin) || !entry.key.isBefore(end)) continue;
      for (final block in entry.value) {
        unique[jsonEncode([block['id'], block['start'], block['end']])] = block;
      }
    }
    blocks = List.unmodifiable(unique.values);
  }
}
