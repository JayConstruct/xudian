import 'package:flutter/material.dart';

import 'app_motion.dart';

/// A programmatic workspace transition. It owns no pointer recognizers, so
/// horizontal gestures inside a module remain entirely with that module.
class WorkspacePageTransition extends StatefulWidget {
  const WorkspacePageTransition({
    super.key,
    required this.destinationId,
    required this.order,
    required this.child,
    this.backgroundColor,
  });

  final String destinationId;
  final int order;
  final Widget child;
  final Color? backgroundColor;

  @override
  State<WorkspacePageTransition> createState() =>
      _WorkspacePageTransitionState();
}

class _WorkspacePageTransitionState extends State<WorkspacePageTransition>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: AppMotion.workspaceTransition,
    value: 1,
  )..addStatusListener(_animationStatusChanged);
  final frames = <String, _WorkspaceFrame>{};
  bool reduceMotion = false;
  TextDirection textDirection = TextDirection.ltr;

  double get progress => AppMotion.enter.transform(controller.value);

  @override
  void initState() {
    super.initState();
    frames[widget.destinationId] = _WorkspaceFrame(widget.child, 0, 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = AppMotion.reduced(context);
    textDirection = Directionality.of(context);
    if (reduceMotion) _finishImmediately();
  }

  @override
  void didUpdateWidget(WorkspacePageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinationId == widget.destinationId) {
      frames[widget.destinationId]!.child = widget.child;
      return;
    }
    if (reduceMotion) {
      _finishImmediately();
      return;
    }
    final direction =
        (widget.order >= oldWidget.order ? 1.0 : -1.0) *
        (textDirection == TextDirection.rtl ? -1 : 1);
    final currentProgress = progress;
    for (final frame in frames.values) {
      frame.start = frame.position(currentProgress);
      frame.end = -direction;
    }
    // A rapid return to a still-visible page reuses its element and begins at
    // its current painted position instead of mounting a second copy.
    final incoming = frames.putIfAbsent(
      widget.destinationId,
      () => _WorkspaceFrame(widget.child, direction, 0),
    );
    incoming.child = widget.child;
    incoming.end = 0;
    controller.forward(from: 0);
  }

  void _finishImmediately() {
    controller.stop();
    frames
      ..clear()
      ..[widget.destinationId] = _WorkspaceFrame(widget.child, 0, 0);
    controller.value = 1;
  }

  void _animationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      frames.removeWhere((id, _) => id != widget.destinationId);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.topLeft,
        children: [
          for (final id in [
            ...frames.keys.where((id) => id != widget.destinationId),
            widget.destinationId,
          ])
            FractionalTranslation(
              key: ValueKey(id),
              translation: Offset(frames[id]!.position(progress), 0),
              child: IgnorePointer(
                ignoring: id != widget.destinationId,
                child: ExcludeSemantics(
                  excluding: id != widget.destinationId,
                  child: TickerMode(
                    enabled: id == widget.destinationId,
                    child: RepaintBoundary(
                      child: Material(
                        color: widget.backgroundColor ?? Colors.transparent,
                        child: frames[id]!.child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _WorkspaceFrame {
  _WorkspaceFrame(this.child, this.start, this.end);
  Widget child;
  double start, end;

  double position(double progress) => start + (end - start) * progress;
}
