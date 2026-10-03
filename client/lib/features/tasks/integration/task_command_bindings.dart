import '../../../core/contracts/command_bus.dart';
import '../application/task_command_service.dart';
import '../domain/task_input.dart';

void registerTaskCommands(
  CommandBus bus,
  TaskCommandService service,
) {
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
      await service.updateFields(
        id,
        changes.map((key, value) => MapEntry('$key', value)),
      );
      return null;
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
      await service.setCompleted(id, completed);
      return null;
    },
  );
}
