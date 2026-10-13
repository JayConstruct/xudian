import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'native_ui.dart';
import 'ui_component.dart';
import 'ui_icon.dart';

/// A transient notice above routes and panels, without reserving page space.
class AppToast {
  // Each app/window owns its notice. An overlay that is disposed must not leave
  // an entry behind for the next app/window to remove.
  static final _active = Expando<_ToastHandle>();

  static const defaultDuration = Duration(seconds: 3);
  static const enterDuration = Duration(milliseconds: 180);
  static const exitDuration = Duration(milliseconds: 140);

  static void show(
    BuildContext context, {
    required String message,
    String kind = 'info',
    Duration duration = defaultDuration,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final previous = _active[overlay];
    // Repeated feedback neither restarts motion nor extends the deadline.
    // A notice already leaving can be shown again as a new interaction.
    if (previous != null &&
        previous.message == message &&
        previous.kind == kind &&
        previous.cardKey.currentState?.closing != true) {
      return;
    }
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
    previous?.entry.remove();
    previous?.entry.dispose();
    final cardKey = GlobalKey<_ToastCardState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
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
                  key: cardKey,
                  message: message,
                  kind: kind,
                  duration: duration,
                  topInset: MediaQuery.paddingOf(overlayContext).top,
                  onClosed: () {
                    if (identical(_active[overlay]?.entry, entry)) {
                      _active[overlay] = null;
                      entry.remove();
                      entry.dispose();
                    }
                  },
                  onDisposed: () {
                    if (identical(_active[overlay]?.entry, entry)) {
                      _active[overlay] = null;
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _active[overlay] = _ToastHandle(entry, cardKey, message, kind);
    overlay.insert(entry);
  }
}

class _ToastHandle {
  _ToastHandle(this.entry, this.cardKey, this.message, this.kind);

  final OverlayEntry entry;
  final GlobalKey<_ToastCardState> cardKey;
  final String message, kind;
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    super.key,
    required this.message,
    required this.kind,
    required this.duration,
    required this.topInset,
    required this.onClosed,
    required this.onDisposed,
  });

  final String message, kind;
  final Duration duration;
  // SafeArea consumes MediaQuery.padding.top before the card is built.
  final double topInset;
  final VoidCallback onClosed;
  final VoidCallback onDisposed;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: AppToast.enterDuration,
    reverseDuration: AppToast.exitDuration,
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
    widget.onDisposed();
    timer?.cancel();
    animation.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final textHeight = math.max(
      48.0,
      media.size.height -
          widget.topInset -
          media.padding.bottom -
          media.viewInsets.bottom -
          36,
    );
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
            Semantics(
              label: switch (widget.kind) {
                'error' => '错误',
                'success' => '成功',
                _ => '提示',
              },
              child: ExcludeSemantics(
                child: UiIcon(icon, color: color, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: textHeight),
                child: SingleChildScrollView(
                  child: Text(
                    widget.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
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
