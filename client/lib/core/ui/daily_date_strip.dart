import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';

import 'temporal_input.dart';
import 'ui_motion.dart';

/// A declared, continuous civil-date band. It never invents dates or counts.
class DailyDateStrip extends StatefulWidget {
  const DailyDateStrip({
    super.key,
    required this.days,
    required this.selectedDate,
    required this.width,
    required this.cellBuilder,
    this.onChanged,
    this.animate = true,
  });
  final List<Map<String, Object?>> days;
  final String selectedDate;
  final double width;
  final Widget Function(Map<String, Object?>) cellBuilder;
  final ValueChanged<String>? onChanged;
  final bool animate;

  static bool supports(List<Map<String, Object?>> days, String selected) {
    if (!days.any((entry) => entry['date'] == selected)) return false;
    DateTime? previous;
    for (final entry in days) {
      final date = parseInputDate(entry['date']);
      if (date == null || date.year < 1 || date.year > 9999) return false;
      final civil = DateTime.utc(date.year, date.month, date.day);
      if (previous != null && civil.difference(previous).inDays != 1) {
        return false;
      }
      previous = civil;
    }
    return days.isNotEmpty;
  }

  @override
  State<DailyDateStrip> createState() => _DailyDateStripState();
}

class _DailyDateStripState extends State<DailyDateStrip>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(vsync: this)
    ..addListener(() => setState(() {}))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          final declared = widget.days.map((entry) => entry['date']).toSet();
          entries.removeWhere((date, _) => !declared.contains(date));
        });
      }
    });
  final entries = <String, Map<String, Object?>>{};
  final from = <String, double>{}, to = <String, double>{};
  double drag = 0;
  int direction = 1;
  bool reducedMotion = false;
  double get cellWidth => widget.width / widget.days.length;
  double get progress => AppMotion.enter.transform(animation.value);
  double position(String date) =>
      (from[date] ?? 0) +
      ((to[date] ?? 0) - (from[date] ?? 0)) * progress +
      drag;

  int ordinal(String raw) {
    final value = parseInputDate(raw)!;
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
    ).difference(DateTime.utc(1)).inDays;
  }

  double target(String date) =>
      (ordinal(date) - ordinal(widget.selectedDate)) * cellWidth * direction;

  @override
  void initState() {
    super.initState();
    for (final entry in widget.days) {
      final date = entry['date'] as String;
      entries[date] = entry;
      from[date] = to[date] = target(date);
    }
    animation.value = 1;
  }

  void move({String? priorSelection}) {
    final current = {for (final date in entries.keys) date: position(date)};
    animation.stop();
    final selectionDelta = priorSelection == null
        ? 0
        : (ordinal(widget.selectedDate) - ordinal(priorSelection)) *
              cellWidth *
              direction;
    for (final entry in widget.days) {
      entries[entry['date'] as String] = entry;
    }
    for (final date in entries.keys) {
      from[date] = current[date] ?? target(date) + selectionDelta;
      to[date] = target(date);
    }
    drag = 0;
    animation.duration = !widget.animate
        ? Duration.zero
        : AppMotion.duration(
            context,
            AppMotion.dateStrip,
            respectHighContrast: true,
          );
    animation.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    if (next != direction) {
      direction = next;
      for (final date in entries.keys) {
        from[date] = to[date] = target(date);
      }
    }
    final reduced =
        !widget.animate ||
        AppMotion.duration(
              context,
              AppMotion.dateStrip,
              respectHighContrast: true,
            ) ==
            Duration.zero;
    if (reduced && !reducedMotion && animation.isAnimating) {
      animation.value = 1;
    }
    reducedMotion = reduced;
  }

  @override
  void didUpdateWidget(DailyDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dates = widget.days.map((entry) => entry['date']).join('|');
    final oldDates = oldWidget.days.map((entry) => entry['date']).join('|');
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.animate != widget.animate ||
        oldWidget.width != widget.width ||
        dates != oldDates) {
      move(priorSelection: oldWidget.selectedDate);
    } else {
      for (final entry in widget.days) {
        entries[entry['date'] as String] = entry;
      }
    }
  }

  void release(DragEndDetails details) {
    final selected = widget.days.indexWhere(
      (entry) => entry['date'] == widget.selectedDate,
    );
    final logical = -drag * direction;
    final velocity = -(details.primaryVelocity ?? 0) * direction;
    var steps = (logical / cellWidth).round();
    if (steps == 0 && velocity.abs() > 400) steps = velocity > 0 ? 1 : -1;
    final index = (selected + steps.clamp(-2, 2)).clamp(
      0,
      widget.days.length - 1,
    );
    final date = widget.days[index]['date'] as String;
    // One release emits at most one declared, valid date. A rejected or delayed
    // business response simply settles the band back to its current selection.
    move();
    if (date != widget.selectedDate) widget.onChanged?.call(date);
  }

  void selectAdjacent(int step) {
    final selected = widget.days.indexWhere(
      (entry) => entry['date'] == widget.selectedDate,
    );
    final next = selected + step;
    if (next >= 0 && next < widget.days.length) {
      widget.onChanged?.call(widget.days[next]['date'] as String);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final declared = widget.days.map((entry) => entry['date']).toSet();
    final selected = widget.days.indexWhere(
      (entry) => entry['date'] == widget.selectedDate,
    );
    return Semantics(
      label: '日期选择，左右滑动切换日期',
      container: true,
      explicitChildNodes: true,
      onIncrease: widget.onChanged != null && selected < widget.days.length - 1
          ? () => selectAdjacent(1)
          : null,
      onDecrease: widget.onChanged != null && selected > 0
          ? () => selectAdjacent(-1)
          : null,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.onChanged == null
            ? null
            : (_) {
                for (final date in entries.keys) {
                  from[date] = to[date] = position(date);
                }
                animation.stop();
                animation.value = 1;
                drag = 0;
              },
        onHorizontalDragUpdate: widget.onChanged == null
            ? null
            : (details) {
                setState(
                  () => drag = (drag + details.delta.dx).clamp(
                    -2 * cellWidth,
                    2 * cellWidth,
                  ),
                );
              },
        onHorizontalDragEnd: widget.onChanged == null ? null : release,
        onHorizontalDragCancel: widget.onChanged == null ? null : move,
        child: ClipRect(
          child: _DateBand(
            cellWidth: cellWidth,
            offsets: [for (final date in entries.keys) position(date)],
            children: [
              for (final entry in entries.entries)
                IgnorePointer(
                  key: ValueKey('daily-date:${entry.key}'),
                  ignoring: !declared.contains(entry.key),
                  child: ExcludeSemantics(
                    excluding: !declared.contains(entry.key),
                    child: widget.cellBuilder(entry.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBand extends MultiChildRenderObjectWidget {
  const _DateBand({
    required this.cellWidth,
    required this.offsets,
    required super.children,
  });
  final double cellWidth;
  final List<double> offsets;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDateBand(cellWidth, offsets);
  @override
  void updateRenderObject(BuildContext context, _RenderDateBand renderObject) {
    renderObject
      ..cellWidth = cellWidth
      ..offsets = offsets
      ..markNeedsLayout();
  }
}

class _DateBandParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderDateBand extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DateBandParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DateBandParentData> {
  _RenderDateBand(this.cellWidth, this.offsets);
  double cellWidth;
  List<double> offsets;
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DateBandParentData) {
      child.parentData = _DateBandParentData();
    }
  }

  @override
  void performLayout() {
    double height = 0;
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: cellWidth),
        parentUsesSize: true,
      );
      height = math.max(height, child.size.height);
      child = (child.parentData! as _DateBandParentData).nextSibling;
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
    child = firstChild;
    var index = 0;
    while (child != null) {
      final data = child.parentData! as _DateBandParentData;
      data.offset = Offset((size.width - cellWidth) / 2 + offsets[index++], 0);
      child = data.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
