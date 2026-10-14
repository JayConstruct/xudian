import 'package:timezone/timezone.dart' as tz;

typedef SystemTimezoneResolver = Future<String?> Function();

/// Never infers a region from an offset or an ambiguous abbreviation.
Future<Map<String, Object?>> readSystemTimezone(
  SystemTimezoneResolver? resolver,
) async {
  if (resolver != null) {
    try {
      final native = await resolver().timeout(const Duration(seconds: 3));
      final zone = const {'GMT', 'Etc/GMT', 'Etc/UTC'}.contains(native)
          ? 'UTC'
          : native;
      if (zone != null &&
          zone.length <= 128 &&
          zone == zone.trim() &&
          (zone == 'UTC' || zone.contains('/'))) {
        tz.getLocation(zone);
        return {'zone': zone, 'source': 'system'};
      }
    } on Object {
      // A missing channel, unsupported platform or invalid identifier must not
      // prevent creating a timetable. The source keeps this fallback visible.
    }
  }
  return {'zone': 'Asia/Shanghai', 'source': 'fallback'};
}
