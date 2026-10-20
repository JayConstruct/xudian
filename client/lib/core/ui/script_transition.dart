import 'package:flutter/material.dart';

import 'ui_motion.dart';

/// Replays a small host-rendered entrance without replacing the child's state.
class ScriptTransition extends StatefulWidget {
  const ScriptTransition({
    super.key,
    required this.child,
    this.effect = 'fade',
    this.visible = true,
    this.replayKey,
    this.navigationDirection,
    Duration? duration,
    this.collapse = false,
  }) : assert(navigationDirection == null || visible && !collapse),
       duration =
           duration ??
           (effect == 'page'
               ? AppMotion.pageTransition
               : AppMotion.scriptTransition);

  final Widget child;
  final String effect;
  final bool visible;
  final Object? replayKey;

  /// Page navigation retains the outgoing view until push/pop motion finishes.
  final String? navigationDirection;
  final Duration duration;
  final bool collapse;

  @override
  State<ScriptTransition> createState() => _ScriptTransitionState();
}

class _ScriptTransitionState extends State<ScriptTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation animation = CurvedAnimation(
    parent: controller,
    curve: AppMotion.enter,
    reverseCurve: AppMotion.leave,
  );
  bool reduceMotion = false;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = AppMotion.reduced(context);
    if (!initialized) {
      initialized = true;
      reduceMotion = reduce;
      _play(replay: true);
    } else if (reduce != reduceMotion) {
      reduceMotion = reduce;
      // Changing accessibility policy finishes the current visibility change;
      // it does not replay an entrance when motion is enabled again.
      controller.value = widget.visible ? 1 : 0;
    }
  }

  void _play({bool replay = false}) {
    if (reduceMotion) {
      controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      controller.forward(from: replay ? 0 : null);
    } else {
      controller.reverse();
    }
  }

  @override
  void didUpdateWidget(ScriptTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.duration = widget.duration;
    if (oldWidget.visible != widget.visible ||
        oldWidget.replayKey != widget.replayKey ||
        oldWidget.effect != widget.effect) {
      _play(
        replay:
            oldWidget.replayKey != widget.replayKey ||
            oldWidget.effect != widget.effect,
      );
    }
  }

  @override
  void dispose() {
    animation.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.effect == 'page' && widget.navigationDirection != null) {
      return _ScriptPageExchange(
        pageKey: widget.replayKey,
        direction: widget.navigationDirection!,
        duration: widget.duration,
        child: widget.child,
      );
    }
    final child = IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeFocus(
        excluding: !widget.visible,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: TickerMode(enabled: widget.visible, child: widget.child),
        ),
      ),
    );
    // Keep the wrapper tree stable when changing effects so focused inputs and
    // other stateful children survive switching the demonstration's animation.
    final content = FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: widget.effect == 'scale'
            ? Tween(begin: .9, end: 1.0).animate(animation)
            : const AlwaysStoppedAnimation(1.0),
        child: SlideTransition(
          position: widget.effect == 'slide' || widget.effect == 'page'
              ? Tween(
                  begin: widget.effect == 'page'
                      ? AppMotion.pageOffset
                      : const Offset(0, .12),
                  end: Offset.zero,
                ).animate(animation)
              : const AlwaysStoppedAnimation(Offset.zero),
          child: child,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: controller,
      child: content,
      builder: (context, child) => Offstage(
        offstage: widget.collapse && !widget.visible && controller.isDismissed,
        child: SizeTransition(
          sizeFactor: widget.collapse
              ? animation
              : const AlwaysStoppedAnimation(1.0),
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
    );
  }
}

/// Match route motion: a push animates its destination, a pop its source.
class _ScriptPageExchange extends StatefulWidget {
  const _ScriptPageExchange({
    required this.pageKey,
    required this.direction,
    required this.duration,
    required this.child,
  });
  final Object? pageKey;
  final String direction;
  final Duration duration;
  final Widget child;
  @override
  State<_ScriptPageExchange> createState() => _ScriptPageExchangeState();
}

class _ScriptPageExchangeState extends State<_ScriptPageExchange>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  )..addStatusListener(_completed);
  late final Animation<double> progress = controller.drive(
    CurveTween(curve: AppMotion.enter),
  );
  Widget? outgoing;
  Object? outgoingKey;
  bool back = false;
  bool reduced = false;

  void _completed(AnimationStatus status) {
    if ((status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) &&
        outgoing != null &&
        mounted) {
      setState(() => outgoing = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = AppMotion.reduced(context);
    if (reduced) {
      outgoing = null;
      controller.value = back ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(_ScriptPageExchange oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.duration = widget.duration;
    if (widget.pageKey == oldWidget.pageKey) return;
    back = widget.direction == 'back';
    outgoing = null;
    outgoingKey = oldWidget.pageKey;
    if (reduced) {
      controller.value = back ? 0 : 1;
    } else if (back) {
      controller.reverse(from: 1);
    } else {
      controller.forward(from: 0);
    }
    outgoing = reduced ? null : oldWidget.child;
  }

  Widget _page(
    Widget child,
    Object? key, {
    required bool active,
    bool animate = false,
  }) {
    Widget result = KeyedSubtree(
      key: ValueKey(key),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      ),
    );
    if (animate) {
      result = FadeTransition(
        opacity: progress,
        child: SlideTransition(
          position: progress.drive(
            Tween(begin: AppMotion.pageOffset, end: Offset.zero),
          ),
          child: result,
        ),
      );
    }
    return IgnorePointer(
      key: ValueKey(key),
      ignoring: !active,
      child: ExcludeFocus(
        excluding: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: TickerMode(enabled: active, child: result),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      if (!back && outgoing != null) _outgoing(animate: false),
      _page(
        widget.child,
        widget.pageKey,
        active: true,
        animate: !back && !reduced,
      ),
      if (back && outgoing != null) _outgoing(animate: true),
    ],
  );

  Widget _outgoing({required bool animate}) => Positioned.fill(
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: _page(outgoing!, outgoingKey, active: false, animate: animate),
      ),
    ),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
