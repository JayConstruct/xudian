import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/date_reveal.dart';
import 'package:task_app/core/ui/ui_motion.dart';

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

  List<int> backgroundPixels(WidgetTester tester) {
    final background = Theme.of(tester.element(find.byType(DateReveal)))
        .scaffoldBackgroundColor;
    return [
      (background.r * 255).round(),
      (background.g * 255).round(),
      (background.b * 255).round(),
      (background.a * 255).round(),
    ];
  }

  void expectSamePaint(List<int> near, List<int> far) {
    for (var channel = 0; channel < near.length; channel++) {
      // Decorative tint is bounded to 4.5% and has no content reveal edge.
      expect((near[channel] - far[channel]).abs(), lessThanOrEqualTo(12));
    }
  }

  testWidgets(
    'old content fades out while pending and ready content fades in independently',
    (tester) async {
      await mount(tester);
      controller.prepare(originGlobal: Offset.zero, initialRadius: 20);
      update(date: 2, color: Colors.blue, ready: false);
      await tester.pump();
      final dynamic state = tester.state(find.byType(DateReveal));
      expect(state.snapshot, isA<ui.Image>());
      expect(state.oldOpacity, 1);
      expect(await pixel(tester, 100, 100), [244, 67, 54, 255]);
      await tester.pump(const Duration(milliseconds: 60));
      expect(state.oldOpacity, greaterThan(0));
      expect(state.oldOpacity, lessThan(1));
      expect(await pixel(tester, 100, 100), isNot([244, 67, 54, 255]));
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.isPreparing, isTrue);
      expect(state.oldOpacity, 0);
      expect(await pixel(tester, 100, 100), backgroundPixels(tester));
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
      expect(state.animation.value, greaterThan(0));
      expect(state.animation.value, lessThan(1));
      final near = await pixel(tester, 5, 5);
      expect(near, isNot([33, 150, 243, 255]));
      expect(near, isNot(backgroundPixels(tester)));
      expectSamePaint(near, await pixel(tester, 195, 195));
      await tester.pumpAndSettle();
      expect(controller.isTransitioning, isFalse);
      expect(state.snapshot, isNull);
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
    'selection during fade reuses one old image and waits for the latest data',
    (tester) async {
      await mount(tester);
      controller.prepare(originGlobal: Offset.zero);
      update(date: 2, color: Colors.blue, ready: true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final dynamic state = tester.state(find.byType(DateReveal));
      final original = state.snapshot;
      final opacity = state.oldOpacity as double;
      controller.prepare(originGlobal: const Offset(200, 200));
      update(date: 3, color: Colors.green, ready: false);
      await tester.pump();
      expect(state.snapshot, same(original));
      expect(state.oldOpacity, opacity);
      expect(state.animation.value, 0);
      expect(controller.isPreparing, isTrue);
      await tester.pump(const Duration(milliseconds: 480));
      expect(controller.isTransitioning, isTrue);
      expect(state.waves, isEmpty);
      expect(state.oldOpacity, 0);
      expect(await pixel(tester, 5, 5), backgroundPixels(tester));
      expect(await pixel(tester, 195, 195), backgroundPixels(tester));
      update(date: 3, color: Colors.green, ready: true);
      await tester.pumpAndSettle();
      expect(controller.isTransitioning, isFalse);
      expect(await pixel(tester, 195, 195), [76, 175, 80, 255]);
    },
  );

  testWidgets(
    'rapid ready selections restart the latest fade with bounded waves',
    (tester) async {
      await mount(tester);
      controller.prepare(originGlobal: Offset.zero);
      update(date: 2, color: Colors.blue, ready: true);
      await tester.pump();
      final dynamic state = tester.state(find.byType(DateReveal));
      final original = state.snapshot;
      for (var date = 3; date <= 8; date++) {
        controller.prepare(originGlobal: const Offset(200, 200));
        update(date: date, color: Colors.green, ready: true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(state.snapshot, same(original));
        expect(state.animation.value, 0);
        expect(controller.isPreparing, isFalse);
        expect(controller.isTransitioning, isTrue);
        expect((state.waves as List).length, lessThanOrEqualTo(3));
        expect(find.byType(DateReveal), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DateReveal),
            matching: find.byType(ColoredBox),
          ),
          findsOneWidget,
        );
      }
      await tester.pump();
      await tester.pump(
        AppMotion.dateContentFade + const Duration(milliseconds: 1),
      );
      expect(controller.isTransitioning, isFalse);
      expect(await pixel(tester, 5, 5), [76, 175, 80, 255]);
      expect(await pixel(tester, 195, 195), [76, 175, 80, 255]);
      expect(
        state.waves,
        isNotEmpty,
        reason: 'Ready data completes its fade without waiting for background waves.',
      );
      await tester.pumpAndSettle();
      expect(state.waves, isEmpty);
    },
  );

  testWidgets('cancel discards a queued reveal and restores live interaction', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare();
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    controller.prepare();
    update(date: 3, color: Colors.green, ready: false);
    await tester.pump();
    controller.cancel();
    await tester.pumpAndSettle();
    expect(controller.isTransitioning, isFalse);
    expect(controller.isPreparing, isFalse);
    expect(await pixel(tester, 100, 100), [76, 175, 80, 255]);
    await tester.tapAt(const Offset(100, 100));
    expect(clicks, 1);
  });

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

  testWidgets('swipe fades all content uniformly without background waves', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare(swipe: true, direction: 1);
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final dynamic state = tester.state(find.byType(DateReveal));
    expect(state.waves, isEmpty);
    final left = await pixel(tester, 5, 100);
    expect(left, await pixel(tester, 195, 100));
    expect(left, isNot([244, 67, 54, 255]));
    expect(left, isNot([33, 150, 243, 255]));
    await tester.pumpAndSettle();
    expect(await pixel(tester, 195, 100), [33, 150, 243, 255]);
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

  testWidgets('header wave origin does not clip or delay the content fade', (
    tester,
  ) async {
    await mount(tester);
    controller.prepare(originGlobal: const Offset(100, -100));
    update(date: 2, color: Colors.blue, ready: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expectSamePaint(await pixel(tester, 100, 5), await pixel(tester, 100, 195));
    await tester.pump(
      AppMotion.dateContentFade + const Duration(milliseconds: 1),
    );
    expect(controller.isTransitioning, isFalse);
    expect(await pixel(tester, 100, 5), [33, 150, 243, 255]);
    expect(await pixel(tester, 100, 195), [33, 150, 243, 255]);
    final dynamic state = tester.state(find.byType(DateReveal));
    expect(state.waves, isNotEmpty);
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
    'live navigation stays untouched while business content fades and remains blocked',
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
                                        : value.date == 2
                                        ? Colors.yellow
                                        : Colors.purple,
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
      controller.prepare(originGlobal: Offset.zero);
      update(date: 3, color: Colors.green, ready: false);
      await tester.pump();
      expect(await pixel(tester, 100, 80), [156, 39, 176, 255]);
      await tester.tapAt(const Offset(100, 80));
      expect(navigationClicks, 2);
      await tester.pump(const Duration(milliseconds: 480));
      expect(await pixel(tester, 100, 80), [156, 39, 176, 255]);
      expect(await pixel(tester, 100, 150), backgroundPixels(tester));
      await tester.tapAt(const Offset(100, 150));
      expect(businessClicks, 0);
      update(date: 3, color: Colors.green, ready: true);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(100, 150));
      expect(businessClicks, 1);
      semantics.dispose();
    },
  );
  testWidgets(
    'readiness loss stops the fade and hides unready replacement content',
    (tester) async {
      await mount(tester);
      controller.prepare(originGlobal: Offset.zero);
      update(date: 2, color: Colors.blue, ready: true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final dynamic state = tester.state(find.byType(DateReveal));
      final original = state.snapshot;
      expect(state.animation.value, greaterThan(0));
      update(date: 2, color: Colors.green, ready: false);
      await tester.pump();
      expect(controller.isPreparing, isTrue);
      expect(state.snapshot, same(original));
      expect(state.animation.value, 0);
      await tester.pump(const Duration(milliseconds: 700));
      expect(await pixel(tester, 5, 5), backgroundPixels(tester));
      expect(await pixel(tester, 195, 195), backgroundPixels(tester));
      await tester.tapAt(const Offset(100, 100));
      expect(clicks, 0);
      update(date: 2, color: Colors.green, ready: true);
      await tester.pumpAndSettle();
      expect(await pixel(tester, 100, 100), [76, 175, 80, 255]);
    },
  );

  testWidgets(
    'removed cards fade to the new empty background without a reveal edge',
    (tester) async {
      await mount(tester);
      controller.prepare(swipe: true);
      update(date: 2, color: Colors.transparent, ready: true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final near = await pixel(tester, 5, 5);
      expect(near, await pixel(tester, 195, 195));
      expect(near, isNot([244, 67, 54, 255]));
      expect(near, isNot(backgroundPixels(tester)));
      await tester.pumpAndSettle();
      expect(await pixel(tester, 195, 195), backgroundPixels(tester));
    },
  );

  testWidgets(
    'ready content remains live while the only image is the original snapshot',
    (tester) async {
      await mount(tester);
      controller.prepare(originGlobal: Offset.zero);
      update(date: 2, color: Colors.blue, ready: false);
      await tester.pump();
      final dynamic state = tester.state(find.byType(DateReveal));
      final original = state.snapshot as ui.Image;
      final bytes = (await tester.runAsync(
        () => original.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final index =
          ((original.height - 1) * original.width + original.width - 1) * 4;
      expect(bytes.buffer.asUint8List().sublist(index, index + 4), [
        244,
        67,
        54,
        255,
      ]);
      update(date: 2, color: Colors.blue, ready: true);
      await tester.pump();
      expect(state.snapshot, same(original));
      expect(
        find.descendant(
          of: find.byType(DateReveal),
          matching: find.byType(ColoredBox),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.byType(DateReveal),
                matching: find.byType(ColoredBox),
              ),
            )
            .color,
        Colors.blue,
      );
      controller.cancel();
      await tester.pump();
      expect(state.snapshot, isNull);
      expect(state.waves, isEmpty);
      expect(await pixel(tester, 195, 195), [33, 150, 243, 255]);
    },
  );
}
