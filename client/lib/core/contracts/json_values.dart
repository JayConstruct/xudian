import 'dart:convert';

Object? freezeJson(Object? value) => switch (value) {
  Map() => Map<String, Object?>.unmodifiable({
    for (final entry in value.entries)
      entry.key as String: freezeJson(entry.value),
  }),
  List() => List<Object?>.unmodifiable(value.map(freezeJson)),
  _ => value,
};

String canonicalJson(Object? value) {
  Object? normalize(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: normalize(item[key])};
    }
    if (item is List) return item.map(normalize).toList();
    return item;
  }

  return jsonEncode(normalize(value));
}
