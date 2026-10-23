import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/daily_widgets.dart';
import 'package:task_app/core/ui/script_keyed_list.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> source(String id) async {
  final path = '../packages/modules/$id';
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(jsonDecode(await File('$path/module.json').readAsString())),
      {'main.js': await File('$path/main.js').readAsString()},
    ),
    allowUnsignedLocal: true,
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> flushUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), true);
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late ModuleActor tasks;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('today-motion-');
    host = ModuleHost(store: store, directory: directory)
      ..clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    for (final id in ['app.tasks', 'app.views.today']) {
      await host.install(await source(id));
    }
    tasks = host.instances['app.tasks']!.actor;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Object?> command(String service, Map<String, Object?> input) async {
    final plan = await host.prepare(
      tasks,
      ServiceRef('app.tasks', service, 1),
      input,
    );
    host.review(plan.id, tasks);
    return host.commit(tasks, plan.id);
  }

  Future<void> show(
    WidgetTester tester, {
    bool reduced = false,
    bool embedded = true,
    String date = '2026-10-10',
  }) async {
    final page = ScriptPage(
      host: host,
      moduleId: 'app.views.today',
      handler: 'render',
      embedded: embedded,
      pageContext: {'pageId': 'app.views.today.tasks', 'selectedDate': date},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(Brightness.light),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: embedded ? SingleChildScrollView(child: page) : page,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'inline quick input survives 50-row insertions, refresh and collapse without losing focus or selection',
    (tester) async {
      host.interaction = (_, method, args) async =>
          method == 'ui.review' ? true : null;
      await db.transaction(() async {
        for (var i = 0; i < 51; i++) {
          final id = 'task-${i.toString().padLeft(3, '0')}';
          await db.customStatement(
            'INSERT INTO host_records(module_id,space,collection,id,value,revision,deleted) VALUES(?,?,?,?,?,1,0)',
            [
              tasks.moduleId,
              tasks.space,
              'tasks',
              id,
              jsonEncode({
                'id': id,
                'title': '任务 $i',
                'priority': 0,
                'createdAt': id,
                'updatedAt': id,
                'plannedDate': '2026-10-10',
                'completedAt': null,
                'deletedAt': null,
                'archivedAt': null,
                'parentTaskId': null,
              }),
            ],
          );
        }
      });
      await show(tester);
      expect(find.byType(TextField), findsNothing);
      await tester.ensureVisible(find.byTooltip('添加任务'));
      await tester.tap(find.byTooltip('添加任务'));
      await settle(tester);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '下一条草稿');
      final field = tester.widget<TextField>(find.byType(TextField));
      final original = tester.element(find.byType(TextField));
      field.controller!.value = const TextEditingValue(
        text: '下一条草稿',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
        composing: TextRange(start: 1, end: 3),
      );
      final value = field.controller!.value;
      await tester.runAsync<Object?>(
        () => command('task.create', {
          'title': '插到最前',
          'priority': 3,
          'plannedDate': '2026-10-10',
        }),
      );
      await settle(tester);
      expect(tester.element(find.byType(TextField)), same(original));
      expect(field.focusNode!.hasFocus, true);
      expect(field.controller!.value, value);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '加载更多任务'));
      await tester.tap(find.widgetWithText(FilledButton, '加载更多任务'));
      await settle(tester);
      expect(find.byType(DailyTaskItem), findsNWidgets(52));
      expect(tester.element(find.byType(TextField)), same(original));
      expect(field.controller!.value, value);
      expect(field.focusNode!.hasFocus, true);
      await tester.runAsync(
        () =>
            command('task.setCompleted', {'id': 'task-000', 'completed': true}),
      );
      await settle(tester);
      expect(find.byType(DailyTaskItem), findsNWidgets(51));
      expect(tester.element(find.byType(TextField)), same(original));
      expect(field.controller!.value, value);
      expect(field.focusNode!.hasFocus, true);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '收起添加'));
      await tester.tap(find.widgetWithText(FilledButton, '收起添加'));
      await settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(field.focusNode!.hasFocus, false);
      await tester.ensureVisible(find.byTooltip('添加任务'));
      await tester.tap(find.byTooltip('添加任务'));
      await settle(tester);
      expect(tester.element(find.byType(TextField)), same(original));
      expect(field.controller!.text, value.text);
      expect(field.controller!.selection, value.selection);
      expect(field.focusNode!.hasFocus, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'standalone production list keeps its focused draft across the former 50-row layout boundary',
    (tester) async {
      await db.transaction(() async {
        for (var i = 0; i < 47; i++) {
          final id = 'task-${i.toString().padLeft(3, '0')}';
          await db.customStatement(
            'INSERT INTO host_records(module_id,space,collection,id,value,revision,deleted) VALUES(?,?,?,?,?,1,0)',
            [
              tasks.moduleId,
              tasks.space,
              'tasks',
              id,
              jsonEncode({
                'id': id,
                'title': '列表任务 $i',
                'priority': 0,
                'createdAt': id,
                'updatedAt': id,
                'plannedDate': '2026-10-10',
                'completedAt': null,
                'deletedAt': null,
                'archivedAt': null,
                'parentTaskId': null,
              }),
            ],
          );
        }
      });
      await show(tester, embedded: false);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(DailyTaskItem).evaluate().length, lessThan(20));
      await tester.tap(find.byTooltip('添加任务'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), '独立页面草稿');
      final original = tester.element(find.byType(TextField));
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      final value = field.controller!.value;
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(
          () => command('task.create', {
            'title': '最前 $i',
            'priority': 3,
            'plannedDate': '2026-10-10',
          }),
        );
        await settle(tester);
      }
      expect(
        tester
            .widget<ScriptKeyedList>(find.byType(ScriptKeyedList))
            .items
            .length,
        53,
      );
      expect(find.byType(ListView), findsOneWidget);
      expect(
        tester.element(find.byType(TextField, skipOffstage: false)),
        same(original),
      );
      expect(field.focusNode!.hasFocus, true);
      expect(field.controller!.value, value);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'production historical completion updates its row and date switching does not exit it',
    (tester) async {
      await tester.runAsync(
        () => command('task.create', {
          'title': '历史任务',
          'plannedDate': '2026-10-09',
        }),
      );
      host.interaction = (_, method, args) async =>
          method == 'ui.review' ? true : null;
      await show(tester, date: '2026-10-09');
      final original = tester.element(find.byType(DailyTaskItem));
      await tester.tap(find.byType(Checkbox));
      await flushUntil(
        tester,
        () =>
            tester.widget<DailyTaskItem>(find.byType(DailyTaskItem)).completed,
      );
      expect(tester.element(find.byType(DailyTaskItem)), same(original));
      final list = tester.widget<ScriptKeyedList>(find.byType(ScriptKeyedList));
      final row = find.byKey(ValueKey((list.scope, list.removeKeys.single)));
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(of: row, matching: find.byType(FadeTransition)),
            )
            .opacity
            .value,
        1,
      );
      await show(tester, date: '2026-10-11');
      expect(find.text('历史任务'), findsNothing);
      expect(
        tester
            .widget<ScriptKeyedList>(find.byType(ScriptKeyedList))
            .feedbackKey,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'production overview retains its element and overlapping date cells when the civil date changes',
    (tester) async {
      final selected = ValueNotifier('2026-10-10');
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder(
                valueListenable: selected,
                builder: (_, date, _) => ScriptPage(
                  host: host,
                  moduleId: 'app.views.today',
                  handler: 'render',
                  embedded: true,
                  pageContext: {
                    'pageId': 'app.views.today.overview',
                    'selectedDate': date,
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final overview = tester.element(find.byType(DayOverview));
      final cell = tester.element(
        find.byKey(const ValueKey('daily-date:2026-10-10')),
      );
      for (final date in ['2026-10-11', '2026-10-09', '2026-10-10']) {
        selected.value = date;
        await tester.pump();
        await settle(tester);
        expect(tester.element(find.byType(DayOverview)), same(overview));
        expect(
          tester.element(find.byKey(const ValueKey('daily-date:2026-10-10'))),
          same(cell),
        );
        expect(
          tester.widget<DayOverview>(find.byType(DayOverview)).selectedDate,
          date,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'native completion commits once without a review and notification failure never undoes success',
    (tester) async {
      final created = object(
        await tester.runAsync<Object?>(
          () => command('task.create', {
            'title': '审核完成测试',
            'plannedDate': '2026-10-10',
          }),
        ),
      );
      final id = created['id'] as String;
      final reviews = <Completer<bool>>[];
      var notifications = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') {
          final gate = Completer<bool>();
          reviews.add(gate);
          return gate.future;
        }
        if (method == 'ui.notify') {
          notifications++;
          expect(
            object(await store.get(tasks, 'tasks', id))['completedAt'],
            isNotNull,
          );
          throw StateError('提示层不可用');
        }
        return null;
      };
      await show(tester, reduced: true);
      await tester.tap(find.byType(Checkbox));
      await settle(tester);
      expect(reviews, isEmpty);
      expect(notifications, 1);
      expect(find.byType(DailyTaskItem), findsNothing);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(
        object(await store.get(tasks, 'tasks', id))['completedAt'],
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'native completion exits after commit and survives its store refresh',
    (tester) async {
      await tester.runAsync(
        () => command('task.create', {
          'title': '提交后退出',
          'plannedDate': '2026-10-10',
        }),
      );
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return null;
      };
      await show(tester);
      final original = tester.element(find.byType(DailyTaskItem));
      await tester.tap(find.byType(Checkbox));
      await flushUntil(
        tester,
        () =>
            tester
                .widget<ScriptKeyedList>(find.byType(ScriptKeyedList))
                .feedbackKey !=
            null,
      );
      expect(tester.element(find.byType(DailyTaskItem)), same(original));
      expect(reviews, 0);
      final ignores = tester.widgetList<IgnorePointer>(
        find.ancestor(
          of: find.byType(DailyTaskItem),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignores.any((widget) => widget.ignoring), true);
      final semantics = tester.widgetList<ExcludeSemantics>(
        find.ancestor(
          of: find.byType(DailyTaskItem),
          matching: find.byType(ExcludeSemantics),
        ),
      );
      expect(semantics.any((widget) => widget.excluding), true);
      await tester.runAsync(
        () => command('task.create', {
          'title': '触发刷新',
          'plannedDate': '2026-10-10',
        }),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(DailyTaskItem), findsOneWidget);
      await flushUntil(tester, () => find.text('触发刷新').evaluate().isNotEmpty);
      expect(
        tester.element(find.widgetWithText(DailyTaskItem, '提交后退出')),
        same(original),
      );
      await tester.pump(const Duration(milliseconds: 141));
      expect(find.text('提交后退出'), findsNothing);
      await settle(tester);
      expect(find.byType(DailyTaskItem), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'native completion rejects a stale row without success feedback',
    (tester) async {
      final created = object(
        await tester.runAsync<Object?>(
          () => command('task.create', {
            'title': '冲突不退出',
            'plannedDate': '2026-10-10',
          }),
        ),
      );
      var notifications = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') return true;
        if (method == 'ui.notify') notifications++;
        return null;
      };
      await show(tester);
      host.clockNow = () => DateTime.utc(2026, 10, 10, 6, 0, 1);
      await tester.runAsync(
        () => command('task.updateFields', {
          'id': created['id'],
          'changes': {'priority': 1},
        }),
      );
      await tester.tap(find.byType(Checkbox));
      await settle(tester);
      expect(
        object(
          await store.get(tasks, 'tasks', created['id'] as String),
        )['completedAt'],
        isNull,
      );
      expect(find.byType(DailyTaskItem), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      expect(
        tester
            .widget<ScriptKeyedList>(find.byType(ScriptKeyedList))
            .feedbackKey,
        isNull,
      );
      expect(notifications, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'production quick add highlights only its committed task and keeps existing rows',
    (tester) async {
      await tester.runAsync(
        () => command('task.create', {
          'title': '保留的任务',
          'plannedDate': '2026-10-10',
        }),
      );
      host.interaction = (_, method, args) async =>
          method == 'ui.review' ? true : null;
      await show(tester);
      final original = tester.element(find.byType(DailyTaskItem));
      await tester.tap(find.byTooltip('添加任务'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '新任务反馈');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '添加'));
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await flushUntil(
        tester,
        () =>
            tester
                .widget<ScriptKeyedList>(find.byType(ScriptKeyedList))
                .feedbackKey !=
            null,
      );
      final list = tester.widget<ScriptKeyedList>(find.byType(ScriptKeyedList));
      expect(list.highlightKeys, hasLength(1));
      expect(list.removeKeys, isEmpty);
      final row = find.byKey(ValueKey((list.scope, list.highlightKeys.single)));
      double amount() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: row,
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color!
              .a;
      expect(amount(), greaterThan(0));
      expect(
        tester.element(find.widgetWithText(DailyTaskItem, '保留的任务')),
        same(original),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await tester.pump(const Duration(milliseconds: 950));
      await settle(tester);
      expect(amount(), 0);
      await tester.runAsync(
        () => command('task.create', {
          'title': '外部新增',
          'plannedDate': '2026-10-10',
        }),
      );
      await settle(tester);
      expect(
        amount(),
        0,
        reason:
            'The persistent feedback token does not replay on external refresh',
      );
      expect(find.byType(DailyTaskItem), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'lazy invalid children render an error without escaping the script boundary',
    (tester) async {
      await tester.runAsync(
        () async => host.install(
          await ScriptPackage.verify(
            await ScriptPackage.build(
              {
                'formatVersion': 3,
                'manifest': {
                  'id': 'app.test.keyed',
                  'name': 'Keyed regression',
                  'version': '1.0.0',
                  'hostApi': '^1.20.0',
                  'dataVersion': 1,
                  'permissions': ['ui'],
                },
                'entryPoint': 'main.js',
                'pages': [
                  {
                    'id': 'app.test.keyed.page',
                    'title': 'Keyed',
                    'handler': 'render',
                  },
                ],
              },
              {
                'main.js': '''export function render() {return {tree: {
      type: 'keyedList', scope: 'test', children: [
        {type: 'transition', key: 'invalid', effect: 'unknown', child: {type: 'text', text: 'bad'}}
      ]
    }}; }''',
              },
            ),
            allowUnsignedLocal: true,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'app.test.keyed',
              handler: 'render',
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.textContaining('模块界面无效：'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
