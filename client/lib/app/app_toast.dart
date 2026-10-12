import '../core/ui/ui_component.dart';
import '../core/ui/native_ui.dart';
import '../core/ui/ui_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

/// A transient notice above routes and panels, without reserving page space.
class AppToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String message,
    String kind = 'info',
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final scope = UiScopeData.maybeOf(context);
    Widget inherit(Widget child) => InheritedTheme.captureAll(
      context,
      scope == null
          ? child
          : UiScopeData(
              registry: scope.registry,
              defaultTheme: scope.defaultTheme,
              defaultOnly: scope.defaultOnly,
              theme: scope.theme,
              child: child,
            ),
    );
    final previous = _current;
    previous?.remove();
    previous?.dispose();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 0,
        left: 12,
        right: 12,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: inherit(
                _ToastCard(
                  message: message,
                  kind: kind,
                  duration: duration,
                  onClosed: () {
                    if (identical(_current, entry)) {
                      _current = null;
                      entry.remove();
                      entry.dispose();
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onClosed,
  });

  final String message, kind;
  final Duration duration;
  final VoidCallback onClosed;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 140),
  );
  late final CurvedAnimation animation = CurvedAnimation(
    parent: controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? timer;
  bool initialized = false, closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = 1;
      } else {
        controller.forward();
      }
      timer = Timer(widget.duration, close);
    } else if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = closing ? 0 : 1;
    }
  }

  Future<void> close() async {
    if (closing) return;
    closing = true;
    timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) {
      try {
        await controller.reverse().orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (mounted) widget.onClosed();
  }

  @override
  void dispose() {
    timer?.cancel();
    animation.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.kind == 'error' ? scheme.error : scheme.primary;
    final icon = switch (widget.kind) {
      'error' => Icons.error_outline_rounded,
      'success' => Icons.check_circle_outline_rounded,
      _ => Icons.info_outline_rounded,
    };
    final notice = Material(
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .16),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UiIcon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 4),
            NativeUi(
              child: IconButton(
                tooltip: '关闭提示',
                onPressed: close,
                icon: const UiIcon(Icons.close_rounded, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -.18),
          end: Offset.zero,
        ).animate(animation),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: UiComponent(
              ref: 'ui.notification@1',
              props: {'message': widget.message, 'kind': widget.kind},
              slots: {'content': notice},
              fallback: notice,
            ),
          ),
        ),
      ),
    );
  }
}
