import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// Motion primitives for the native dock. Retargeting an active spring keeps
/// its ticker running, so frequent pointer moves cannot stall the first frame.
class DockSpring extends ChangeNotifier {
  DockSpring(TickerProvider vsync, double initial)
    : value = initial,
      target = initial {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  SpringSimulation? _simulation;
  SpringDescription? _spring;
  Duration _lastFrame = Duration.zero;
  Duration _retargetedAt = Duration.zero;
  double value, target;
  double velocity = 0;

  void moveTo(
    double destination,
    SpringDescription spring, {
    bool animate = true,
  }) {
    if (!animate) {
      jumpTo(destination);
      return;
    }
    if (destination == target &&
        ((_simulation != null && identical(_spring, spring)) ||
            (_simulation == null && value == target))) {
      return;
    }
    target = destination;
    _spring = spring;
    _simulation = SpringSimulation(
      spring,
      value,
      target,
      velocity,
      snapToEnd: true,
    );
    if (_ticker.isActive) {
      _retargetedAt = _lastFrame;
    } else {
      _lastFrame = _retargetedAt = Duration.zero;
      _ticker.start();
    }
  }

  void jumpTo(double destination) {
    _ticker.stop();
    _simulation = null;
    _spring = null;
    final changed = value != destination || velocity != 0;
    value = target = destination;
    velocity = 0;
    if (changed) notifyListeners();
  }

  void _tick(Duration elapsed) {
    _lastFrame = elapsed;
    final simulation = _simulation!;
    final seconds = (elapsed - _retargetedAt).inMicroseconds / 1000000;
    if (simulation.isDone(seconds)) {
      value = target;
      velocity = 0;
      _simulation = null;
      _ticker.stop();
    } else {
      value = simulation.x(seconds);
      velocity = simulation.dx(seconds);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

abstract final class DockPhysics {
  static final tracking = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 120),
  );
  static final lifting = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 280),
    bounce: .2,
  );
  static final settling = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 500),
    bounce: .32,
  );

  /// Diminishing displacement, bounded even when dragged far off the dock.
  static double resistance(double displacement, double limit) {
    if (limit <= 0) return 0;
    return displacement * limit / (limit + displacement.abs() * .6);
  }
}

/// Changes paint and keeps hit targets and reported toolbar size at rest.
class DockElasticSurface extends StatefulWidget {
  const DockElasticSurface({
    super.key,
    required this.enabled,
    required this.child,
    this.edgePullOnly = false,
  });

  final bool enabled, edgePullOnly;
  final Widget child;

  @override
  State<DockElasticSurface> createState() => _DockElasticSurfaceState();
}

class _DockElasticSurfaceState extends State<DockElasticSurface>
    with TickerProviderStateMixin {
  late final lift = DockSpring(this, 0);
  late final x = DockSpring(this, 0);
  late final y = DockSpring(this, 0);
  late final motion = Listenable.merge([lift, x, y]);
  int? pointer;
  Offset origin = Offset.zero;

  @override
  void didUpdateWidget(DockElasticSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      pointer = null;
      lift.jumpTo(0);
      x.jumpTo(0);
      y.jumpTo(0);
    }
  }

  void _down(PointerDownEvent event) {
    if (!mounted ||
        !widget.enabled ||
        pointer != null ||
        event.buttons & kPrimaryButton == 0) {
      return;
    }
    pointer = event.pointer;
    origin = event.localPosition;
    lift.moveTo(1, DockPhysics.lifting);
  }

  void _move(PointerMoveEvent event) {
    if (pointer != event.pointer) return;
    final size = context.size;
    if (size == null) return;
    final movement = widget.edgePullOnly
        ? Offset(
            event.localPosition.dx -
                event.localPosition.dx.clamp(0.0, size.width),
            0,
          )
        : event.localPosition - origin;
    final limit = size.shortestSide * .14;
    x.moveTo(DockPhysics.resistance(movement.dx, limit), DockPhysics.tracking);
    y.moveTo(DockPhysics.resistance(movement.dy, limit), DockPhysics.tracking);
  }

  void _up(PointerEvent event) {
    if (pointer != event.pointer) return;
    pointer = null;
    lift.moveTo(0, DockPhysics.settling);
    x.moveTo(0, DockPhysics.settling);
    y.moveTo(0, DockPhysics.settling);
  }

  @override
  void dispose() {
    pointer = null;
    lift.dispose();
    x.dispose();
    y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: motion,
        child: widget.child,
        builder: (context, child) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          if (width <= 0 || height <= 0) return child!;
          final scale =
              1 + lift.value * math.min(.25, 16 / math.max(width, height));
          return Transform(
            alignment: Alignment.center,
            transformHitTests: false,
            transform: Matrix4.diagonal3Values(
              scale * (1 + x.value.abs() / width * .5),
              scale * (1 + y.value.abs() / height * .5),
              1,
            )..setTranslationRaw(x.value, y.value, 0),
            child: child,
          );
        },
      ),
    ),
  );
}
