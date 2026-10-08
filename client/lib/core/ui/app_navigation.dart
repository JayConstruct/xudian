import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppNavigation extends NavigatorObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  final List<Route<dynamic>> _routes = [];

  bool get hasBlockingPopup => _routes.lastOrNull is PopupRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index < 0) return;
    if (newRoute == null) {
      _routes.removeAt(index);
    } else {
      _routes[index] = newRoute;
    }
  }

  void open(Widget page, {required String name}) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) throw StateError('应用导航尚未就绪');
    if (hasBlockingPopup) throw StateError('请先处理应用当前的弹窗');
    navigator.push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: name),
        builder: (_) => page,
      ),
    );
  }
}

final appNavigationProvider = Provider<AppNavigation>((ref) => AppNavigation());
