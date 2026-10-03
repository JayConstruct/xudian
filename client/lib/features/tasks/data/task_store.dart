import 'package:drift/drift.dart';

import '../../../data/app_database.dart';

class TaskStore {
  TaskStore(this.db);

  final AppDatabase db;

  Stream<List<Project>> watchProjects() => (db.select(
    db.projects,
  )..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();

  Stream<List<Task>> watchTasks() => (db.select(
    db.tasks,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Stream<List<Task>> watchProjectTasks(String projectId) =>
      (db.select(db.tasks)
            ..where(
              (t) =>
                  t.projectId.equals(projectId) &
                  t.parentTaskId.isNull() &
                  t.deletedAt.isNull() &
                  t.archivedAt.isNull(),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.completedAt.isNotNull()),
              (t) => OrderingTerm.desc(t.priority),
              (t) => OrderingTerm.desc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .watch();

  Future<List<Project>> listProjects() => (db.select(
    db.projects,
  )..orderBy([(p) => OrderingTerm.asc(p.name)])).get();

  Future<List<Task>> listTasks() => (db.select(
    db.tasks,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Future<Project?> findProject(String id) =>
      (db.select(db.projects)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<Task?> findTask(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertProject(Project project) =>
      db.into(db.projects).insert(project);
  Future<void> insertTask(Task task) => db.into(db.tasks).insert(task);

  Future<void> updateTaskFields(String id, Map<String, Object?> changes) {
    return (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: changes.containsKey('title')
            ? Value(changes['title'] as String)
            : const Value.absent(),
        priority: changes.containsKey('priority')
            ? Value(changes['priority'] as int)
            : const Value.absent(),
        dueDate: changes.containsKey('dueDate')
            ? Value(changes['dueDate'] as String?)
            : const Value.absent(),
        plannedDate: changes.containsKey('plannedDate')
            ? Value(changes['plannedDate'] as String?)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setTaskCompleted(String id, DateTime? completedAt) =>
      (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          completedAt: Value(completedAt),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
