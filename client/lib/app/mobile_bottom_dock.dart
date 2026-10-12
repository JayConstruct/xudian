import '../core/ui/ui_icon.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../core/ui/app_destination.dart';
import '../core/ui/ui_annotation.dart';
import '../core/ui/ui_component.dart';
import 'toolbar_size_reporter.dart';
import 'dock_motion.dart';
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
    this.onAssistant,
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

  /// Page-scoped assistance. A missing callback hides the separate AI button.
  final VoidCallback? onAssistant;

  static double navigationHeight(BuildContext context) =>
      62 + math.max(0, MediaQuery.textScalerOf(context).scale(11) - 11);

  static double inputHeight(BuildContext context) =>
      52 + math.max(0, MediaQuery.textScalerOf(context).scale(14) - 14);

  static double height(
    BuildContext context, {
    required bool hasInput,
    required bool showNavigation,
  }) =>
      (hasInput ? inputHeight(context) + 12 : 0) +
      (showNavigation ? navigationHeight(context) : 0) +
      (hasInput && showNavigation ? 8 : 0);

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
    final fallback = SizedBox(
      key: const ValueKey('mobile-bottom-dock'),
      width: double.infinity,
      child: _DockSizeTransition(
        duration: duration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (this.input != null)
              FrostedToolbarSurface(
                child: Padding(padding: const EdgeInsets.all(6), child: input),
              ),
            if (this.input != null && showNavigation) const SizedBox(height: 8),
            if (showNavigation) navigation,
          ],
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
          'hasAssistant': onAssistant != null,
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
          if (onAssistant != null) 'assistant': (_) => onAssistant!(),
        },
        fallback: fallback,
      ),
    );
  }

  Widget _navigation(BuildContext context, Duration duration) {
    final visibleCount = (this.visibleCount ?? math.min(4, destinations.length))
        .clamp(0, destinations.length);
    final hasMore =
        onAssistant == null &&
        (this.hasMore ?? destinations.length > visibleCount);
    return _FloatingDockNavigation(
      destinations: destinations.take(visibleCount).toList(),
      selectedIndex: selectedIndex,
      hasMore: hasMore,
      onAssistant: onAssistant,
      moreSelected:
          onAssistant == null &&
          (moreSelected || (hasMore && selectedIndex >= visibleCount)),
      duration: duration,
      onSelected: onSelected,
      annotate: _annotated,
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

/// The capsule previews a drag locally; a page switch happens once on release.
/// The separate page action remains outside the scrub gesture.
class _FloatingDockNavigation extends StatefulWidget {
  const _FloatingDockNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.hasMore,
    required this.moreSelected,
    required this.duration,
    required this.onSelected,
    required this.annotate,
    this.onAssistant,
  });

  final List<AppDestination> destinations;
  final int selectedIndex;
  final bool hasMore, moreSelected;
  final Duration duration;
  final ValueChanged<int> onSelected;
  final Widget Function(String id, String label, Widget child) annotate;
  final VoidCallback? onAssistant;

  @override
  State<_FloatingDockNavigation> createState() =>
      _FloatingDockNavigationState();
}

class _FloatingDockNavigationState extends State<_FloatingDockNavigation>
    with TickerProviderStateMixin {
  late final lens = DockSpring(this, math.max(0, selected).toDouble());
  late final lift = DockSpring(this, 0);
  late final motion = Listenable.merge([lens, lift]);
  int? pointer;
  int? preview;
  bool dragging = false;
  bool verticalCancel = false;
  Offset origin = Offset.zero;
  VelocityTracker? tracker;

  bool get animated => widget.duration != Duration.zero;
  int get selected =>
      !widget.moreSelected &&
          widget.selectedIndex >= 0 &&
          widget.selectedIndex < widget.destinations.length
      ? widget.selectedIndex
      : -1;

  @override
  void didUpdateWidget(_FloatingDockNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinations.map((e) => e.id).join('\n') !=
        widget.destinations.map((e) => e.id).join('\n')) {
      pointer = null;
      preview = null;
      dragging = false;
      tracker = null;
      lift.moveTo(0, DockPhysics.settling, animate: animated);
    }
    if (!animated) {
      lift.jumpTo(0);
      lens.jumpTo(lens.target);
    }
    if (pointer == null && selected >= 0) {
      lens.moveTo(selected.toDouble(), DockPhysics.settling, animate: animated);
    }
  }

  double _position(Offset local, double width, bool rtl) {
    final count = widget.destinations.length;
    if (count == 0 || width <= 0) return 0;
    final x = rtl ? width - local.dx : local.dx;
    final position = x / (width / count) - .5;
    if (position < 0) return DockPhysics.resistance(position, .2);
    if (position > count - 1) {
      return count - 1 + DockPhysics.resistance(position - count + 1, .2);
    }
    return position;
  }

  int _index(double position) =>
      position.round().clamp(0, widget.destinations.length - 1);

  void _down(PointerDownEvent event, double width, bool rtl) {
    if (!mounted || pointer != null || event.buttons & kPrimaryButton == 0) {
      return;
    }
    pointer = event.pointer;
    origin = event.localPosition;
    dragging = verticalCancel = false;
    tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
    final index = _index(_position(event.localPosition, width, rtl));
    setState(() => preview = index);
    lens.moveTo(index.toDouble(), DockPhysics.settling, animate: animated);
    lift.moveTo(animated ? 1 : 0, DockPhysics.lifting, animate: animated);
  }

  void _move(PointerMoveEvent event, double width, bool rtl) {
    if (pointer != event.pointer || verticalCancel) return;
    tracker?.addPosition(event.timeStamp, event.localPosition);
    final delta = event.localPosition - origin;
    if (!dragging) {
      if (delta.dy.abs() > kTouchSlop && delta.dy.abs() > delta.dx.abs()) {
        verticalCancel = true;
        lift.moveTo(0, DockPhysics.settling, animate: animated);
        lens.moveTo(
          math.max(0, selected).toDouble(),
          DockPhysics.settling,
          animate: animated,
        );
        setState(() => preview = null);
        return;
      }
      if (delta.dx.abs() < kTouchSlop) return;
      dragging = true;
    }
    final position = _position(event.localPosition, width, rtl);
    lens.moveTo(position, DockPhysics.tracking, animate: animated);
    final index = _index(position);
    if (preview != index) setState(() => preview = index);
  }

  void _end(PointerEvent event, double extent, bool rtl) {
    if (pointer != event.pointer) return;
    var candidate = preview;
    final commit = event is PointerUpEvent && !verticalCancel;
    if (commit && dragging && candidate != null && extent > 0) {
      final speed = tracker?.getVelocity().pixelsPerSecond.dx ?? 0;
      final lead = speed / extent * .1 * (rtl ? -1 : 1);
      candidate = (lens.target + lead)
          .round()
          .clamp(candidate - 1, candidate + 1)
          .clamp(0, widget.destinations.length - 1);
    }
    final wasDragging = dragging;
    pointer = null;
    tracker = null;
    dragging = false;
    setState(() => preview = null);
    lift.moveTo(0, DockPhysics.settling, animate: animated);
    final destination = commit && candidate != null
        ? candidate
        : math.max(0, selected);
    lens.moveTo(
      destination.toDouble(),
      DockPhysics.settling,
      animate: animated,
    );
    if (commit &&
        candidate != null &&
        (!wasDragging || candidate != selected || widget.moreSelected)) {
      widget.onSelected(candidate);
    }
  }

  @override
  void dispose() {
    pointer = null;
    tracker = null;
    lens.dispose();
    lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.destinations.length;
    final hasAction = widget.onAssistant != null || widget.hasMore;
    if (count == 0 && !hasAction) return const SizedBox.shrink();
    final height = MobileBottomDock.navigationHeight(context);
    return SizedBox(
      key: const ValueKey('mobile-navigation'),
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = math.max(
            0.0,
            constraints.maxWidth -
                (hasAction ? height + (count > 0 ? 8 : 0) : 0),
          );
          final width = math.min(count * 72.0 + 8, available);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (count > 0)
                SizedBox(
                  key: const ValueKey('mobile-navigation-capsule'),
                  width: width,
                  child: DockElasticSurface(
                    enabled: animated,
                    edgePullOnly: true,
                    child: FrostedToolbarSurface(
                      pill: true,
                      clipContent: false,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: LayoutBuilder(
                          builder: (context, slots) {
                            final rtl =
                                Directionality.of(context) == TextDirection.rtl;
                            final extent = slots.maxWidth / count;
                            return Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (event) =>
                                  _down(event, slots.maxWidth, rtl),
                              onPointerMove: (event) =>
                                  _move(event, slots.maxWidth, rtl),
                              onPointerUp: (event) => _end(event, extent, rtl),
                              onPointerCancel: (event) =>
                                  _end(event, extent, rtl),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  if (selected >= 0 || preview != null)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: AnimatedBuilder(
                                          animation: motion,
                                          builder: (context, _) {
                                            final growth = 28 * lift.value;
                                            final stretch = animated
                                                ? (lens.velocity.abs() / 8)
                                                          .clamp(0.0, 1.0) *
                                                      .25
                                                : 0.0;
                                            final w =
                                                (extent + growth) *
                                                (1 + stretch);
                                            final h =
                                                (slots.maxHeight + growth) *
                                                (1 - stretch * .5);
                                            final logical = lens.value.clamp(
                                              -.4,
                                              count - .6,
                                            );
                                            final visual = rtl
                                                ? count - 1 - logical
                                                : logical;
                                            return OverflowBox(
                                              alignment: Alignment.topLeft,
                                              minWidth: 0,
                                              minHeight: 0,
                                              maxWidth: double.infinity,
                                              maxHeight: double.infinity,
                                              child: Transform.translate(
                                                offset: Offset(
                                                  (visual + .5) * extent -
                                                      w / 2,
                                                  (slots.maxHeight - h) / 2,
                                                ),
                                                child: SizedBox(
                                                  width: w,
                                                  height: h,
                                                  child: DecoratedBox(
                                                    key: const ValueKey(
                                                      'mobile-navigation-indicator',
                                                    ),
                                                    decoration: ShapeDecoration(
                                                      shape:
                                                          const StadiumBorder(),
                                                      color: Color.alphaBlend(
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                              alpha:
                                                                  .14 +
                                                                  .04 *
                                                                      lift.value
                                                                          .clamp(
                                                                            0.0,
                                                                            1.0,
                                                                          ),
                                                            ),
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .surface,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      for (var i = 0; i < count; i++)
                                        Expanded(
                                          child: widget.annotate(
                                            widget.destinations[i].id,
                                            widget.destinations[i].label,
                                            _DockDestination(
                                              key: ValueKey(
                                                widget.destinations[i].id,
                                              ),
                                              label:
                                                  widget.destinations[i].label,
                                              icon: widget.destinations[i].icon,
                                              selected: i == selected,
                                              highlighted:
                                                  i == (preview ?? selected),
                                              duration: widget.duration,
                                              motion: motion,
                                              emphasis: () => (
                                                amount:
                                                    selected < 0 &&
                                                        preview == null
                                                    ? 0.0
                                                    : (1 -
                                                              (lens.value - i)
                                                                  .abs())
                                                          .clamp(0.0, 1.0),
                                                lift: lift.value,
                                              ),
                                              onTap: () => widget.onSelected(i),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              if (count > 0 && hasAction) const SizedBox(width: 8),
              if (hasAction)
                SizedBox(
                  key: ValueKey(
                    widget.onAssistant == null
                        ? 'mobile-navigation-more'
                        : 'mobile-navigation-assistant',
                  ),
                  width: height,
                  child: DockElasticSurface(
                    enabled: animated,
                    child: FrostedToolbarSurface(
                      pill: true,
                      child: AnimatedContainer(
                        duration: widget.duration,
                        decoration: ShapeDecoration(
                          shape: const CircleBorder(),
                          color:
                              widget.onAssistant == null && widget.moreSelected
                              ? Theme.of(context).colorScheme.primary
                                    .withValues(alpha: .12)
                              : Colors.transparent,
                        ),
                        child: widget.annotate(
                          widget.onAssistant == null
                              ? 'app.shell.more'
                              : 'app.shell.assistant',
                          widget.onAssistant == null ? '更多' : 'AI',
                          _DockDestination(
                            key: ValueKey(
                              widget.onAssistant == null ? 'more' : 'assistant',
                            ),
                            label: widget.onAssistant == null ? '更多' : 'AI',
                            icon: widget.onAssistant == null
                                ? Icons.more_horiz_rounded
                                : Icons.auto_awesome_rounded,
                            selected:
                                widget.onAssistant == null &&
                                widget.moreSelected,
                            highlighted:
                                widget.onAssistant == null &&
                                widget.moreSelected,
                            duration: widget.duration,
                            onTap:
                                widget.onAssistant ??
                                () => widget.onSelected(count),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

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
          clipBehavior: Clip.none,
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
    required this.highlighted,
    required this.duration,
    required this.onTap,
    this.motion,
    this.emphasis,
  });
  final String label;
  final IconData icon;
  final bool selected, highlighted;
  final Duration duration;
  final VoidCallback onTap;
  final Listenable? motion;
  final ({double amount, double lift}) Function()? emphasis;

  @override
  State<_DockDestination> createState() => _DockDestinationState();
}

class _DockDestinationState extends State<_DockDestination> {
  bool focused = false;

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final feedback = widget.emphasis?.call();
    final amount = feedback?.amount ?? (widget.highlighted ? 1.0 : 0.0);
    final color = Color.lerp(
      AppDesign.muted(context),
      theme.colorScheme.primary,
      amount,
    )!;
    return Transform.scale(
      scale: 1 + .12 * amount * (feedback?.lift ?? 0),
      transformHitTests: false,
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UiIcon(
              widget.icon,
              color: color,
              size: 22,
              selected: widget.selected,
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedDefaultTextStyle(
                duration: widget.motion == null
                    ? widget.duration
                    : Duration.zero,
                style: theme.textTheme.labelSmall!.copyWith(
                  color: color,
                  fontSize: 11,
                  fontWeight: widget.highlighted
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.motion == null
        ? _content(context)
        : AnimatedBuilder(
            animation: widget.motion!,
            builder: (context, _) => _content(context),
          );
    final control = widget.motion == null
        ? InkWell(
            customBorder: const StadiumBorder(),
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: widget.onTap,
            child: content,
          )
        : FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            onShowFocusHighlight: (value) => setState(() => focused = value),
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onTap();
                  return null;
                },
              ),
            },
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: StadiumBorder(
                  side: focused
                      ? BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : BorderSide.none,
                ),
              ),
              child: content,
            ),
          );
    return Semantics(
      button: true,
      selected: widget.selected,
      onTap: widget.motion != null ? widget.onTap : null,
      child: control,
    );
  }
}
