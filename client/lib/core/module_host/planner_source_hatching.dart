import 'package:flutter/material.dart';

class PlannerSourceHatching extends CustomPainter {
  const PlannerSourceHatching(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .14)
      ..strokeWidth = .6;
    for (double x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PlannerSourceHatching oldDelegate) =>
      oldDelegate.color != color;
}
