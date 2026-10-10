import '../../../core/contracts/command_bus.dart';
import '../application/task_command_service.dart';
import '../domain/task_input.dart';
import '../domain/task_snapshot.dart';

void registerTaskCommands(CommandBus bus, TaskCommandService service) {
  bus.register(
    'project.create',
    permission: 'tasks.write',
    handler: (payload) async {
      final name = payload['name'];
      if (name is! String) {
        throw ArgumentError('project.create requires name');
      }
      final project = await service.createProject(name);
      return <String, Object?>{'id': project.id};
    },
  );

  bus.register(
    'task.create',
    permission: 'tasks.write',
    handler: (payload) async {
      final title = payload['title'];
      if (title is! String) {
        throw ArgumentError('task.create requires title');
      }
      final task = await service.createTask(
        CreateTaskInput(
          title: title,
          projectId: payload['projectId'] as String?,
          parentTaskId: payload['parentTaskId'] as String?,
          priority: payload['priority'] as int? ?? 0,
          dueDate: payload['dueDate'] as String?,
          plannedDate: payload['plannedDate'] as String?,
        ),
      );
      return <String, Object?>{'id': task.id};
    },
  );
  bus.register(
    'task.updateFields',
    permission: 'tasks.write',
    handler: (payload) async {
      final id = payload['id'];
      final changes = payload['changes'];
      if (id is! String || changes is! Map) {
        throw ArgumentError('task.updateFields requires id and changes');
      }
      final task = await service.updateFields(
        id,
        changes.map((key, value) => MapEntry('$key', value)),
        expectedUpdatedAt: _expectedRevision(payload),
        expectedValues: _expectedValues(payload),
      );
      return payload.containsKey('expectedValues')
          ? taskStateSnapshot(task)
          : null;
    },
  );

  bus.register(
    'task.setCompleted',
    permission: 'tasks.write',
    handler: (payload) async {
      final id = payload['id'];
      final completed = payload['completed'];
      if (id is! String || completed is! bool) {
        throw ArgumentError('task.setCompleted requires id and completed');
      }
      final task = await service.setCompleted(
        id,
        completed,
        expectedUpdatedAt: _expectedRevision(payload),
        expectedValues: _expectedValues(payload),
      );
      return payload.containsKey('expectedValues')
          ? taskStateSnapshot(task)
          : null;
    },
  );
}

DateTime? _expectedRevision(Map<String, Object?> payload) {
  final value = payload['expectedUpdatedAt'];
  if (value == null) return null;
  if (value is! String) throw ArgumentError('Invalid expected task revision');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw ArgumentError('Invalid expected task revision');
  return parsed;
}

Map<String, Object?>? _expectedValues(Map<String, Object?> payload) {
  final value = payload['expectedValues'];
  if (value == null) return null;
  if (value is! Map) throw ArgumentError('Invalid expected task snapshot');
  return value.cast<String, Object?>();
}
