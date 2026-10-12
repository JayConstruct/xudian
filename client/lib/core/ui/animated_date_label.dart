import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'ui_motion.dart';

/// A complete, accessible Text owns layout. Only its changing date ranges are
/// repainted while the unchanged month/year remain at their normal positions.
class AnimatedDateLabel extends StatefulWidget {
  const AnimatedDateLabel({
    super.key,
    required this.title,
    required this.date,
    required this.style,
    required this.maxLines,
  });

  final String title;
  final String? date;
  final TextStyle style;
  final int maxLines;

  @override
  State<AnimatedDateLabel> createState() => _AnimatedDateLabelState();
}

class _AnimatedDateLabelState extends State<AnimatedDateLabel>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: AppMotion.dateTitle,
    value: 1,
  );
  String? previous;
  double direction = 1;
  double startProgress = 0;
  double get progress =>
      startProgress +
      (1 - startProgress) * Curves.easeOutCubic.transform(controller.value);

  bool get immediate =>
      AppMotion.duration(
        context,
        AppMotion.dateTitle,
        respectHighContrast: true,
      ) ==
      Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (immediate && controller.isAnimating) controller.value = 1;
  }

  @override
  void didUpdateWidget(AnimatedDateLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      final reversing = controller.isAnimating && widget.title == previous;
      final oldProgress = progress;
      previous = controller.isAnimating && oldProgress < .5 && !reversing
          ? previous
          : oldWidget.title;
      startProgress = reversing ? 1 - oldProgress : 0;
      direction =
          widget.date != null &&
              oldWidget.date != null &&
              widget.date!.compareTo(oldWidget.date!) < 0
          ? -1
          : 1;
      if (immediate) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: Text(
      widget.title,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    ),
    builder: (context, child) => DateLabelPaint(
      previous: previous,
      current: widget.title,
      progress: immediate ? 1 : progress,
      direction: direction,
      child: child!,
    ),
  );
}

/// Paint state is explicit so rendering tests can inspect animation direction
/// and changed ranges without creating duplicate text or semantics widgets.
class DateLabelPaint extends SingleChildRenderObjectWidget {
  const DateLabelPaint({
    super.key,
    required this.previous,
    required this.current,
    required this.progress,
    required this.direction,
    required super.child,
  });
  final String? previous;
  final String current;
  final double progress, direction;

  List<String> get changedParts {
    final before = _parts(previous), after = _parts(current);
    if (before == null || after == null) return const ['title'];
    return [
      for (var i = 0; i < after.length; i++)
        if (before[i].text != after[i].text)
          const ['year', 'month', 'day', 'separator', 'weekday'][i],
    ];
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _DateLabelRender(this);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _DateLabelRender).config = this;
  }
}

class _Part {
  const _Part(this.text, this.start, this.end);
  final String text;
  final int start, end;
}

List<_Part>? _parts(String? title) {
  if (title == null) return null;
  final match = RegExp(r'^(\d+年)?(\d+月)(\d+日)(\s+)(周[一二三四五六日天])$')
      .firstMatch(title);
  if (match == null) return null;
  var start = 0;
  return [
    for (var i = 1; i <= 5; i++)
      () {
        final text = match.group(i) ?? '';
        final part = _Part(text, start, start + text.length);
        start += text.length;
        return part;
      }(),
  ];
}

class _DateLabelRender extends RenderProxyBox {
  _DateLabelRender(this._config);
  DateLabelPaint _config;
  set config(DateLabelPaint value) {
    _config = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paragraph = child;
    if (_config.progress >= 1 ||
        _config.previous == null ||
        paragraph is! RenderParagraph) {
      super.paint(context, offset);
      return;
    }
    final old = TextPainter(
      text: TextSpan(text: _config.previous, style: paragraph.text.style),
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textWidthBasis: paragraph.textWidthBasis,
      textHeightBehavior: paragraph.textHeightBehavior,
    )..layout(maxWidth: constraints.maxWidth);
    final current = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textWidthBasis: paragraph.textWidthBasis,
      textHeightBehavior: paragraph.textHeightBehavior,
    )..layout(maxWidth: constraints.maxWidth);
    try {
      final before = _parts(_config.previous), after = _parts(_config.current);
      if (before == null ||
          after == null ||
          before.first.text.isEmpty != after.first.text.isEmpty) {
        _paintWhole(context, offset, current, old);
        return;
      }
      final changed = <(Rect, Rect)>[];
      for (var i = 0; i < after.length; i++) {
        if (before[i].text == after[i].text) continue;
        final newBoxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: after[i].start, extentOffset: after[i].end),
        );
        final oldBoxes = old.getBoxesForSelection(
          TextSelection(
            baseOffset: before[i].start,
            extentOffset: before[i].end,
          ),
        );
        if (after[i].text.isEmpty) continue;
        if (before[i].text.isEmpty) {
          for (final box in newBoxes) {
            changed.add((box.toRect(), Rect.zero));
          }
          continue;
        }
        // A line reflow is safer as one smooth label transition. The complete
        // Text still lays out normally at the user's scale.
        if (newBoxes.length != oldBoxes.length ||
            newBoxes.isEmpty ||
            newBoxes.indexed.any(
              (entry) => (entry.$2.top - oldBoxes[entry.$1].top).abs() > 1,
            )) {
          _paintWhole(context, offset, current, old);
          return;
        }
        for (var j = 0; j < newBoxes.length; j++) {
          changed.add((newBoxes[j].toRect(), oldBoxes[j].toRect()));
        }
      }
      var still = Path()..addRect(offset & size);
      for (final (now, _) in changed) {
        still = Path.combine(
          PathOperation.difference,
          still,
          Path()..addRect(now.shift(offset)),
        );
      }
      final canvas = context.canvas;
      canvas.save();
      canvas.clipPath(still);
      context.paintChild(paragraph, offset);
      canvas.restore();
      for (final (now, was) in changed) {
        final height = now.height;
        canvas.save();
        canvas.clipRect(now.shift(offset));
        if (!was.isEmpty) {
          final oldOffset =
              offset +
              Offset(
                now.left - was.left,
                now.top -
                    was.top -
                    height * _config.progress * _config.direction,
              );
          canvas.save();
          canvas.clipRect(was.shift(oldOffset));
          old.paint(canvas, oldOffset);
          canvas.restore();
        }
        final newOffset =
            offset +
            Offset(0, height * (1 - _config.progress) * _config.direction);
        canvas.save();
        canvas.clipRect(now.shift(newOffset));
        current.paint(canvas, newOffset);
        canvas.restore();
        canvas.restore();
      }
    } finally {
      old.dispose();
      current.dispose();
    }
  }

  void _paintWhole(
    PaintingContext context,
    Offset offset,
    TextPainter current,
    TextPainter old,
  ) {
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);
    canvas.saveLayer(
      offset & size,
      Paint()..color = Colors.white.withValues(alpha: 1 - _config.progress),
    );
    old.paint(
      canvas,
      offset +
          Offset(0, -size.height * .12 * _config.progress * _config.direction),
    );
    canvas.restore();
    canvas.saveLayer(
      offset & size,
      Paint()..color = Colors.white.withValues(alpha: _config.progress),
    );
    current.paint(
      canvas,
      offset +
          Offset(
            0,
            size.height * .12 * (1 - _config.progress) * _config.direction,
          ),
    );
    canvas.restore();
    canvas.restore();
  }
}
