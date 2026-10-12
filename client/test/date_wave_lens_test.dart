import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/date_wave_lens.dart';

void main() {
  test('wavefront locally enlarges by 1.04 while its position stays fixed', () {
    double sample(double d) =>
        dateWaveLensSourceRadius(distance: d, radius: 100, width: 56);
    expect(sample(100), 100);
    final sourceDerivative = (sample(100.001) - sample(99.999)) / .002;
    expect(1 / sourceDerivative, closeTo(1.0416667, .00001));
    expect(sample(72), 72);
    expect(sample(128), 128);
    expect(sample(40), 40);
    expect(sample(160), 160);
    var maxDisplacement = 0.0;
    for (var d = 72.0; d <= 128; d += .1) {
      final displacement = (sample(d) - d).abs();
      if (displacement > maxDisplacement) maxDisplacement = displacement;
    }
    expect(maxDisplacement, greaterThan(.2));
    expect(maxDisplacement, lessThan(1));
  });

  test('zero strength preserves the complete page geometry', () {
    for (var d = 0.0; d < 200; d++) {
      expect(
        dateWaveLensSourceRadius(
          distance: d,
          radius: 100,
          width: 56,
          strength: 0,
        ),
        d,
      );
    }
  });

  testWidgets(
    'only the wave band refracts, leaving navigation and interior still',
    (tester) async {
      await tester.runAsync(() async {
        const size = ui.Size(240, 240);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          ui.Offset.zero & size,
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        for (var x = 0; x < 240; x += 4) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x.toDouble(), 0, 2, 240),
            ui.Paint()..color = const ui.Color(0xFF000000),
          );
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(240, 240);
        picture.dispose();
        final painted = ui.PictureRecorder();
        final output = ui.Canvas(painted);
        output.drawImage(image, ui.Offset.zero, ui.Paint());
        const navigation = ui.Rect.fromLTWH(0, 0, 240, 60);
        expect(
          paintDateWaveLens(
            output,
            oldImage: image,
            newImage: image,
            oldSize: size,
            newSize: size,
            origin: const ui.Offset(120, 120),
            radius: 80,
            width: 56,
            bounds: ui.Offset.zero & size,
            navigation: [navigation],
          ),
          isTrue,
        );
        final resultPicture = painted.endRecording();
        final result = await resultPicture.toImage(240, 240);
        resultPicture.dispose();
        final before = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final after = (await result.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var refractedPixels = 0;
        for (var y = 0; y < 240; y++) {
          for (var x = 0; x < 240; x++) {
            final distance =
                (ui.Offset(x + .5, y + .5) - const ui.Offset(120, 120))
                    .distance;
            final offset = (y * 240 + x) * 4;
            final changed = before[offset] != after[offset];
            if (y < 60 || distance < 50 || distance > 110) {
              expect(changed, isFalse, reason: 'unaffected pixel ($x,$y)');
            } else if (changed) {
              refractedPixels++;
            }
          }
        }
        expect(refractedPixels, greaterThan(500));
        // The texture at the wavefront itself does not jump to another stripe.
        // Pixel centres sit half a pixel either side of the mathematical circle;
        // tolerate the corresponding tiny bilinear sampling displacement.
        for (final x in [199, 200]) {
          final offset = (120 * 240 + x) * 4;
          expect((after[offset] - before[offset]).abs(), lessThan(10));
        }
        image.dispose();
        result.dispose();
      });
    },
  );

  testWidgets(
    'old and new half bands preserve their own dates without crossing',
    (tester) async {
      await tester.runAsync(() async {
        Future<ui.Image> solid(ui.Color color, int pixels) async {
          final recorder = ui.PictureRecorder();
          ui.Canvas(recorder).drawRect(
            ui.Rect.fromLTWH(0, 0, pixels.toDouble(), pixels.toDouble()),
            ui.Paint()..color = color,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(pixels, pixels);
          picture.dispose();
          return image;
        }

        final old = await solid(const ui.Color(0xFFFF0000), 240);
        final target = await solid(const ui.Color(0xFF0000FF), 480);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImage(old, ui.Offset.zero, ui.Paint());
        canvas.drawCircle(
          const ui.Offset(120, 120),
          80,
          ui.Paint()..color = const ui.Color(0xFF0000FF),
        );
        paintDateWaveLens(
          canvas,
          oldImage: old,
          newImage: target,
          oldSize: const ui.Size(240, 240),
          newSize: const ui.Size(240, 240),
          origin: const ui.Offset(120, 120),
          radius: 80,
          width: 56,
          bounds: const ui.Rect.fromLTWH(0, 0, 240, 240),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(240, 240);
        picture.dispose();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        List<int> at(int x, int y) =>
            bytes.sublist((y * 240 + x) * 4, (y * 240 + x) * 4 + 4);
        expect(at(190, 120), [0, 0, 255, 255]);
        expect(at(210, 120), [255, 0, 0, 255]);
        expect(at(120, 120), [0, 0, 255, 255]);
        expect(at(235, 120), [255, 0, 0, 255]);
        old.dispose();
        target.dispose();
        image.dispose();
      });
    },
  );
}
