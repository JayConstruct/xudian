import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_icons.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_icon.dart';
import 'package:task_app/core/ui/ui_pack.dart';

void main() {
  test(
    'vector vocabulary paints without clipping at small and large sizes',
    () async {
      for (final extent in [16, 24, 64]) {
        for (final glyph in AppGlyph.values) {
          expect(appIconName(appIconData(glyph.name)), glyph.name);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..translate(4, 4);
          AppIconPainter(
            glyph: glyph,
            color: Colors.black,
            highContrast: true,
          ).paint(canvas, Size.square(extent.toDouble()));
          final picture = recorder.endRecording();
          final raster = await picture.toImage(extent + 8, extent + 8);
          final bytes = (await raster.toByteData())!.buffer.asUint8List();
          var painted = 0;
          for (var y = 0; y < extent + 8; y++) {
            for (var x = 0; x < extent + 8; x++) {
              final alpha = bytes[(y * (extent + 8) + x) * 4 + 3];
              if (alpha > 0) painted++;
              if (x < 4 || y < 4 || x >= extent + 4 || y >= extent + 4) {
                expect(
                  alpha,
                  0,
                  reason: '${glyph.name} is clipped at $extent px',
                );
              }
            }
          }
          expect(
            painted,
            greaterThan(8),
            reason: '${glyph.name} must be visible',
          );
          raster.dispose();
          picture.dispose();
        }
      }
    },
  );

  testWidgets(
    'public vectors stay square inside stretched narrow and wide parents',
    (tester) async {
      for (final width in [320.0, 1100.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    defaultUiComponent(
                      'ui.icon@1',
                      {'name': 'calendar', 'size': 28},
                      {},
                      {},
                    ),
                    const SizedBox(
                      height: 56,
                      child: UiIcon(Icons.today_outlined, size: 32),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final paints = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((widget) => widget.painter is AppIconPainter)
            .toList();
        expect(tester.getSize(find.byWidget(paints[0])), const Size.square(28));
        expect(tester.getSize(find.byWidget(paints[1])), const Size.square(32));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'icons inherit theme, retain labels and do not change hit targets',
    (tester) async {
      final selected = ValueNotifier(false);
      addTearDown(selected.dispose);
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(Brightness.dark),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: selected,
              builder: (_, value, _) => IconButton(
                tooltip: '查看今天',
                onPressed: () => presses++,
                icon: UiIcon(
                  Icons.today_outlined,
                  semanticLabel: '日历',
                  selected: value,
                ),
              ),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byType(IconButton));
      expect(find.bySemanticsLabel('日历'), findsOneWidget);
      await tester.tap(find.byTooltip('查看今天'));
      expect(presses, 1);
      selected.value = true;
      await tester.pump();
      expect(tester.getRect(find.byType(IconButton)), before);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<AppIconPainter>()
          .single;
      expect(painter.selected, true);
      expect(painter.color, isNot(Colors.black));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an icon recipe replaces native artwork while the action stays usable',
    (tester) async {
      final pack = UiPackDefinition.parse(
        moduleId: 'test.icons',
        version: '1.0.0',
        digest: 'test',
        source: {
          'contractVersion': 1,
          'components': {
            'ui.icon@1': {
              'tree': {
                'type': 'primitive',
                'name': 'icon',
                'props': {
                  'name': 'folder',
                  'size': {
                    'bind': ['props', 'size'],
                  },
                },
              },
            },
          },
        },
      );
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UiPackScope(
            previewPacks: {'test.icons': pack},
            previewSelection: UiSelection(globalPackId: 'test.icons'),
            child: Scaffold(
              body: IconButton(
                tooltip: '真实操作',
                onPressed: () => presses++,
                icon: const UiIcon(Icons.today_outlined, size: 32),
              ),
            ),
          ),
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<AppIconPainter>()
          .single;
      expect(painter.glyph, AppGlyph.folder);
      final painting = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .singleWhere((widget) => widget.painter is AppIconPainter);
      expect(tester.getSize(find.byWidget(painting)), const Size.square(32));
      await tester.tap(find.byTooltip('真实操作'));
      expect(presses, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test('produce a reviewable vector contact sheet', () async {
    const width = 600, height = 450;
    final fontFile = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    final hasLabelFont = await fontFile.exists();
    if (hasLabelFont) {
      final loader = FontLoader('IconPreviewLabels')
        ..addFont(
          Future.value(ByteData.sublistView(await fontFile.readAsBytes())),
        );
      await loader.load();
    }
    final recorder = ui.PictureRecorder();
    // Draw the same vector source used by the app, with no bitmap dependency.
    final board = Canvas(recorder);
    board.drawColor(AppDesign.lightCanvas, BlendMode.src);
    for (var i = 0; i < AppGlyph.values.length; i++) {
      final x = (i % 8) * 75.0, y = (i ~/ 8) * 86.0;
      board.save();
      board.translate(x + 22, y + 12);
      AppIconPainter(
        glyph: AppGlyph.values[i],
        color: AppDesign.brand,
      ).paint(board, const Size.square(32));
      board.restore();
      if (!hasLabelFont) continue;
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: 'IconPreviewLabels',
                fontSize: 11,
                textAlign: TextAlign.center,
              ),
            )
            ..pushStyle(ui.TextStyle(color: AppDesign.charcoal))
            ..addText(AppGlyph.values[i].name);
      final text = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 75));
      board.drawParagraph(text, Offset(x, y + 55));
      text.dispose();
    }
    final picture = recorder.endRecording();
    final raster = await picture.toImage(width, height);
    final output = File('../dist/verification/app-icons-preview.png');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(
      (await raster.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List(),
    );
    raster.dispose();
    picture.dispose();
  });
}
