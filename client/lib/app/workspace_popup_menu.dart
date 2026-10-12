import '../core/ui/native_ui.dart';
import '../core/ui/ui_icon.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_system.dart';

/// The workspace menu animates as one surface, with a dismissible scrim.
class WorkspacePopupMenu extends StatefulWidget {
  const WorkspacePopupMenu({
    super.key,
    required this.items,
    required this.onSelected,
    this.haptics = true,
    this.reduceMotion = false,
  });

  final List<PopupMenuEntry<int>> items;
  final ValueChanged<int> onSelected;
  final bool haptics;
  final bool reduceMotion;

  @override
  State<WorkspacePopupMenu> createState() => _WorkspacePopupMenuState();
}

class _WorkspacePopupMenuState extends State<WorkspacePopupMenu> {
  bool _open = false;

  Future<void> _showMenu() async {
    if (_open) return;
    final navigator = Navigator.of(context);
    final button = context.findRenderObject()! as RenderBox;
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    final localizations = MaterialLocalizations.of(context);
    var anchor =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    setState(() => _open = true);
    if (widget.haptics) unawaited(HapticFeedback.lightImpact());
    final selected = await navigator.push<int>(
      _WorkspaceMenuRoute(
        items: widget.items,
        themes: themes,
        menuLabel: localizations.popupMenuLabel,
        dismissLabel: localizations.modalBarrierDismissLabel,
        reduceMotion:
            widget.reduceMotion || MediaQuery.disableAnimationsOf(context),
        anchor: () {
          if (button.attached && overlay.attached) {
            anchor =
                button.localToGlobal(Offset.zero, ancestor: overlay) &
                button.size;
          }
          return anchor;
        },
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (selected != null) widget.onSelected(selected);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    expanded: _open,
    child: NativeUi(
      child: IconButton(
        tooltip: '页面菜单',
        style: IconButton.styleFrom(
          minimumSize: const Size.square(kMinInteractiveDimension),
          fixedSize: const Size.square(kMinInteractiveDimension),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          backgroundColor: Theme.of(context).colorScheme.surface
              .withValues(alpha: MediaQuery.highContrastOf(context) ? 1 : .8),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(
              alpha: MediaQuery.highContrastOf(context) ? 1 : .45,
            ),
          ),
        ),
        icon: const UiIcon(Icons.more_horiz_rounded, size: 22),
        onPressed: _showMenu,
        // Opening feedback is provided once, using the app's haptic preference.
        enableFeedback: false,
      ),
    ),
  );
}

class _WorkspaceMenuRoute extends PopupRoute<int> {
  _WorkspaceMenuRoute({
    required this.items,
    required this.themes,
    required this.menuLabel,
    required this.dismissLabel,
    required this.reduceMotion,
    required this.anchor,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final List<PopupMenuEntry<int>> items;
  final CapturedThemes themes;
  final String menuLabel;
  final String dismissLabel;
  final bool reduceMotion;
  final Rect Function() anchor;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 120);

  @override
  bool get barrierDismissible => true;

  @override
  Color get barrierColor => const Color(0x1F000000);

  @override
  String get barrierLabel => dismissLabel;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final direction = Directionality.of(context);
    final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return CustomSingleChildLayout(
      delegate: _WorkspaceMenuLayout(
        anchor(),
        media.padding + media.viewInsets,
        direction,
      ),
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: curved.drive(Tween(begin: .94, end: 1.0)),
          alignment: direction == TextDirection.ltr
              ? Alignment.topRight
              : Alignment.topLeft,
          child: themes.wrap(
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                return Semantics(
                  role: SemanticsRole.menu,
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: menuLabel,
                  child: Material(
                    key: const ValueKey('workspace-menu-surface'),
                    color:
                        theme.popupMenuTheme.color ?? theme.colorScheme.surface,
                    elevation: theme.popupMenuTheme.elevation ?? 8,
                    shape: AppDesign.smoothShape(radius: 20),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: IntrinsicWidth(child: ListBody(children: items)),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceMenuLayout extends SingleChildLayoutDelegate {
  _WorkspaceMenuLayout(this.anchor, this.padding, this.direction);

  final Rect anchor;
  final EdgeInsets padding;
  final TextDirection direction;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.max(0.0, constraints.maxWidth - padding.horizontal - 16);
    return BoxConstraints(
      minWidth: math.min(196, width),
      maxWidth: math.min(280, width),
      maxHeight: math.max(0, constraints.maxHeight - padding.vertical - 16),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = direction == TextDirection.ltr
        ? anchor.right - childSize.width
        : anchor.left;
    return Offset(
      x.clamp(
        padding.left + 8,
        size.width - padding.right - childSize.width - 8,
      ),
      (anchor.bottom + 4).clamp(
        padding.top + 8,
        size.height - padding.bottom - childSize.height - 8,
      ),
    );
  }

  @override
  bool shouldRelayout(_WorkspaceMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      padding != oldDelegate.padding ||
      direction != oldDelegate.direction;
}
