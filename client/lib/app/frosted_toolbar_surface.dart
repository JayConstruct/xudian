import 'dart:ui';

import 'package:flutter/material.dart';

import 'design_system.dart';

/// A bounded glass surface leaves underlying content visible while keeping
/// controls legible. High contrast uses an opaque surface without blur.
class FrostedToolbarSurface extends StatelessWidget {
  const FrostedToolbarSurface({
    super.key,
    required this.child,
    this.radius = AppDesign.dockRadius,
    this.surfaceKey,
  });

  final Widget child;
  final double radius;
  final Key? surfaceKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final shape = AppDesign.smoothShape(radius: radius);
    final surface = Color.alphaBlend(
      scheme.primary.withValues(alpha: dark ? .035 : .015),
      scheme.surface,
    );
    return RepaintBoundary(
      child: DecoratedBox(
        key: surfaceKey,
        decoration: ShapeDecoration(
          shape: shape,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .24 : .07),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRSuperellipse(
          borderRadius: shape.borderRadius,
          child: BackdropFilter(
            enabled: !highContrast,
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape.copyWith(
                  side: BorderSide(
                    color: highContrast
                        ? scheme.onSurface.withValues(alpha: .35)
                        : scheme.outlineVariant.withValues(
                            alpha: dark ? .5 : .6,
                          ),
                  ),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    surface.withValues(alpha: highContrast ? 1 : .9),
                    surface.withValues(alpha: highContrast ? 1 : .84),
                  ],
                ),
              ),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
