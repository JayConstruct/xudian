import 'dart:ui';

import 'package:flutter/material.dart';

import 'ui_component.dart';
import 'ui_icon.dart';
import 'native_ui.dart';
import 'ui_design.dart';

export 'ui_design.dart';

/// Content groups sit quietly on the canvas; floating controls own the shadows.
class ContentSurface extends StatelessWidget {
  const ContentSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => UiComponent(
    ref: 'ui.card@1',
    slots: {
      'content': Padding(padding: padding ?? EdgeInsets.zero, child: child),
    },
    fallback: Material(
      color: AppDesign.surface(context),
      shape: Theme.of(context).cardTheme.shape ?? AppDesign.smoothShape(),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    ),
  );
}

class DetailPage extends StatelessWidget {
  const DetailPage({
    super.key,
    required this.title,
    required this.child,
    this.leading,
    this.titleMaxLines = 1,
  });

  final String title;
  final Widget child;
  final Widget? leading;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    double? toolbarHeight;
    if (titleMaxLines > 1) {
      final style =
          Theme.of(context).appBarTheme.titleTextStyle ??
          Theme.of(context).textTheme.titleLarge;
      final painter =
          TextPainter(
            text: TextSpan(text: title, style: style),
            maxLines: titleMaxLines,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(
            maxWidth: (MediaQuery.sizeOf(context).width - 112).clamp(
              48,
              double.infinity,
            ),
          );
      toolbarHeight = (painter.height + 16).clamp(
        kToolbarHeight,
        double.infinity,
      );
      painter.dispose();
    }
    return NativeUi(
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: toolbarHeight,
          title: Text(
            title,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
          leading: leading,
          centerTitle: false,
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SizedBox.expand(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: AppDesign.muted(context)),
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    ),
  );
}

class TaskSummary extends StatelessWidget {
  const TaskSummary({super.key, required this.total, required this.completed});

  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
    child: Text(
      completed == 0
          ? '$total 项待办'
          : '${total - completed} 项待办 · $completed 项完成',
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: AppDesign.muted(context)),
    ),
  );
}

class WorkspaceEmptyState extends StatelessWidget {
  const WorkspaceEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.task_alt_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        32,
        24,
        32,
        WorkspaceContentInsets.bottomOf(context) + 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight:
              (constraints.maxHeight -
                      WorkspaceContentInsets.bottomOf(context) -
                      48)
                  .clamp(0, double.infinity),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiIcon(
                icon,
                size: 36,
                color: AppDesign.muted(context).withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppDesign.muted(context)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Space scrollable pages need below their last item to clear the floating dock.
class WorkspaceContentInsets extends InheritedWidget {
  const WorkspaceContentInsets({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkspaceContentInsets>()
          ?.bottom ??
      0;

  @override
  bool updateShouldNotify(WorkspaceContentInsets oldWidget) =>
      bottom != oldWidget.bottom;
}

class FloatingSurface extends StatelessWidget {
  const FloatingSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final surface = AppDesign.surface(context);
    final shape = AppDesign.smoothShape(radius: AppDesign.floatingRadius);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: AppDesign.softShadow(context),
      ),
      child: ClipRSuperellipse(
        borderRadius: shape.borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            shape: shape,
            color: surface.withValues(alpha: 0.91),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class TaskObjectTile extends StatefulWidget {
  const TaskObjectTile({
    super.key,
    required this.title,
    required this.completed,
    required this.onCompleted,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final bool completed;
  final ValueChanged<bool?>? onCompleted;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  State<TaskObjectTile> createState() => _TaskObjectTileState();
}

class _TaskObjectTileState extends State<TaskObjectTile> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: hovered
              ? theme.colorScheme.surfaceContainerHigh
              : widget.completed
              ? theme.colorScheme.surfaceContainerLow
              : theme.colorScheme.surface,
          shape: AppDesign.smoothShape(),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            customBorder: AppDesign.smoothShape(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  NativeUi(
                    child: Checkbox(
                      value: widget.completed,
                      onChanged: widget.onCompleted,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            decoration: widget.completed
                                ? TextDecoration.lineThrough
                                : null,
                            color: widget.completed
                                ? AppDesign.muted(context)
                                : null,
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 3),
                          DefaultTextStyle.merge(
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppDesign.muted(context),
                            ),
                            child: widget.subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
