import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/content_colors.dart';

double _contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  test('identity colors survive reordering and reconstructed identities', () {
    final identities = List.generate(80, (i) => 'course:$i');
    final original = {
      for (final identity in identities)
        identity: ContentColors.accent(identity),
    };
    for (final identity in identities.reversed) {
      final reconstructed = String.fromCharCodes(identity.codeUnits);
      expect(ContentColors.accent(reconstructed), original[identity]);
    }
  });

  test('many identities use a broad hue range beyond a fixed palette', () {
    final colors = List.generate(240, (i) => ContentColors.accent('task:$i'));
    expect(colors.toSet().length, greaterThan(100));
    final hueBands = colors
        .map((color) => (HSLColor.fromColor(color).hue / 30).floor())
        .toSet();
    expect(hueBands.length, greaterThanOrEqualTo(10));
  });

  test('explicit hex and integer colors override the identity', () {
    expect(
      ContentColors.accent('first', color: '#aB46C8'),
      const Color(0xffab46c8),
    );
    expect(
      ContentColors.accent('second', color: 0x11337799),
      const Color(0xff337799),
    );
    expect(
      ContentColors.accent('third', color: '#aB46C8'),
      ContentColors.accent('first', color: '#aB46C8'),
    );
  });

  test('malformed custom colors fall back to the stable identity color', () {
    final fallback = ContentColors.accent('stable');
    for (final malformed in <Object?>[
      null,
      '',
      '#123',
      '#1234567',
      '#GG1234',
      'red',
      1.5,
      <String, Object?>{'color': '#123456'},
    ]) {
      expect(ContentColors.accent('stable', color: malformed), fallback);
    }
  });

  for (final brightness in Brightness.values) {
    test('titles meet 4.5 contrast on $brightness colored surfaces', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xff6750a4),
        brightness: brightness,
      );
      final accents = [
        for (var i = 0; i < 240; i++) ContentColors.accent('subject:$i'),
        Colors.black,
        Colors.white,
        Colors.yellow,
        Colors.blue,
      ];
      for (final accent in accents) {
        final background = ContentColors.surface(accent, scheme);
        final foreground = ContentColors.foreground(
          accent,
          background,
          scheme.onSurface,
        );
        expect(background.a, 1);
        expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
    });
  }
}
