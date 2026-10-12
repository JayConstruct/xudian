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
