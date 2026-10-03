import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/module_context.dart';
import 'application/providers.dart';

class QuickTaskInput extends ConsumerStatefulWidget {
  const QuickTaskInput({
    super.key,
    this.controller,
    required this.hintText,
    this.defaults = const {},
    this.moduleContext = const ModuleContext.system(),
  });

  final TextEditingController? controller;
  final String hintText;
  final Map<String, Object?> defaults;
  final ModuleContext moduleContext;

  @override
  ConsumerState<QuickTaskInput> createState() => _QuickTaskInputState();
}

class _QuickTaskInputState extends ConsumerState<QuickTaskInput> {
  late final TextEditingController controller =
      widget.controller ?? TextEditingController();
  bool submitting = false;

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (submitting) return;
    final draft = controller.text;
    final title = draft.trim();
    if (title.isEmpty) return;
    if (title.length > 300) {
      _showError('任务标题不能超过 300 个字符');
      return;
    }
    // Capture the destination before awaiting: navigation may change meanwhile.
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final payload = <String, Object?>{
      for (final entry in widget.defaults.entries)
        entry.key: entry.value == r'$today' ? today : entry.value,
      'title': title,
    };
    final moduleContext = widget.moduleContext;
    setState(() {
      submitting = true;
    });
    try {
      final commands = await ref.read(commandBusProvider.future);
      await commands.execute(moduleContext, 'task.create', payload);
      if (!mounted) return;
      // Do not erase a new draft typed while the previous task was saving.
      if (controller.text == draft) controller.clear();
    } catch (exception) {
      if (mounted) _showError('添加失败，请重试：$exception');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: controller,
          style: Theme.of(context).textTheme.bodyMedium,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.add_rounded, size: 20),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => IconButton.filled(
          tooltip: submitting ? '正在添加' : '添加任务',
          onPressed: submitting || value.text.trim().isEmpty ? null : _submit,
          icon: submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_upward_rounded, size: 20),
        ),
      ),
    ],
  );
}
