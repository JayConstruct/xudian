import 'package:flutter/material.dart';

import 'app_motion.dart';
import '../core/ui/page_first_frame.dart';

/// A programmatic workspace transition. It owns no pointer recognizers, so
/// horizontal gestures inside a module remain entirely with that module.
class WorkspacePageTransition extends StatefulWidget {
  const WorkspacePageTransition({
    super.key,
    required this.destinationId,
    required this.order,
    required this.child,
    this.backgroundColor,
    this.maxRetainedPages = 1,
    this.retentionKeys,
    this.deferUntilReady = false,
  }) : assert(maxRetainedPages >= 1);

  final String destinationId;
  final int order;
  final Widget child;
  final Color? backgroundColor;

  /// Retain a bounded set of visited pages, including their real widget state.
  /// Hidden pages stop ticking and cannot receive input or accessibility focus.
  final int maxRetainedPages;

  /// When supplied, removed or changed identities dispose their cached page.
  /// The application includes module generation, layout and stable context.
  final Map<String, Object?>? retentionKeys;

  /// Keep the outgoing content visible while a first visit prepares its frame.
  /// Returning to an already rendered page starts the transition immediately.
  final bool deferUntilReady;

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
  bool waitingForReady = false;
  double pendingDirection = 1;

  double get progress => AppMotion.enter.transform(controller.value);

  @override
  void initState() {
    super.initState();
    frames[widget.destinationId] = _newFrame(0);
  }

  _WorkspaceFrame _newFrame(double start) => _WorkspaceFrame(
    widget.child,
    start,
    0,
    widget.retentionKeys?[widget.destinationId],
  );

  void _pruneInvalidFrames() {
    final keys = widget.retentionKeys;
    if (keys == null) return;
    frames.removeWhere(
      (id, frame) => !keys.containsKey(id) || keys[id] != frame.retentionKey,
    );
  }

  void _trimFrames() {
    for (final id in frames.keys.toList()) {
      if (frames.length <= widget.maxRetainedPages) break;
      if (id != widget.destinationId) frames.remove(id);
    }
  }

  void _touch(String id) {
    final frame = frames.remove(id);
    if (frame != null) frames[id] = frame;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = AppMotion.reduced(context);
    textDirection = Directionality.of(context);
    if (reduceMotion && !waitingForReady) _finishImmediately();
  }

  @override
  void didUpdateWidget(WorkspacePageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pruneInvalidFrames();
    if (oldWidget.destinationId == widget.destinationId) {
      final frame = frames.putIfAbsent(
        widget.destinationId,
        () => _newFrame(0),
      );
      frame.child = widget.child;
      if (!waitingForReady) frame.visible = true;
      _touch(widget.destinationId);
      if (!controller.isAnimating && !waitingForReady) _trimFrames();
      return;
    }
    final direction =
        (widget.order >= oldWidget.order ? 1.0 : -1.0) *
        (textDirection == TextDirection.rtl ? -1 : 1);
    final incoming = frames.putIfAbsent(
      widget.destinationId,
      () => _newFrame(direction)..visible = false,
    );
    incoming.child = widget.child;
    _touch(widget.destinationId);
    if (widget.deferUntilReady && !incoming.ready) {
      final currentProgress = progress;
      controller.stop();
      for (final frame in frames.values.where((frame) => frame.visible)) {
        frame.start = frame.end = frame.position(currentProgress);
      }
      waitingForReady = true;
      pendingDirection = direction;
      return;
    }
    if (reduceMotion) {
      _finishImmediately();
    } else {
      _startTransition(direction);
    }
  }

  void _startTransition(double direction) {
    waitingForReady = false;
    final currentProgress = progress;
    for (final frame in frames.values.where((frame) => frame.visible)) {
      frame.start = frame.position(currentProgress);
      frame.end = -direction;
    }
    // A rapid return to a still-visible page reuses its element and begins at
    // its current painted position instead of mounting a second copy.
    final incoming = frames.putIfAbsent(
      widget.destinationId,
      () => _newFrame(direction),
    );
    if (!incoming.visible) incoming.start = direction;
    incoming.child = widget.child;
    incoming.end = 0;
    incoming.visible = true;
    _touch(widget.destinationId);
    controller.forward(from: 0);
  }

  void _frameReady(String id, _WorkspaceFrame frame) {
    if (!mounted || !identical(frames[id], frame)) return;
    frame.ready = true;
    if (waitingForReady && id == widget.destinationId) {
      setState(() {
        if (reduceMotion) {
          _finishImmediately();
        } else {
          _startTransition(pendingDirection);
        }
      });
    }
  }

  VoidCallback _readyCallback(String id, _WorkspaceFrame frame) =>
      () => _frameReady(id, frame);

  void _finishImmediately() {
    controller.stop();
    waitingForReady = false;
    _pruneInvalidFrames();
    final current = frames.putIfAbsent(
      widget.destinationId,
      () => _newFrame(0),
    );
    current.child = widget.child;
    for (final entry in frames.entries) {
      entry.value.visible = entry.key == widget.destinationId;
    }
    current.start = current.end = 0;
    _touch(widget.destinationId);
    _trimFrames();
    controller.value = 1;
  }

  void _animationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (waitingForReady) return;
    setState(() {
      for (final entry in frames.entries) {
        entry.value.visible = entry.key == widget.destinationId;
      }
      _trimFrames();
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
                child: ExcludeFocus(
                  excluding: id != widget.destinationId,
                  child: ExcludeSemantics(
                    excluding: id != widget.destinationId,
                    child: TickerMode(
                      enabled: id == widget.destinationId,
                      child: Offstage(
                        offstage: !frames[id]!.visible,
                        child: RepaintBoundary(
                          child: Material(
                            color: widget.backgroundColor ?? Colors.transparent,
                            child: KeyedSubtree(
                              key: ObjectKey(frames[id]!),
                              child: PageFirstFrameScope(
                                onReady: _readyCallback(id, frames[id]!),
                                child: frames[id]!.child,
                              ),
                            ),
                          ),
                        ),
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
  _WorkspaceFrame(this.child, this.start, this.end, this.retentionKey);
  Widget child;
  double start, end;
  final Object? retentionKey;
  bool visible = true;
  bool ready = false;

  double position(double progress) => start + (end - start) * progress;
}
