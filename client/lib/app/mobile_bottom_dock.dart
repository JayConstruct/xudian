import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/ui/app_destination.dart';
import 'design_system.dart';

class MobileBottomDock extends StatelessWidget {
  const MobileBottomDock({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.showNavigation,
    this.input,
  });

  final List<AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool showNavigation;
  final Widget? input;

  static double navigationHeight(BuildContext context) =>
      60 + math.max(0, MediaQuery.textScalerOf(context).scale(12) - 12);

  static double inputHeight(BuildContext context) =>
      52 + math.max(0, MediaQuery.textScalerOf(context).scale(14) - 14);

  static double height(
    BuildContext context, {
    required bool hasInput,
    required bool showNavigation,
  }) =>
      12 +
      (hasInput ? inputHeight(context) : 0) +
      (showNavigation ? navigationHeight(context) : 0) +
      (hasInput && showNavigation ? 7 : 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final shape = AppDesign.smoothShape(radius: AppDesign.dockRadius);
    final surface = Color.alphaBlend(
      scheme.primary.withValues(alpha: dark ? 0.035 : 0.015),
      scheme.surface,
    );

    return DecoratedBox(
      key: const ValueKey('mobile-bottom-dock'),
      decoration: ShapeDecoration(
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.24 : 0.075),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRSuperellipse(
        borderRadius: shape.borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: shape.copyWith(
                side: BorderSide(
                  color: highContrast
                      ? scheme.onSurface.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: dark ? 0.14 : 0.8),
                ),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  surface.withValues(alpha: highContrast ? 0.98 : 0.87),
                  surface.withValues(alpha: highContrast ? 0.98 : 0.74),
                ],
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: _DockSizeTransition(
                duration: duration,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (input != null)
                        SizedBox(height: inputHeight(context), child: input),
                      if (input != null && showNavigation)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          child: SizedBox(
                            height: 1,
                            child: ColoredBox(
                              color: scheme.onSurface.withValues(alpha: 0.065),
                            ),
                          ),
                        ),
                      if (showNavigation) _navigation(context, duration),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navigation(BuildContext context, Duration duration) {
    final visibleCount = math.min(4, destinations.length);
    final hasMore = destinations.length > visibleCount;
    final count = visibleCount + (hasMore ? 1 : 0);
    final selected = math.min(selectedIndex, visibleCount);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      key: const ValueKey('mobile-navigation'),
      height: navigationHeight(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / count;
          return Stack(
            children: [
              AnimatedPositionedDirectional(
                key: const ValueKey('mobile-navigation-indicator'),
                duration: duration,
                curve: Curves.easeOutCubic,
                start: selected * itemWidth + 4,
                top: 3,
                bottom: 3,
                width: itemWidth - 8,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: AppDesign.smoothShape(
                      radius: AppDesign.selectionRadius,
                      side: BorderSide(
                        color: scheme.primary.withValues(alpha: 0.07),
                      ),
                    ),
                    color: scheme.primaryContainer.withValues(alpha: 0.78),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: _DockDestination(
                        key: ValueKey(
                          i < visibleCount ? destinations[i].id : 'more',
                        ),
                        label: i < visibleCount ? destinations[i].label : '更多',
                        icon: i < visibleCount
                            ? (i == selected
                                  ? destinations[i].selectedIcon
                                  : destinations[i].icon)
                            : Icons.more_horiz_rounded,
                        selected: i == selected,
                        duration: duration,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A zero-duration AnimatedSize can finish during layout when preferences
/// change. Skip its render object entirely when animations are disabled.
class _DockSizeTransition extends StatelessWidget {
  const _DockSizeTransition({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => duration == Duration.zero
      ? child
      : AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: child,
        );
}

class _DockDestination extends StatefulWidget {
  const _DockDestination({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  State<_DockDestination> createState() => _DockDestinationState();
}

class _DockDestinationState extends State<_DockDestination> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.selected
        ? theme.colorScheme.primary
        : AppDesign.muted(context);
    return Semantics(
      button: true,
      selected: widget.selected,
      child: Tooltip(
        message: widget.label,
        child: InkWell(
          customBorder: AppDesign.smoothShape(
            radius: AppDesign.selectionRadius,
          ),
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => pressed = value),
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.09),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.035),
          child: AnimatedScale(
            scale: pressed ? 0.94 : 1,
            duration: widget.duration == Duration.zero
                ? Duration.zero
                : const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: color, size: 23),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedDefaultTextStyle(
                      duration: widget.duration,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: color,
                        fontSize: 12,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
