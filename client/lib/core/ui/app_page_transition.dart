import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import 'ui_motion.dart';

/// Shared motion for Material routes, including module and settings pages.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return const CupertinoPageTransitionsBuilder().buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    final incoming = animation.drive(CurveTween(curve: AppMotion.enter));
    return FadeTransition(
      opacity: incoming,
      child: SlideTransition(
        position: incoming.drive(
          Tween(begin: const Offset(.04, 0), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
