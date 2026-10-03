import '../../../core/contracts/query_bus.dart';
import '../application/task_query_service.dart';

void registerTaskQueries(QueryBus bus, TaskQueryService service) {
  bus.register(
    'task.list',
    permission: 'tasks.read',
    handler: (payload) => service.snapshots.get(
      now: service.now(),
      filter: payload['filter'],
      namespace: payload['fieldNamespace'] as String?,
    ),
    watchHandler: (payload) => service.snapshots.watch(
      now: service.now(),
      filter: payload['filter'],
      namespace: payload['fieldNamespace'] as String?,
    ),
  );
  bus.register(
    'task.get',
    permission: 'tasks.read',
    handler: (payload) async {
      final id = payload['id'];
      if (id is! String || id.isEmpty) {
        throw ArgumentError('task.get requires id');
      }
      final rows = await service.snapshots.get(
        now: service.now(),
        filter: {'field': 'id', 'op': 'eq', 'value': id},
      );
      return rows.singleOrNull;
    },
  );
  bus.register(
    'project.list',
    permission: 'tasks.read',
    handler: (_) async {
      final projects = await service.listProjects();
      return projects
          .map(
            (project) => <String, Object?>{
              'id': project.id,
              'name': project.name,
              'archived': project.archivedAt != null,
            },
          )
          .toList(growable: false);
    },
  );
}
