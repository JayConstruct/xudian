import 'package:flutter/material.dart';

import 'app_motion.dart';

import '../core/ui/temporal_input.dart';
import '../core/ui/ui_icon.dart';
import '../core/ui/native_ui.dart';

/// Date controls belong to the composition's header, not to an inline section.
class WorkspaceDateTitle extends StatefulWidget {
  const WorkspaceDateTitle({
    super.key,
    required this.title,
    required this.date,
    required this.style,
    required this.onEvent,
  });

  final String title;
  final String? date;
  final TextStyle style;
  final ValueChanged<String>? onEvent;

  @override
  State<WorkspaceDateTitle> createState() => _WorkspaceDateTitleState();
}

class _WorkspaceDateTitleState extends State<WorkspaceDateTitle> {
  double direction = 1;

  @override
  void didUpdateWidget(WorkspaceDateTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.date != oldWidget.date &&
        widget.date != null &&
        oldWidget.date != null) {
      direction = widget.date!.compareTo(oldWidget.date!) < 0 ? -1 : 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = parseInputDate(widget.date);
    final enabled = widget.onEvent != null && date != null;
    final duration = AppMotion.duration(context, AppMotion.dateChange);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = (constraints.maxWidth - (enabled ? 96 : 0) - 12)
            .clamp(1.0, double.infinity);
        final painter = TextPainter(
          text: TextSpan(text: widget.title, style: widget.style),
          maxLines: 3,
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
                    tooltip: '前一天',
                    onPressed: widget.date == '0001-01-01'
                        ? null
                        : () => widget.onEvent!('date.previous'),
                    icon: const UiIcon(Icons.chevron_left_rounded),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('workspace-date-picker'),
                    onPressed: enabled
                        ? () => widget.onEvent!('date.choose')
                        : null,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      minimumSize: const Size(48, 48),
                      alignment: Alignment.centerLeft,
                    ),
                    child: Tooltip(
                      message: '选择日期',
                      child: Semantics(
                        label: widget.title,
                        excludeSemantics: true,
                        child: AnimatedSwitcher(
                          duration: duration,
                          switchInCurve: AppMotion.enter,
                          switchOutCurve: AppMotion.leave,
                          // Rapid changes keep only the most recent departing
                          // label. Accessibility always announces the current one.
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              if (previous.isNotEmpty) previous.last,
                              ?current,
                            ],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: Offset(direction * .12, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Text(
                            widget.title,
                            key: ValueKey(widget.date),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: widget.style,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (enabled)
                  IconButton(
                    tooltip: '后一天',
                    onPressed: widget.date == '9999-12-31'
                        ? null
                        : () => widget.onEvent!('date.next'),
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
