import 'package:flutter/material.dart';

/// Stable presentation colors; independent of ordering, dates and app restarts.
abstract final class ContentColors {
  static Color accent(Object? identity, {Object? color}) {
    if (color is int) return Color(color).withValues(alpha: 1);
    if (color is String && RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(color)) {
      return Color(int.parse('FF${color.substring(1)}', radix: 16));
    }
    var hash = 0x811c9dc5;
    for (final unit in '${identity ?? ''}'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    // Continuous hues rather than a small repeating palette. Color is an aid;
    // titles, times, source icons and hatching still identify each block.
    return HSLColor.fromAHSL(1, (hash % 36000) / 100, .58, .56).toColor();
  }

  static Color surface(Color accent, ColorScheme scheme) => Color.alphaBlend(
    accent.withValues(alpha: scheme.brightness == Brightness.dark ? .24 : .20),
    scheme.surface,
  );

  static Color foreground(Color accent, Color background, Color ink) {
    final backgroundLuminance = background.computeLuminance();
    for (var step = 0; step <= 20; step++) {
      final candidate = Color.lerp(
        accent.withValues(alpha: 1),
        ink,
        step / 20,
      )!;
      final luminance = candidate.computeLuminance();
      final contrast = luminance > backgroundLuminance
          ? (luminance + .05) / (backgroundLuminance + .05)
          : (backgroundLuminance + .05) / (luminance + .05);
      if (contrast >= 4.5) return candidate;
    }
    return ink;
  }
}
