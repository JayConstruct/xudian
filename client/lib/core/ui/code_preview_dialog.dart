import 'ui_icon.dart';
import 'native_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showCodePreviewDialog(
  BuildContext context,
  Map<String, Object?> spec,
) => showDialog<void>(
  context: context,
  builder: (_) => CodePreviewDialog(
    title: spec['title'] as String,
    sections: [
      for (final section in spec['sections'] as List)
        Map<String, Object?>.from(section as Map),
    ],
  ),
);

class CodePreviewDialog extends StatefulWidget {
  const CodePreviewDialog({
    super.key,
    required this.title,
    required this.sections,
  });

  final String title;
  final List<Map<String, Object?>> sections;

  @override
  State<CodePreviewDialog> createState() => _CodePreviewDialogState();
}

class _CodePreviewDialogState extends State<CodePreviewDialog> {
  String? copied;

  Future<void> copy(String code, String label) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) setState(() => copied = label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return NativeUi(
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: (size.height - 96).clamp(120, 800),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: widget.title,
                        child: Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ),
                    NativeUi(
                      child: IconButton(
                        tooltip: '关闭调用方式',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const UiIcon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, section) in widget.sections.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        section['title'] as String,
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ),
                                    NativeUi(
                                      child: TextButton.icon(
                                        key: ValueKey('copy-code-$index'),
                                        onPressed: () => copy(
                                          section['code'] as String,
                                          section['title'] as String,
                                        ),
                                        icon: const UiIcon(
                                          Icons.copy_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('复制'),
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: SelectableText(
                                    section['code'] as String,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (copied != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '已复制：$copied',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                NativeUi(
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('copy-all-code'),
                    onPressed: () => copy(
                      widget.sections
                          .map((section) => section['code'])
                          .join('\n\n'),
                      '全部调用方式',
                    ),
                    icon: const UiIcon(Icons.copy_all_rounded),
                    label: const Text('复制全部'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
