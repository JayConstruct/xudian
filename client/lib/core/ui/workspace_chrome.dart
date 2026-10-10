import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Opt-in workspace chrome follows deliberate vertical scrolling. Resizes,
/// restored positions and script-driven jumps cannot hide navigation.
class WorkspaceChromeController extends ChangeNotifier {
  String? _identity;
  bool _enabled = false, _userScrolling = false;
  bool collapsed = false;
  double _distance = 0;
  bool _scheduled = false, _disposed = false;

  void configure(String identity, {required bool enabled}) {
    if (_identity != identity || _enabled != enabled) {
      _identity = identity;
      _enabled = enabled;
      collapsed = false;
      _userScrolling = false;
      _distance = 0;
    }
  }

  bool handleScroll(ScrollNotification notification) {
    if (!_enabled ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
      if (!_userScrolling) _distance = 0;
    } else if (notification is ScrollStartNotification) {
      _userScrolling = notification.dragDetails != null;
      _distance = 0;
    } else if (notification is ScrollEndNotification) {
      _userScrolling = false;
      _distance = 0;
    } else if (notification is OverscrollNotification) {
      if ((_userScrolling || notification.dragDetails != null) &&
          notification.overscroll < 0 &&
          notification.metrics.pixels <=
              notification.metrics.minScrollExtent + 1) {
        reveal();
      }
    } else if (notification is ScrollUpdateNotification &&
        (_userScrolling || notification.dragDetails != null)) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (delta < 0 &&
          notification.metrics.pixels <=
              notification.metrics.minScrollExtent + 1) {
        reveal();
        return false;
      }
      if (_distance.sign != delta.sign) _distance = 0;
      _distance += delta;
      if (!collapsed &&
          _distance >= 48 &&
          notification.metrics.pixels > notification.metrics.minScrollExtent) {
        collapsed = true;
        _distance = 0;
        _notifyLater();
      } else if (collapsed && _distance <= -16) {
        reveal();
      }
    }
    return false;
  }

  void reveal() {
    _distance = 0;
    if (!collapsed) return;
    collapsed = false;
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
