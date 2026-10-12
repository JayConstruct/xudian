import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/date_reveal.dart';

typedef Frame = ({
  int date,
  Color color,
  bool ready,
  bool reduced,
  bool contrast,
});

void main() {
  late DateRevealController controller;
  late ValueNotifier<Frame> frame;
  late GlobalKey boundaryKey;
  var clicks = 0;

  Future<void> mount(
    WidgetTester tester, {
    bool blockInteraction = true,
  }) async {
    controller = DateRevealController();
    frame = ValueNotifier((
      date: 1,
      color: Colors.red,
      ready: true,
      reduced: false,
      contrast: false,
    ));
    boundaryKey = GlobalKey();
    clicks = 0;
    addTearDown(controller.dispose);
    addTearDown(frame.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder(
            valueListenable: frame,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: value.reduced,
                highContrast: value.contrast,
              ),
              child: SizedBox(
                width: 200,
                height: 200,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: DateRevealScope(
                    controller: controller,
                    child: DateReveal(
                      controller: controller,
                      revision: value.date,
                      ready: value.ready,
                      blockInteraction: blockInteraction,
                      child: Semantics(
                        label: 'Date ${value.date}',
                        button: true,
                        child: GestureDetector(
                          onTap: () => clicks++,
                          child: ColoredBox(color: value.color),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void update({
    required int date,
    required Color color,
    required bool ready,
    bool reduced = false,
    bool contrast = false,
  }) => frame.value = (
    date: date,
    color: color,
    ready: ready,
    reduced: reduced,
    contrast: contrast,
  );

  Future<List<int>> pixel(WidgetTester tester, int x, int y) async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (y * image.width + x) * 4;
      final result = data!.buffer.asUint8List().sublist(offset, offset + 4);
      image.dispose();
      return result;
    }))!;
  }

  testWidgets(
    'freezes complete paint until ready then reveals from button edge',
    (tester) async {
      await mount(tester);
      controller.prepare(originGlobal: const Offset(0, 0), initialRadius: 20);
      update(date: 2, color: Colors.blue, ready: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.isPreparing, isTrue);
      expect(await pixel(tester, 100, 100), [244, 67, 54, 255]);
      expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox).last).color,
        Colors.blue,
      );
      await tester.tapAt(const Offset(100, 100));
      expect(clicks, 0);

      update(date: 2, color: Colors.blue, ready: true);
      await tester.pump();
      expect(controller.isPreparing, isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(await pixel(tester, 5, 5), [33, 150, 243, 255]);
      expect(await pixel(tester, 195, 195), [244, 67, 54, 255]);
      await tester.pumpAndSettle();
      expect(controller.isTransitioning, isFalse);
      expect(await pixel(tester, 195, 195), [33, 150, 243, 255]);
      await tester.tapAt(const Offset(100, 100));
      expect(clicks, 1);
    },
  );

  testWidgets('latest selection replaces pending target without exposing it', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare();
    update(date: 2, color: Colors.blue, ready: false);
    await tester.pump();
    controller.prepare(originGlobal: const Offset(200, 0));
    update(date: 3, color: Colors.green, ready: false);
    await tester.pump();
    expect(await pixel(tester, 100, 100), [244, 67, 54, 255]);
    update(date: 3, color: Colors.green, ready: true);
    await tester.pumpAndSettle();
    expect(await pixel(tester, 100, 100), [76, 175, 80, 255]);
  });

  testWidgets(
    'selection during reveal freezes current composite without jump',
    (tester) async {
      await mount(tester);
      controller.prepare(originGlobal: Offset.zero);
      update(date: 2, color: Colors.blue, ready: true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final corner = await pixel(tester, 5, 5);
      final farCorner = await pixel(tester, 195, 195);
      controller.prepare(originGlobal: const Offset(200, 200));
      update(date: 3, color: Colors.green, ready: false);
      await tester.pump();
      expect(await pixel(tester, 5, 5), corner);
      expect(await pixel(tester, 195, 195), farCorner);
      update(date: 3, color: Colors.green, ready: true);
      await tester.pumpAndSettle();
      expect(controller.isTransitioning, isFalse);
    },
  );

  testWidgets(
    'revision fallback captures old paint without an explicit origin',
    (tester) async {
      await mount(tester);
      update(date: 2, color: Colors.blue, ready: false);
      await tester.pump();
      expect(await pixel(tester, 100, 100), [244, 67, 54, 255]);
      controller.cancel();
      await tester.pump();
      expect(await pixel(tester, 100, 100), [33, 150, 243, 255]);
    },
  );

  testWidgets('swipe reveals horizontally without a radial wave', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare(swipe: true, direction: 1);
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(await pixel(tester, 5, 100), [244, 67, 54, 255]);
    expect(await pixel(tester, 195, 100), [33, 150, 243, 255]);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'reduced motion and high contrast wait for data then update directly',
    (tester) async {
      await mount(tester);
      for (final contrast in [false, true]) {
        controller.prepare();
        update(
          date: 2,
          color: Colors.blue,
          ready: false,
          reduced: !contrast,
          contrast: contrast,
        );
        await tester.pump();
        expect(controller.isPreparing, isTrue);
        update(
          date: 2,
          color: Colors.blue,
          ready: true,
          reduced: !contrast,
          contrast: contrast,
        );
        await tester.pumpAndSettle();
        expect(controller.isTransitioning, isFalse);
        expect(await pixel(tester, 100, 100), [33, 150, 243, 255]);
      }
    },
  );

  testWidgets('scope allows navigation interaction to be handled by host', (
    tester,
  ) async {
    await mount(tester, blockInteraction: false);
    controller.prepare();
    update(date: 2, color: Colors.blue, ready: false);
    await tester.pump();
    final context = tester.element(find.byType(DateReveal));
    expect(DateRevealScope.read(context), same(controller));
    await tester.tapAt(const Offset(100, 100));
    expect(clicks, 1);
    controller.cancel();
    await tester.pump();
  });

  testWidgets('origin above viewport reveals from the header button', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare(originGlobal: const Offset(100, -100));
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pump();
    await tester.pump();
    // Sample behind the wider halo, where the new content is fully revealed.
    await tester.pump(const Duration(milliseconds: 140));
    expect(await pixel(tester, 100, 5), [33, 150, 243, 255]);
    expect(await pixel(tester, 100, 195), [244, 67, 54, 255]);
    await tester.pumpAndSettle();
  });

  testWidgets('changing accessibility during reveal completes its ticker', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare();
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.isTransitioning, isTrue);
    update(date: 2, color: Colors.blue, ready: true, contrast: true);
    await tester.pumpAndSettle();
    expect(controller.isTransitioning, isFalse);
    expect(await pixel(tester, 100, 100), [33, 150, 243, 255]);
  });

  testWidgets('snapshot creates no old semantic subtree', (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    controller.prepare();
    update(date: 2, color: Colors.blue, ready: false);
    await tester.pump();
    final tree = tester
        .binding
        .renderViews
        .single
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!
        .toStringDeep();
    expect(tree, isNot(contains('Date 1')));
    expect(tree, isNot(contains('Date 2')));
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Date 2'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('removing reveal clears status before reusing its controller', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare();
    update(date: 2, color: Colors.blue, ready: false);
    await tester.pump();
    expect(controller.isTransitioning, isTrue);
    expect(controller.isPreparing, isTrue);
    final changes = <(bool, bool)>[];
    controller.addListener(() {
      changes.add((controller.isTransitioning, controller.isPreparing));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.isTransitioning, isFalse);
    expect(controller.isPreparing, isFalse);
    expect(changes.last, (false, false));

    await tester.pumpWidget(
      MaterialApp(
        home: DateReveal(
          controller: controller,
          revision: 2,
          ready: true,
          child: const ColoredBox(color: Colors.green),
        ),
      ),
    );
    expect(controller.isTransitioning, isFalse);
    expect(controller.isPreparing, isFalse);
    controller.prepare();
    expect(controller.isPreparing, isTrue);
    controller.cancel();
    await tester.pump();
    expect(controller.isTransitioning, isFalse);
  });

  testWidgets(
    'live navigation moves visibly while old business paint stays frozen',
    (tester) async {
      await mount(tester);
      var navigationClicks = 0;
      var businessClicks = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: RepaintBoundary(
                key: boundaryKey,
                child: DateRevealScope(
                  controller: controller,
                  child: ValueListenableBuilder(
                    valueListenable: frame,
                    builder: (_, value, _) => DateReveal(
                      controller: controller,
                      revision: value.date,
                      ready: value.ready,
                      blockInteraction: false,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: controller,
                              builder: (_, _) => IgnorePointer(
                                ignoring: controller.isTransitioning,
                                child: ExcludeSemantics(
                                  excluding: controller.isTransitioning,
                                  child: Semantics(
                                    label: 'Business ${value.date}',
                                    child: GestureDetector(
                                      onTap: () => businessClicks++,
                                      child: ColoredBox(color: value.color),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: value.date == 1 ? 0 : 60,
                            height: 40,
                            child: DateRevealNavigation(
                              child: Semantics(
                                label: 'Navigation ${value.date}',
                                child: GestureDetector(
                                  onTap: () => navigationClicks++,
                                  child: ColoredBox(
                                    color: value.date == 1
                                        ? Colors.orange
                                        : Colors.yellow,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(await pixel(tester, 100, 20), [255, 152, 0, 255]);
      controller.prepare(originGlobal: Offset.zero);
      update(date: 2, color: Colors.blue, ready: false);
      await tester.pump();
      expect(await pixel(tester, 100, 80), [255, 235, 59, 255]);
      expect(await pixel(tester, 100, 150), [244, 67, 54, 255]);
      // Neither the old navigation position nor its orange raster remains.
      final background = Theme.of(tester.element(find.byType(DateReveal)))
          .scaffoldBackgroundColor;
      expect(await pixel(tester, 100, 20), [
        (background.r * 255).round(),
        (background.g * 255).round(),
        (background.b * 255).round(),
        (background.a * 255).round(),
      ]);
      await tester.tapAt(const Offset(100, 80));
      await tester.tapAt(const Offset(100, 150));
      expect(navigationClicks, 1);
      expect(businessClicks, 0);
      final tree = tester
          .binding
          .renderViews
          .single
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep();
      expect(tree, contains('Navigation 2'));
      expect(tree, isNot(contains('Navigation 1')));
      expect(tree, isNot(contains('Business 1')));
      expect(tree, isNot(contains('Business 2')));

      update(date: 2, color: Colors.blue, ready: true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(await pixel(tester, 100, 80), [255, 235, 59, 255]);
      await tester.pump(const Duration(milliseconds: 75));
      expect(await pixel(tester, 100, 80), [
        255,
        235,
        59,
        255,
      ], reason: 'The visible wave must not tint the live date controls.');
      await tester.tapAt(const Offset(100, 150));
      expect(businessClicks, 0);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(100, 150));
      expect(businessClicks, 1);
      semantics.dispose();
    },
  );
  testWidgets('readiness loss during reveal freezes its current composite', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare(originGlobal: Offset.zero);
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final near = await pixel(tester, 5, 5);
    final far = await pixel(tester, 195, 195);
    expect(near, [33, 150, 243, 255]);
    expect(far, [244, 67, 54, 255]);
    update(date: 2, color: Colors.green, ready: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.isPreparing, isTrue);
    expect(await pixel(tester, 5, 5), near);
    expect(await pixel(tester, 195, 195), far);
    update(date: 2, color: Colors.green, ready: true);
    await tester.pumpAndSettle();
    expect(await pixel(tester, 100, 100), [76, 175, 80, 255]);
  });
  testWidgets('wave replaces removed cards with the new empty background', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare(originGlobal: Offset.zero);
    update(date: 2, color: Colors.transparent, ready: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final background = Theme.of(tester.element(find.byType(DateReveal)))
        .scaffoldBackgroundColor;
    expect(await pixel(tester, 5, 5), [
      (background.r * 255).round(),
      (background.g * 255).round(),
      (background.b * 255).round(),
      (background.a * 255).round(),
    ]);
    expect(await pixel(tester, 195, 195), [244, 67, 54, 255]);
    await tester.pumpAndSettle();
    expect(await pixel(tester, 195, 195), isNot([244, 67, 54, 255]));
  });

  testWidgets('lens samples the complete ready page behind the old paint', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare(originGlobal: Offset.zero);
    update(date: 2, color: Colors.blue, ready: false);
    await tester.pump();
    final dynamic state = tester.state(find.byType(DateReveal));
    expect(
      state.targetSnapshot,
      isNull,
      reason: 'Unready contributions must not become a lens texture.',
    );
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pump();
    final texture = state.targetSnapshot as ui.Image;
    final bytes = (await tester.runAsync(
      () => texture.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final index =
        ((texture.height - 1) * texture.width + texture.width - 1) * 4;
    expect(bytes.buffer.asUint8List().sublist(index, index + 4), [
      33,
      150,
      243,
      255,
    ], reason: 'Capture the full new layer, including its unrevealed corner.');
    expect(await pixel(tester, 195, 195), [244, 67, 54, 255]);
    controller.cancel();
    await tester.pump();
    expect(state.targetSnapshot, isNull);
    expect(await pixel(tester, 195, 195), [33, 150, 243, 255]);
  });
}
