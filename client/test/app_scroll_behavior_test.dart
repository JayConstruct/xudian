import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_scroll_behavior.dart';

void main() {
  for (final count in [2, 20]) {
    testWidgets(
      '${count == 2 ? 'short' : 'long'} pages reveal edge space without resizing content and return on release',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: SingleChildScrollView(
                    key: const ValueKey('page'),
                    controller: controller,
                    child: Column(
                      children: [
                        for (var i = 0; i < count; i++)
                          SizedBox(
                            key: ValueKey('row-$i'),
                            width: 300,
                            height: 60,
                            child: Text('Row $i'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final viewport = tester.getRect(find.byKey(const ValueKey('page')));
        final firstRow = find.byKey(const ValueKey('row-0'));
        final rowSize = tester.getSize(firstRow);
        final start = tester.getTopLeft(firstRow);
        final topDrag = await tester.startGesture(viewport.center);
        await topDrag.moveBy(const Offset(0, 80));
        await topDrag.moveBy(const Offset(0, 80));
        await tester.pump();
        expect(controller.offset, lessThan(0));
        expect(tester.getTopLeft(firstRow).dy, greaterThan(start.dy));
        expect(tester.getSize(firstRow), rowSize);
        expect(find.byType(StretchingOverscrollIndicator), findsNothing);
        expect(find.byType(GlowingOverscrollIndicator), findsNothing);
        await topDrag.up();
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(0, 0.1));
        expect(tester.getTopLeft(firstRow).dy, closeTo(start.dy, 0.1));

        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        final bottom = controller.position.maxScrollExtent;
        final lastRow = find.byKey(ValueKey('row-${count - 1}'));
        final lastStart = tester.getTopLeft(lastRow);
        final bottomDrag = await tester.startGesture(viewport.center);
        await bottomDrag.moveBy(const Offset(0, -80));
        await bottomDrag.moveBy(const Offset(0, -80));
        await tester.pump();
        expect(controller.offset, greaterThan(bottom));
        expect(tester.getTopLeft(lastRow).dy, lessThan(lastStart.dy));
        expect(tester.getSize(lastRow), rowSize);
        await bottomDrag.up();
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(bottom, 0.1));
        expect(tester.getTopLeft(lastRow).dy, closeTo(lastStart.dy, 0.1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('horizontal Android surfaces still clamp at their edges', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            child: const SizedBox(width: 1600, height: 200),
          ),
        ),
      ),
    );
    final drag = await tester.startGesture(const Offset(400, 100));
    await drag.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(controller.offset, 0);
    await drag.up();
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });
}
