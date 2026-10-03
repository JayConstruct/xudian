import '../../../data/app_database.dart';
import '../data/task_store.dart';
import '../data/task_snapshot_query.dart';

class TaskQueryService {
  TaskQueryService(this.store, {this.now = DateTime.now});

  final TaskStore store;
  final DateTime Function() now;
  late final snapshots = TaskSnapshotQuery(store.db);

  Stream<List<Task>> watchProjectTasks(String projectId) =>
      store.watchProjectTasks(projectId);

  Stream<List<Project>> watchProjects() => store.watchProjects();

  Stream<List<Task>> watchTasks() => store.watchTasks();

  Future<List<Project>> listProjects() => store.listProjects();

  Future<List<Task>> listTasks() => store.listTasks();
}
