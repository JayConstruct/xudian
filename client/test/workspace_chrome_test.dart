import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/workspace_chrome.dart';

FixedScrollMetrics metrics(
  double offset, {
  AxisDirection axis = AxisDirection.down,
}) => FixedScrollMetrics(
  minScrollExtent: 0,
  maxScrollExtent: 600,
  pixels: offset,
  viewportDimension: 500,
  axisDirection: axis,
  devicePixelRatio: 1,
);

void main() {
  testWidgets(
    'scroll thresholds ignore jitter, horizontal motion, nested and programmatic jumps',
    (tester) async {
      late BuildContext context;
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
      final controller = WorkspaceChromeController();
      addTearDown(controller.dispose);
      controller.configure('page:1', enabled: true);
      void move(
        double offset,
        double delta, {
        bool user = true,
        AxisDirection axis = AxisDirection.down,
        int depth = 0,
      }) {
        controller.handleScroll(
          ScrollUpdateNotification(
            metrics: metrics(offset, axis: axis),
            context: context,
            scrollDelta: delta,
            depth: depth,
            dragDetails: user
                ? DragUpdateDetails(
                    globalPosition: Offset.zero,
                    delta: Offset(0, -delta),
                  )
                : null,
          ),
        );
      }

      move(120, 120, user: false);
      move(120, 120, axis: AxisDirection.right);
      move(120, 120, depth: 1);
      expect(controller.collapsed, isFalse);
      move(20, 20);
      move(15, -5);
      move(35, 20);
      expect(controller.collapsed, isFalse);
      move(63, 28);
      expect(controller.collapsed, isTrue);
      move(57, -6);
      expect(controller.collapsed, isTrue);
      move(45, -12);
      expect(controller.collapsed, isFalse);
      await tester.pump();
    },
  );

  testWidgets(
    'wheel scrolling, top-edge recovery and active page changes preserve navigation access',
    (tester) async {
      late BuildContext context;
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
      final controller = WorkspaceChromeController();
      addTearDown(controller.dispose);
      controller.configure('page:1', enabled: true);
      controller.handleScroll(
        UserScrollNotification(
          metrics: metrics(0),
          context: context,
          direction: ScrollDirection.reverse,
        ),
      );
      controller.handleScroll(
        ScrollUpdateNotification(
          metrics: metrics(60),
          context: context,
          scrollDelta: 60,
        ),
      );
      expect(controller.collapsed, isTrue);
      controller.handleScroll(
        OverscrollNotification(
          metrics: metrics(0),
          context: context,
          overscroll: -12,
          dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
        ),
      );
      expect(controller.collapsed, isFalse);
      controller.handleScroll(
        ScrollUpdateNotification(
          metrics: metrics(80),
          context: context,
          scrollDelta: 80,
          dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
        ),
      );
      expect(controller.collapsed, isTrue);
      controller.configure('page:2', enabled: true);
      expect(controller.collapsed, isFalse);
      controller.handleScroll(
        ScrollUpdateNotification(
          metrics: metrics(80),
          context: context,
          scrollDelta: 80,
          dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
        ),
      );
      expect(controller.collapsed, isTrue);
      controller.configure('page:2', enabled: false);
      expect(controller.collapsed, isFalse);
      controller.handleScroll(
        ScrollUpdateNotification(
          metrics: metrics(200),
          context: context,
          scrollDelta: 200,
          dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
        ),
      );
      expect(controller.collapsed, isFalse);
      await tester.pump();
    },
  );
}
