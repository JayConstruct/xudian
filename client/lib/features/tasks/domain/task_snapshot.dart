import '../../../data/app_database.dart';

Map<String, Object?> taskStateSnapshot(Task task) => {
  'id': task.id,
  'projectId': task.projectId,
  'parentTaskId': task.parentTaskId,
  'title': task.title,
  'notes': task.notes,
  'priority': task.priority,
  'dueDate': task.dueDate,
  'plannedDate': task.plannedDate,
  'completedAt': task.completedAt?.toIso8601String(),
  'archivedAt': task.archivedAt?.toIso8601String(),
  'deletedAt': task.deletedAt?.toIso8601String(),
  'updatedAt': task.updatedAt.toIso8601String(),
};
