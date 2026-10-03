import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/module_context.dart';
import '../../app/design_system.dart';
import '../../data/app_database.dart';
import 'application/providers.dart';
import 'task_editor.dart';

class TaskListPage extends ConsumerWidget {
  const TaskListPage({
    super.key,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.projectId,
  });

  final String emptyTitle;
  final String emptySubtitle;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectTasksProvider(projectId));
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('无法读取任务：$error')),
      data: (tasks) {
        final visible = tasks;

        if (visible.isEmpty) {
          return WorkspaceEmptyState(
            title: emptyTitle,
            subtitle: emptySubtitle,
          );
        }

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            WorkspaceContentInsets.bottomOf(context) + 24,
          ),
          itemCount: visible.length + 1,
          separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 0 : 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return TaskSummary(
                total: visible.length,
                completed: visible
                    .where((task) => task.completedAt != null)
                    .length,
              );
            }
            final task = visible[index - 1];
            return TaskObjectTile(
              key: ValueKey(task.id),
              title: task.title,
              onTap: () => showTaskEditor(
                context: context,
                moduleContext: const ModuleContext.system(),
                taskId: task.id,
                title: task.title,
                priority: task.priority,
                plannedDate: task.plannedDate,
                dueDate: task.dueDate,
              ),
              completed: task.completedAt != null,
              onCompleted: (value) async {
                final commands = await ref.read(commandBusProvider.future);
                await commands.execute(
                  const ModuleContext.system(),
                  'task.setCompleted',
                  {'id': task.id, 'completed': value ?? false},
                );
              },
              subtitle: _subtitle(task),
            );
          },
        );
      },
    );
  }

  Widget? _subtitle(Task task) {
    final parts = <String>[];
    if (task.dueDate != null) parts.add('截止 ${task.dueDate}');
    if (task.plannedDate != null) parts.add('计划 ${task.plannedDate}');
    if (task.priority > 0) parts.add('优先级 ${task.priority}');
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }
}
