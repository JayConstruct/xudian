import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/time_grid.dart';

void main() {
  testWidgets(
    'chrome cycles retain scroll position but window and timetable changes reset the range',
    (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = ValueNotifier((
        header: 88.0,
        inset: 168.0,
        rows: 16,
        rowHeight: 72.0,
        keyboard: 0.0,
      ));
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: state,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.only(bottom: value.keyboard),
                disableAnimations: true,
              ),
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                body: Padding(
                  padding: EdgeInsets.only(
                    top: value.header,
                    bottom: value.keyboard,
                  ),
                  child: TimeGrid(
                    columns: const [
                      {'id': 'mon', 'label': '周一'},
                    ],
                    rows: [
                      for (var i = 0; i < value.rows; i++)
                        {'id': '$i', 'label': '节次 $i'},
                    ],
                    blocks: const [],
                    onEvent: (_) {},
                    bottomInset: value.inset,
                    options: {'rowHeight': value.rowHeight, 'headerHeight': 48},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      ScrollPosition position() => find
          .descendant(
            of: find.byKey(const PageStorageKey('time-grid-vertical')),
            matching: find.byType(Scrollable),
          )
          .evaluate()
          .whereType<StatefulElement>()
          .map((e) => e.state)
          .whereType<ScrollableState>()
          .singleWhere((s) => s.widget.axisDirection == AxisDirection.down)
          .position;
      await tester.pump();
      final scroll = position();
      final extent = scroll.maxScrollExtent;
      scroll.jumpTo(extent - 20);
      await tester.pump();
      final readingOffset = scroll.pixels;
      for (var i = 0; i < 4; i++) {
        state.value = (
          header: 0,
          inset: 60,
          rows: 16,
          rowHeight: 72,
          keyboard: 0,
        );
        await tester.pump();
        expect(scroll.pixels, closeTo(readingOffset, .01));
        expect(scroll.maxScrollExtent, closeTo(extent, .01));
        state.value = (
          header: 88,
          inset: 168,
          rows: 16,
          rowHeight: 72,
          keyboard: 0,
        );
        await tester.pump();
        expect(scroll.pixels, closeTo(readingOffset, .01));
        expect(scroll.maxScrollExtent, closeTo(extent, .01));
      }
      Future<void> checkNaturalRange() async {
        await tester.pump();
        final natural =
            (state.value.rows * state.value.rowHeight +
                    state.value.inset -
                    scroll.viewportDimension)
                .clamp(0, double.infinity);
        expect(
          scroll.maxScrollExtent,
          closeTo(natural, .01),
          reason:
              'A genuine geometry change must discard previous chrome padding.',
        );
        expect(scroll.pixels, lessThanOrEqualTo(scroll.maxScrollExtent));
      }

      tester.view.physicalSize = const Size(360, 840);
      await checkNaturalRange();
      state.value = (header: 0, inset: 60, rows: 8, rowHeight: 72, keyboard: 0);
      await checkNaturalRange();
      expect(scroll.maxScrollExtent, 0);
      state.value = (
        header: 0,
        inset: 60,
        rows: 8,
        rowHeight: 120,
        keyboard: 0,
      );
      await checkNaturalRange();
      state.value = (
        header: 0,
        inset: 60,
        rows: 8,
        rowHeight: 120,
        keyboard: 220,
      );
      await checkNaturalRange();
      state.value = (
        header: 0,
        inset: 60,
        rows: 8,
        rowHeight: 120,
        keyboard: 0,
      );
      await checkNaturalRange();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'column requests locate courses and retain subsequent manual scroll',
    (tester) async {
      final options = ValueNotifier<Map<String, Object?>>({
        'fillWidth': true,
        'labelWidth': 42,
        'minColumnWidth': 68,
      });
      addTearDown(options.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                height: 500,
                child: ValueListenableBuilder<Map<String, Object?>>(
                  valueListenable: options,
                  builder: (_, value, child) => TimeGrid(
                    options: value,
                    columns: [
                      for (var i = 1; i <= 7; i++)
                        {'id': 'day$i', 'title': '日期 $i'},
                    ],
                    rows: const [
                      {'id': '1', 'title': '节次 1'},
                      {'id': '2', 'title': '节次 2'},
                    ],
                    blocks: const [
                      {
                        'column': 'day7',
                        'start': 0,
                        'end': 1,
                        'title': '周末课程',
                        'event': {'type': 'detail'},
                      },
                    ],
                    onEvent: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final body = tester.widget<SingleChildScrollView>(
        find.byKey(const PageStorageKey('time-grid-horizontal')),
      );
      expect(body.controller!.offset, 0);
      expect(tester.getTopLeft(find.text('周末课程')).dx, greaterThan(360));

      options.value = {
        ...options.value,
        'scrollToColumn': 'day7',
        'scrollRequest': 1,
      };
      await tester.pump();
      await tester.pump();
      expect(body.controller!.offset, greaterThan(0));
      expect(tester.getTopLeft(find.text('周末课程')).dx, lessThan(360));
      expect(
        (tester.getCenter(find.text('日期 7')).dx -
                tester.getCenter(find.text('周末课程')).dx)
            .abs(),
        lessThan(40),
      );
      // Ordinary query refreshes preserve a user scroll after the explicit jump.
      body.controller!.jumpTo(80);
      options.value = {...options.value, 'rowHeight': 80};
      await tester.pump();
      await tester.pump();
      expect(body.controller!.offset, 80);
      expect(
        (tester.getCenter(find.text('日期 7')).dx -
                tester.getCenter(find.text('周末课程')).dx)
            .abs(),
        lessThan(40),
      );

      options.value = {
        ...options.value,
        'scrollToColumn': 'day1',
        'scrollRequest': 2,
      };
      await tester.pump();
      await tester.pump();
      expect(body.controller!.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
