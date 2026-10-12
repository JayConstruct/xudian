import 'package:flutter/material.dart';

/// Shared presentation for workspace dates, contributed titles and toolbars.
/// Modules continue to own their labels and navigation actions.
abstract final class WorkspaceTypography {
  static const titleMaxLines = 3;
  static const titlePadding = EdgeInsets.symmetric(horizontal: 6, vertical: 8);

  static TextStyle titleStyle(TextTheme theme) =>
      (theme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
      );
}
