import 'package:flutter/material.dart';

/// Shared host motion defaults. Script declarations can override durations.
abstract final class AppMotion {
  /// Selection tint in a standalone date overview, not the title or strip.
  static const dateChange = Duration(milliseconds: 180);
  static const dateTitle = Duration(milliseconds: 280);
  static const dateStrip = Duration(milliseconds: 320);

  /// Decorative background feedback; content readiness uses its own fade.
  static const dateReveal = Duration(milliseconds: 480);
  static const dateContentFade = Duration(milliseconds: 180);
  static const dateContentLeave = Duration(milliseconds: 120);
  static const dateWaveSpacing = Duration(milliseconds: 80);

  /// Reserved rhythm; current quick-add transitions declare 220ms in JS.
  static const disclosure = Duration(milliseconds: 220);
  static const scriptTransition = Duration(milliseconds: 350);
  static const pageTransition = Duration(milliseconds: 300);
  static const pageOffset = Offset(.04, 0);
  static const workspaceTransition = Duration(milliseconds: 360);
  static const enter = Curves.easeOutCubic;
  static const leave = Curves.easeInCubic;

  static AnimationStyle dialogStyle(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 180),
          reverseDuration: Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration duration(
    BuildContext context,
    Duration normal, {
    bool respectHighContrast = false,
  }) =>
      reduced(context) ||
          respectHighContrast && MediaQuery.highContrastOf(context)
      ? Duration.zero
      : normal;
}

/// Geometry for short form and confirmation dialogs; DialogRoute owns the fade.
class CompactDialogMotion extends StatelessWidget {
  const CompactDialogMotion({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || AppMotion.reduced(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = AppMotion.enter.transform(animation.value);
        return Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: Transform.scale(scale: .98 + .02 * t, child: child),
        );
      },
    );
  }
}
