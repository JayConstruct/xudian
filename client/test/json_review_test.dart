import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/json_review.dart';

class _CountingList extends ListBase<Object?> {
  int reads = 0;
  @override
  int get length => 100000;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  Object? operator [](int index) {
    reads++;
    return 'entry $index';
  }

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('read only');
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test('short-value probe stops without walking the entire collection', () {
    final values = _CountingList();
    expect(smallJsonReviewText(values), isNull);
    expect(values.reads, lessThan(100));
    expect(smallJsonReviewText({'value': true}), '{\n  "value": true\n}');
    expect(smallJsonReviewText(List.filled(10000, 'a').join()), isNull);
  });

  test(
    'large minified strings split losslessly without broken surrogate pairs',
    () {
      final value = '${'a' * (jsonReviewPageLength - 2)}😀${'b' * 20000}';
      final pages = prepareJsonReview(value);
      expect(pages.length, greaterThan(2));
      expect(pages.join(), const JsonEncoder.withIndent('  ').convert(value));
      for (final page in pages) {
        expect(page.length, lessThanOrEqualTo(jsonReviewPageLength));
        expect(page.isNotEmpty, isTrue);
        expect(
          page.codeUnitAt(page.length - 1),
          isNot(inInclusiveRange(0xd800, 0xdbff)),
        );
        expect(page.codeUnitAt(0), isNot(inInclusiveRange(0xdc00, 0xdfff)));
      }
    },
  );

  testWidgets(
    'closed details do no preparation and reopening reuses their snapshot',
    (tester) async {
      var calls = 0;
      final value = {'tail': 'complete snapshot'};
      Future<List<String>> prepare(Object? data) async {
        calls++;
        return prepareJsonReview(data);
      }

      Widget section() =>
          JsonReviewSection(title: '全量原始详情', value: value, prepare: prepare);
      await tester.pumpWidget(_app(section()));
      expect(calls, 0);
      expect(find.byType(JsonReviewContent), findsNothing);
      await tester.tap(find.text('全量原始详情'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('complete snapshot'), findsOneWidget);
      await tester.pumpWidget(_app(section()));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('全量原始详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全量原始详情'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('complete snapshot'), findsOneWidget);
    },
  );

  testWidgets(
    'replacement while folded waits for expansion and discards previous content',
    (tester) async {
      var calls = 0;
      Future<List<String>> prepare(Object? data) async {
        calls++;
        return prepareJsonReview(data);
      }

      final before = {'value': 'before'}, after = {'value': 'after'};
      Widget section(Object? value) =>
          JsonReviewSection(title: '详情', value: value, prepare: prepare);
      await tester.pumpWidget(_app(section(before)));
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(section(after)));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining('after'), findsOneWidget);
      expect(find.textContaining('before'), findsNothing);
    },
  );

  testWidgets('obsolete and closed-view preparation cannot publish results', (
    tester,
  ) async {
    final requests = <Completer<List<String>>>[];
    Future<List<String>> prepare(Object? data) {
      final request = Completer<List<String>>();
      requests.add(request);
      return request.future;
    }

    await tester.pumpWidget(
      _app(JsonReviewContent(value: 'old', prepare: prepare)),
    );
    await tester.pumpWidget(
      _app(JsonReviewContent(value: 'new', prepare: prepare)),
    );
    requests[0].complete(['stale snapshot']);
    await tester.pumpAndSettle();
    expect(find.text('stale snapshot'), findsNothing);
    requests[1].complete(['new snapshot']);
    await tester.pumpAndSettle();
    expect(find.text('new snapshot'), findsOneWidget);
    await tester.pumpWidget(
      _app(JsonReviewContent(value: 'closed', prepare: prepare)),
    );
    await tester.pumpWidget(_app(const SizedBox()));
    requests[2].completeError(StateError('late failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'readiness stays false after failure and becomes true only after successful retry',
    (tester) async {
      final requests = <Completer<List<String>>>[];
      final ready = <bool>[];
      Future<List<String>> prepare(Object? data) {
        final request = Completer<List<String>>();
        requests.add(request);
        return request.future;
      }

      await tester.pumpWidget(
        _app(
          JsonReviewContent(
            value: 'review',
            prepare: prepare,
            onReadyChanged: ready.add,
          ),
        ),
      );
      expect(ready, [false]);
      requests.single.completeError(StateError('failed to prepare'));
      await tester.pumpAndSettle();
      expect(ready, [false]);
      expect(find.text('无法显示完整详情，请重试。'), findsOneWidget);
      await tester.tap(find.text('重试加载详情'));
      await tester.pumpAndSettle();
      expect(ready, [false, false]);
      requests.last.complete(['complete review']);
      await tester.pumpAndSettle();
      expect(ready, [false, false, true]);
      expect(find.text('complete review'), findsOneWidget);
    },
  );

  testWidgets(
    'one page is laid out and full copy uses the exact prepared snapshot',
    (tester) async {
      final value = {'value': '${'x' * 20000}😀尾部'};
      final snapshot = prepareJsonReview(value);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        _app(JsonReviewContent(value: value, prepare: (_) async => snapshot)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        snapshot.first,
      );
      await tester.tap(find.text('下一段'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        snapshot[1],
      );
      // Copy never serializes a potentially changed caller object a second time.
      value['value'] = 'mutated after preparation';
      await tester.runAsync(() async {
        await tester.tap(find.text('复制完整详情'));
        for (var attempt = 0; attempt < 1000 && copied == null; attempt++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(copied, snapshot.join());
      await tester.pumpAndSettle();
      expect(find.text('已复制完整详情'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    },
  );
}
