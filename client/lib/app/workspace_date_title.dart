import 'package:flutter/material.dart';

import '../core/ui/animated_date_label.dart';
import '../core/ui/temporal_input.dart';
import '../core/ui/ui_icon.dart';
import '../core/ui/ui_design.dart';
import '../core/ui/native_ui.dart';
import '../core/ui/workspace_typography.dart';

/// Date controls belong to the composition's header, not to an inline section.
class WorkspaceDateTitle extends StatefulWidget {
  const WorkspaceDateTitle({
    super.key,
    required this.title,
    required this.date,
    this.style,
    required this.onEvent,
    this.onEventWithOrigin,
  });

  final String title;
  final String? date;
  final TextStyle? style;
  final ValueChanged<String>? onEvent;
  final void Function(String type, Rect bounds)? onEventWithOrigin;

  @override
  State<WorkspaceDateTitle> createState() => _WorkspaceDateTitleState();
}

class _WorkspaceDateTitleState extends State<WorkspaceDateTitle> {
  final previousKey = GlobalKey(), nextKey = GlobalKey();
  final titleKey = GlobalKey();

  void event(String type, GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (widget.onEventWithOrigin != null && box is RenderBox && box.hasSize) {
      widget.onEventWithOrigin!(
        type,
        box.localToGlobal(Offset.zero) & box.size,
      );
    } else {
      widget.onEvent?.call(type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = parseInputDate(widget.date);
    final enabled = widget.onEvent != null && date != null;
    final titleStyle =
        widget.style ??
        WorkspaceTypography.titleStyle(Theme.of(context).textTheme);
    Widget step(
      String tooltip,
      String eventName,
      GlobalKey key,
      IconData icon,
      bool available,
    ) => IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: available ? () => event(eventName, key) : null,
      icon: UiIcon(icon, size: 20),
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
    );
    final scheme = Theme.of(context).colorScheme;
    return NativeUi(
      child: Row(
        children: [
          Expanded(
            child: KeyedSubtree(
              key: titleKey,
              child: TextButton(
                key: const ValueKey('workspace-date-picker'),
                onPressed: enabled
                    ? () => event('date.choose', titleKey)
                    : null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsetsDirectional.only(
                    top: 8,
                    bottom: 8,
                    end: 4,
                  ),
                  minimumSize: const Size(48, 48),
                  alignment: Alignment.centerLeft,
                  foregroundColor: scheme.onSurface,
                ),
                child: Tooltip(
                  message: '选择日期',
                  child: Semantics(
                    label: widget.title,
                    excludeSemantics: true,
                    child: AnimatedDateLabel(
                      title: widget.title,
                      date: widget.date,
                      maxLines: WorkspaceTypography.titleMaxLines,
                      style: titleStyle,
                      compactWeekday: enabled,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (enabled)
            Material(
              color: scheme.surface,
              shape: AppDesign.smoothShape(
                radius: 15,
                side: BorderSide(color: scheme.outlineVariant, width: .8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  step(
                    '前一天',
                    'date.previous',
                    previousKey,
                    Icons.chevron_left_rounded,
                    widget.date != '0001-01-01',
                  ),
                  SizedBox(
                    height: 18,
                    child: VerticalDivider(
                      width: 1,
                      thickness: .8,
                      color: scheme.outlineVariant,
                    ),
                  ),
                  step(
                    '后一天',
                    'date.next',
                    nextKey,
                    Icons.chevron_right_rounded,
                    widget.date != '9999-12-31',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
