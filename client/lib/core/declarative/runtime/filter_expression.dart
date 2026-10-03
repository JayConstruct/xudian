class FilterExpression {
  const FilterExpression();

  bool evaluate(
    Map<String, Object?> row,
    Object? expression, {
    DateTime? now,
    String? fieldNamespace,
  }) {
    if (expression == null) return true;
    if (expression is! Map) {
      throw const FormatException('Filter expression must be an object');
    }
    final map = expression.map((key, value) => MapEntry('$key', value));

    if (map.containsKey('all')) {
      final items = _list(map['all'], 'all');
      return items.every(
        (item) => evaluate(row, item, now: now, fieldNamespace: fieldNamespace),
      );
    }
    if (map.containsKey('any')) {
      final items = _list(map['any'], 'any');
      return items.any(
        (item) => evaluate(row, item, now: now, fieldNamespace: fieldNamespace),
      );
    }
    if (map.containsKey('not')) {
      return !evaluate(
        row,
        map['not'],
        now: now,
        fieldNamespace: fieldNamespace,
      );
    }

    final field = map['field'];
    final op = map['op'];
    if (field is! String || op is! String) {
      throw const FormatException('Filter leaf requires field and op');
    }
    final actual = _read(row, field, fieldNamespace);
    final expected = _resolve(map['value'], now ?? DateTime.now());

    return switch (op) {
      'eq' => actual == expected,
      'ne' => actual != expected,
      'isNull' => actual == null,
      'notNull' => actual != null,
      'lt' =>
        actual != null && expected != null && _compare(actual, expected) < 0,
      'lte' =>
        actual != null && expected != null && _compare(actual, expected) <= 0,
      'gt' =>
        actual != null && expected != null && _compare(actual, expected) > 0,
      'gte' =>
        actual != null && expected != null && _compare(actual, expected) >= 0,
      'contains' => actual is List && actual.contains(expected),
      _ => throw FormatException('Unsupported filter operator: $op'),
    };
  }

  Object? _read(Map<String, Object?> row, String path, String? fieldNamespace) {
    if (path.startsWith('fields.')) {
      final fields = row['fields'];
      if (fields is! Map) return null;
      var key = path.substring('fields.'.length);
      if (!key.contains(':') && fieldNamespace != null) {
        key = '$fieldNamespace:$key';
      }
      return fields[key];
    }

    Object? current = row;
    for (final segment in path.split('.')) {
      if (current is! Map) return null;
      current = current[segment];
    }
    return current;
  }

  Object? _resolve(Object? value, DateTime now) {
    if (value != r'$today') return value;
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int _compare(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    throw FormatException('Values are not comparable: $a / $b');
  }

  List<Object?> _list(Object? value, String name) {
    if (value is! List) {
      throw FormatException('$name must be an array');
    }
    return value;
  }
}
