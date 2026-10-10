import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/time_grid.dart';

void main() {
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
