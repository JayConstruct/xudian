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

/// Compact content filters and underlined section tabs. Choice labels and
/// events are module data; the host owns scrolling, focus and hit targets.
class ScriptTabChoices extends StatelessWidget {
  const ScriptTabChoices({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.underlined = false,
    this.scrollable = false,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final bool underlined, scrollable;

  Widget _choice(BuildContext context, int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = selectedIndex == index;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSelected == null ? null : () => onSelected!(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: !underlined && selected
                      ? ShapeDecoration(
                          color: scheme.primaryContainer,
                          shape: AppDesign.smoothShape(radius: 12),
                        )
                      : null,
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (underlined && selected)
                  Positioned(
                    bottom: 0,
                    left: 12,
                    right: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox(height: 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final needsScroll =
            scrollable || scale > 1.3 || constraints.maxWidth < 280;
        if (needsScroll) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < labels.length; index++)
                  _choice(context, index),
              ],
            ),
          );
        }
        return Row(
          children: [
            for (var index = 0; index < labels.length; index++)
              Expanded(child: _choice(context, index)),
          ],
        );
      },
    );
  }
}
