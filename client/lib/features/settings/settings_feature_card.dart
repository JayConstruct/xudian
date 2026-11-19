import 'package:flutter/material.dart';

import '../../core/ui/ui_design.dart';
import '../../core/ui/ui_icon.dart';

class SettingsFeatureCard extends StatelessWidget {
  const SettingsFeatureCard({
    super.key,
    this.appearance = false,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool appearance;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = appearance
        ? colors.primary
        : dark
        ? const Color(0xffbdd6c7)
        : const Color(0xff486359);
    final greenTint = dark ? const Color(0x2e3e7c4e) : const Color(0x1f4e7966);
    final base = appearance
        ? Color.lerp(colors.surface, colors.primaryContainer, dark ? .76 : 1)!
        : Color.alphaBlend(greenTint, colors.surface);
    final outline = Color.lerp(base, accent, .16)!;
    final shape = AppDesign.smoothShape(
      radius: 18,
      side: BorderSide(color: outline, width: .8),
    );
    return Material(
      color: base,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomPaint(
                      size: const Size(47, 32),
                      painter: _SettingsPreview(
                        appearance: appearance,
                        accent: accent,
                        background: base,
                        colors: colors,
                      ),
                    ),
                    const Spacer(),
                    UiIcon(
                      Icons.chevron_right_rounded,
                      size: 12,
                      color: accent,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12.7, height: 1.35, color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPreview extends CustomPainter {
  const _SettingsPreview({
    required this.appearance,
    required this.accent,
    required this.background,
    required this.colors,
  });
  final bool appearance;
  final Color accent, background;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint();
    final outline = Color.lerp(background, accent, .55)!;
    void panel(Rect rect, double radius, Color paper, Color border) {
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(shape, fill..color = paper);
      canvas.drawRRect(shape, ink..color = border);
    }

    void line(double x1, double y1, double x2, double y2, Color color) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), ink..color = color);
    canvas.save();
    canvas.translate(1, 0);
    if (appearance) {
      panel(const Rect.fromLTWH(0, 1, 28, 24), 6, colors.surface, outline);
      canvas.drawCircle(const Offset(11, 12), 3.2, ink..color = accent);
      line(11, 6, 11, 7, accent);
      line(11, 17, 11, 18, accent);
      line(5, 12, 6, 12, accent);
      line(16, 12, 17, 12, accent);
      final night = colors.brightness == Brightness.dark
          ? Color.lerp(colors.onPrimary, colors.primary, .35)!
          : colors.primary;
      panel(const Rect.fromLTWH(20, 9, 25, 21), 5.5, night, night);
      final moon = Path()
        ..moveTo(35.8, 14)
        ..cubicTo(28.7, 14.8, 30.5, 25.4, 38, 23)
        ..lineTo(39, 22.4)
        ..cubicTo(35.5, 21.8, 33.9, 17.4, 35.8, 14)
        ..close();
      canvas.drawPath(
        moon,
        fill
          ..color = colors.brightness == Brightness.dark
              ? colors.primary
              : colors.onPrimary,
      );
    } else {
      panel(const Rect.fromLTWH(9, 1, 35, 24), 4, colors.surface, outline);
      line(20, 2.5, 20, 23.5, outline);
      line(24, 9, 37, 9, outline);
      line(24, 13, 33, 13, outline);
      panel(const Rect.fromLTWH(0, 6, 16, 24), 3.5, background, accent);
      line(2, 23.6, 14, 23.6, accent);
      line(6.2, 26.6, 9.8, 26.6, accent);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SettingsPreview oldDelegate) =>
      appearance != oldDelegate.appearance ||
      accent != oldDelegate.accent ||
      background != oldDelegate.background ||
      colors != oldDelegate.colors;
}
