import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/core/module_host/time_grid.dart';

Future<void> settleNative(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory dir;
  Future<void> setup(
    WidgetTester tester, {
    bool schedule = false,
    bool tasks = false,
  }) async {
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = CollectionStore(db);
      dir = await Directory.systemTemp.createTemp('host-ui-');
      host = ModuleHost(store: store, directory: dir);
      await host.initialize();
      for (final id in [
        if (tasks) 'app.tasks',
        if (tasks) 'app.views.inbox',
        if (schedule) 'app.schedule',
      ]) {
        await host.install(
          await ScriptPackage.verify(
            await File('../dist/modules/$id.xmodule').readAsBytes(),
            allowUnsignedLocal: true,
          ),
        );
      }
    });
    addTearDown(() async {
      await host.close();
      await store.close();
      await db.close();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: XudianApp(),
      ),
    );
    await settleNative(tester);
  }

  testWidgets(
    'production shell retains settings and recovery without business modules',
    (tester) async {
      await setup(tester);
      expect(find.text('没有可用工作区'), findsOneWidget);
      await tester.tap(find.text('打开设置并恢复模块'));
      await settleNative(tester);
      expect(find.text('外观与交互'), findsOneWidget);
      expect(find.text('模块与连接'), findsOneWidget);
      await tester.tap(find.text('模块与连接'));
      await settleNative(tester);
      await tester.tap(find.text('模块管理与恢复'));
      await settleNative(tester);
      expect(find.byType(HostManagerPage), findsOneWidget);
      expect(find.text('导入 .xmodule'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('independent module settings stay under the module category', (
    tester,
  ) async {
    await setup(tester);
    await tester.runAsync(() async {
      await host.install(
        await ScriptPackage.verify(
          await ScriptPackage.build(
            {
              'formatVersion': 3,
              'manifest': {
                'id': 'private.settings',
                'version': '1.0.0',
                'hostApi': '^1.0.0',
                'dataVersion': 1,
                'permissions': ['ui'],
                'dependencies': [],
              },
              'entryPoint': 'main.js',
              'collections': [],
              'pages': [],
              'services': [],
              'contributions': [
                {
                  'id': 'private.settings.content',
                  'slot': 'settingsSections',
                  'kind': 'content',
                  'handler': 'render',
                  'label': '独立模块设置',
                },
              ],
            },
            {
              'main.js': "export function render(){return {state:{},tree:{type:'text',text:'独立模块设置'}};}",
            },
          ),
          allowUnsignedLocal: true,
        ),
      );
    });
    await settleNative(tester);
    await tester.tap(find.text('打开设置并恢复模块'));
    await settleNative(tester);
    expect(find.text('独立模块设置'), findsNothing);
    await tester.tap(find.text('模块与连接'));
    await settleNative(tester);
    expect(find.text('独立模块设置'), findsOneWidget);
    expect(find.text('模块管理与恢复'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'script task input prepares host-reviewed changes and writes generic records',
    (tester) async {
      await setup(tester, tasks: true);
      expect(find.text('收件箱为空'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '买牛奶');
      await tester.ensureVisible(find.text('添加'));
      await tester.tap(find.text('添加'));
      await settleNative(tester);
      expect(find.text('确认实际数据变更'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await settleNative(tester);
      expect(find.text('买牛奶'), findsOneWidget);
      final rows = await tester.runAsync(
        () => store.query(host.instances['app.tasks']!.actor, 'tasks', {}),
      );
      expect(object(rows!.single)['title'], '买牛奶');
      expect(await tester.runAsync(() => db.select(db.tasks).get()), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'importing schedule package adds a declarative week view to unchanged shell',
    (tester) async {
      await setup(tester);
      await tester.runAsync(() async {
        await host.install(
          await ScriptPackage.verify(
            await File('../dist/modules/app.schedule.xmodule').readAsBytes(),
            allowUnsignedLocal: true,
          ),
        );
        final actor = host.instances['app.schedule']!.actor;
        final p = await host.prepare(
          actor,
          const ServiceRef('app.schedule', 'schedule.timetable.save', 1),
          {
            'timetable': {
              'id': 'table',
              'name': '测试课表',
              'firstMonday': '2026-09-07',
              'totalWeeks': 20,
              'timezone': 'Asia/Shanghai',
              'displayWeekStart': 1,
              'periods': [
                {'number': 1, 'start': '08:00', 'end': '08:45'},
              ],
            },
          },
        );
        host.review(p.id, actor);
        await host.commit(actor, p.id);
      });
      await settleNative(tester);
      expect(find.byType(TimeGrid), findsOneWidget);
      expect(
        tester.widget<TimeGrid>(find.byType(TimeGrid)).rows.single['subtitle'],
        '08:00\n08:45',
      );
      await tester.runAsync(() => host.uninstall('app.schedule'));
      await settleNative(tester);
      expect(find.text('没有可用工作区'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'timeGrid exposes two overlapping blocks and accepts half-open adjacent intervals',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeGrid(
              columns: const [
                {'id': 'mon', 'label': '周一'},
              ],
              rows: const [
                {'id': '1', 'label': '1'},
                {'id': '2', 'label': '2'},
              ],
              blocks: const [
                {
                  'id': 'a',
                  'column': 'mon',
                  'start': 0,
                  'end': 1,
                  'title': 'A',
                },
                {
                  'id': 'b',
                  'column': 'mon',
                  'start': 0,
                  'end': 1,
                  'title': 'B',
                },
                {
                  'id': 'c',
                  'column': 'mon',
                  'start': 1,
                  'end': 2,
                  'title': 'C',
                },
              ],
              onEvent: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
