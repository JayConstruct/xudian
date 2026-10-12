import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/workspace_date_title.dart';
import 'package:task_app/core/ui/workspace_typography.dart';
import 'package:task_app/core/ui/animated_date_label.dart';

void main() {
  testWidgets(
    'unchanged month pixels stay still while day and weekday roll and reverse',
    (tester) async {
      final label = ValueNotifier(('2026-10-10', '10月10日 周六'));
      addTearDown(label.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ValueListenableBuilder(
                valueListenable: label,
                builder: (_, value, _) => WorkspaceDateTitle(
                  title: value.$2,
                  date: value.$1,
                  onEvent: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      Future<({List<int> bytes, int width})> capture() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final result = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final result = (
            bytes: bytes!.buffer.asUint8List().toList(),
            width: image.width,
          );
          image.dispose();
          return result;
        });
        return result!;
      }

      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText).first,
      );
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final month = boxes.single.toRect().shift(
        paragraph.localToGlobal(Offset.zero, ancestor: boundary),
      );
      final before = await capture();
      label.value = ('2026-10-11', '10月11日 周日');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final middle = await capture();
      for (var y = month.top.ceil(); y < month.bottom.floor(); y++) {
        final start = (y * before.width + month.left.ceil()) * 4;
        final end = (y * before.width + month.right.floor()) * 4;
        expect(
          middle.bytes.sublist(start, end),
          before.bytes.sublist(start, end),
        );
      }
      expect(middle.bytes, isNot(before.bytes));
      label.value = ('2026-10-10', '10月10日 周六');
      await tester.pump();
      final reversed = await capture();
      // Rasterization may round a glyph's subpixel position differently when
      // the old/new paint order swaps; the visible frame must stay continuous.
      var changedBytes = 0;
      var deltaSum = 0;
      for (var i = 0; i < middle.bytes.length; i++) {
        final delta = (reversed.bytes[i] - middle.bytes[i]).abs();
        if (delta > 0) changedBytes++;
        deltaSum += delta;
      }
      expect(changedBytes / middle.bytes.length, lessThan(.005));
      expect(deltaSum / middle.bytes.length, lessThan(.1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date parts update separately, reverse continuously and keep one current label',
    (tester) async {
      final label = ValueNotifier(('2026-10-10', '10月10日 周六'));
      addTearDown(label.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: label,
              builder: (_, value, _) => WorkspaceDateTitle(
                date: value.$1,
                title: value.$2,
                onEvent: (_) {},
              ),
            ),
          ),
        ),
      );
      DateLabelPaint paint() =>
          tester.widget<DateLabelPaint>(find.byType(DateLabelPaint));
      label.value = ('2026-10-11', '10月11日 周日');
      await tester.pump();
      expect(paint().changedParts, ['day', 'weekday']);
      expect(paint().direction, 1);
      await tester.pump(const Duration(milliseconds: 90));
      final forwardProgress = paint().progress;
      expect(forwardProgress, allOf(greaterThan(0), lessThan(1)));
      label.value = ('2026-10-10', '10月10日 周六');
      await tester.pump();
      expect(paint().direction, -1);
      expect(paint().progress, closeTo(1 - forwardProgress, .001));
      expect(find.bySemanticsLabel('10月10日 周六'), findsOneWidget);
      expect(find.bySemanticsLabel('10月11日 周日'), findsNothing);
      expect(find.byType(Text), findsOneWidget);
      await tester.pumpAndSettle();
      label.value = ('2026-11-01', '11月1日 周日');
      await tester.pump();
      expect(paint().changedParts, ['month', 'day', 'weekday']);
      await tester.pumpAndSettle();
      label.value = ('2027-01-01', '2027年1月1日 周五');
      await tester.pump();
      expect(paint().changedParts, ['year', 'month', 'weekday']);
      await tester.pumpAndSettle();
      label.value = ('2028-01-01', '2028年1月1日 周六');
      await tester.pump();
      expect(paint().changedParts, ['year', 'weekday']);
      await tester.pumpAndSettle();
      expect(paint().progress, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final media in [
    const MediaQueryData(disableAnimations: true),
    const MediaQueryData(highContrast: true),
  ]) {
    testWidgets(
      'reduced or high contrast dates update without rolling: ${media.highContrast}',
      (tester) async {
        final date = ValueNotifier('2026-10-10');
        addTearDown(date.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: media,
                child: ValueListenableBuilder(
                  valueListenable: date,
                  builder: (_, value, _) => WorkspaceDateTitle(
                    date: value,
                    title: value == '2026-10-10' ? '10月10日 周六' : '10月11日 周日',
                    onEvent: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        date.value = '2026-10-11';
        await tester.pump();
        expect(
          tester.widget<DateLabelPaint>(find.byType(DateLabelPaint)).progress,
          1,
        );
        expect(find.text('10月11日 周日'), findsOneWidget);
        expect(find.text('10月10日 周六'), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'custom labels preserve their text and use the whole-label fallback',
    (tester) async {
      final label = ValueNotifier(('2026-10-10', 'Saturday, 10 October'));
      addTearDown(label.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: label,
              builder: (_, value, _) => WorkspaceDateTitle(
                title: value.$2,
                date: value.$1,
                onEvent: (_) {},
              ),
            ),
          ),
        ),
      );
      label.value = ('2026-10-11', 'Sunday, 11 October');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final paint = tester.widget<DateLabelPaint>(find.byType(DateLabelPaint));
      expect(paint.changedParts, ['title']);
      expect(paint.progress, allOf(greaterThan(0), lessThan(1)));
      expect(find.text('Sunday, 11 October'), findsOneWidget);
      expect(find.text('Saturday, 10 October'), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'enabling high contrast during a roll stops the ticker immediately',
    (tester) async {
      final configuration = ValueNotifier((false, '2026-10-10'));
      addTearDown(configuration.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: configuration,
              builder: (_, value, _) => MediaQuery(
                data: MediaQueryData(highContrast: value.$1),
                child: WorkspaceDateTitle(
                  date: value.$2,
                  title: value.$2 == '2026-10-10' ? '10月10日 周六' : '10月11日 周日',
                  onEvent: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      configuration.value = (false, '2026-10-11');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      configuration.value = (true, '2026-10-11');
      await tester.pump();
      expect(
        tester.widget<DateLabelPaint>(find.byType(DateLabelPaint)).progress,
        1,
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid date changes keep latest label semantics and accept every control event',
    (tester) async {
      final date = ValueNotifier('2026-10-10');
      addTearDown(date.dispose);
      final events = <String>[];
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: date,
                builder: (_, value, _) => WorkspaceDateTitle(
                  title: value,
                  date: value,
                  style: const TextStyle(fontSize: 24),
                  onEvent: events.add,
                ),
              ),
            ),
          ),
        );
        for (final value in [
          '2026-10-11',
          '2026-10-12',
          '2026-10-09',
          '2026-10-10',
        ]) {
          date.value = value;
          await tester.pump(const Duration(milliseconds: 30));
          await tester.tap(find.byTooltip('后一天'));
          expect(find.bySemanticsLabel(value), findsOneWidget);
          expect(find.byType(Text).evaluate().length, lessThanOrEqualTo(2));
        }
        expect(events, List.filled(4, 'date.next'));
        await tester.pumpAndSettle();
        expect(find.text('2026-10-10'), findsOneWidget);
        expect(find.text('2026-10-09'), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('reduced motion changes date without a departing visible label', (
    tester,
  ) async {
    final date = ValueNotifier('2026-10-10');
    addTearDown(date.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ValueListenableBuilder(
              valueListenable: date,
              builder: (_, value, _) => WorkspaceDateTitle(
                title: value,
                date: value,
                style: const TextStyle(fontSize: 24),
                onEvent: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    date.value = '2026-10-11';
    await tester.pumpAndSettle();
    expect(find.text('2026-10-10'), findsNothing);
    expect(find.text('2026-10-11'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'date title uses shared typography without suppressing $scale text scaling',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: WorkspaceDateTitle(
                  title: '2027年1月1日 周五',
                  date: '2027-01-01',
                  onEvent: (_) {},
                ),
              ),
            ),
          ),
        );
        final title = find.text('2027年1月1日 周五');
        expect(
          tester.widget<Text>(title).style,
          WorkspaceTypography.titleStyle(
            Theme.of(tester.element(title)).textTheme,
          ),
        );
        expect(
          MediaQuery.textScalerOf(tester.element(title)).scale(24),
          24 * scale,
        );
        expect(tester.widget<Text>(title).maxLines, 3);
        expect(
          tester.getSize(find.byType(WorkspaceDateTitle)).height,
          greaterThanOrEqualTo(tester.getSize(title).height + 16),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'date header has accessible controls and animated changes at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final events = <String>[];
        final date = ValueNotifier('2026-10-10');
        addTearDown(date.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ValueListenableBuilder(
                    valueListenable: date,
                    builder: (_, value, _) => WorkspaceDateTitle(
                      title: value == '2026-10-10' ? '10月10日 周六' : '10月11日 周日',
                      date: value,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      onEvent: events.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('后一天'));
        await tester.tap(find.byKey(const ValueKey('workspace-date-picker')));
        expect(events, ['date.next', 'date.choose']);
        expect(
          tester.getSize(find.byTooltip('后一天')).height,
          greaterThanOrEqualTo(48),
        );
        date.value = '2026-10-11';
        await tester.pump();
        expect(find.text('10月10日 周六'), findsNothing);
        expect(find.text('10月11日 周日'), findsOneWidget);
        final animation = tester.widget<DateLabelPaint>(
          find.byType(DateLabelPaint),
        );
        expect(animation.previous, '10月10日 周六');
        expect(animation.changedParts, ['day', 'weekday']);
        await tester.pumpAndSettle();
        expect(find.text('10月10日 周六'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
