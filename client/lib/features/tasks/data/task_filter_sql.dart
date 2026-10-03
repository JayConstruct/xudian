import 'package:drift/drift.dart';

import '../../../data/app_database.dart';

/// Compiles only expressions whose SQL semantics match FilterExpression.
/// Returning null keeps the existing Dart evaluator for the whole expression.
class TaskFilterSql {
  TaskFilterSql(this.tasks, this.now);

  final $TasksTable tasks;
  final DateTime now;

  Expression<bool>? compile(Object? filter) {
    if (filter == null) return const Constant(true);
    if (filter is! Map) return null;
    for (final group in ['all', 'any']) {
      if (filter.containsKey(group)) {
        final children = filter[group];
        if (children is! List) return null;
        Expression<bool> result = Constant(group == 'all');
        for (final child in children) {
          final compiled = compile(child);
          if (compiled == null) return null;
          result = group == 'all' ? result & compiled : result | compiled;
        }
        return result;
      }
    }
    if (filter.containsKey('not')) {
      final child = compile(filter['not']);
      return child?.not();
    }
    final field = filter['field'];
    final op = filter['op'];
    if (op is! String) return null;
    final value = filter['value'] == r'$today'
        ? '${now.year.toString().padLeft(4, '0')}-'
              '${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')}'
        : filter['value'];
    final textColumn = switch (field) {
      'id' => tasks.id,
      'projectId' => tasks.projectId,
      'parentTaskId' => tasks.parentTaskId,
      'title' => tasks.title,
      'notes' => tasks.notes,
      'plannedDate' => tasks.plannedDate,
      'dueDate' => tasks.dueDate,
      _ => null,
    };
    if (textColumn != null) {
      if (value != null && value is! String) return null;
      final equality = _equality<String>(textColumn, op, value as String?);
      if (equality != null) return equality;
      // Date strings use ASCII ordering in both runtimes. Other text ordering
      // may differ between Dart UTF-16 and SQLite UTF-8, so retain Dart there.
      if ((field == 'dueDate' || field == 'plannedDate') &&
          value is String &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        return _compare(textColumn, op, value);
      }
      return null;
    }
    if (field == 'priority') {
      if (value != null && value is! int) return null;
      return _equality<int>(tasks.priority, op, value as int?) ??
          (value is int ? _compare(tasks.priority, op, value) : null);
    }
    final boolean = switch (field) {
      'completed' => tasks.completedAt.isNotNull(),
      'archived' => tasks.archivedAt.isNotNull(),
      'deleted' => tasks.deletedAt.isNotNull(),
      _ => null,
    };
    if (boolean != null && (value == null || value is bool)) {
      return _equality<bool>(boolean, op, value as bool?);
    }
    return null;
  }

  Expression<bool>? _equality<T extends Object>(
    Expression<T> column,
    String op,
    T? value,
  ) => switch (op) {
    'isNull' => column.isNull(),
    'notNull' => column.isNotNull(),
    'eq' => value == null ? column.isNull() : column.isValue(value),
    'ne' => value == null ? column.isNotNull() : column.isNotValue(value),
    _ => null,
  };

  Expression<bool>? _compare<T extends Comparable<dynamic>>(
    Expression<T> column,
    String op,
    T value,
  ) {
    final comparison = switch (op) {
      'lt' => column.isSmallerThanValue(value),
      'lte' => column.isSmallerOrEqualValue(value),
      'gt' => column.isBiggerThanValue(value),
      'gte' => column.isBiggerOrEqualValue(value),
      _ => null,
    };
    // SQL NULL must evaluate to false, including when enclosed in NOT.
    return comparison == null ? null : column.isNotNull() & comparison;
  }
}
