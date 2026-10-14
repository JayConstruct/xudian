import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import '../performance/ui_load_trace.dart';

/// The workspace can prepare a destination before replacing visible content.
class PageFirstFrameScope extends InheritedWidget {
  PageFirstFrameScope({super.key, required this.onReady, required Widget child})
    : super(child: PageFirstFrameGate(child: child));

  final VoidCallback onReady;

  static PageFirstFrameScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageFirstFrameScope>();

  @override
  bool updateShouldNotify(PageFirstFrameScope oldWidget) => false;
}

/// Tracks actual renderers rather than imposing a loading or animation delay.
class PageFirstFrameReadiness {
  PageFirstFrameReadiness(this.onReady);
  final VoidCallback onReady;
  final pending = <Object>{};
  bool blocked = false, reported = false, disposed = false, scheduled = false;
  bool awaitingNextPaint = false;

  void begin(Object owner) {
    if (reported || disposed) return;
    pending.add(owner);
  }

  void complete(Object owner, {bool painted = false}) {
    pending.remove(owner);
    if (!painted &&
        WidgetsBinding.instance.schedulerPhase ==
            SchedulerPhase.postFrameCallbacks) {
      // An already queued callback for this frame cannot validate a tree that
      // was changed after paint. Reserve an actual subsequent frame instead.
      if (!awaitingNextPaint) {
        awaitingNextPaint = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          awaitingNextPaint = false;
          _reportIfReady();
        });
        WidgetsBinding.instance.scheduleFrame();
      }
      return;
    }
    // A nested gate has already checked its rendered subtree after paint. Its
    // readiness can propagate through ancestors in this same frame. Script
    // results and composition notifications still wait for their own next paint.
    if (painted &&
        WidgetsBinding.instance.schedulerPhase ==
            SchedulerPhase.postFrameCallbacks) {
      _reportIfReady();
      return;
    }
    checkAfterFrame();
  }

  void _reportIfReady() {
    if (disposed ||
        reported ||
        blocked ||
        awaitingNextPaint ||
        pending.isNotEmpty) {
      return;
    }
    reported = true;
    onReady();
  }

  void checkAfterFrame() {
    if (scheduled || reported || disposed) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      _reportIfReady();
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}

class PageFirstFrameReadinessScope extends InheritedWidget {
  const PageFirstFrameReadinessScope({
    super.key,
    required this.readiness,
    required super.child,
  });
  final PageFirstFrameReadiness readiness;

  static PageFirstFrameReadiness? read(BuildContext context) => context
      .getInheritedWidgetOfExactType<PageFirstFrameReadinessScope>()
      ?.readiness;

  @override
  bool updateShouldNotify(PageFirstFrameReadinessScope oldWidget) =>
      readiness != oldWidget.readiness;
}

/// Root pages hold this gate during initialization, then release it only after
/// all current script renderers and composed sections have a usable first tree.
class PageFirstFrameGate extends StatefulWidget {
  const PageFirstFrameGate({
    super.key,
    this.blocked = false,
    required this.child,
  });
  final bool blocked;
  final Widget child;

  @override
  State<PageFirstFrameGate> createState() => _PageFirstFrameGateState();
}

class _PageFirstFrameGateState extends State<PageFirstFrameGate> {
  final loadTrace = UiLoadTrace.start('page.firstFrame');
  PageFirstFrameReadiness? parentReadiness;
  late final readiness = PageFirstFrameReadiness(() {
    if (!mounted) return;
    loadTrace?.finish(arguments: {'outcome': 'ready'});
    if (parentReadiness != null) {
      parentReadiness!.complete(this, painted: true);
    } else {
      PageFirstFrameScope.read(context)?.onReady();
    }
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = PageFirstFrameReadinessScope.read(context);
    if (parent == parentReadiness) return;
    parentReadiness?.complete(this);
    parentReadiness = parent;
    if (!readiness.reported) parentReadiness?.begin(this);
  }

  @override
  void dispose() {
    loadTrace?.finish(arguments: {'outcome': 'disposed'});
    parentReadiness?.complete(this);
    readiness.disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    readiness.blocked = widget.blocked;
    readiness.checkAfterFrame();
    return PageFirstFrameReadinessScope(
      readiness: readiness,
      child: widget.child,
    );
  }
}
