import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/declarative/declarative_module.dart';
import '../../core/modules/module_context.dart';
import '../../app/design_system.dart';
import '../tasks/application/providers.dart';
import '../tasks/task_editor.dart';
import 'declarative_field_editor.dart';

class DeclarativeTaskPage extends ConsumerStatefulWidget {
  const DeclarativeTaskPage({
    super.key,
    required this.module,
    required this.moduleContext,
    required this.page,
  });

  final DeclarativeModule module;
  final ModuleContext moduleContext;
  final Map<String, Object?> page;

  @override
  ConsumerState<DeclarativeTaskPage> createState() =>
      _DeclarativeTaskPageState();
}

class _DeclarativeTaskPageState extends ConsumerState<DeclarativeTaskPage>
    with WidgetsBindingObserver {
  late Map<String, Object?> view;
  late Stream<Object?> result;
  Timer? dayTimer;
  final pendingTasks = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayRefresh();
    final viewId = widget.page['view'];
    view = widget.module.views.firstWhere((item) => item['id'] == viewId);
    result = _watch();
  }

  @override
  void didUpdateWidget(covariant DeclarativeTaskPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module || oldWidget.page != widget.page) {
      view = widget.module.views.firstWhere(
        (item) => item['id'] == widget.page['view'],
      );
      result = _watch();
    }
  }

  void _scheduleDayRefresh() {
    dayTimer?.cancel();
    final now = ref.read(queryClockProvider)();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    dayTimer = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      setState(() => result = _watch());
      _scheduleDayRefresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => result = _watch());
      _scheduleDayRefresh();
    }
  }

  @override
  void dispose() {
    dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Stream<Object?> _watch() async* {
    final moduleContext = widget.moduleContext;
    final source = view['source'] as String;
    final payload = <String, Object?>{
      'filter': view['filter'],
      'fieldNamespace': widget.module.manifest.id,
    };
    final bus = await ref.read(queryBusProvider.future);
    yield* bus.watch(moduleContext, source, payload);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Object?>(
      stream: result,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('模块加载失败：${snapshot.error}'));
        }
        final rows = (snapshot.data as List).cast<Map<String, Object?>>();
        if (rows.isEmpty) {
          return WorkspaceEmptyState(
            title: (view['emptyText'] as String?) ?? '暂无任务',
            subtitle: widget.page['quickAdd'] == true
                ? '从底部输入栏开始记录'
                : '符合条件的任务会显示在这里',
          );
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            WorkspaceContentInsets.bottomOf(context) + 24,
          ),
          itemCount: rows.length + 1,
          separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 0 : 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return TaskSummary(
                total: rows.length,
                completed: rows
                    .where((task) => task['completed'] == true)
                    .length,
              );
            }
            final task = rows[index - 1];
            return TaskObjectTile(
              key: ValueKey(task['id']),
              title: task['title'] as String,
              onTap: widget.moduleContext.allows('tasks.write')
                  ? () => showTaskEditor(
                      context: context,
                      moduleContext: widget.moduleContext,
                      taskId: task['id'] as String,
                      title: task['title'] as String,
                      priority: task['priority'] as int? ?? 0,
                      plannedDate: task['plannedDate'] as String?,
                      dueDate: task['dueDate'] as String?,
                    )
                  : null,
              completed: task['completed'] == true,
              onCompleted:
                  widget.moduleContext.allows('tasks.write') &&
                      !pendingTasks.contains(task['id'])
                  ? (value) => _setCompleted(task, value ?? false)
                  : null,
              subtitle: _subtitle(task),
              trailing: widget.module.fields.isNotEmpty
                  ? IconButton(
                      tooltip: '编辑扩展字段',
                      icon: const Icon(Icons.tune_outlined),
                      onPressed:
                          widget.moduleContext.allows('fields.write') &&
                              !pendingTasks.contains(task['id'])
                          ? () => _editFields(task)
                          : null,
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  Future<void> _setCompleted(Map<String, Object?> task, bool completed) async {
    final id = task['id'] as String;
    if (!pendingTasks.add(id)) return;
    setState(() {});
    try {
      final bus = await ref.read(commandBusProvider.future);
      await bus.execute(widget.moduleContext, 'task.setCompleted', {
        'id': id,
        'completed': completed,
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新失败：$error')));
      }
    } finally {
      pendingTasks.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editFields(Map<String, Object?> task) async {
    final current =
        (task['fields'] as Map?)?.cast<String, Object?>() ?? const {};
    final values = await showDeclarativeFieldEditor(
      context: context,
      module: widget.module,
      current: current,
    );
    if (values == null || !mounted) return;
    final changes = <String, Object?>{
      for (final field in widget.module.fields)
        '${widget.module.manifest.id}:${field['id']}': values[field['id']],
    };
    await _saveFields(task['id'] as String, changes);
  }

  Future<void> _saveFields(String taskId, Map<String, Object?> values) async {
    if (!mounted || !pendingTasks.add(taskId)) return;
    setState(() {});
    try {
      final bus = await ref.read(commandBusProvider.future);
      await bus.execute(widget.moduleContext, 'field.setMany', {
        'taskId': taskId,
        'values': values,
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('字段保存失败：$error'),
            action: SnackBarAction(
              label: '重试',
              onPressed: () => _saveFields(taskId, values),
            ),
          ),
        );
      }
    } finally {
      pendingTasks.remove(taskId);
      if (mounted) setState(() {});
    }
  }

  Widget? _subtitle(Map<String, Object?> task) {
    final parts = <String>[];
    if (task['dueDate'] != null) parts.add('截止 ${task['dueDate']}');
    if (task['plannedDate'] != null) parts.add('计划 ${task['plannedDate']}');
    final priority = task['priority'] as int? ?? 0;
    if (priority > 0) parts.add('优先级 $priority');
    final fields =
        (task['fields'] as Map?)?.cast<String, Object?>() ?? const {};
    final showFields =
        (view['showFields'] as List?)?.cast<String>() ?? const [];
    for (final key in showFields) {
      final fieldKey = key.contains(':')
          ? key
          : '${widget.module.manifest.id}:$key';
      final value = fields[fieldKey];
      if (value != null) parts.add('$key: $value');
    }
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }
}
