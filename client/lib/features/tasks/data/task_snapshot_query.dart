import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/declarative/runtime/filter_expression.dart';
import '../../../data/app_database.dart';
import 'task_filter_sql.dart';

typedef TaskSnapshot = Map<String, Object?>;

/// A single reactive query watches tasks, field values, and active definitions.
/// No per-task queries or large IN parameter lists are needed.
class TaskSnapshotQuery {
  TaskSnapshotQuery(this.db);
  final AppDatabase db;

  Selectable<TypedResult> _query(Object? filter, DateTime now) {
    final activeKeys = db.selectOnly(db.fieldDefinitions)
      ..addColumns([db.fieldDefinitions.key])
      ..where(db.fieldDefinitions.active.equals(true));
    return db.select(db.tasks).join([
        leftOuterJoin(
          db.fieldValues,
          db.fieldValues.taskId.equalsExp(db.tasks.id) &
              db.fieldValues.fieldKey.isInQuery(activeKeys),
        ),
      ])
      ..where(
        TaskFilterSql(db.tasks, now).compile(filter) ?? const Constant(true),
      )
      ..orderBy([
        OrderingTerm.desc(db.tasks.createdAt),
        OrderingTerm.asc(db.tasks.id),
      ]);
  }

  List<TaskSnapshot> _snapshots(
    List<TypedResult> results,
    Object? filter,
    String? namespace,
    DateTime now,
  ) {
    final tasks = <String, TaskSnapshot>{};
    for (final result in results) {
      final task = result.readTable(db.tasks);
      final row = tasks.putIfAbsent(
        task.id,
        () => {
          'id': task.id,
          'projectId': task.projectId,
          'parentTaskId': task.parentTaskId,
          'title': task.title,
          'notes': task.notes,
          'priority': task.priority,
          'dueDate': task.dueDate,
          'plannedDate': task.plannedDate,
          'completed': task.completedAt != null,
          'archived': task.archivedAt != null,
          'deleted': task.deletedAt != null,
          'createdAt': task.createdAt.toIso8601String(),
          'fields': <String, Object?>{},
        },
      );
      final field = result.readTableOrNull(db.fieldValues);
      if (field != null) {
        (row['fields'] as Map<String, Object?>)[field.fieldKey] = jsonDecode(
          field.valueJson,
        );
      }
    }
    return tasks.values
        .where(
          (row) => const FilterExpression().evaluate(
            row,
            filter,
            fieldNamespace: namespace,
            now: now,
          ),
        )
        .toList(growable: false);
  }

  Future<List<TaskSnapshot>> get({
    Object? filter,
    String? namespace,
    DateTime? now,
  }) async {
    final date = now ?? DateTime.now();
    return _snapshots(
      await _query(filter, date).get(),
      filter,
      namespace,
      date,
    );
  }

  Stream<List<TaskSnapshot>> watch({
    Object? filter,
    String? namespace,
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    return _query(
      filter,
      date,
    ).watch().map((rows) => _snapshots(rows, filter, namespace, date));
  }
}
