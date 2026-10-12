import 'package:flutter/widgets.dart';

/// Presentation state shared by one mounted page composition, never records,
/// entity identities, layout configuration or application-wide preferences.
const pageRuntimeContextKeys = {'selectedDate'};

Map<String, Object?> withoutRuntimePageContext(Map<String, Object?> values) => {
  for (final entry in values.entries)
    if (!pageRuntimeContextKeys.contains(entry.key)) entry.key: entry.value,
};

Map<String, Object?> validateRuntimeContextPatch(Object? raw) {
  if (raw is! Map ||
      raw.keys.any(
        (key) => key is! String || !pageRuntimeContextKeys.contains(key),
      )) {
    throw const FormatException('Runtime context only accepts selectedDate');
  }
  final value = raw['selectedDate'];
  if (raw.isEmpty) return const {};
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException(
      'selectedDate requires a civil YYYY-MM-DD date',
    );
  }
  final date = DateTime.tryParse(value);
  if (date == null ||
      date.year < 1 ||
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' !=
          value) {
    throw const FormatException('selectedDate requires a valid civil date');
  }
  return Map.unmodifiable({'selectedDate': value});
}

class PageRuntimeContextScope extends InheritedWidget {
  const PageRuntimeContextScope({
    super.key,
    required this.values,
    required this.revision,
    required this.update,
    required this.currentValues,
    required this.currentRevision,
    required super.child,
  });
  final Map<String, Object?> values;
  final int revision;
  final Map<String, Object?> Function() currentValues;
  final int Function() currentRevision;
  final bool Function(Map<String, Object?> patch) update;
  static PageRuntimeContextScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageRuntimeContextScope>();
  static PageRuntimeContextScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageRuntimeContextScope>();
  @override
  bool updateShouldNotify(PageRuntimeContextScope oldWidget) =>
      revision != oldWidget.revision || values != oldWidget.values;
}
