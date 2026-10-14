import 'ui_icon.dart';
import 'native_ui.dart';
import 'ui_design.dart';
import 'ui_toast.dart';

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
  bool copying = false;
  (String, String)? failedCopy;

  Future<void> copy(String code, String label) async {
    if (copying) return;
    setState(() {
      copying = true;
      failedCopy = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        AppToast.show(context, message: '已复制：$label', kind: 'success');
      }
    } catch (_) {
      if (mounted) setState(() => failedCopy = (code, label));
    } finally {
      if (mounted) setState(() => copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return NativeUi(
      child: Dialog(
        insetPadding: AppDesign.dialogInsets,
        shape: AppDesign.smoothShape(radius: AppDesign.floatingRadius),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: (size.height - 96).clamp(120, 800),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: AppDesign.dialogTitlePadding,
                child: Row(
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
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: AppDesign.dialogContentPadding,
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
                                      onPressed: copying
                                          ? null
                                          : () => copy(
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
                                decoration: ShapeDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  shape: AppDesign.smoothShape(),
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
              if (failedCopy case (final code, final label))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '复制失败，请重试',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      NativeUi(
                        child: TextButton(
                          onPressed: () => copy(code, label),
                          child: const Text('重试复制'),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: AppDesign.dialogActionsPadding,
                child: NativeUi(
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('copy-all-code'),
                    onPressed: copying
                        ? null
                        : () => copy(
                            widget.sections
                                .map((section) => section['code'])
                                .join('\n\n'),
                            '全部调用方式',
                          ),
                    icon: const UiIcon(Icons.copy_all_rounded),
                    label: const Text('复制全部'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
