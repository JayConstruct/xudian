import 'package:flutter/material.dart';

/// Shared host motion rhythm. Business modules only declare visible state.
abstract final class AppMotion {
  static const dateChange = Duration(milliseconds: 180);
  static const disclosure = Duration(milliseconds: 220);
  static const scriptTransition = Duration(milliseconds: 350);
  static const workspaceTransition = Duration(milliseconds: 360);
  static const enter = Curves.easeOutCubic;
  static const leave = Curves.easeInCubic;

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
