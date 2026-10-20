import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/time_range_table.dart';

void main() {
  Rect semanticBounds(SemanticsNode node) {
    var bounds = node.rect;
    SemanticsNode? ancestor = node;
    while (ancestor != null) {
      if (ancestor.transform case final transform?) {
        bounds = MatrixUtils.transformRect(transform, bounds);
      }
      ancestor = ancestor.parent;
    }
    return bounds;
  }

  Map<String, Object?> initial() => {
    'durationMinutes': '45',
    'rows': [
      {
        'id': '1',
        'label': '第 1 节',
        'start': '08:00',
        'end': '08:45',
        'manualEnd': false,
      },
      {
        'id': '2',
        'label': '第 2 节',
        'start': '10:00',
        'end': '10:50',
        'manualEnd': true,
      },
    ],
  };

  Future<void> choose(
    WidgetTester tester,
    String key,
    int hour,
    int minute,
  ) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    final wheels = find.byType(CupertinoPicker);
    tester
        .widget<CupertinoPicker>(wheels.at(0))
        .scrollController!
        .jumpToItem(hour);
    tester
        .widget<CupertinoPicker>(wheels.at(1))
        .scrollController!
        .jumpToItem(minute);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 420.0]) {
    testWidgets(
      '$width px table semantics align with visual cells and activate the correct time picker',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: TimeRangeTable(
                        value: initial(),
                        baseline: initial(),
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (final label in ['节次', '开始', '结束']) {
            final heading = find.text(label);
            final bounds = semanticBounds(tester.getSemantics(heading));
            expect(
              bounds.contains(tester.getCenter(heading)),
              true,
              reason: 'The $label header must occupy its painted column',
            );
          }
          for (final id in ['1', '2']) {
            for (final part in ['start', 'end']) {
              final cell = find.byKey(ValueKey('time-range-$id-$part'));
              final bounds = semanticBounds(tester.getSemantics(cell));
              final painted = tester.getRect(cell);
              expect(bounds.left, closeTo(painted.left, .01));
              expect(bounds.top, closeTo(painted.top, .01));
              expect(bounds.right, closeTo(painted.right, .01));
              expect(bounds.bottom, closeTo(painted.bottom, .01));
              await tester.tapAt(bounds.center);
              await tester.pumpAndSettle();
              final wheels = find.byType(CupertinoPicker);
              expect(wheels, findsNWidgets(2));
              final row = (initial()['rows'] as List).singleWhere(
                (row) => row['id'] == id,
              );
              final time = (row[part] as String)
                  .split(':')
                  .map(int.parse)
                  .toList();
              expect(
                tester
                    .widget<CupertinoPicker>(wheels.at(0))
                    .scrollController!
                    .selectedItem,
                time[0],
              );
              expect(
                tester
                    .widget<CupertinoPicker>(wheels.at(1))
                    .scrollController!
                    .selectedItem,
                time[1],
              );
              await tester.tap(find.text('取消'));
              await tester.pumpAndSettle();
            }
          }
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'local edits calculate automatic ends and preserve manual ends without replacing controls',
    (tester) async {
      final baseline = initial();
      final value = ValueNotifier(initial());
      addTearDown(value.dispose);
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: value,
              builder: (_, draft, _) => SingleChildScrollView(
                child: TimeRangeTable(
                  value: draft,
                  baseline: baseline,
                  onChanged: (next) {
                    changes++;
                    value.value = next;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final state = tester.state(find.byType(TimeRangeTable));
      final duration = find.byKey(const ValueKey('time-range-duration'));
      final controller = tester.widget<TextField>(duration).controller;
      await tester.enterText(duration, '60');
      await tester.pump();
      expect((value.value['rows'] as List).first['end'], '08:45');
      expect(value.value['dirty'], true);
      expect(value.value['saveDisabled'], false);
      await choose(tester, 'time-range-1-start', 8, 10);
      expect((value.value['rows'] as List).first['end'], '09:10');
      await choose(tester, 'time-range-2-start', 10, 10);
      expect((value.value['rows'] as List)[1]['end'], '10:50');
      await choose(tester, 'time-range-1-end', 9, 15);
      await choose(tester, 'time-range-1-start', 8, 20);
      expect((value.value['rows'] as List).first['end'], '09:15');
      expect((value.value['rows'] as List).first['manualEnd'], true);
      expect(identical(tester.state(find.byType(TimeRangeTable)), state), true);
      expect(
        identical(tester.widget<TextField>(duration).controller, controller),
        true,
      );
      expect(changes, 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel keeps draft untouched and invalid duration disables saving',
    (tester) async {
      Map<String, Object?>? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TimeRangeTable(
                value: initial(),
                baseline: initial(),
                onChanged: (value) => changed = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('time-range-1-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(changed, null);
      await tester.enterText(
        find.byKey(const ValueKey('time-range-duration')),
        '',
      );
      await tester.pump();
      expect(changed!['saveDisabled'], true);
      expect(changed!['resetDisabled'], false);
      expect((changed!['rows'] as List).first['start'], '08:00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('320px large text keeps table readable and cells at least 48px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: TimeRangeTable(
                  value: initial(),
                  baseline: initial(),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('开始'), findsOneWidget);
    expect(find.text('结束'), findsOneWidget);
    expect(find.text('开始时间'), findsNothing);
    final size = tester.getSize(
      find.byKey(const ValueKey('time-range-1-start')),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
