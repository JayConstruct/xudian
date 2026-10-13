import 'package:timezone/timezone.dart' as tz;

import 'module_package.dart' show string;

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

Map<String, Object?> clockToLocal(Map<String, Object?> args) {
  final utc = string(args['utc'], 'UTC instant');
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$')
      .hasMatch(utc)) {
    throw const FormatException(
      'UTC instant must be an ISO timestamp ending in Z',
    );
  }
  final parsed = DateTime.tryParse(utc);
  // DateTime.parse normalizes invalid civil dates and times; reject those.
  if (parsed == null ||
      _date(parsed) != utc.substring(0, 10) ||
      _time(parsed) != utc.substring(11, 16) ||
      parsed.second.toString().padLeft(2, '0') != utc.substring(17, 19)) {
    throw const FormatException('Invalid UTC instant');
  }
  final local = tz.TZDateTime.from(
    parsed,
    tz.getLocation(string(args['zone'], 'zone')),
  );
  return {'date': _date(local), 'time': _time(local), 'weekday': local.weekday};
}

Map<String, Object?> clockToUtc(Map<String, Object?> args) {
  final date = string(args['date'], 'date');
  final time = string(args['time'], 'time');
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
    throw const FormatException('Expected date YYYY-MM-DD and time HH:mm');
  }
  final wall = DateTime.tryParse('${date}T$time:00Z');
  if (wall == null || _date(wall) != date || _time(wall) != time) {
    throw const FormatException('Invalid civil date or time');
  }
  final location = tz.getLocation(string(args['zone'], 'zone'));
  final candidates = <int>{};
  // Check every distinct offset, including historical and non-hour offsets.
  // TZDateTime's civil constructor shifts gaps and selects one side of folds.
  for (final offset in location.zones.map((zone) => zone.offset).toSet()) {
    final instant = wall.millisecondsSinceEpoch - offset;
    final local = tz.TZDateTime.fromMillisecondsSinceEpoch(location, instant);
    if (_date(local) == date &&
        _time(local) == time &&
        local.second == 0 &&
        local.millisecond == 0) {
      candidates.add(instant);
    }
  }
  final instants = candidates.toList()..sort();
  return {
    'status': instants.isEmpty
        ? 'nonexistent'
        : instants.length == 1
        ? 'unique'
        : 'ambiguous',
    'instants': [
      for (final instant in instants)
        DateTime.fromMillisecondsSinceEpoch(
          instant,
          isUtc: true,
        ).toIso8601String(),
    ],
  };
}
