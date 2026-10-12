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
    this.pill = false,
    this.clipContent = true,
    this.surfaceKey,
  });

  final Widget child;
  final double radius;
  final bool pill;
  final bool clipContent;
  final Key? surfaceKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final shape = pill
        ? const StadiumBorder()
        : AppDesign.smoothShape(radius: radius);
    final surface = Color.alphaBlend(
      scheme.primary.withValues(alpha: dark ? .025 : .008),
      scheme.surface,
    );
    final glass = BackdropFilter(
      enabled: !highContrast,
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape.copyWith(
            side: BorderSide(
              color: highContrast
                  ? scheme.onSurface.withValues(alpha: .35)
                  : scheme.outlineVariant.withValues(alpha: .35),
            ),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              surface.withValues(alpha: highContrast ? 1 : .88),
              surface.withValues(alpha: highContrast ? 1 : .80),
            ],
          ),
        ),
        child: clipContent
            ? Material(type: MaterialType.transparency, child: child)
            : null,
      ),
    );
    return RepaintBoundary(
      child: DecoratedBox(
        key: surfaceKey,
        decoration: ShapeDecoration(
          shape: shape,
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .22 : .045),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .08 : .025),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: !clipContent
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipPath(
                      clipper: ShapeBorderClipper(shape: shape),
                      child: glass,
                    ),
                  ),
                  RepaintBoundary(
                    child: Material(
                      type: MaterialType.transparency,
                      child: child,
                    ),
                  ),
                ],
              )
            : pill
            ? ClipPath(
                clipper: const ShapeBorderClipper(shape: StadiumBorder()),
                child: glass,
              )
            : ClipRSuperellipse(
                borderRadius: BorderRadius.circular(radius),
                child: glass,
              ),
      ),
    );
  }
}
