import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ui/app_destination.dart';
import '../core/ui/ui_annotation.dart';
import '../core/ui/ui_component.dart';
import 'toolbar_size_reporter.dart';
import 'design_system.dart';
import 'frosted_toolbar_surface.dart';

class MobileBottomDock extends StatelessWidget {
  const MobileBottomDock({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.showNavigation,
    this.input,
    this.visibleCount,
    this.hasMore,
    this.moreSelected = false,
    this.annotate = false,
    this.entryModuleIds = const {},
    this.onSizeChanged,
  });

  final List<AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool showNavigation;
  final Widget? input;
  final int? visibleCount;
  final bool? hasMore;
  final bool moreSelected;
  final bool annotate;
  final Map<String, String> entryModuleIds;
  final ValueChanged<Size>? onSizeChanged;

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
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final navigation = showNavigation
        ? _navigation(context, duration)
        : const SizedBox.shrink();
    final input = this.input == null
        ? const SizedBox.shrink()
        : SizedBox(height: inputHeight(context), child: this.input);
    final fallback = FrostedToolbarSurface(
      surfaceKey: const ValueKey('mobile-bottom-dock'),
      child: _DockSizeTransition(
        duration: duration,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (this.input != null) input,
              if (this.input != null && showNavigation)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: .065),
                    ),
                  ),
                ),
              if (showNavigation) navigation,
            ],
          ),
        ),
      ),
    );
    return ToolbarSizeReporter(
      onSizeChanged: onSizeChanged,
      child: UiComponent(
        ref: 'ui.chrome.bottomNav@1',
        props: {
          'selectedIndex': selectedIndex,
          'showNavigation': showNavigation,
          'hasInput': this.input != null,
          'moreSelected': moreSelected,
          'destinations': [
            for (var i = 0; i < destinations.length; i++)
              {
                'id': destinations[i].id,
                'label': destinations[i].label,
                'index': i,
                'selected': !moreSelected && i == selectedIndex,
              },
          ],
        },
        slots: {'navigation': navigation, 'input': input},
        events: {
          'select': (value) {
            if (value is int && value >= 0 && value < destinations.length) {
              onSelected(value);
            }
          },
          'more': (_) => onSelected(destinations.length),
        },
        fallback: fallback,
      ),
    );
  }

  Widget _navigation(BuildContext context, Duration duration) {
    final visibleCount = (this.visibleCount ?? math.min(4, destinations.length))
        .clamp(0, destinations.length);
    final hasMore = this.hasMore ?? destinations.length > visibleCount;
    final count = visibleCount + (hasMore ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    final selected = moreSelected
        ? visibleCount
        : (selectedIndex < 0 ? -1 : math.min(selectedIndex, visibleCount));
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      key: const ValueKey('mobile-navigation'),
      height: navigationHeight(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / count;
          return Stack(
            children: [
              if (selected >= 0 && selected < count)
                PositionedDirectional(
                  start: 4,
                  top: 3,
                  bottom: 3,
                  width: itemWidth - 8,
                  child: AnimatedSlide(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    offset: Offset(
                      selected *
                          itemWidth /
                          (itemWidth - 8) *
                          (Directionality.of(context) == TextDirection.rtl
                              ? -1
                              : 1),
                      0,
                    ),
                    child: RepaintBoundary(
                      key: const ValueKey('mobile-navigation-indicator'),
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: AppDesign.smoothShape(
                            radius: AppDesign.selectionRadius,
                            side: BorderSide(
                              color: scheme.primary.withValues(alpha: 0.07),
                            ),
                          ),
                          color: scheme.primaryContainer.withValues(
                            alpha: 0.78,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: _annotated(
                        i < visibleCount
                            ? destinations[i].id
                            : 'app.shell.more',
                        i < visibleCount ? destinations[i].label : '更多',
                        _DockDestination(
                          key: ValueKey(
                            i < visibleCount ? destinations[i].id : 'more',
                          ),
                          label: i < visibleCount
                              ? destinations[i].label
                              : '更多',
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
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _annotated(String id, String label, Widget child) => annotate
      ? UiAnnotation(
          id: id,
          name: label,
          moduleId: entryModuleIds[id] ?? 'app.core.system',
          slot: 'main',
          purpose: '主导航入口',
          child: child,
        )
      : child;
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
