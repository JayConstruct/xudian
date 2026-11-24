import 'package:flutter/material.dart';

import 'ui_design.dart';
import 'ui_icon.dart';

/// Semantic, theme-aware accents for script-authored content.
Color scriptTone(BuildContext context, String tone) {
  final scheme = Theme.of(context).colorScheme;
  final dark = scheme.brightness == Brightness.dark;
  return switch (tone) {
    'success' => dark ? const Color(0xFF9DD8A9) : const Color(0xFF277542),
    'warning' => dark ? const Color(0xFFF0C779) : const Color(0xFF8B590B),
    'muted' => scheme.onSurfaceVariant,
    _ => scheme.primary,
  };
}

Color scriptToneSurface(BuildContext context, String tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (dark) return scriptTone(context, tone).withValues(alpha: .14);
  return switch (tone) {
    'success' => const Color(0xFFE1F5E5),
    'warning' => const Color(0xFFFFF2D7),
    'muted' => const Color(0xFFEAEBEF),
    _ => Theme.of(context).colorScheme.primaryContainer,
  };
}

class ScriptBadge extends StatelessWidget {
  const ScriptBadge({
    super.key,
    required this.text,
    this.tone = 'accent',
    this.icon,
  });

  final String text, tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    decoration: ShapeDecoration(
      color: scriptToneSurface(context, tone),
      shape: AppDesign.smoothShape(radius: 8),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          UiIcon(icon, size: 14, color: scriptTone(context, tone)),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scriptTone(context, tone),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

class ScriptGlyph extends StatelessWidget {
  const ScriptGlyph({
    super.key,
    required this.icon,
    this.size = 20,
    this.tone = 'accent',
    this.surface = false,
    this.surfaceSize = 40,
    this.label,
  });

  final IconData? icon;
  final double size, surfaceSize;
  final String tone;
  final bool surface;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final glyph = UiIcon(
      icon,
      size: size,
      color: scriptTone(context, tone),
      semanticLabel: label,
    );
    if (!surface) return glyph;
    return Container(
      width: surfaceSize,
      height: surfaceSize,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: scriptToneSurface(context, tone),
        shape: AppDesign.smoothShape(radius: 12),
      ),
      child: glyph,
    );
  }
}

class ScriptGroupedRow extends StatelessWidget {
  const ScriptGroupedRow({
    super.key,
    required this.position,
    required this.child,
  });
  final String position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = position == 'first' || position == 'only';
    final last = position == 'last' || position == 'only';
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? 18 : 0),
      bottom: Radius.circular(last ? 18 : 0),
    );
    final side = BorderSide(
      color: scheme.outlineVariant.withValues(alpha: .62),
    );
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 0, bottom: last ? 6 : 0),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: radius,
          ),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border(
                left: side,
                right: side,
                top: first ? side : BorderSide.none,
                bottom: last ? side : BorderSide.none,
              ),
              borderRadius: radius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(type: MaterialType.transparency, child: child),
                if (!last)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 58,
                      end: 12,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 0.7,
                      color: side.color,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact, top-aligned time rail for variable-height entries.
class ScriptTimelineEntry extends StatelessWidget {
  const ScriptTimelineEntry({
    super.key,
    required this.time,
    required this.child,
    required this.first,
    required this.last,
    required this.filled,
    required this.divider,
    this.detailIcon,
  });

  final String time;
  final Widget child;
  final bool first, last, filled, divider;
  final IconData? detailIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timeWidth = MediaQuery.textScalerOf(context).scale(40);
    final center = first ? 20.0 : 25.0;
    final top = filled
        ? 0.0
        : first
        ? 6.0
        : 11.0;
    return Stack(
      children: [
        if (!first || !last)
          PositionedDirectional(
            start: timeWidth + 12,
            width: 1,
            top: first ? center : 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: last ? center : double.infinity,
                color: scheme.outlineVariant,
              ),
            ),
          ),
        PositionedDirectional(
          start: timeWidth + 9,
          top: center - 3.5,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? scheme.primary : theme.scaffoldBackgroundColor,
              border: Border.all(
                color: filled ? scheme.primary : scheme.outline,
                width: 1.3,
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: timeWidth,
              child: Padding(
                padding: EdgeInsets.only(top: center - 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detailIcon != null)
                      UiIcon(detailIcon, size: 13, color: scheme.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 26),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: divider
                      ? Border(
                          top: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: .65),
                          ),
                        )
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: top,
                    bottom: filled
                        ? 9
                        : last
                        ? 6
                        : 16,
                  ),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ScriptSectionLabel extends StatelessWidget {
  const ScriptSectionLabel({
    super.key,
    required this.title,
    required this.caption,
    this.onTap,
    this.chevron = false,
  });
  final String title, caption;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          caption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (chevron)
          UiIcon(
            Icons.chevron_right,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: onTap == null
          ? child
          : Semantics(
              button: true,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: child,
                ),
              ),
            ),
    );
  }
}
