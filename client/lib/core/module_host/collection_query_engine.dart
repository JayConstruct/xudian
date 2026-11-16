import 'dart:convert';

import '../contracts/json_values.dart';
import 'module_package.dart';

typedef CollectionSql = Future<List<Map<String, Object?>>> Function(
  String query, [
  List<Object?> args,
]);

/// Query execution owns scalar equivalence and its bounded metadata cache.
/// Authorization, collection revisions and transaction overlays stay in the store.
class CollectionQueryEngine {
  CollectionQueryEngine(this.sql);
  final CollectionSql sql;
  final _compatibility = <String, bool>{};

  /// Keep filtering and pagination inside SQLite when its scalar semantics
  /// exactly match the Dart fallback. Checks return metadata only, never records.
  Future<List<Object?>?> sqlPage(
    List<String> scope,
    String collection,
    Map<String, Object?> options,
    int offset,
    int limit,
    int revision,
  ) async {
    final compiler = _ScalarQueryCompiler();
    final predicate = compiler.filter(options['filter']);
    if (predicate == null) return null;
    const where = 'module_id=? AND space=? AND collection=? AND deleted=0';
    final sorts = options['sort'] as List? ?? [];
    if (sorts.length > 64 || compiler.args.length > 700) return null;
    final compatibilityKey = canonicalJson({
      'scope': scope,
      'revision': revision,
      'sort': sorts,
      'types': compiler.typeChecks.map(
        (key, value) => MapEntry(key, value.toList()),
      ),
      'ascii': compiler.asciiChecks.toList(),
    });
    final cached = _compatibility[compatibilityKey];
    if (cached == false) return null;
    void cache(bool compatible) {
      if (_compatibility.length >= 128) _compatibility.clear();
      _compatibility[compatibilityKey] = compatible;
    }

    final orderBy = <String>[];
    final orderArgs = <Object?>[];
    for (final raw in sorts) {
      final sort = object(raw);
      final path = compiler.path(sort['field']);
      if (path == null) return null;
      orderBy.add(
        "json_extract(value,?) ${sort['direction'] == 'desc' ? 'DESC' : 'ASC'}",
      );
      orderArgs.add(path);
      if (cached == true) continue;
      final kinds =
          (await sql(
                'SELECT DISTINCT json_type(value,?) AS kind FROM host_records WHERE $where',
                [path, ...scope],
              ))
              .map((row) => row['kind'])
              .where((kind) => kind != null && kind != 'null')
              .toSet();
      if (kinds.every((kind) => kind == 'integer' || kind == 'real')) {
        // Nulls sort first ascending, as in compare.
      } else if (kinds.every((kind) => kind == 'text')) {
        compiler.asciiChecks.add(path);
      } else if (kinds.every((kind) => kind == 'true' || kind == 'false')) {
        // Both booleans have the same order as their Dart string values.
      } else {
        cache(false);
        return null;
      }
    }
    if (cached != true) {
      for (final check in compiler.typeChecks.entries) {
        final placeholders = List.filled(check.value.length, '?').join(',');
        final invalid = await sql(
          'SELECT 1 FROM host_records WHERE $where AND '
          'json_type(value,?) IS NOT NULL AND json_type(value,?) NOT IN ($placeholders) LIMIT 1',
          [...scope, check.key, check.key, ...check.value],
        );
        if (invalid.isNotEmpty) {
          cache(false);
          return null;
        }
      }
      for (final path in compiler.asciiChecks) {
        final invalid = await sql(
          'SELECT 1 FROM host_records WHERE $where AND json_type(value,?)=\'text\' AND '
          'length(CAST(json_extract(value,?) AS BLOB)) != length(json_extract(value,?)) LIMIT 1',
          [...scope, path, path, path],
        );
        if (invalid.isNotEmpty) {
          cache(false);
          return null;
        }
      }
      // Record IDs are the stable tiebreaker. Non-ASCII IDs use the Dart path so
      // ordering also remains exact for UTF-16 surrogate pairs.
      final unicodeIds = await sql(
        'SELECT 1 FROM host_records WHERE $where AND length(CAST(id AS BLOB)) != length(id) LIMIT 1',
        scope,
      );
      if (unicodeIds.isNotEmpty) {
        cache(false);
        return null;
      }
      cache(true);
    }
    orderBy.add('id ASC');
    final rows = await sql(
      'SELECT id,value FROM host_records WHERE $where AND ($predicate) '
      'ORDER BY ${orderBy.join(',')} LIMIT ? OFFSET ?',
      [...scope, ...compiler.args, ...orderArgs, limit, offset],
    );
    return (freezeJson([
      for (final row in rows) jsonDecode(row['value'] as String),
    ]) as List).cast<Object?>();
  }

  /// Keyset chunks bound decoded memory even when a predicate cannot use SQL.
  /// A bounded max heap retains only offset + limit rows for sorted queries.
  Future<({List<Object?> page, int decoded})> fallbackPage(
    List<String> scope,
    Map<String, Object?> options,
    List<Map<String, Object?>> overlay,
    int offset,
    int limit,
  ) async {
    final pending = {for (final write in overlay) write['id'] as String: write};
    final sorts = options['sort'] as List? ?? [];
    int order(Object? a, Object? b) {
      for (final raw in sorts) {
        final sort = object(raw);
        var result = compare(
          field(a, sort['field'] as String),
          field(b, sort['field'] as String),
        );
        if (sort['direction'] == 'desc') result = -result;
        if (result != 0) return result;
      }
      return '${object(a)['id']}'.compareTo('${object(b)['id']}');
    }

    final capacity = offset + limit;
    final heap = <Object?>[];
    final page = <Object?>[];
    var matched = 0, decoded = 0;
    void include(Object? value) {
      if (value == null || !matches(object(value), options['filter'])) return;
      if (sorts.isEmpty) {
        if (matched++ >= offset && page.length < limit) page.add(value);
        return;
      }
      if (heap.length < capacity) {
        heap.add(value);
        var index = heap.length - 1;
        while (index > 0) {
          final parent = (index - 1) ~/ 2;
          if (order(heap[parent], heap[index]) >= 0) break;
          final swap = heap[parent];
          heap[parent] = heap[index];
          heap[index] = swap;
          index = parent;
        }
      } else if (order(value, heap.first) < 0) {
        heap[0] = value;
        var index = 0;
        while (index * 2 + 1 < heap.length) {
          var child = index * 2 + 1;
          if (child + 1 < heap.length &&
              order(heap[child + 1], heap[child]) > 0) {
            child++;
          }
          if (order(heap[index], heap[child]) >= 0) break;
          final swap = heap[index];
          heap[index] = heap[child];
          heap[child] = swap;
          index = child;
        }
      }
    }

    String? cursor;
    while (true) {
      final rows = await sql(
        'SELECT id,value FROM host_records WHERE module_id=? AND space=? AND collection=? '
        'AND deleted=0 ${cursor == null ? '' : 'AND id>? '}ORDER BY id LIMIT ?',
        [...scope, ?cursor, 256],
      );
      for (final row in rows) {
        final write = pending.remove(row['id']);
        if (write != null) {
          include(write['value']);
        } else {
          decoded++;
          include(jsonDecode(row['value'] as String));
        }
      }
      if (rows.length < 256) break;
      cursor = rows.last['id'] as String;
    }
    // Map insertion order preserves the historical no-sort overlay semantics.
    for (final write in pending.values) {
      include(write['value']);
    }
    if (sorts.isNotEmpty) {
      heap.sort(order);
      page.addAll(heap.skip(offset).take(limit));
    }
    return (page: (freezeJson(page) as List).cast<Object?>(), decoded: decoded);
  }

  static Object? field(Object? value, String path) {
    for (final part in path.split('.')) {
      if (value is! Map) return null;
      value = value[part];
    }
    return value;
  }

  static int compare(Object? a, Object? b) => a == b
      ? 0
      : a == null
      ? -1
      : b == null
      ? 1
      : a is num && b is num
      ? a.compareTo(b)
      : '$a'.compareTo('$b');
  static bool matches(Map<String, Object?> value, Object? raw) {
    if (raw == null) return true;
    final f = object(raw);
    if (f['all'] is List) {
      return (f['all'] as List).every((v) => matches(value, v));
    }
    if (f['any'] is List) {
      return (f['any'] as List).any((v) => matches(value, v));
    }
    final actual = field(value, string(f['field'], 'filter.field')),
        expected = f['value'];
    return switch (f['op']) {
      'eq' => canonicalJson(actual) == canonicalJson(expected),
      'ne' => canonicalJson(actual) != canonicalJson(expected),
      'isNull' => actual == null,
      'notNull' => actual != null,
      'in' =>
        expected is List &&
            expected.any((v) => canonicalJson(v) == canonicalJson(actual)),
      'contains' =>
        actual is String && expected is String && actual.contains(expected),
      'lt' =>
        actual != null && expected != null && compare(actual, expected) < 0,
      'lte' =>
        actual != null && expected != null && compare(actual, expected) <= 0,
      'gt' =>
        actual != null && expected != null && compare(actual, expected) > 0,
      'gte' =>
        actual != null && expected != null && compare(actual, expected) >= 0,
      _ => throw FormatException('Unsupported filter operation: ${f['op']}'),
    };
  }
}

/// SQL supports only values whose equality and ordering agree with canonical
/// JSON and _compare. Unsupported shapes intentionally retain the Dart path.
class _ScalarQueryCompiler {
  final args = <Object?>[];
  final typeChecks = <String, Set<String>>{};
  final asciiChecks = <String>{};
  int _nodes = 0;

  String? path(Object? field) {
    if (field is! String || field.isEmpty) return null;
    final parts = field.split('.');
    if (parts.any(
      (part) => !RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(part),
    )) {
      return null;
    }
    return r'$' + parts.map((part) => '."$part"').join();
  }

  void requireTypes(String path, Set<String> kinds) {
    final previous = typeChecks[path];
    if (previous == null) {
      typeChecks[path] = kinds;
    } else {
      previous.retainAll(kinds);
    }
  }

  String? filter(Object? raw, [int depth = 0]) {
    if (raw == null) return '1';
    if (depth > 32 || ++_nodes > 128 || raw is! Map) return null;
    final f = raw.cast<String, Object?>();
    for (final group in ['all', 'any']) {
      if (f[group] is List) {
        final clauses = <String>[];
        for (final child in f[group] as List) {
          final compiled = filter(child, depth + 1);
          if (compiled == null) return null;
          clauses.add('($compiled)');
        }
        if (clauses.isEmpty) return group == 'all' ? '1' : '0';
        return clauses.join(group == 'all' ? ' AND ' : ' OR ');
      }
    }
    final jsonPath = path(f['field']);
    if (jsonPath == null) return null;
    final expected = f['value'];
    switch (f['op']) {
      case 'isNull':
        args.add(jsonPath);
        return "COALESCE(json_type(value,?), 'null')='null'";
      case 'notNull':
        args.add(jsonPath);
        return "COALESCE(json_type(value,?), 'null')!='null'";
      case 'eq':
      case 'ne':
        final equal = equality(jsonPath, expected);
        return equal == null
            ? null
            : f['op'] == 'eq'
            ? equal
            : 'NOT ($equal)';
      case 'in':
        if (expected is! List) return '0';
        if (expected.isEmpty) return '0';
        if (expected.length > 128) return null;
        final clauses = <String>[];
        for (final value in expected) {
          final equal = equality(jsonPath, value);
          if (equal == null) return null;
          clauses.add('($equal)');
        }
        return clauses.join(' OR ');
      case 'lt':
      case 'lte':
      case 'gt':
      case 'gte':
        if (expected == null) return '0';
        if (expected is num && expected.isFinite) {
          requireTypes(jsonPath, {'null', 'integer', 'real'});
        } else if (expected is String &&
            expected.codeUnits.every((c) => c > 0 && c < 128)) {
          requireTypes(jsonPath, {'null', 'text'});
          asciiChecks.add(jsonPath);
        } else {
          return null;
        }
        final operator = {
          'lt': '<',
          'lte': '<=',
          'gt': '>',
          'gte': '>=',
        }[f['op']];
        args.addAll([jsonPath, canonicalJson(expected)]);
        return "COALESCE(json_extract(value,?) $operator json_extract(?, '\$'),0)";
      default:
        return null;
    }
  }

  String? equality(String path, Object? expected) {
    if (expected == null) {
      args.add(path);
      return "COALESCE(json_type(value,?), 'null')='null'";
    }
    if (expected is bool) {
      args.add(path);
      return "COALESCE(json_type(value,?)='${expected ? 'true' : 'false'}',0)";
    }
    if (expected is String || expected is int) {
      args.addAll([
        path,
        expected is String ? 'text' : 'integer',
        path,
        canonicalJson(expected),
      ]);
      return "COALESCE(json_type(value,?)=? AND json_extract(value,?)=json_extract(?, '\$'),0)";
    }
    return null;
  }
}
