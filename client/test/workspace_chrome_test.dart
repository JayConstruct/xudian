import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
