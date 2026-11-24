import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import 'ui_motion.dart';

/// Shared motion for Material routes, including module and settings pages.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder({this.reduceMotion = false});

  /// Routes created under this builder finish immediately after the first
  /// frame. A zero duration avoids holding a route on screen without motion.
  final bool reduceMotion;

  @override
  bool operator ==(Object other) =>
      other is AppPageTransitionsBuilder && other.reduceMotion == reduceMotion;

  @override
  int get hashCode => reduceMotion.hashCode;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : AppMotion.pageTransition;

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion || AppMotion.reduced(context)) return child;
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
          Tween(begin: AppMotion.pageOffset, end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
