import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppDesign {
  static const brand = Color(0xFF52699C);
  static const lightCanvas = Color(0xFFF1F3F5);
  static const darkCanvas = Color(0xFF191C20);
  static const compactRadius = 12.0;
  static const controlRadius = 14.0;
  static const radius = 16.0;
  static const selectionRadius = 20.0;
  static const floatingRadius = 24.0;
  static const dockRadius = 28.0;

  /// Shared continuous curve for surfaces, outlines, shadows and ink effects.
  static RoundedSuperellipseBorder smoothShape({
    double radius = AppDesign.radius,
    BorderSide side = BorderSide.none,
  }) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(radius),
    side: side,
  );

  static Color canvas(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkCanvas
      : lightCanvas;

  static Color surface(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: brightness,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: dark ? darkCanvas : lightCanvas,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  static List<BoxShadow> softShadow(BuildContext context) => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.055,
      ),
      blurRadius: 28,
      offset: const Offset(0, 9),
    ),
  ];
}

/// Content groups sit quietly on the canvas; floating controls own the shadows.
class ContentSurface extends StatelessWidget {
  const ContentSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Material(
    color: AppDesign.surface(context),
    shape: AppDesign.smoothShape(),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
  );
}

class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), centerTitle: false),
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
  );
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
              Icon(
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
                  Checkbox(
                    value: widget.completed,
                    onChanged: widget.onCompleted,
                    visualDensity: VisualDensity.compact,
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
