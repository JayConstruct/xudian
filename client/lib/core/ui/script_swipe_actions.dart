import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'script_motion.dart';
import 'script_ui_scope.dart';
import 'ui_icon.dart';
import 'ui_motion.dart';
import 'workspace_popup_menu.dart';

class ScriptSwipeAction {
  const ScriptSwipeAction(
    this.label,
    this.event,
    this.icon,
    this.disabled, {
    this.dividerBefore = false,
    this.danger = false,
    this.copyText,
    this.command,
  });
  final String label;
  final Map<String, Object?>? event, command;
  final String? copyText;
  final IconData? icon;
  final bool disabled, dividerBefore, danger;
}

class ScriptSwipeConfig {
  ScriptSwipeConfig({
    required this.enabled,
    required this.end,
    this.longPressMenu = false,
    this.anchorStart = false,
    this.highlightOutset = EdgeInsets.zero,
    required this.extent,
    required this.threshold,
    required this.timing,
    required this.actions,
    required this.identity,
  });
  final bool enabled, end, longPressMenu, anchorStart;
  final EdgeInsets highlightOutset;
  final double extent, threshold;
  final ScriptTiming timing;
  final List<ScriptSwipeAction> actions;
  final String identity;
  factory ScriptSwipeConfig.parse(
    Map<String, Object?> spec,
    IconData? Function(Object?) icon,
  ) {
    uiObject(spec, {
      'type',
      'key',
      'enabled',
      'side',
      'menuTrigger',
      'menuAlign',
      'menuHighlightOutset',
      'extent',
      'openThreshold',
      'settle',
      'actions',
      'child',
      'revision',
    }, 'swipeActions');
    final enabled = spec.containsKey('enabled') ? spec['enabled'] : true;
    final side = spec.containsKey('side') ? spec['side'] : 'end';
    final revision = spec['revision'];
    final trigger = spec.containsKey('menuTrigger')
        ? spec['menuTrigger']
        : 'button';
    if (spec.containsKey('menuAlign') &&
            !['start', 'end'].contains(spec['menuAlign']) ||
        enabled is! bool ||
        !['button', 'longPress'].contains(trigger) ||
        !['start', 'end'].contains(side) ||
        spec.containsKey('revision') &&
            revision is! String &&
            revision is! int) {
      throw const FormatException('Invalid swipeActions configuration');
    }
    final raw = spec['actions'];
    final outset = spec['menuHighlightOutset'];
    if (outset != null &&
        (trigger != 'longPress' ||
            spec['menuAlign'] != 'start' ||
            outset is! List ||
            outset.length != 2)) {
      throw const FormatException('Invalid menuHighlightOutset');
    }
    final maximum = trigger == 'longPress' ? 7 : 3;
    if (raw is! List || raw.isEmpty || raw.length > maximum) {
      throw FormatException('swipeActions requires 1–$maximum actions');
    }
    final actions = <ScriptSwipeAction>[];
    for (final item in raw) {
      final action = uiObject(item, {
        'label',
        'icon',
        'event',
        'command',
        'copyText',
        'disabled',
        'dividerBefore',
        'tone',
      }, 'swipe action');
      final label = action['label'], event = action['event'];
      final disabled = action.containsKey('disabled')
          ? action['disabled']
          : false;
      final glyph = action.containsKey('icon') ? icon(action['icon']) : null;
      final copy = action.containsKey('copyText');
      if (action.containsKey('command') &&
          (trigger != 'longPress' || action['command'] is! Map)) {
        throw const FormatException('Invalid long-press command');
      }
      if (label is! String ||
          label.trim().isEmpty ||
          (copy
              ? action['copyText'] is! String ||
                    action.containsKey('event') ||
                    action.containsKey('command')
              : event is! Map) ||
          disabled is! bool ||
          action.containsKey('dividerBefore') &&
              action['dividerBefore'] is! bool ||
          action.containsKey('tone') && action['tone'] != 'danger' ||
          action.containsKey('icon') &&
              (action['icon'] is! String || glyph == null)) {
        throw const FormatException('Invalid swipe action');
      }
      actions.add(
        ScriptSwipeAction(
          label,
          (event as Map?)?.cast<String, Object?>(),
          glyph,
          disabled,
          command: (action['command'] as Map?)?.cast<String, Object?>(),
          copyText: action['copyText'] as String?,
          dividerBefore: action['dividerBefore'] == true,
          danger: action['tone'] == 'danger',
        ),
      );
    }
    final extent = uiNumber(
      spec['extent'],
      trigger == 'longPress' ? 48 : raw.length * 48.0,
      240,
      'swipe extent',
    );
    return ScriptSwipeConfig(
      enabled: enabled,
      end: side == 'end',
      longPressMenu: trigger == 'longPress',
      anchorStart: spec['menuAlign'] == 'start',
      highlightOutset: outset is List
          ? EdgeInsets.symmetric(
              horizontal: uiNumber(
                outset[0],
                0,
                24,
                'horizontal highlight outset',
              ),
              vertical: uiNumber(outset[1], 0, 24, 'vertical highlight outset'),
            )
          : EdgeInsets.zero,
      extent: extent,
      threshold: spec.containsKey('openThreshold')
          ? uiNumber(spec['openThreshold'], .2, .8, 'openThreshold')
          : .4,
      timing: spec.containsKey('settle')
          ? ScriptTiming.parse(spec['settle'])
          : const ScriptTiming(),
      actions: List.unmodifiable(actions),
      identity: jsonEncode({
        for (final entry in spec.entries)
          if (entry.key != 'child') entry.key: entry.value,
      }),
    );
  }
}

/// Horizontal presentation only. Actions retain the page's normal workflow.
class ScriptSwipeActions extends StatefulWidget {
  const ScriptSwipeActions({
    super.key,
    required this.config,
    required this.canSwipe,
    required this.child,
    required this.onAction,
  });
  final ScriptSwipeConfig config;
  final bool canSwipe;
  final Widget child;
  final Future<void> Function(ScriptSwipeAction action) onAction;
  @override
  State<ScriptSwipeActions> createState() => _ScriptSwipeActionsState();
}

class _ScriptSwipeActionsState extends State<ScriptSwipeActions>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        resources?.release(this);
      }
    });
  final menu = MenuController();
  final menuFocus = FocusNode();
  final pointers = <int>{};
  ScriptUiResources? resources;
  ScrollPosition? position;
  Object? group;
  bool active = true, busy = false, tracking = false, locked = false;
  bool reduced = false, cancelled = false;
  double sign = -1;
  Size? geometry;
  TextScaler? scaler;
  bool get enabled => active && !busy && widget.config.enabled && !locked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ScriptUiScope.maybeOf(context);
    final nextResources = scope?.resources;
    final scrollable = Scrollable.maybeOf(context);
    final nextPosition = scrollable?.position;
    final nextSign =
        (Directionality.of(context) == TextDirection.ltr) == widget.config.end
        ? -1.0
        : 1.0;
    final nextScaler = MediaQuery.textScalerOf(context);
    final nextActive =
        (scope?.active ?? true) && TickerMode.valuesOf(context).enabled;
    final nextBusy = scope?.busy ?? false;
    // A backgrounded route may never receive the old pointer's up event.
    if (!nextActive) pointers.clear();
    if (!identical(resources, nextResources) ||
        !identical(nextPosition, position) ||
        sign != nextSign ||
        scaler != nextScaler ||
        !nextActive ||
        nextBusy) {
      _close(rebuild: false, deferMenu: true);
    }
    resources = nextResources;
    if (!identical(nextPosition, position)) {
      position?.isScrollingNotifier.removeListener(_scrollChanged);
      position = nextPosition;
      position?.isScrollingNotifier.addListener(_scrollChanged);
    }
    group = scrollable ?? resources ?? this;
    sign = nextSign;
    scaler = nextScaler;
    active = nextActive;
    busy = nextBusy;
    reduced = AppMotion.reduced(context);
    if (reduced && controller.isAnimating) {
      controller.value = controller.value >= widget.config.threshold ? 1 : 0;
      resources?.release(this);
    }
  }

  @override
  void didUpdateWidget(ScriptSwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.identity != widget.config.identity ||
        oldWidget.canSwipe != widget.canSwipe) {
      _close(rebuild: false, deferMenu: true);
      if (!widget.canSwipe) pointers.clear();
      sign =
          (Directionality.of(context) == TextDirection.ltr) == widget.config.end
          ? -1
          : 1;
    }
  }

  void _scrollChanged() {
    if (position?.isScrollingNotifier.value == true) _close();
  }

  void _close({bool rebuild = true, bool deferMenu = false}) {
    controller.value = 0;
    resources?.release(this);
    resources?.forget(this);
    tracking = false;
    cancelled = true;
    if (menu.isOpen) {
      if (deferMenu) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) menu.close();
        });
      } else {
        menu.close();
      }
    }
    if (rebuild && mounted) setState(() {});
  }

  void _own() => resources?.open(group!, this, _close);
  void _start(DragStartDetails details) {
    if (!enabled || cancelled || pointers.length > 1) return;
    _own();
    controller.stop();
    resources?.release(this);
    setState(() => tracking = true);
  }

  void _update(DragUpdateDetails details) {
    if (!tracking || cancelled || !enabled) return;
    controller.value =
        (controller.value + details.delta.dx * sign / widget.config.extent)
            .clamp(0.0, 1.0);
  }

  void _end(DragEndDetails details) {
    if (!tracking || cancelled || !enabled) return;
    setState(() => tracking = false);
    final target = controller.value >= widget.config.threshold ? 1.0 : 0.0;
    if (target == 0) resources?.forget(this);
    if (reduced ||
        widget.config.timing.duration == Duration.zero ||
        resources?.acquire(this) == false) {
      controller.value = target;
      resources?.release(this);
    } else {
      unawaited(
        controller
            .animateTo(
              target,
              duration: widget.config.timing.duration,
              curve: widget.config.timing.curve,
            )
            .orCancel
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _dispatch(ScriptSwipeAction action, String identity) async {
    if (!enabled || action.disabled || identity != widget.config.identity) {
      return;
    }
    setState(() => locked = true);
    _close();
    try {
      await widget.onAction(action);
    } finally {
      if (mounted) setState(() => locked = false);
    }
  }

  bool _fits(double width) {
    if (!widget.canSwipe ||
        widget.config.extent < widget.config.actions.length * 48 ||
        !width.isFinite ||
        width < widget.config.extent + 48) {
      return false;
    }
    for (final action in widget.config.actions) {
      final painter = TextPainter(
        text: TextSpan(
          text: action.label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final fits =
          painter.width + 24 <=
          widget.config.extent / widget.config.actions.length;
      painter.dispose();
      if (!fits) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.config.identity;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final narrow = width < 96;
          final bodyWidth = narrow || widget.config.longPressMenu
              ? width
              : width - 48;
          final nextGeometry = Size(
            bodyWidth,
            MediaQuery.textScalerOf(context).scale(1),
          );
          if (geometry != null && geometry != nextGeometry) {
            _close(rebuild: false, deferMenu: true);
          }
          geometry = nextGeometry;
          final swipe = _fits(bodyWidth);
          if (!swipe) pointers.clear();
          Widget content = widget.child;
          if (widget.config.longPressMenu) {
            final actions = widget.config.actions;
            content = WorkspacePopupMenu(
              key: ValueKey(identity),
              longPressChild: widget.child,
              anchorStart: widget.config.anchorStart,
              highlightOutset: widget.config.highlightOutset,
              enabled: enabled,
              haptics: PopupMenuTheme.of(context).enableFeedback ?? true,
              items: [
                for (final (index, action) in actions.indexed) ...[
                  if (action.dividerBefore) const PopupMenuDivider(height: 5),
                  PopupMenuItem<int>(
                    value: index,
                    height: 43,
                    enabled: !action.disabled,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        if (action.icon != null) ...[
                          UiIcon(
                            action.icon,
                            size: 19,
                            color: action.danger
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            action.label,
                            style: TextStyle(
                              fontSize: 15,
                              color: action.danger
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              onSelected: (index) =>
                  unawaited(_dispatch(actions[index], identity)),
            );
          }
          final body = !swipe
              ? content
              : Listener(
                  onPointerDown: (event) {
                    if (!enabled) return;
                    if (pointers.isEmpty) cancelled = false;
                    pointers.add(event.pointer);
                    if (pointers.length > 1) _close();
                  },
                  onPointerUp: (event) => pointers.remove(event.pointer),
                  onPointerCancel: (event) {
                    if (pointers.remove(event.pointer)) _close();
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: enabled ? _start : null,
                    onHorizontalDragUpdate: enabled ? _update : null,
                    onHorizontalDragEnd: enabled ? _end : null,
                    onHorizontalDragCancel: enabled ? _close : null,
                    child: AnimatedBuilder(
                      animation: controller,
                      child: content,
                      builder: (_, child) {
                        final open =
                            controller.value == 1 &&
                            !tracking &&
                            !controller.isAnimating;
                        final intercept =
                            tracking ||
                            controller.isAnimating ||
                            controller.value > 0;
                        return ClipRect(
                          child: Stack(
                            children: [
                              if (controller.value > 0)
                                PositionedDirectional(
                                  top: 0,
                                  bottom: 0,
                                  start: widget.config.end ? null : 0,
                                  end: widget.config.end ? 0 : null,
                                  width: widget.config.extent,
                                  child: ClipRect(
                                    clipper: _SwipeRevealClipper(
                                      controller.value,
                                      fromRight: sign < 0,
                                    ),
                                    child: ExcludeSemantics(
                                      excluding: !open,
                                      child: ExcludeFocus(
                                        excluding: !open,
                                        child: IgnorePointer(
                                          ignoring: !open || !enabled,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              for (final action
                                                  in widget.config.actions)
                                                Expanded(
                                                  child: TextButton(
                                                    style: TextButton.styleFrom(
                                                      shape:
                                                          const RoundedRectangleBorder(),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                      backgroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .surfaceContainerHigh,
                                                    ),
                                                    onPressed:
                                                        enabled &&
                                                            !action.disabled
                                                        ? () => unawaited(
                                                            _dispatch(
                                                              action,
                                                              identity,
                                                            ),
                                                          )
                                                        : null,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        if (action.icon != null)
                                                          UiIcon(
                                                            action.icon,
                                                            size: 16,
                                                          ),
                                                        Text(action.label),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ClipRect(
                                clipper: _SwipeRevealClipper(
                                  1 -
                                      controller.value *
                                          widget.config.extent /
                                          bodyWidth,
                                  fromRight: sign > 0,
                                ),
                                child: Stack(
                                  children: [
                                    IgnorePointer(
                                      ignoring: intercept,
                                      child: ExcludeFocus(
                                        excluding: intercept,
                                        child: ExcludeSemantics(
                                          excluding: intercept,
                                          child: child!,
                                        ),
                                      ),
                                    ),
                                    if (intercept)
                                      Positioned.fill(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: open ? _close : null,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
          if (widget.config.longPressMenu) return body;
          final more = MenuAnchor(
            controller: menu,
            childFocusNode: menuFocus,
            onOpen: () {
              controller.value = 0;
              resources?.release(this);
              _own();
            },
            onClose: () => resources?.forget(this),
            menuChildren: [
              for (final action in widget.config.actions)
                MenuItemButton(
                  onPressed: enabled && !action.disabled
                      ? () => unawaited(_dispatch(action, identity))
                      : null,
                  leadingIcon: action.icon == null ? null : UiIcon(action.icon),
                  child: Text(action.label),
                ),
            ],
            builder: (_, menuController, _) => IconButton(
              focusNode: menuFocus,
              tooltip: '更多操作',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: enabled
                  ? () {
                      if (menuController.isOpen) {
                        menuController.close();
                      } else {
                        menuController.open();
                      }
                    }
                  : null,
              icon: const Icon(Icons.more_horiz),
            ),
          );
          return narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    body,
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: more,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: body),
                    more,
                  ],
                );
        },
      ),
    );
  }

  @override
  void dispose() {
    resources?.release(this);
    resources?.forget(this);
    position?.isScrollingNotifier.removeListener(_scrollChanged);
    menuFocus.dispose();
    controller.dispose();
    super.dispose();
  }
}

class _SwipeRevealClipper extends CustomClipper<Rect> {
  const _SwipeRevealClipper(this.fraction, {required this.fromRight});

  final double fraction;
  final bool fromRight;

  @override
  Rect getClip(Size size) {
    final width = size.width * fraction;
    return Rect.fromLTWH(
      fromRight ? size.width - width : 0,
      0,
      width,
      size.height,
    );
  }

  @override
  bool shouldReclip(_SwipeRevealClipper oldClipper) =>
      oldClipper.fraction != fraction || oldClipper.fromRight != fromRight;
}
