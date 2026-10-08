import 'package:uuid/uuid.dart';

import '../../../core/events/domain_event.dart';
import '../../../core/events/event_bus.dart';
import '../../../data/app_database.dart';
import '../data/change_journal.dart';
import '../data/task_store.dart';
import '../domain/task_input.dart';
import '../domain/task_snapshot.dart';
import '../../../core/contracts/json_values.dart';

class TaskCommandService {
  TaskCommandService({
    required this.db,
    required this.store,
    required this.journal,
    required this.events,
  });

  final AppDatabase db;
  final TaskStore store;
  final ChangeJournal journal;
  final EventBus events;
  final Uuid _uuid = const Uuid();

  Future<Project> createProject(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty || cleaned.length > 120) {
      throw ArgumentError('项目名称需为 1–120 个字符');
    }
    final now = DateTime.now();
    final project = Project(
      id: _uuid.v7(),
      name: cleaned,
      createdAt: now,
      updatedAt: now,
      archivedAt: null,
    );
    await db.transaction(() async {
      await store.insertProject(project);
      await journal.append(
        entityType: 'project',
        entityId: project.id,
        action: 'create',
        payload: {'name': cleaned},
      );
    });
    events.publish(
      DomainEvent(
        type: 'project.created',
        entityType: 'project',
        entityId: project.id,
        payload: {'name': cleaned},
      ),
    );
    return project;
  }

  Future<Task> createTask(CreateTaskInput input) async {
    final title = input.title.trim();
    if (title.isEmpty || title.length > 300) {
      throw ArgumentError('任务标题需为 1–300 个字符');
    }
    if (input.priority < 0 || input.priority > 3) {
      throw ArgumentError('优先级必须在 0–3 之间');
    }
    _validateDate(input.dueDate);
    _validateDate(input.plannedDate);

    final now = DateTime.now();
    late Task task;
    await db.transaction(() async {
      if (input.projectId != null) {
        final project = await store.findProject(input.projectId!);
        if (project == null || project.archivedAt != null) {
          throw StateError('项目不可用');
        }
      }
      if (input.parentTaskId != null) {
        final parent = await store.findTask(input.parentTaskId!);
        if (parent == null ||
            parent.deletedAt != null ||
            parent.archivedAt != null) {
          throw StateError('父任务不可用');
        }
        if (parent.projectId != input.projectId) {
          throw StateError('子任务必须与父任务属于同一项目');
        }
      }
      task = Task(
        id: _uuid.v7(),
        projectId: input.projectId,
        parentTaskId: input.parentTaskId,
        title: title,
        notes: '',
        priority: input.priority,
        dueDate: input.dueDate,
        plannedDate: input.plannedDate,
        completedAt: null,
        archivedAt: null,
        deletedAt: null,
        createdAt: now,
        updatedAt: now,
      );
      await store.insertTask(task);
      await journal.append(
        entityType: 'task',
        entityId: task.id,
        action: 'create',
        payload: {
          'title': title,
          'projectId': input.projectId,
          'parentTaskId': input.parentTaskId,
          'priority': input.priority,
          'dueDate': input.dueDate,
          'plannedDate': input.plannedDate,
        },
      );
    });
    events.publish(
      DomainEvent(type: 'task.created', entityType: 'task', entityId: task.id),
    );
    return task;
  }

  Future<Task> updateFields(
    String id,
    Map<String, Object?> changes, {
    DateTime? expectedUpdatedAt,
    Map<String, Object?>? expectedValues,
  }) async {
    final current = await store.findTask(id);
    if (current == null) throw StateError('任务不存在');
    if (current.deletedAt != null) {
      throw StateError('已删除的任务不能修改');
    }

    const allowed = {'title', 'priority', 'dueDate', 'plannedDate'};
    for (final key in changes.keys) {
      if (!allowed.contains(key)) {
        throw ArgumentError('不支持修改字段：$key');
      }
    }
    if (changes.isEmpty) return current;

    if (changes.containsKey('title')) {
      final title = changes['title'];
      if (title is! String ||
          title.trim().isEmpty ||
          title.trim().length > 300) {
        throw ArgumentError('任务标题需为 1–300 个字符');
      }
      changes = {...changes, 'title': title.trim()};
    }
    if (changes.containsKey('priority')) {
      final priority = changes['priority'];
      if (priority is! int || priority < 0 || priority > 3) {
        throw ArgumentError('优先级必须在 0–3 之间');
      }
    }
    if (changes.containsKey('dueDate')) {
      _validateDate(changes['dueDate'] as String?);
    }
    if (changes.containsKey('plannedDate')) {
      _validateDate(changes['plannedDate'] as String?);
    }

    final updated = await db.transaction(() async {
      await _checkRevision(id, expectedUpdatedAt, expectedValues);
      await store.updateTaskFields(id, changes);
      await journal.append(
        entityType: 'task',
        entityId: id,
        action: 'update',
        payload: changes,
      );
      return (await store.findTask(id))!;
    });
    events.publish(
      DomainEvent(
        type: 'task.updated',
        entityType: 'task',
        entityId: id,
        payload: {'fields': changes.keys.toList(growable: false)},
      ),
    );
    return updated;
  }

  Future<Task> setCompleted(
    String id,
    bool completed, {
    DateTime? expectedUpdatedAt,
    Map<String, Object?>? expectedValues,
  }) async {
    final current = await store.findTask(id);
    if (current == null) throw StateError('任务不存在');
    if (current.deletedAt != null) throw StateError('已删除的任务不能修改');

    final updated = await db.transaction(() async {
      await _checkRevision(id, expectedUpdatedAt, expectedValues);
      await store.setTaskCompleted(id, completed ? DateTime.now() : null);
      await journal.append(
        entityType: 'task',
        entityId: id,
        action: completed ? 'complete' : 'reopen',
      );
      return (await store.findTask(id))!;
    });
    events.publish(
      DomainEvent(
        type: completed ? 'task.completed' : 'task.reopened',
        entityType: 'task',
        entityId: id,
      ),
    );
    return updated;
  }

  Future<void> _checkRevision(
    String id,
    DateTime? expected,
    Map<String, Object?>? values,
  ) async {
    final current = await store.findTask(id);
    if (current == null || current.deletedAt != null) {
      throw StateError('任务已不可用');
    }
    if (expected != null && current.updatedAt != expected) {
      throw StateError('任务已被其他操作修改，请重新生成方案');
    }
    if (values != null &&
        canonicalJson(values) != canonicalJson(taskStateSnapshot(current))) {
      throw StateError('任务内容已变化，请重新生成方案');
    }
  }

  void _validateDate(String? value) {
    if (value == null) return;
    final parsed = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        parsed == null ||
        '${parsed.year.toString().padLeft(4, '0')}-'
                '${parsed.month.toString().padLeft(2, '0')}-'
                '${parsed.day.toString().padLeft(2, '0')}' !=
            value) {
      throw ArgumentError('日期格式必须为 YYYY-MM-DD');
    }
  }
}
