import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui_motion.dart';

/// Equal-width choices wrap on narrow or large-text layouts without clipping.
class SlidingSegments<T extends Object> extends StatelessWidget {
  const SlidingSegments({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.scrollable = false,
    this.minSegmentWidth = 64,
    this.minSegmentHeight = 48,
    this.wrapSegment,
  }) : assert(minSegmentWidth >= 16);

  final Widget Function(T value, Widget child)? wrapSegment;
  final bool scrollable;
  final double minSegmentWidth, minSegmentHeight;
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (segments.isEmpty) return const SizedBox.shrink();
    final selectedIndex = segments.indexWhere(
      (segment) => segment.value == selected,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        // Inside a horizontal scroll view the width is unbounded. Keep each
        // label on one line so a scrollable track does not grow a wrapped row
        // taller than the surrounding toolbar.
        var minimum = scaler.scale(minSegmentWidth - 16) + 16;
        if (!constraints.hasBoundedWidth) {
          final labelStyle = theme.textTheme.labelLarge!;
          for (final segment in segments) {
            final label = segment.label;
            if (label is! Text) continue;
            final value = label.data ?? label.textSpan?.toPlainText();
            if (value == null || value.isEmpty) continue;
            final painter = TextPainter(
              text: TextSpan(text: value, style: labelStyle.merge(label.style)),
              textDirection: Directionality.of(context),
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            final width = painter.width + 12 + (segment.icon == null ? 0 : 24);
            minimum = math.max(minimum, width);
          }
        }
        final desired = minimum * segments.length + 8;
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : desired;
        final track = scrollable && available < desired ? desired : available;
        final columns = ((track - 8) / minimum).floor().clamp(
          1,
          segments.length,
        );
        final width = ((track - 8) / columns).clamp(0.0, double.infinity);
        final slide = columns == segments.length;
        final validSelection =
            selectedIndex >= 0 && selectedIndex < segments.length;
        final position = selectedIndex.toDouble();
        Widget trackContents(double? sliderPosition) => Stack(
          children: [
            if (sliderPosition != null)
              PositionedDirectional(
                start: sliderPosition * width,
                width: width,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: .08),
                        offset: const Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            Wrap(
              children: [
                for (var index = 0; index < segments.length; index++)
                  SizedBox(
                    width: width,
                    child: _choice(theme, index, slide, sliderPosition),
                  ),
              ],
            ),
          ],
        );

        final control = SizedBox(
          width: track,
          child: Material(
            color: slide
                ? scheme.surfaceContainerHighest
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: slide && validSelection && !AppMotion.reduced(context)
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(end: position),
                      duration: AppMotion.tabChange,
                      curve: Curves.easeInOut,
                      builder: (context, value, _) => trackContents(value),
                    )
                  : trackContents(slide && validSelection ? position : null),
            ),
          ),
        );
        return track > available
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: control,
              )
            : control;
      },
    );
  }

  Widget _choice(ThemeData theme, int index, bool slide, double? position) {
    final scheme = theme.colorScheme;
    final segment = segments[index];
    final isSelected = selected == segment.value;
    final enabled = onChanged != null && segment.enabled;
    // Tint each label by how much of its segment the moving indicator covers.
    final coverage = position == null
        ? (isSelected ? 1.0 : 0.0)
        : (1.0 - (position - index).abs()).clamp(0.0, 1.0);
    final corners = BorderRadius.circular(11);
    final color = enabled
        ? Color.lerp(scheme.onSurfaceVariant, scheme.primary, coverage)!
        : scheme.onSurface.withValues(alpha: .38);
    final labelStyle = theme.textTheme.labelLarge!.copyWith(
      color: color,
      fontWeight: FontWeight.lerp(FontWeight.w400, FontWeight.w600, coverage),
    );
    final content = Semantics(
      selected: isSelected,
      enabled: enabled,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: !slide && isSelected
            ? scheme.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: corners,
        child: InkWell(
          borderRadius: corners,
          splashFactory: slide ? NoSplash.splashFactory : null,
          highlightColor: slide ? Colors.transparent : null,
          onTap: enabled ? () => onChanged!(segment.value) : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minSegmentHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Center(
                heightFactor: 1,
                child: IconTheme.merge(
                  data: IconThemeData(size: 20, color: color),
                  child: DefaultTextStyle(
                    style: labelStyle,
                    textAlign: TextAlign.center,
                    child: segment.label == null
                        ? segment.icon!
                        : segment.icon == null
                        ? segment.label!
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              segment.icon!,
                              const SizedBox(width: 4),
                              Flexible(child: segment.label!),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final choice = segment.tooltip == null
        ? content
        : Tooltip(message: segment.tooltip!, child: content);
    return wrapSegment?.call(segment.value, choice) ?? choice;
  }
}
