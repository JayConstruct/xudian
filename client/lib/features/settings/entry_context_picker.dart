import '../../core/ui/ui_design.dart';
import 'package:flutter/material.dart';

import '../../core/ui/ui_composition.dart';
import '../../core/ui/native_ui.dart';
import '../../data/app_database.dart';
import 'settings_widgets.dart';

Future<PageContext?> chooseEntryContext(
  BuildContext context,
  AppDatabase database,
  PageContext current, {
  Iterable<String> requiredKeys = const [],
}) async {
  final tasks = await database.select(database.tasks).get();
  final projects = await database.select(database.projects).get();
  if (!context.mounted) return null;
  String? taskId = tasks.any((task) => task.id == current.taskId)
      ? current.taskId
      : null;
  String? projectId = projects.any((project) => project.id == current.projectId)
      ? current.projectId
      : null;
  return showModalBottomSheet<PageContext>(
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => NativeUi(
        child: SettingsSheet(
          title: const Text('补充上下文'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('未指定的上下文由宿主提供；选择具体对象不会增加模块权限。'),
                NativeUi(
                  child: DropdownButtonFormField<String>(
                    borderRadius: AppDesign.selectionBorderRadius,
                    initialValue: taskId ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '任务'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('由宿主提供')),
                      for (final task in tasks)
                        DropdownMenuItem(
                          value: task.id,
                          child: Text(
                            task.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        update(() => taskId = value == '' ? null : value),
                  ),
                ),
                const SizedBox(height: 12),
                NativeUi(
                  child: DropdownButtonFormField<String>(
                    borderRadius: AppDesign.selectionBorderRadius,
                    initialValue: projectId ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '项目'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('由宿主提供')),
                      for (final project in projects)
                        DropdownMenuItem(
                          value: project.id,
                          child: Text(
                            project.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        update(() => projectId = value == '' ? null : value),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            NativeUi(
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
            ),
            NativeUi(
              child: TextButton(
                onPressed:
                    (requiredKeys.contains('taskId') && taskId == null ||
                        requiredKeys.contains('projectId') && projectId == null)
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        PageContext(
                          values: {...current.values}
                            ..remove('taskId')
                            ..remove('projectId'),
                          taskId: taskId,
                          projectId: projectId,
                        ),
                      ),
                child: const Text('使用此上下文'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
