import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_scroll_behavior.dart';
import 'package:task_app/core/ui/workspace_chrome.dart';

FixedScrollMetrics metrics(
  double pixels, {
  AxisDirection axis = AxisDirection.down,
}) => FixedScrollMetrics(
  minScrollExtent: 0,
  maxScrollExtent: 600,
  pixels: pixels,
  viewportDimension: 500,
  axisDirection: axis,
  devicePixelRatio: 1,
);

void main() {
  late WorkspaceChromeController controller;
  late BuildContext context;
  setUp(() {
    controller = WorkspaceChromeController();
    controller.configure('page:1', enabled: true);
    controller.updateHeaderExtent(100);
  });
  tearDown(() => controller.dispose());
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
  }

  void move(
    double pixels,
    double distance, {
    bool drag = true,
    double? scrollDelta,
    int depth = 0,
    AxisDirection axis = AxisDirection.down,
  }) {
    controller.handleScroll(
      ScrollUpdateNotification(
        metrics: metrics(pixels, axis: axis),
        context: context,
        scrollDelta: scrollDelta ?? distance,
        depth: depth,
        dragDetails: drag
            ? DragUpdateDetails(
                globalPosition: Offset.zero,
                delta: Offset(0, -distance),
              )
            : null,
      ),
    );
  }

  testWidgets(
    'each physical drag controls partial travel without a threshold or snap',
    (tester) async {
      await mount(tester);
      move(10, 10);
      expect(controller.hiddenExtent, 10);
      move(25, 15);
      expect(controller.progress, .25);
      move(13, -12);
      expect(controller.progress, .13);
      controller.handleScroll(
        ScrollEndNotification(metrics: metrics(13), context: context),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.progress, .13);
      move(250, 200);
      expect(controller.collapsed, isTrue);
      move(240, -10);
      expect(controller.progress, .9);
      controller.reveal();
      expect(controller.progress, 0);
      controller.configure('page:2', enabled: false);
      move(200, 200);
      expect(controller.progress, 0);
    },
  );

  testWidgets(
    'inertia, rebound, program jumps, horizontal and nested movement do not drive chrome',
    (tester) async {
      await mount(tester);
      move(80, 80);
      final progress = controller.progress;
      for (final pixels in [150.0, 640.0, 620.0, 600.0, 560.0, 0.0]) {
        move(pixels, -40, drag: false);
      }
      move(200, 120, axis: AxisDirection.right);
      move(200, 120, depth: 1);
      expect(controller.progress, progress);
      move(530, -30);
      expect(controller.progress, .5);
      controller.configure('page:2', enabled: true);
      expect(controller.progress, 0);
    },
  );

  testWidgets(
    'upward travel first closes a top gap, including an update crossing the edge',
    (tester) async {
      await mount(tester);
      move(-40, -40);
      expect(controller.hiddenExtent, 0);
      move(-20, 20);
      expect(controller.hiddenExtent, 0);
      move(10, 50, scrollDelta: 30);
      expect(controller.hiddenExtent, 10);
      move(35, 25);
      expect(controller.hiddenExtent, 35);
      move(-10, -45);
      expect(controller.hiddenExtent, 0);
      move(0, 10, drag: false);
      expect(controller.hiddenExtent, 0);
      await tester.pump();
    },
  );

  testWidgets(
    'an explicit wheel signal authorizes only its own scroll update',
    (tester) async {
      await mount(tester);
      controller.handlePointerSignal(
        const PointerScrollEvent(scrollDelta: Offset(0, 25)),
      );
      move(25, 25, drag: false);
      expect(controller.hiddenExtent, 25);
      move(40, 15, drag: false);
      expect(controller.hiddenExtent, 25);
      controller.handlePointerSignal(
        const PointerScrollEvent(scrollDelta: Offset(0, -10)),
      );
      move(30, -10, drag: false);
      expect(controller.hiddenExtent, 15);
      await tester.pump();
    },
  );

  testWidgets(
    'coordinated scrolling consumes header travel before rows and ignores its notifications',
    (tester) async {
      final scroll = WorkspaceChromeScrollController()..chrome = controller;
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceChromeScrollScope(
            controller: controller,
            child: NotificationListener<ScrollNotification>(
              onNotification: controller.handleScroll,
              child: Column(
                children: [
                  WorkspaceChromeHeader(
                    controller: controller,
                    child: const SizedBox(height: 100),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scroll,
                      child: const SizedBox(height: 2000),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final position = scroll.position as ScrollPositionWithSingleContext;
      late Drag gesture;
      void beginDrag() => gesture = position.drag(
        DragStartDetails(globalPosition: Offset.zero),
        () {},
      );
      void drag(double offset) => gesture.update(
        DragUpdateDetails(
          globalPosition: Offset.zero,
          delta: Offset(0, offset),
          primaryDelta: offset,
        ),
      );
      beginDrag();
      drag(-40);
      await tester.pump();
      expect(controller.hiddenExtent, 40);
      expect(position.pixels, 0);
      position.goBallistic(1000);
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      expect(controller.hiddenExtent, 40);

      beginDrag();
      drag(-90);
      await tester.pump();
      expect(controller.collapsed, isTrue);
      expect(position.pixels, 30);
      drag(20);
      await tester.pump();
      expect(controller.hiddenExtent, 100);
      expect(position.pixels, 10);
      drag(100);
      await tester.pump();
      expect(controller.hiddenExtent, 10);
      expect(position.pixels, 0);
      position.pointerScroll(120);
      await tester.pumpAndSettle();
      expect(controller.collapsed, isTrue);
      expect(position.pixels, 30);
      position.jumpTo(200);
      await tester.pumpAndSettle();
      expect(controller.collapsed, isTrue);
      expect(position.pixels, 200);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final wheel in [false, true]) {
    testWidgets(
      '${wheel ? 'wheel' : 'drag'} returns rows to the top before revealing chrome and opening a gap',
      (tester) async {
        final scroll = WorkspaceChromeScrollController()..chrome = controller;
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Column(
              children: [
                WorkspaceChromeHeader(
                  controller: controller,
                  child: const SizedBox(height: 100),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: const SizedBox(height: 2000),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        final position = scroll.position as ScrollPositionWithSingleContext;
        final gesture = wheel
            ? null
            : position.drag(
                DragStartDetails(globalPosition: Offset.zero),
                () {},
              );
        Future<void> travel(double delta) async {
          if (wheel) {
            position.pointerScroll(delta);
          } else {
            gesture!.update(
              DragUpdateDetails(
                globalPosition: Offset.zero,
                delta: Offset(0, -delta),
                primaryDelta: -delta,
              ),
            );
          }
          await tester.pump();
          await tester.pump();
        }

        await travel(300);
        expect(controller.collapsed, isTrue);
        expect(position.pixels, 200);
        await travel(-80);
        expect(controller.collapsed, isTrue);
        expect(position.pixels, 120);
        await travel(-150);
        expect(controller.hiddenExtent, 70);
        expect(position.pixels, 0);
        await travel(-40);
        expect(controller.hiddenExtent, 30);
        expect(position.pixels, 0);
        await travel(-30);
        expect(controller.expanded, isTrue);
        expect(position.pixels, 0);
        await travel(-40);
        expect(controller.expanded, isTrue);
        expect(position.pixels, wheel ? 0 : -40);
        if (!wheel) {
          final recovery = -position.physics.applyPhysicsToUserOffset(
            position,
            -100,
          );
          await travel(100);
          expect(position.pixels, 0);
          expect(controller.hiddenExtent, closeTo(recovery - 40, .01));
          await travel(300);
          final contentOffset = position.pixels;
          expect(controller.collapsed, isTrue);
          final distance = contentOffset + controller.headerExtent + 20;
          gesture!.update(
            DragUpdateDetails(
              globalPosition: Offset.zero,
              delta: Offset(0, distance),
              primaryDelta: distance,
            ),
          );
          expect(controller.expanded, isTrue);
          expect(position.pixels, closeTo(-20, .01));
          await tester.pump();
          await tester.pump();
          expect(position.pixels, closeTo(-20, .01));
        }
        gesture?.end(DragEndDetails(primaryVelocity: 0));
        await tester.pumpAndSettle();
        expect(controller.expanded, isTrue);
        expect(position.pixels, closeTo(0, .01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'downward inertia scrolls rows but cannot skip hidden chrome into a gap',
    (tester) async {
      final scroll = WorkspaceChromeScrollController()..chrome = controller;
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: SingleChildScrollView(
            controller: scroll,
            child: const SizedBox(height: 2000),
          ),
        ),
      );
      await tester.pump();
      final position = scroll.position as ScrollPositionWithSingleContext;
      position.pointerScroll(300);
      expect(controller.collapsed, isTrue);
      expect(position.pixels, 200);
      position.goBallistic(-2000);
      await tester.pump(const Duration(milliseconds: 32));
      expect(position.pixels, lessThan(200));
      expect(position.pixels, greaterThanOrEqualTo(0));
      await tester.pumpAndSettle();
      expect(controller.collapsed, isTrue);
      expect(position.pixels, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('fully hidden header releases focus and cannot regain it', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return Column(
              children: [
                WorkspaceChromeHeader(
                  controller: controller,
                  child: SizedBox(
                    height: 96,
                    child: Focus(focusNode: focus, child: const SizedBox()),
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    move(200, 200);
    await tester.pump();
    await tester.pump();
    expect(controller.collapsed, isTrue);
    expect(focus.hasFocus, isFalse);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    controller.reveal();
    await tester.pump();
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'header clips exactly physical travel and retains state through resize and hiding',
    (tester) async {
      final height = ValueNotifier(96.0);
      addTearDown(height.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return Column(
                children: [
                  ValueListenableBuilder(
                    valueListenable: height,
                    builder: (_, fullHeight, _) => WorkspaceChromeHeader(
                      controller: controller,
                      child: SizedBox(
                        height: fullHeight,
                        child: const Material(
                          child: TextField(key: ValueKey('draft')),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(controller.headerExtent, 96);
      final field = find.byKey(const ValueKey('draft'));
      await tester.enterText(field, '保留草稿');
      final original = tester.state(field);
      move(24, 24);
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(find.byType(WorkspaceChromeHeader)).height, 72);
      expect(tester.getTopLeft(field).dy, -24);
      height.value = 120;
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(controller.headerExtent, 120);
      expect(controller.hiddenExtent, 24);
      expect(tester.getSize(find.byType(WorkspaceChromeHeader)).height, 96);
      move(200, 176);
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(find.byType(WorkspaceChromeHeader)).height, 0);
      expect(find.byKey(const ValueKey('draft')), findsNothing);
      controller.reveal();
      await tester.pump();
      await tester.pump();
      expect(identical(tester.state(field), original), isTrue);
      expect(find.text('保留草稿'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
