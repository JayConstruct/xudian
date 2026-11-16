import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'script_ui_scope.dart';
import 'ui_motion.dart';

Map<String, Object?> uiObject(Object? raw, Set<String> fields, String label) {
  if (raw is! Map || raw.keys.any((k) => k is! String || !fields.contains(k))) {
    throw FormatException('Invalid $label fields');
  }
  return raw.cast<String, Object?>();
}

double uiNumber(Object? raw, double min, double max, String label) {
  if (raw is! num || !raw.isFinite || raw < min || raw > max) {
    throw FormatException('Invalid $label');
  }
  return raw.toDouble();
}

class ScriptTiming {
  const ScriptTiming({
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOut,
  });
  final Duration duration;
  final Curve curve;
  factory ScriptTiming.parse(Object? raw) {
    final spec = uiObject(raw, {'duration', 'curve'}, 'timing');
    final duration = spec.containsKey('duration')
        ? uiNumber(spec['duration'], 0, 2000, 'duration')
        : 180.0;
    if (duration != duration.roundToDouble()) {
      throw const FormatException('Duration must be integer milliseconds');
    }
    final curve = switch (spec.containsKey('curve')
        ? spec['curve']
        : 'easeOut') {
      'linear' => Curves.linear,
      'easeIn' => Curves.easeIn,
      'easeOut' => Curves.easeOut,
      'easeInOut' => Curves.easeInOut,
      _ => throw const FormatException('Invalid motion curve'),
    };
    return ScriptTiming(
      duration: Duration(milliseconds: duration.toInt()),
      curve: curve,
    );
  }
}

@immutable
class ScriptMotionValue {
  const ScriptMotionValue({
    this.opacity = 1,
    this.x = 0,
    this.y = 0,
    this.scale = 1,
  });
  final double opacity, x, y, scale;
  factory ScriptMotionValue.parse(Object? raw) {
    final spec = uiObject(raw, {
      'opacity',
      'translateX',
      'translateY',
      'scale',
    }, 'motion target');
    if (spec.isEmpty) {
      throw const FormatException('Motion target cannot be empty');
    }
    double value(String key, double fallback, double min, double max) =>
        spec.containsKey(key) ? uiNumber(spec[key], min, max, key) : fallback;
    return ScriptMotionValue(
      opacity: value('opacity', 1, 0, 1),
      x: value('translateX', 0, -4096, 4096),
      y: value('translateY', 0, -4096, 4096),
      scale: value('scale', 1, .1, 4),
    );
  }
  ScriptMotionValue interpolate(ScriptMotionValue end, double t) =>
      ScriptMotionValue(
        opacity: lerpDouble(opacity, end.opacity, t)!,
        x: lerpDouble(x, end.x, t)!,
        y: lerpDouble(y, end.y, t)!,
        scale: lerpDouble(scale, end.scale, t)!,
      );
  @override
  bool operator ==(Object other) =>
      other is ScriptMotionValue &&
      opacity == other.opacity &&
      x == other.x &&
      y == other.y &&
      scale == other.scale;
  @override
  int get hashCode => Object.hash(opacity, x, y, scale);
}

class ScriptMotion extends StatefulWidget {
  const ScriptMotion({
    super.key,
    required this.target,
    this.timing = const ScriptTiming(),
    required this.child,
  });
  final ScriptMotionValue target;
  final ScriptTiming timing;
  final Widget child;
  @override
  State<ScriptMotion> createState() => _ScriptMotionState();
}

class _ScriptMotionState extends State<ScriptMotion>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, value: 1)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) resources?.release(this);
    });
  late ScriptMotionValue from = widget.target, to = widget.target;
  Curve curve = Curves.easeOut;
  ScriptUiResources? resources;
  bool immediate = false;
  ScriptMotionValue get value =>
      from.interpolate(to, curve.transform(controller.value));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ScriptUiScope.maybeOf(context);
    if (!identical(resources, scope?.resources)) resources?.release(this);
    resources = scope?.resources;
    immediate =
        AppMotion.reduced(context) ||
        !(scope?.active ?? true) ||
        !TickerMode.valuesOf(context).enabled;
    if (immediate) {
      controller.value = 1;
      resources?.release(this);
    }
  }

  @override
  void didUpdateWidget(ScriptMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target == widget.target) return;
    from = value;
    to = widget.target;
    curve = widget.timing.curve;
    controller.duration = widget.timing.duration;
    if (immediate ||
        widget.timing.duration == Duration.zero ||
        resources?.acquire(this) == false) {
      controller.value = 1;
      resources?.release(this);
    } else {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    resources?.release(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (_, child) {
      final current = value;
      return Opacity(
        opacity: current.opacity,
        child: Transform.translate(
          offset: Offset(current.x, current.y),
          child: Transform.scale(scale: current.scale, child: child),
        ),
      );
    },
  );
}

class ScriptButtonFeedback {
  const ScriptButtonFeedback(this.scale, this.duration);
  final double scale;
  final Duration duration;
  factory ScriptButtonFeedback.parse(Object? raw) {
    final spec = uiObject(raw, {'pressedScale', 'duration'}, 'button feedback');
    final scale = spec.containsKey('pressedScale')
        ? uiNumber(spec['pressedScale'], .9, 1, 'pressedScale')
        : .98;
    final duration = spec.containsKey('duration')
        ? uiNumber(spec['duration'], 0, 300, 'feedback duration')
        : 100.0;
    if (duration != duration.roundToDouble()) {
      throw const FormatException('Invalid feedback duration');
    }
    return ScriptButtonFeedback(
      scale,
      Duration(milliseconds: duration.toInt()),
    );
  }
}

/// The actual button still owns activation, semantics, focus and its hit area.
class ScriptFeedbackButton extends StatefulWidget {
  const ScriptFeedbackButton({
    super.key,
    required this.feedback,
    required this.onPressed,
    required this.child,
    this.variant,
    this.style,
  });
  final ScriptButtonFeedback feedback;
  final VoidCallback? onPressed;
  final Widget child;
  final String? variant;
  final ButtonStyle? style;
  @override
  State<ScriptFeedbackButton> createState() => _ScriptFeedbackButtonState();
}

class _ScriptFeedbackButtonState extends State<ScriptFeedbackButton> {
  final states = WidgetStatesController();
  @override
  void initState() {
    super.initState();
    states.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ScriptUiScope.maybeOf(context);
    final active = scope?.active ?? true;
    final child = ScriptMotion(
      target: ScriptMotionValue(
        scale:
            active &&
                widget.onPressed != null &&
                states.value.contains(WidgetState.pressed)
            ? widget.feedback.scale
            : 1,
      ),
      timing: ScriptTiming(duration: widget.feedback.duration),
      child: widget.child,
    );
    final press = active ? widget.onPressed : null;
    return switch (widget.variant) {
      'text' => TextButton(
        onPressed: press,
        statesController: states,
        style: widget.style,
        child: child,
      ),
      'outlined' => OutlinedButton(
        onPressed: press,
        statesController: states,
        style: widget.style,
        child: child,
      ),
      'filled' => FilledButton(
        onPressed: press,
        statesController: states,
        style: widget.style,
        child: child,
      ),
      _ => FilledButton.tonal(
        onPressed: press,
        statesController: states,
        style: widget.style,
        child: child,
      ),
    };
  }
}
