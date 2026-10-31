import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Optional visual configuration. Task states and labels belong to the module.
class PlannerCardAppearance {
  const PlannerCardAppearance({
    this.dashed = false,
    this.lineThrough = false,
    this.cornerIcon = '',
    this.badgeText = '',
  });

  factory PlannerCardAppearance.of(Map<String, Object?> item) {
    final value = item['appearance'];
    if (value is! Map) return const PlannerCardAppearance();
    return PlannerCardAppearance(
      dashed: value['borderStyle'] == 'dashed',
      lineThrough: value['titleDecoration'] == 'lineThrough',
      cornerIcon: switch (value['cornerIcon']) {
        'slash' => 'slash',
        'check' => 'check',
        _ => '',
      },
      badgeText: value['badgeText'] is String
          ? value['badgeText'] as String
          : '',
    );
  }

  final bool dashed, lineThrough;
  final String cornerIcon, badgeText;
  bool get decorated => dashed || cornerIcon.isNotEmpty || badgeText.isNotEmpty;
}

/// Paints an outline and status marks without changing card or text geometry.
/// Corner marks and labels only use the free space beside the time labels.
class PlannerCardDecoration extends StatelessWidget {
  const PlannerCardDecoration({
    super.key,
    required this.appearance,
    required this.child,
    required this.color,
    required this.surface,
    required this.textStyle,
    required this.textDirection,
    required this.textScaler,
    this.selectedColor,
    this.leadingLabelWidth = 0,
    this.badgeSize = 16,
    this.full = true,
  });

  final PlannerCardAppearance appearance;
  final Widget child;
  final Color color, surface;
  final Color? selectedColor;
  final TextStyle textStyle;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final double leadingLabelWidth, badgeSize;
  final bool full;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _CardAppearancePainter(this),
    child: child,
  );
}

class _CardAppearancePainter extends CustomPainter {
  _CardAppearancePainter(this.config);

  final PlannerCardDecoration config;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final appearance = config.appearance;
    if (appearance.dashed) {
      final outline = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            (Offset.zero & size).deflate(
              math.min(.7, math.min(size.width, size.height) / 4),
            ),
            const Radius.circular(8.3),
          ),
        );
      final paint = Paint()
        ..color = config.selectedColor ?? config.color.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = config.selectedColor == null ? 1 : 1.5
        ..strokeCap = StrokeCap.round;
      for (final metric in outline.computeMetrics()) {
        for (double offset = 0; offset < metric.length; offset += 7) {
          canvas.drawPath(
            metric.extractPath(offset, math.min(offset + 4, metric.length)),
            paint,
          );
        }
      }
    }
    const inset = 3.0;
    final freeWidth = math.max(
      0.0,
      size.width - config.leadingLabelWidth - inset * 2,
    );
    final extent = math.min(
      config.badgeSize,
      math.min(freeWidth, size.height - inset * 2),
    );
    if (appearance.cornerIcon.isNotEmpty && extent >= 7) {
      final rect = Rect.fromLTWH(
        size.width - inset - extent,
        config.full ? inset : size.height - inset - extent,
        extent,
        extent,
      );
      final paint = Paint()
        ..color = config.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, extent * .1)
        ..strokeCap = StrokeCap.round;
      if (appearance.cornerIcon == 'slash') {
        canvas.drawCircle(rect.center, extent * .4, paint);
        canvas.drawLine(
          Offset(rect.left + extent * .23, rect.top + extent * .23),
          Offset(rect.left + extent * .77, rect.top + extent * .77),
          paint,
        );
      } else {
        canvas.drawPath(
          Path()
            ..moveTo(rect.left + extent * .18, rect.top + extent * .5)
            ..lineTo(rect.left + extent * .42, rect.top + extent * .72)
            ..lineTo(rect.left + extent * .82, rect.top + extent * .25),
          paint,
        );
      }
    }
    if (!config.full || appearance.badgeText.isEmpty) return;
    final text = TextPainter(
      text: TextSpan(
        text: appearance.badgeText,
        style: config.textStyle.copyWith(
          color: config.color,
          fontSize: 9,
          height: 1.1,
        ),
      ),
      textDirection: config.textDirection,
      textScaler: config.textScaler,
      maxLines: 1,
    )..layout();
    final width = text.width + 10, height = text.height + 4;
    if (width <= freeWidth && height + extent + inset * 3 < size.height) {
      final rect = Rect.fromLTWH(
        size.width - inset - width,
        size.height - inset - height,
        width,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..color = Color.alphaBlend(
            config.color.withValues(alpha: .08),
            config.surface,
          ),
      );
      text.paint(canvas, Offset(rect.left + 5, rect.top + 2));
    }
    text.dispose();
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_CardAppearancePainter oldDelegate) =>
      config.appearance.dashed != oldDelegate.config.appearance.dashed ||
      config.appearance.cornerIcon !=
          oldDelegate.config.appearance.cornerIcon ||
      config.appearance.badgeText != oldDelegate.config.appearance.badgeText ||
      config.color != oldDelegate.config.color ||
      config.surface != oldDelegate.config.surface ||
      config.selectedColor != oldDelegate.config.selectedColor ||
      config.leadingLabelWidth != oldDelegate.config.leadingLabelWidth ||
      config.badgeSize != oldDelegate.config.badgeSize ||
      config.full != oldDelegate.config.full ||
      config.textStyle != oldDelegate.config.textStyle ||
      config.textScaler != oldDelegate.config.textScaler ||
      config.textDirection != oldDelegate.config.textDirection;
}
