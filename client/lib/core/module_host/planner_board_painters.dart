part of 'planner_board.dart';

class _BoardLines extends CustomPainter {
  _BoardLines(
    this.columnWidth,
    this.scale,
    this.startMinute,
    this.color, {
    this.interval = 30,
  });
  final int interval;
  final double columnWidth, scale;
  final int startMinute;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .6)
      ..strokeWidth = .5;
    for (double x = 0; x <= size.width; x += columnWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (
      var minute = ((startMinute + interval - 1) ~/ interval) * interval;
      (minute - startMinute) * scale < size.height;
      minute += interval
    ) {
      final y = (minute - startMinute) * scale;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_BoardLines old) =>
      old.interval != interval ||
      old.columnWidth != columnWidth ||
      old.scale != scale ||
      old.startMinute != startMinute ||
      old.color != color;
}

class _DenseOccupancy extends CustomPainter {
  _DenseOccupancy(
    this.group,
    this.color,
    this.visibleTop,
    this.visibleBottom, {
    this.shortBands = false,
  });
  final bool shortBands;
  final BoardGroup group;
  final Color color;
  final double visibleTop, visibleBottom;
  @override
  void paint(Canvas canvas, Size size) {
    final width = shortBands ? size.width : size.width / group.lanes;
    final fill = Paint()..color = color.withValues(alpha: .13);
    for (final segment in group.segments) {
      if (segment.top > visibleBottom) break;
      if (segment.bottom < visibleTop) continue;
      final rect = Rect.fromLTWH(
        shortBands ? 0 : segment.lane * width,
        segment.top - group.top,
        width,
        segment.bottom - segment.top,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_DenseOccupancy old) =>
      old.group != group ||
      old.shortBands != shortBands ||
      old.color != color ||
      old.visibleTop != visibleTop ||
      old.visibleBottom != visibleBottom;
}

/// Source texture is shared by the card and compact occupancy indicators.

class _ShortTaskLeader extends CustomPainter {
  const _ShortTaskLeader(this.color, this.downward);
  final Color color;
  final bool downward;
  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(0, downward ? 0 : size.height);
    final end = Offset(size.width, downward ? size.height : 0);
    final paint = Paint()
      ..color = color.withValues(alpha: .75)
      ..strokeWidth = .8;
    canvas.drawLine(start, end, paint);
    canvas.drawCircle(start, 1.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ShortTaskLeader old) =>
      old.color != color || old.downward != downward;
}

/// Draggable positions this zero-size root at the pointer. Its child keeps its
/// real layout size and paints back inside the safe screen rectangle.
