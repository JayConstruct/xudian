class CreateTaskInput {
  const CreateTaskInput({
    required this.title,
    this.projectId,
    this.parentTaskId,
    this.priority = 0,
    this.dueDate,
    this.plannedDate,
  });

  final String title;
  final String? projectId;
  final String? parentTaskId;
  final int priority;
  final String? dueDate;
  final String? plannedDate;
}
