import 'package:flutter/material.dart';

import 'native_ui.dart';
import 'ui_icon.dart';
import 'ui_surfaces.dart';

/// Compact, theme-based presentation shared by script conversation interfaces.
class ConversationMessage extends StatelessWidget {
  const ConversationMessage({
    super.key,
    required this.text,
    required this.outgoing,
    required this.label,
  });

  final String text, label;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: outgoing ? .88 : 1,
        child: Column(
          crossAxisAlignment: outgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!outgoing) ...[
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
            ],
            Material(
              color: outgoing
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerLow,
              shape: AppDesign.smoothShape(radius: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: SelectableText(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationComposer extends StatelessWidget {
  const ConversationComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.busy,
    required this.onChanged,
    required this.onSend,
    required this.onCancel,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool busy, enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => FloatingSurface(
    padding: const EdgeInsets.all(6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: NativeUi(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => NativeUi(
            child: IconButton.filled(
              tooltip: busy ? '取消当前操作' : '发送',
              onPressed: busy
                  ? onCancel
                  : enabled && value.text.trim().isNotEmpty
                  ? onSend
                  : null,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: UiIcon(
                busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
