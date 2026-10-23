import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/ui_motion.dart';

/// A paint-only edge marker. Its child keeps exactly the same layout in both
/// states; callers choose a free corner for unusually compact presentations.
class PlannerStatusIndicator extends StatefulWidget {
  const PlannerStatusIndicator({
    super.key,
    required this.child,
    required this.completed,
    required this.color,
    this.badgeSize = 16,
    this.railWidth = 3,
    this.leadingLabelWidth,
    this.badgeAtBottom = false,
  });

  final Widget child;
  final bool completed;
  final Color color;
  final double badgeSize;
  final double railWidth;
  final double? leadingLabelWidth;
  final bool badgeAtBottom;

  @override
  State<PlannerStatusIndicator> createState() => _PlannerStatusIndicatorState();
}

class _PlannerStatusIndicatorState extends State<PlannerStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(
    vsync: this,
    value: widget.completed ? 1 : 0,
    duration: const Duration(milliseconds: 280),
  );

  void _update() {
    final target = widget.completed ? 1.0 : 0.0;
    if (AppMotion.reduced(context)) {
      _progress.value = target;
    } else {
      // Reversing an in-flight change continues from the current shape.
      _progress.animateTo(
        target,
        duration: Duration(
          microseconds: (280000 * (target - _progress.value).abs()).round(),
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) _update();
  }

  @override
  void didUpdateWidget(PlannerStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.completed != widget.completed) _update();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _StatusPainter(
      progress: _progress,
      color: widget.color,
      badgeSize: widget.badgeSize,
      railWidth: widget.railWidth,
      leadingLabelWidth: widget.leadingLabelWidth,
      badgeAtBottom: widget.badgeAtBottom,
    ),
    child: widget.child,
  );
}

class _StatusPainter extends CustomPainter {
  _StatusPainter({
    required this.progress,
    required this.color,
    required this.badgeSize,
    required this.railWidth,
    required this.leadingLabelWidth,
    required this.badgeAtBottom,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double badgeSize;
  final double railWidth;
  final double? leadingLabelWidth;
  final bool badgeAtBottom;

  double _phase(double from, double to) =>
      ((progress.value - from) / (to - from)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const inset = 3.0;
    final safeBadgeSize = leadingLabelWidth == null
        ? badgeSize
        : math.min(
            badgeSize,
            math.max(railWidth, size.width - leadingLabelWidth! - inset),
          );
    final extent = math.min(
      safeBadgeSize,
      math.min(size.width - inset * 2, size.height - inset * 2),
    );
    if (extent <= 0) return;
    // Shrink entirely within the right padding before widening in the corner.
    // Overlapping these phases would briefly paint over the title on tall cards.
    final shrink = Curves.easeInOutCubic.transform(_phase(0, .5));
    final widen = Curves.easeInOutCubic.transform(_phase(.5, .8));
    final width = railWidth + (extent - railWidth) * widen;
    final height = (size.height - inset * 2) * (1 - shrink) + extent * shrink;
    // Pending rails live inside the existing right padding. A tiny completed
    // marker stays there too; regular badges use the free time-row corner.
    final right =
        size.width - math.min(inset, math.max(0, extent - railWidth)) * widen;
    final top = badgeAtBottom ? size.height - inset - height : inset;
    final rect = Rect.fromLTWH(right - width, top, width, height);
    final ink = Color.lerp(
      color,
      const Color(0xff343b47),
      Curves.easeInOut.transform(_phase(.38, .8)),
    )!;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(9)),
    );
    // Keep antialiasing within the declared free area, including subpixel
    // corners on very narrow columns.
    canvas.clipRect(rect, doAntiAlias: false);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(1.5 + (4 - 1.5) * widen)),
      Paint()..color = ink,
    );
    final check = Curves.easeOut.transform(_phase(.72, 1));
    if (check == 0) {
      canvas.restore();
      return;
    }
    final path = Path()
      ..moveTo(rect.left + rect.width * .25, rect.top + rect.height * .51)
      ..lineTo(rect.left + rect.width * .43, rect.top + rect.height * .69)
      ..lineTo(rect.left + rect.width * .76, rect.top + rect.height * .32);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * check),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, extent * .125)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_StatusPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      badgeSize != oldDelegate.badgeSize ||
      railWidth != oldDelegate.railWidth ||
      leadingLabelWidth != oldDelegate.leadingLabelWidth ||
      badgeAtBottom != oldDelegate.badgeAtBottom;
}
