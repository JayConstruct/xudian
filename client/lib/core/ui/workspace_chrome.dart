import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Chrome follows physical user travel, never a released-finger simulation,
/// restored position or layout correction. Partial travel stays where released.
class WorkspaceChromeController extends ChangeNotifier {
  String? _identity;
  bool _enabled = false;
  double _headerExtent = 64, _hiddenExtent = 0;
  double? _wheelTravel;
  bool _scheduled = false, _disposed = false;

  double get headerExtent => _headerExtent;
  double get hiddenExtent => _hiddenExtent;
  double get progress => (_hiddenExtent / _headerExtent).clamp(0, 1);
  bool get collapsed => progress >= 1;
  bool get expanded => _hiddenExtent == 0;

  void configure(String identity, {required bool enabled}) {
    if (_identity != identity || _enabled != enabled) {
      _identity = identity;
      _enabled = enabled;
      _hiddenExtent = 0;
      _wheelTravel = null;
    }
  }

  void updateHeaderExtent(double value) {
    if (_disposed ||
        !value.isFinite ||
        value <= 0 ||
        (value - _headerExtent).abs() < .1) {
      return;
    }
    final wasCollapsed = collapsed;
    _headerExtent = value;
    _hiddenExtent = wasCollapsed ? value : _hiddenExtent.clamp(0, value);
    _notifyLater();
  }

  /// A pointer signal explicitly authorizes one wheel update. User-scroll
  /// direction alone cannot distinguish a wheel from inertial scrolling.
  void handlePointerSignal(PointerSignalEvent event) {
    if (!_enabled ||
        event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0) {
      return;
    }
    _wheelTravel = event.scrollDelta.dy;
    WidgetsBinding.instance.addPostFrameCallback((_) => _wheelTravel = null);
  }

  bool handleScroll(ScrollNotification notification) {
    if (!_enabled ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    // Coordinated scroll positions already allocate this physical movement
    // before scrolling the content. Their notifications must not apply it twice.
    final notificationContext = notification.context;
    if (notificationContext != null) {
      final position = Scrollable.maybeOf(notificationContext)?.position;
      if (position is _WorkspaceChromeScrollPosition &&
          identical(position.chrome, this)) {
        return false;
      }
    }
    double? delta;
    double previous = notification.metrics.pixels;
    if (notification is ScrollUpdateNotification) {
      previous -= notification.scrollDelta ?? 0;
      final drag = notification.dragDetails;
      if (drag != null) {
        delta = -(drag.primaryDelta ?? drag.delta.dy);
        if (notification.metrics.axisDirection == AxisDirection.up) {
          delta = -delta;
        }
      } else if (_wheelTravel != null &&
          (notification.scrollDelta ?? 0).sign == _wheelTravel!.sign) {
        delta = notification.scrollDelta;
        _wheelTravel = null;
      }
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      final drag = notification.dragDetails!;
      delta = -(drag.primaryDelta ?? drag.delta.dy);
      if (notification.metrics.axisDirection == AxisDirection.up) {
        delta = -delta;
      }
    }
    if (delta == null || delta == 0) return false;
    final min = notification.metrics.minScrollExtent;
    if (delta > 0 && previous < min) {
      // An upward finger first closes the top pull-down gap. Only its remaining
      // travel can move the toolbar, even when one update crosses the edge.
      if (notification.metrics.pixels <= min) return false;
      // Bouncing physics can resist travel even while closing the gap. The
      // in-bounds remainder is the distance actually left after that resistance.
      delta = (notification.metrics.pixels - min).clamp(0, delta);
    }
    final next = (_hiddenExtent + delta).clamp(0, _headerExtent).toDouble();
    if (next != _hiddenExtent) {
      _hiddenExtent = next;
      _notifyLater();
    }
    return false;
  }

  double _consumeScrollDelta(ScrollMetrics metrics, double delta) {
    if (!_enabled || delta == 0) return delta;
    // Let bouncing scroll physics close the real pull-down gap first. Only
    // travel remaining beyond that edge can start collapsing the header.
    final gap = delta > 0 && metrics.pixels < metrics.minScrollExtent
        ? (metrics.minScrollExtent - metrics.pixels).clamp(0.0, delta)
        : 0.0;
    final content = delta < 0 && metrics.pixels > metrics.minScrollExtent
        ? (metrics.pixels - metrics.minScrollExtent).clamp(0.0, -delta)
        : 0.0;
    final available = delta - gap + content;
    final next = (_hiddenExtent + available)
        .clamp(0.0, _headerExtent)
        .toDouble();
    final consumed = next - _hiddenExtent;
    if (consumed != 0) {
      _hiddenExtent = next;
      _notifyLater();
    }
    return delta - consumed;
  }

  void reveal() {
    if (_hiddenExtent == 0) return;
    _hiddenExtent = 0;
    _notifyLater();
  }

  void _notifyLater() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Supplies the workspace header to scrollables that allocate header and content
/// travel in sequence, rather than reacting after both have moved.
class WorkspaceChromeScrollScope extends InheritedWidget {
  const WorkspaceChromeScrollScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final WorkspaceChromeController controller;

  static WorkspaceChromeController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WorkspaceChromeScrollScope>()
      ?.controller;

  @override
  bool updateShouldNotify(WorkspaceChromeScrollScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

/// Coordinates physical drags and wheel movement only. Ballistic scrolling,
/// restored offsets and programmatic jumps retain their normal behavior.
class WorkspaceChromeScrollController extends ScrollController {
  WorkspaceChromeController? _chrome;

  set chrome(WorkspaceChromeController? value) {
    _chrome = value;
    for (final position in positions) {
      (position as _WorkspaceChromeScrollPosition).chrome = value;
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _WorkspaceChromeScrollPosition(
    chrome: _chrome,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _WorkspaceChromeScrollPosition extends ScrollPositionWithSingleContext {
  _WorkspaceChromeScrollPosition({
    required this.chrome,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  WorkspaceChromeController? chrome;

  @override
  void applyUserOffset(double delta) {
    if (delta == 0) return;
    updateUserScrollDirection(
      delta > 0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    final scrollDelta = -physics.applyPhysicsToUserOffset(this, delta);
    final remaining =
        chrome?._consumeScrollDelta(this, scrollDelta) ?? scrollDelta;
    if (remaining != 0) setPixels(pixels + remaining);
  }

  @override
  void pointerScroll(double delta) {
    final remaining = chrome?._consumeScrollDelta(this, delta) ?? delta;
    super.pointerScroll(remaining);
  }

  @override
  void correctBy(double correction) {
    final controller = chrome;
    if (controller != null &&
        controller._enabled &&
        controller.expanded &&
        activity is DragScrollActivity &&
        pixels < minScrollExtent &&
        correction == minScrollExtent - pixels) {
      return;
    }
    super.correctBy(correction);
  }

  @override
  double applyBoundaryConditions(double value) {
    final controller = chrome;
    if (controller != null &&
        controller._enabled &&
        !controller.expanded &&
        pixels >= minScrollExtent &&
        value < minScrollExtent) {
      return value - minScrollExtent;
    }
    return super.applyBoundaryConditions(value);
  }

  @override
  void goBallistic(double velocity) {
    final controller = chrome;
    if (controller != null &&
        controller._enabled &&
        ((velocity > 0 && !controller.collapsed) ||
            (velocity < 0 &&
                pixels <= minScrollExtent &&
                !controller.expanded))) {
      // A fling cannot skip the unfinished first stage and start scrolling
      // rows under a partially moved header. Keep bounce correction available.
      velocity = 0;
    }
    super.goBallistic(velocity);
  }
}

/// The original full-height header remains mounted. Bottom alignment moves it
/// upwards behind the clip by exactly the hidden physical distance.
class WorkspaceChromeHeader extends StatelessWidget {
  const WorkspaceChromeHeader({
    super.key,
    required this.controller,
    required this.child,
  });
  final WorkspaceChromeController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: _HeaderExtentReporter(
      onHeight: controller.updateHeaderExtent,
      child: child,
    ),
    builder: (context, child) => ClipRect(
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1 - controller.progress,
        child: Offstage(offstage: controller.collapsed, child: child),
      ),
    ),
  );
}

class _HeaderExtentReporter extends SingleChildRenderObjectWidget {
  const _HeaderExtentReporter({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _HeaderExtentRenderBox(onHeight);
  @override
  void updateRenderObject(
    BuildContext context,
    _HeaderExtentRenderBox renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _HeaderExtentRenderBox extends RenderProxyBox {
  _HeaderExtentRenderBox(this.onHeight);
  ValueChanged<double> onHeight;
  double? previous;
  @override
  void performLayout() {
    super.performLayout();
    if (previous != size.height) {
      previous = size.height;
      final height = size.height;
      WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
    }
  }
}
