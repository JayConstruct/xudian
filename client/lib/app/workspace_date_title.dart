import 'package:flutter/material.dart';

import '../core/ui/animated_date_label.dart';
import '../core/ui/temporal_input.dart';
import '../core/ui/ui_icon.dart';
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = (constraints.maxWidth - (enabled ? 96 : 0) - 12)
            .clamp(1.0, double.infinity);
        final painter = TextPainter(
          text: TextSpan(text: widget.title, style: titleStyle),
          maxLines: WorkspaceTypography.titleMaxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: textWidth);
        final height = (painter.height + 16).clamp(48.0, double.infinity);
        painter.dispose();
        return SizedBox(
          height: height,
          child: NativeUi(
            child: Row(
              children: [
                if (enabled)
                  IconButton(
                    key: previousKey,
                    tooltip: '前一天',
                    onPressed: widget.date == '0001-01-01'
                        ? null
                        : () => event('date.previous', previousKey),
                    icon: const UiIcon(Icons.chevron_left_rounded),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                Expanded(
                  child: KeyedSubtree(
                    key: titleKey,
                    child: TextButton(
                      key: const ValueKey('workspace-date-picker'),
                      onPressed: enabled
                          ? () => event('date.choose', titleKey)
                          : null,
                      style: TextButton.styleFrom(
                        padding: WorkspaceTypography.titlePadding,
                        minimumSize: const Size(48, 48),
                        alignment: Alignment.centerLeft,
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
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (enabled)
                  IconButton(
                    key: nextKey,
                    tooltip: '后一天',
                    onPressed: widget.date == '9999-12-31'
                        ? null
                        : () => event('date.next', nextKey),
                    icon: const UiIcon(Icons.chevron_right_rounded),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
