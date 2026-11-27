import 'planner_board_types.dart';

typedef PlannerGap = (DateTime, DateTime);

/// Neighbouring free intervals in one immutable board snapshot.
class PlannerBoardGaps {
  PlannerBoardGaps(this.parse);
  final DateTime? Function(Object?) parse;

  List<BoardItem>? _source;
  final _dailyOccupancy =
      <(DateTime, DateTime), List<(Object?, DateTime, DateTime)>>{};
  // The selected block and the current drag preview can both be on screen.
  final _results = <bool, ({Object inputs, List<PlannerGap> gaps})>{};

  List<PlannerGap> around(
    List<BoardItem> blocks,
    Object? id,
    DateTime start,
    DateTime end, {
    List<Object?>? replacements,
  }) {
    if (!identical(blocks, _source)) {
      _source = blocks;
      _dailyOccupancy.clear();
      _results.clear();
    }
    final inputs = (id, start, end, replacements);
    final preview = replacements != null;
    final cached = _results[preview];
    if (cached != null && cached.inputs == inputs) return cached.gaps;
    final gaps = _neighbours(blocks, id, start, end, replacements ?? const []);
    _results[preview] = (inputs: inputs, gaps: gaps);
    return gaps;
  }

  List<PlannerGap> _neighbours(
    List<BoardItem> blocks,
    Object? id,
    DateTime start,
    DateTime end,
    List<Object?> replacements,
  ) {
    final date = DateTime.utc(start.year, start.month, start.day),
        next = DateTime.utc(
          end.year,
          end.month,
          end.day,
        ).add(const Duration(days: 1));
    final changed = {
      for (final replacement in replacements.whereType<Map>())
        replacement['id']: replacement,
    };
    final spans = <(DateTime, DateTime)>[];
    // Parse the full data source once for each relevant day and data revision.
    // Pointer frames only inspect that day's cached occupancy.
    final daily = _dailyOccupancy.putIfAbsent((date, next), () {
      final result = <(Object?, DateTime, DateTime)>[];
      for (final block in blocks) {
        if (block['occupiesTime'] == false) continue;
        final a = parse(block['start']), b = parse(block['end']);
        if (a != null && b != null && a.isBefore(next) && b.isAfter(date)) {
          result.add((block['id'], a, b));
        }
      }
      return result;
    });
    for (final original in daily) {
      if (original.$1 == id || changed.containsKey(original.$1)) {
        continue;
      }
      spans.add((
        original.$2.isBefore(date) ? date : original.$2,
        original.$3.isAfter(next) ? next : original.$3,
      ));
    }
    for (final block in changed.values) {
      if (block['id'] == id) continue;
      final a = parse(block['start']), b = parse(block['end']);
      if (a == null || b == null || !a.isBefore(next) || !b.isAfter(date)) {
        continue;
      }
      spans.add((a.isBefore(date) ? date : a, b.isAfter(next) ? next : b));
    }
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(DateTime, DateTime)>[];
    for (final span in spans) {
      if (merged.isEmpty || span.$1.isAfter(merged.last.$2)) {
        merged.add(span);
      } else if (span.$2.isAfter(merged.last.$2)) {
        merged[merged.length - 1] = (merged.last.$1, span.$2);
      }
    }
    if (merged.any((span) => span.$1.isBefore(end) && span.$2.isAfter(start))) {
      return [];
    }
    DateTime? previous, following;
    for (final span in merged) {
      if (!span.$2.isAfter(start)) previous = span.$2;
      if (!span.$1.isBefore(end)) {
        following = span.$1;
        break;
      }
    }
    return [
      if (previous != null && start.isAfter(previous)) (previous, start),
      if (following != null && following.isAfter(end)) (end, following),
    ];
  }
}
