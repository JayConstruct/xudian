import 'dart:math' as math;

import 'planner_board_types.dart';

class BoardSegment {
  BoardSegment(
    this.item,
    this.start,
    this.end,
    this.dayIndex,
    this.day,
    this.from,
    this.to,
    this.top,
    this.bottom,
  );
  final BoardItem item;
  final DateTime start, end, from, to;
  final int dayIndex;
  final String day;
  final double top, bottom;
  int lane = 0;
  String get key => '${item['id']}:$day';
}

class BoardGroup {
  BoardGroup(this.segments, this.top, this.bottom, this.lanes);
  final List<BoardSegment> segments;
  final double top, bottom;
  final int lanes;
}

class BoardGeometry {
  BoardGeometry(this.days, this.byKey, this.byId);
  final List<List<BoardGroup>> days;
  final Map<String, BoardGroup> byKey;
  final Map<Object?, BoardItem> byId;
}

/// Pure geometry and its revision cache, independent of widgets and gestures.
class PlannerBoardLayout {
  List<BoardItem>? _source;
  Object? _settings;
  BoardGeometry? _cached;
  void clear() {
    _source = null;
    _settings = null;
    _cached = null;
  }

  BoardGeometry index(
    List<BoardItem> items, {
    required List<BoardItem> days,
    required int startMinute,
    required int endMinute,
    required double scale,
    required double cardHeight,
    required double titleBandHeight,
    required DateTime? Function(Object?) parse,
    required bool cacheable,
  }) {
    final settings = (
      days,
      startMinute,
      endMinute,
      scale,
      cardHeight,
      titleBandHeight,
    );
    if (cacheable &&
        identical(items, _source) &&
        settings == _settings &&
        _cached != null) {
      return _cached!;
    }
    final segments = List.generate(days.length, (_) => <BoardSegment>[]);
    final starts = [
      for (final day in days)
        DateTime.utc(
          parse(day['date'])!.year,
          parse(day['date'])!.month,
          parse(day['date'])!.day,
        ),
    ];
    final bounds = [
      for (final day in starts)
        (
          day.add(Duration(minutes: startMinute)),
          day.add(Duration(minutes: endMinute)),
        ),
    ];
    // Parse each item once per data/geometry revision, never per scroll frame.
    for (final item in items) {
      final start = parse(item['start']), end = parse(item['end']);
      if (start == null || end == null || !end.isAfter(start)) continue;
      for (var day = 0; day < days.length; day++) {
        final (from, to) = bounds[day];
        if (!start.isBefore(to) || !end.isAfter(from)) continue;
        final top = math.max(
          0.0,
          start.difference(from).inMilliseconds / 60000 * scale,
        );
        final bottom = math.min(
          (endMinute - startMinute) * scale,
          end.difference(from).inMilliseconds / 60000 * scale,
        );
        segments[day].add(
          BoardSegment(
            item,
            start,
            end,
            day,
            '${days[day]['date']}',
            from,
            to,
            top,
            bottom,
          ),
        );
      }
    }
    final byKey = <String, BoardGroup>{};
    double labelBottom(BoardSegment segment) =>
        segment.bottom - segment.top >= titleBandHeight
        ? segment.bottom
        : math.max(segment.bottom, segment.top + cardHeight);
    final groupsByDay = <List<BoardGroup>>[];
    for (final day in segments) {
      day.sort((a, b) {
        final order = a.top.compareTo(b.top);
        return order != 0
            ? order
            : '${a.item['id']}'.compareTo('${b.item['id']}');
      });
      final groups = <BoardGroup>[];
      var current = <BoardSegment>[];
      var groupBottom = 0.0;
      void finish() {
        if (current.isEmpty) return;
        final ends = <double>[];
        for (final segment in current) {
          var lane = ends.indexWhere((end) => end <= segment.top);
          if (lane < 0) {
            lane = ends.length;
            ends.add(0);
          }
          ends[lane] = labelBottom(segment);
          segment.lane = lane;
        }
        final group = BoardGroup(
          current,
          current.first.top,
          groupBottom,
          ends.length,
        );
        groups.add(group);
        for (final segment in current) {
          byKey[segment.key] = group;
        }
        current = [];
      }

      for (final segment in day) {
        if (current.isNotEmpty && segment.top >= groupBottom) finish();
        current.add(segment);
        groupBottom = math.max(
          current.length == 1 ? 0 : groupBottom,
          labelBottom(segment),
        );
      }
      finish();
      groupsByDay.add(groups);
    }
    final result = BoardGeometry(groupsByDay, byKey, {
      for (final item in items) item['id']: item,
    });
    if (cacheable) {
      _source = items;
      _settings = settings;
      _cached = result;
    }
    return result;
  }
}
