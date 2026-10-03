import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/app_database.dart';

class FieldValueStore {
  FieldValueStore(this.db);
  final AppDatabase db;

  Future<FieldDefinition> _definition(String taskId, String fieldKey) async {
    final definition = await (db.select(
      db.fieldDefinitions,
    )..where((row) => row.key.equals(fieldKey))).getSingleOrNull();
    if (definition == null || !definition.active) {
      throw StateError('Unknown or inactive field: $fieldKey');
    }
    final task = await (db.select(
      db.tasks,
    )..where((row) => row.id.equals(taskId))).getSingleOrNull();
    if (task == null || task.deletedAt != null) throw StateError('任务不存在或已删除');
    return definition;
  }

  /// Returns false for an unchanged value, so callers can avoid duplicate logs.
  Future<bool> setValue({
    required String taskId,
    required String fieldKey,
    required Object? value,
  }) => db.transaction(() async {
    final definition = await _definition(taskId, fieldKey);
    _validateValue(definition, value);
    final encoded = jsonEncode(value);
    final existing =
        await (db.select(db.fieldValues)..where(
              (row) =>
                  row.taskId.equals(taskId) & row.fieldKey.equals(fieldKey),
            ))
            .getSingleOrNull();
    if (existing?.valueJson == encoded) return false;
    await db
        .into(db.fieldValues)
        .insertOnConflictUpdate(
          FieldValue(
            taskId: taskId,
            fieldKey: fieldKey,
            valueJson: encoded,
            updatedAt: DateTime.now(),
          ),
        );
    return true;
  });

  Future<bool> clearValue({required String taskId, required String fieldKey}) =>
      db.transaction(() async {
        await _definition(taskId, fieldKey);
        return await (db.delete(db.fieldValues)..where(
                  (row) =>
                      row.taskId.equals(taskId) & row.fieldKey.equals(fieldKey),
                ))
                .go() >
            0;
      });

  Future<Map<String, Object?>> valuesForTask(String taskId) async =>
      (await valuesForTasks([taskId]))[taskId] ?? {};

  Future<Map<String, Map<String, Object?>>> valuesForTasks(
    Iterable<String> taskIds,
  ) async {
    final ids = taskIds.toSet().toList(growable: false);
    final result = <String, Map<String, Object?>>{};
    // Respect SQLite parameter limits for callers requesting many tasks.
    for (var start = 0; start < ids.length; start += 500) {
      final end = start + 500 < ids.length ? start + 500 : ids.length;
      final query =
          db.select(db.fieldValues).join([
            innerJoin(
              db.fieldDefinitions,
              db.fieldDefinitions.key.equalsExp(db.fieldValues.fieldKey),
            ),
          ])..where(
            db.fieldValues.taskId.isIn(ids.sublist(start, end)) &
                db.fieldDefinitions.active.equals(true),
          );
      for (final row in await query.get()) {
        final value = row.readTable(db.fieldValues);
        result.putIfAbsent(value.taskId, () => {})[value.fieldKey] = jsonDecode(
          value.valueJson,
        );
      }
    }
    return result;
  }

  void _validateValue(FieldDefinition definition, Object? value) {
    final config = jsonDecode(definition.configJson) as Map;
    final options = config['options'];
    final valid = switch (definition.type) {
      'text' => value is String,
      'number' => value is num && value.isFinite,
      'boolean' => value is bool,
      'date' => value is String && _isDate(value),
      'datetime' => value is String && _isDateTime(value),
      'select' => value is String && options is List && options.contains(value),
      'multiSelect' =>
        value is List &&
            options is List &&
            value.toSet().length == value.length &&
            value.every((item) => item is String && options.contains(item)),
      _ => false,
    };
    if (!valid) {
      throw ArgumentError(
        'Invalid value for field ${definition.key} (${definition.type})',
      );
    }
  }

  bool _isDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final date = DateTime.tryParse(value);
    return date != null &&
        '${date.year.toString().padLeft(4, '0')}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}' ==
            value;
  }

  bool _isDateTime(String value) {
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(?:Z|[+-](\d{2}):?(\d{2}))?$',
    ).firstMatch(value);
    return match != null &&
        _isDate(match[1]!) &&
        int.parse(match[2]!) < 24 &&
        int.parse(match[3]!) < 60 &&
        int.parse(match[4] ?? '0') < 60 &&
        int.parse(match[5] ?? '0') < 24 &&
        int.parse(match[6] ?? '0') < 60 &&
        DateTime.tryParse(value) != null;
  }
}
