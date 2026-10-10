import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/modules/module_context.dart';
import 'application/providers.dart';

Future<bool?> showTaskEditor({
  required BuildContext context,
  required ModuleContext moduleContext,
  required String taskId,
  required String title,
  required int priority,
  String? plannedDate,
  String? dueDate,
}) {
  final editor = TaskEditor(
    moduleContext: moduleContext,
    taskId: taskId,
    title: title,
    priority: priority,
    plannedDate: plannedDate,
    dueDate: dueDate,
  );
  if (MediaQuery.sizeOf(context).width >= 820) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        alignment: Alignment.centerRight,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: 440, child: editor),
      ),
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(heightFactor: 0.9, child: editor),
    ),
  );
}

class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({
    super.key,
    required this.moduleContext,
    required this.taskId,
    required this.title,
    required this.priority,
    this.plannedDate,
    this.dueDate,
  });

  final ModuleContext moduleContext;
  final String taskId;
  final String title;
  final int priority;
  final String? plannedDate;
  final String? dueDate;

  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  final formKey = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.title);
  late final plannedDate = TextEditingController(text: widget.plannedDate);
  late final dueDate = TextEditingController(text: widget.dueDate);
  late int priority = widget.priority;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    title.dispose();
    plannedDate.dispose();
    dueDate.dispose();
    super.dispose();
  }

  String? _validateDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final text = value.trim();
    final parsed = DateTime.tryParse(text);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
        parsed == null ||
        _formatDate(parsed) != text) {
      return '请输入有效日期，如 2026-10-02';
    }
    return null;
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(TextEditingController controller) async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _validateDate(controller.text) == null &&
              controller.text.trim().isNotEmpty &&
              (DateTime.tryParse(controller.text.trim())?.year ?? 0) >= 1
          ? DateTime.parse(controller.text.trim())
          : DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date != null && mounted) controller.text = _formatDate(date);
  }

  Future<void> _save() async {
    if (saving || !formKey.currentState!.validate()) return;
    final values = <String, Object?>{
      'title': title.text.trim(),
      'priority': priority,
      'plannedDate': plannedDate.text.trim().isEmpty
          ? null
          : plannedDate.text.trim(),
      'dueDate': dueDate.text.trim().isEmpty ? null : dueDate.text.trim(),
    };
    final original = <String, Object?>{
      'title': widget.title,
      'priority': widget.priority,
      'plannedDate': widget.plannedDate,
      'dueDate': widget.dueDate,
    };
    final changes = <String, Object?>{
      for (final entry in values.entries)
        if (entry.value != original[entry.key]) entry.key: entry.value,
    };
    if (changes.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final commands = await ref.read(commandBusProvider.future);
      await commands.execute(widget.moduleContext, 'task.updateFields', {
        'id': widget.taskId,
        'changes': changes,
      });
      if (!mounted) return;
      setState(() => saving = false);
      Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '保存失败，请重试：$exception';
        });
      }
    }
  }

  Widget _dateField(String label, TextEditingController controller) =>
      TextFormField(
        controller: controller,
        enabled: !saving,
        keyboardType: TextInputType.datetime,
        validator: _validateDate,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'YYYY-MM-DD，可留空',
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '清除$label',
                onPressed: saving ? null : controller.clear,
                icon: const Icon(Icons.clear, size: 18),
              ),
              IconButton(
                tooltip: '选择$label',
                onPressed: saving ? null : () => _pickDate(controller),
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: SafeArea(
      top: false,
      child: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '任务详情',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭详情',
                  onPressed: saving
                      ? null
                      : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: title,
              enabled: !saving,
              minLines: 1,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(labelText: '任务标题'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? '请输入任务标题'
                  : value.trim().length > 300
                  ? '任务标题不能超过 300 个字符'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              borderRadius: AppDesign.selectionBorderRadius,
              initialValue: priority,
              decoration: const InputDecoration(labelText: '优先级'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('无优先级')),
                DropdownMenuItem(value: 1, child: Text('低')),
                DropdownMenuItem(value: 2, child: Text('中')),
                DropdownMenuItem(value: 3, child: Text('高')),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => priority = value!),
            ),
            const SizedBox(height: 20),
            _dateField('计划日', plannedDate),
            const SizedBox(height: 20),
            _dateField('截止日', dueDate),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? '正在保存…' : '保存修改'),
            ),
          ],
        ),
      ),
    ),
  );
}
