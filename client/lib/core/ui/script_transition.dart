import 'package:flutter/material.dart';

import '../../app/app_motion.dart';

/// Replays a small host-rendered entrance without replacing the child's state.
class ScriptTransition extends StatefulWidget {
  const ScriptTransition({
    super.key,
    required this.child,
    this.effect = 'fade',
    this.visible = true,
    this.replayKey,
    this.duration = AppMotion.scriptTransition,
    this.collapse = false,
  });

  final Widget child;
  final String effect;
  final bool visible;
  final Object? replayKey;
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
          position: widget.effect == 'slide'
              ? Tween(
                  begin: const Offset(0, .12),
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
