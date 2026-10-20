import 'package:flutter/material.dart';

import '../core/ui/ui_motion.dart';

/// Toolbar visibility has its own timeline; scrolling only changes its target.
class WorkspaceToolbarTransition extends StatefulWidget {
  const WorkspaceToolbarTransition({
    super.key,
    required this.visible,
    required this.builder,
  });

  final bool visible;
  final Widget Function(BuildContext context, double presence) builder;

  @override
  State<WorkspaceToolbarTransition> createState() =>
      _WorkspaceToolbarTransitionState();
}

class _WorkspaceToolbarTransitionState extends State<WorkspaceToolbarTransition>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
    duration: AppMotion.pageTransition,
  );
  late final animation = CurvedAnimation(
    parent: controller,
    curve: AppMotion.enter,
    reverseCurve: AppMotion.leave,
  );

  void _update() {
    if (AppMotion.reduced(context)) {
      controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(WorkspaceToolbarTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _update();
  }

  @override
  void dispose() {
    animation.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) => widget.builder(context, animation.value),
  );
}
