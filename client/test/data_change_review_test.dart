import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_scroll_behavior.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/data_change_review.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';
import 'package:task_app/core/module_host/host_schema.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/ui/json_review.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/data/app_database.dart';

Map<String, Object?> _write(
  String id,
  Object? before,
  Object? after, {
  String moduleId = 'test.notes',
}) => {
  'moduleId': moduleId,
  'space': 'test-data',
  'collection': 'notes',
  'id': id,
  'before': before,
  'value': after,
};

Map<String, Object?> _plan(List<Object?> writes) => {
  'planId': 'frozen-plan',
  'writes': writes,
  'result': {'message': '真实结果'},
};

Future<void> _waitForReviewContent(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // compute uses a real isolate; fake animation time alone does not wait for it.
  await tester.runAsync(() async {
    for (
      var attempt = 0;
      attempt < 1000 && find.text('正在准备完整详情…').evaluate().isNotEmpty;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
  expect(find.text('正在准备完整详情…'), findsNothing);
}

void main() {
  test('summarizes add update delete unchanged with record names and all changed fields', () {
    final summary = DataChangeSummary.tryParse(
      _plan([
        _write('add', null, {'id': 'add', 'title': '新任务'}),
        _write(
          'update',
          {'id': 'update', 'title': '旧标题', 'due': '昨日', 'removed': 1},
          {
            'id': 'update',
            'title': '新标题',
            'due': null,
            'nested': {'important': false},
          },
        ),
        _write(
          'delete',
          {'id': 'delete', 'name': '旧课程'},
          null,
          moduleId: 'test.courses',
        ),
        _write(
          'same',
          {'id': 'same', 'name': '不变'},
          {'name': '不变', 'id': 'same'},
        ),
      ]),
    )!;
    for (final kind in DataChangeKind.values) {
      expect(summary.count(kind), 1);
    }
    expect(summary.moduleIds, {'test.notes', 'test.courses'});
    expect(summary.records.map((record) => record.label), [
      '新任务',
      '新标题',
      '旧课程',
      '不变',
    ]);
    final fields = summary.records[1].fields;
    expect(fields.map((field) => field.field), [
      'title',
      'due',
      'removed',
      'nested',
    ]);
    expect(fields.firstWhere((field) => field.field == 'due').hasAfter, isTrue);
    expect(
      fields.firstWhere((field) => field.field == 'removed').hasAfter,
      isFalse,
    );
    expect(
      fields.firstWhere((field) => field.field == 'nested').hadBefore,
      isFalse,
    );
  });

  test(
    'only actual fully recognizable plans are classified including empty plans',
    () {
      expect(DataChangeSummary.tryParse(_plan([]))!.changedCount, 0);
      for (final details in [
        null,
        {},
        {'writes': []},
        {'planId': 'p'},
        {'planId': '', 'writes': []},
        {..._plan([]), 'definition': {}},
        {
          'definition': {},
          'preview': {'writes': []},
        },
        {
          'scopes': ['test.notes/write@1'],
        },
        _plan([
          {'moduleId': 'test.notes', 'id': 'a', 'value': null},
        ]),
        _plan([
          _write('a', null, {'id': 'wrong'}),
        ]),
        _plan([_write('a', 'unknown-record', null)]),
        _plan([
          {
            ..._write('a', null, {'id': 'a'}),
            'operation': 'unknown',
          },
        ]),
        _plan([
          _write('a', null, {'id': 'a'}),
          _write('a', {'id': 'a'}, null),
        ]),
      ]) {
        expect(DataChangeSummary.tryParse(details), isNull, reason: '$details');
      }
    },
  );

  test('summary freezes incoming values without querying current records', () {
    final after = {'id': 'a', 'title': '审核时的名称'};
    final writes = [_write('a', null, after)];
    final summary = DataChangeSummary.tryParse(_plan(writes))!;
    after['title'] = '之后的名称';
    writes.clear();
    expect(summary.records.single.label, '审核时的名称');
    expect(
      () => summary.records.single.write['value'] = null,
      throwsUnsupportedError,
    );
  });

  Future<void> show(
    WidgetTester tester,
    Object? details, {
    String title = '确认变更',
    bool detailsOnly = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          theme: AppDesign.theme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => detailsOnly
                  ? showDataChangeDetails(context, DataChangeSummary.tryParse(details)!)
                  : reviewDialog(context, title, details, packageReview: title.startsWith('审核')),
                child: const Text('审核'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('审核'));
    await _waitForReviewContent(tester);
  }

  testWidgets(
    'compact review names deleted and updated records',
    (tester) async {
      await show(
        tester,
        _plan([
          _write('a', {'id': 'a', 'title': '要删除的任务', 'priority': 3}, null),
          _write(
            'b',
            {'id': 'b', 'name': '原名称', 'done': false},
            {'id': 'b', 'name': '新名称', 'done': true},
          ),
        ]),
      );
      expect(find.text('修改 1 项 · 删除 1 项').evaluate().length +
          find.text('删除 1 项 · 修改 1 项').evaluate().length, 1);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('要删除的任务'), findsOneWidget);
      expect(find.text('新名称'), findsOneWidget);
      expect(find.text('受影响的记录'), findsOneWidget);
      expect(find.text('全量原始详情'), findsNothing);
    },
  );

  testWidgets(
    'unknown writes fall back and package grants never claim no change',
    (tester) async {
      await show(
        tester,
        _plan([
          {'id': '未知', 'value': null},
        ]),
      );
      expect(find.text('无法生成可靠的数据摘要，请核对以下原始详情。'), findsOneWidget);
      expect(find.text('没有实际数据变化'), findsNothing);
      expect(find.textContaining('未知'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await show(tester, {
        'digest': 'digest',
        'preview': {'writes': []},
      }, title: '审核模块');
      expect(find.text('没有实际数据变化'), findsNothing);
      expect(find.textContaining('digest'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await show(tester, {
        'scopes': ['test.notes/write@1'],
      }, title: '审核授权');
      expect(find.text('没有实际数据变化'), findsNothing);
      expect(find.textContaining('test.notes/write@1'), findsOneWidget);
    },
  );

  testWidgets('empty actual plan states no data changes', (tester) async {
    await show(tester, _plan([]));
    expect(find.text('没有实际数据变化'), findsOneWidget);
    expect(find.text('全量原始详情'), findsNothing);
  });

  testWidgets('raw review cannot be confirmed when preparing details fails', (
    tester,
  ) async {
    await show(tester, {'invalidJson': double.nan});
    expect(find.text('无法显示完整详情，请重试。'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, '确认');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('重试加载详情'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dialog rebuild preserves the frozen review and reopening prepares a fresh snapshot',
    (tester) async {
      final details = _plan([]);
      await show(tester, details, detailsOnly: true);
      await tester.tap(find.text('全量原始详情'));
      await tester.pumpAndSettle();
      final raw = find.byType(JsonReviewContent);
      final snapshot = tester.widget<JsonReviewContent>(raw).value;
      final state = tester.state(raw);
      details['result'] = {'message': '下一次审核的结果'};
      tester.view.physicalSize = const Size(900, 700);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(
        identical(tester.widget<JsonReviewContent>(raw).value, snapshot),
        isTrue,
      );
      expect(identical(tester.state(raw), state), isTrue);
      expect(find.textContaining('真实结果'), findsOneWidget);
      expect(find.textContaining('下一次审核的结果'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('审核'));
      await tester.pumpAndSettle();
      expect(find.byType(JsonReviewContent), findsNothing);
      await tester.ensureVisible(find.text('全量原始详情'));
      await tester.tap(find.text('全量原始详情'));
      await tester.pumpAndSettle();
      expect(find.textContaining('下一次审核的结果'), findsOneWidget);
      expect(find.textContaining('真实结果'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('raw package review body drags to its last original field', (
    tester,
  ) async {
    await show(tester, {
      'definition': {
        'notes': [for (var i = 0; i < 100; i++) '原始说明$i'],
      },
      'tail': '原始计划末尾',
    }, title: '审核模块文件、数据、界面和权限');
    final view = find.byType(SingleChildScrollView);
    final viewport = tester.getRect(view);
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: view, matching: find.byType(Scrollable)).first,
    );
    final raw = find.byType(SelectableText);
    final start = Offset(tester.getRect(raw).center.dx, viewport.bottom - 40);
    expect(tester.getRect(raw).contains(start), isTrue);
    final initial = scroll.position.pixels;
    for (
      var attempt = 0;
      attempt < 100 &&
          scroll.position.pixels < scroll.position.maxScrollExtent - 1;
      attempt++
    ) {
      await tester.timedDragFrom(
        start,
        const Offset(0, -180),
        const Duration(milliseconds: 250),
      );
      await tester.pumpAndSettle();
    }
    expect(scroll.position.pixels, greaterThan(initial));
    expect(scroll.position.pixels, closeTo(scroll.position.maxScrollExtent, 1));
    expect(tester.widget<SelectableText>(raw).data, contains('原始计划末尾'));
    expect(find.text('确认').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'dragging long nested values reaches the next record and full raw tail',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final longValue = [
        for (var i = 0; i < 70; i++) {'index': i, 'value': '完整记录字段$i'},
      ];
      await show(
        tester,
        _plan([
          _write(
            'first',
            {'id': 'first', 'title': '首条记录'},
            {'id': 'first', 'title': '首条记录', 'nested': longValue},
          ),
          _write('next', null, {'id': 'next', 'title': '后续记录'}),
        ]),
        detailsOnly: true,
      );
      final valueDisclosure = find.textContaining('之后：内容较长，展开查看完整值');
      await tester.ensureVisible(valueDisclosure);
      await tester.tap(valueDisclosure);
      await _waitForReviewContent(tester);
      final view = find.byType(SingleChildScrollView);
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: view, matching: find.byType(Scrollable)).first,
      );
      final body = find
          .byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                (widget.data?.contains('完整记录字段69') ?? false),
          )
          .first;
      final viewport = tester.getRect(view);
      scroll.position.jumpTo(
        scroll.position.pixels + tester.getTopLeft(body).dy - viewport.top - 24,
      );
      await tester.pump();
      final start = Offset(viewport.center.dx, viewport.bottom - 40);
      expect(tester.getRect(body).contains(start), isTrue);
      final initial = scroll.position.pixels;
      await tester.timedDragFrom(
        start,
        const Offset(0, -180),
        const Duration(milliseconds: 250),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(initial));
      final next = find.text('新增 · 后续记录');
      for (
        var attempt = 0;
        attempt < 150 && !tester.getRect(next).overlaps(viewport);
        attempt++
      ) {
        await tester.timedDragFrom(
          start,
          const Offset(0, -180),
          const Duration(milliseconds: 250),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.getRect(next).overlaps(viewport), isTrue);
      final rawDisclosure = find.text('全量原始详情');
      await tester.ensureVisible(rawDisclosure);
      await tester.tap(rawDisclosure);
      await _waitForReviewContent(tester);
      final raw = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data?.contains('frozen-plan') ?? false),
      );
      scroll.position.jumpTo(
        scroll.position.pixels + tester.getTopLeft(raw).dy - viewport.top - 24,
      );
      await tester.pump();
      final beforeRaw = scroll.position.pixels;
      expect(tester.getRect(raw).contains(start), isTrue);
      for (
        var attempt = 0;
        attempt < 200 &&
            scroll.position.pixels < scroll.position.maxScrollExtent - 1;
        attempt++
      ) {
        await tester.timedDragFrom(
          start,
          const Offset(0, -220),
          const Duration(milliseconds: 250),
        );
        await tester.pumpAndSettle();
      }
      expect(scroll.position.pixels, greaterThan(beforeRaw));
      expect(
        scroll.position.pixels,
        closeTo(scroll.position.maxScrollExtent, 1),
      );
      expect(tester.widget<SelectableText>(raw).data, contains('真实结果'));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'remaining fields and long nested values can be expanded completely',
    (tester) async {
      final longValue = List.filled(700, '值').join();
      await show(
        tester,
        _plan([
          _write(
            'a',
            {'id': 'a'},
            {
              'id': 'a',
              'title': '大量字段',
              for (var i = 0; i < 14; i++) 'field$i': i,
              'nested': {'payload': longValue},
            },
          ),
        ]),
        detailsOnly: true,
      );
      expect(find.text('field13'), findsNothing);
      final fields = find.text('其余 4 个变化字段');
      await tester.ensureVisible(fields);
      await tester.tap(fields);
      await tester.pumpAndSettle();
      expect(find.text('field13'), findsOneWidget);
      expect(find.text('nested'), findsOneWidget);
      final value = find.textContaining('之后：内容较长，展开查看完整值');
      await tester.ensureVisible(value);
      await tester.tap(value);
      await _waitForReviewContent(tester);
      expect(find.textContaining(longValue), findsOneWidget);
    },
  );

  test(
    'native settings plans and unchanged records are represented accurately',
    () {
      final summary = DataChangeSummary.tryParse(
        _plan([
          {
            'moduleId': 'app.host',
            'space': 'host-controls',
            'collection': 'settings',
            'id': 'appearance',
            'before': {
              'id': 'appearance',
              'values': {'darkMode': false},
            },
            'value': {
              'id': 'appearance',
              'values': {'darkMode': true},
            },
          },
          _write('same', {'id': 'same'}, {'id': 'same'}),
        ]),
      )!;
      expect(summary.moduleIds, {'app.host'});
      expect(summary.count(DataChangeKind.update), 1);
      expect(summary.count(DataChangeKind.unchanged), 1);
      expect(summary.records.first.fields.single.field, 'values');
    },
  );

  testWidgets(
    'large batches are bounded with deletion first and all writes in raw detail',
    (tester) async {
      final writes = [
        for (var i = 0; i < 50; i++)
          _write('a$i', null, {'id': 'a$i', 'name': '记录$i'}),
        _write('delete', {'id': 'delete', 'name': '最后的删除'}, null),
      ];
      await show(tester, _plan(writes), detailsOnly: true);
      expect(find.text('删除 · 最后的删除'), findsOneWidget);
      expect(find.text('新增 · 记录18'), findsOneWidget);
      expect(find.text('新增 · 记录19'), findsNothing);
      expect(find.textContaining('其余 31 条'), findsOneWidget);
      final raw = find.text('全量原始详情');
      await tester.ensureVisible(raw);
      await tester.tap(raw);
      await _waitForReviewContent(tester);
      final content = find.byType(JsonReviewContent);
      final body = find.descendant(
        of: content,
        matching: find.byType(SelectableText),
      );
      final next = find.descendant(
        of: content,
        matching: find.widgetWithText(TextButton, '下一段'),
      );
      final pages = <String>[];
      while (true) {
        final text = tester.widget<SelectableText>(body).data!;
        expect(text.length, lessThanOrEqualTo(jsonReviewPageLength));
        pages.add(text);
        if (next.evaluate().isEmpty ||
            tester.widget<TextButton>(next).onPressed == null) {
          break;
        }
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(pages.length, greaterThan(1));
      expect(jsonDecode(pages.join()), _plan(writes));
      expect(find.textContaining('记录49'), findsOneWidget);
    },
  );

  testWidgets('narrow large text keeps summary scroll and cancel accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => reviewDialog(
                context,
                '确认实际数据变更',
                _plan([
                  _write('a', {
                    'id': 'a',
                    'title': '需要审核的较长名称记录',
                    'nested': {'before': false},
                  }, null),
                ]),
              ),
              child: const Text('审核'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('审核'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认实际数据变更'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling a real frozen plan leaves the database unchanged', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final store = CollectionStore(db);
    addTearDown(() async {
      await store.close();
      await db.close();
    });
    await tester.runAsync(() async {
      await createHostSchema(db);
      final package = await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.notes',
              'version': '1.0.0',
              'hostApi': '^1.21.0',
              'dataVersion': 1,
              'permissions': [],
            },
            'entryPoint': 'main.js',
            'pages': [],
            'services': [],
            'collections': [
              {
                'id': 'notes',
                'schema': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'title': {'type': 'string'},
                  },
                  'required': ['id', 'title'],
                },
                'indexes': [],
              },
            ],
          },
          {'main.js': 'export const main = () => {};'},
        ),
        allowUnsignedLocal: true,
      );
      await store.define(package, 'test-data');
    });
    final actor = ModuleActor('test.notes', '1.0.0', 'test-data', 1, {});
    store.activate(actor);
    late ChangePlan plan;
    await tester.runAsync(() async {
      final session = SnapshotSession(actor, 'cancel-request');
      await store.stage(session, actor, {
        'writes': [
          {
            'collection': 'notes',
            'id': 'a',
            'value': {'id': 'a', 'title': '取消的新记录'},
          },
        ],
      });
      plan = store.seal(session);
    });
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                accepted = await reviewDialog(context, '确认实际数据变更', {
                  'planId': plan.id,
                  'writes': plan.writes,
                  'result': plan.result,
                });
                if (accepted == true) {
                  await store.commit(plan.id, actor, authorize: (_) {});
                }
              },
              child: const Text('审核'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('审核'));
    await tester.pumpAndSettle();
    expect(find.text('取消的新记录'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
    await tester.runAsync(() async {
      expect(await store.get(actor, 'notes', 'a'), isNull);
      expect(await store.sql('SELECT * FROM host_commits'), isEmpty);
    });
  });
}
