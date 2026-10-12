import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

Future<ScriptPackage> compactProvider() async => ScriptPackage.verify(
  await ScriptPackage.build(
    object(
      jsonDecode(
        await File('../packages/modules/example.ui.compact/module.json')
            .readAsString(),
      ),
    ),
    {},
  ),
  allowUnsignedLocal: true,
);

Future<ScriptPackage> consumer({bool declaresProvider = true}) async =>
    ScriptPackage.verify(
      await ScriptPackage.build(
        {
          'formatVersion': 3,
          'manifest': {
            'id': 'test.button.consumer',
            'version': '1.0.0',
            'hostApi': '^1.12.0',
            'dataVersion': 1,
            'permissions': [],
            'dependencies': declaresProvider ? ['example.ui.compact'] : [],
          },
          'entryPoint': 'main.js',
          'collections': [],
          'services': [],
          'pages': [],
        },
        {
          'main.js': declaresProvider
              ? r'''
import {ui} from '@xudian/sdk';
export function render({state={},event}) {
  if (event?.type==='choose') state={...state,last:event.button,count:(state.count||0)+1};
  return {state,tree:{type:'column',children:[
    ui.component('example.ui.compact.primaryButton@1',{
      props:{label:'保存草稿'},events:{press:{type:'choose',button:'primary'}}}),
    ui.component('example.ui.compact.outlineButton@1',{
      props:{label:'稍后处理'},events:{press:{type:'choose',button:'outline'}}}),
    {type:'text',text:'收到 '+(state.last||'无')+' · '+(state.count||0)}
  ]}};
}
'''
              : r'''
import {ui} from '@xudian/sdk';
export function render() {
  return {tree:ui.component('example.ui.compact.primaryButton@1',{
    props:{label:'未声明依赖的按钮'},events:{press:{type:'choose'}}})};
}
''',
        },
      ),
      allowUnsignedLocal: true,
    );

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late List<Map<String, Object?>> initialRecords;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('registered-buttons-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    await host.install(await compactProvider());
    final now = DateTime.now();
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'existing-task',
            title: '保留真实任务',
            createdAt: now,
            updatedAt: now,
          ),
        );
    initialRecords = await store.sql(
      'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
    );
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'test.button.consumer',
              handler: 'render',
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> verifyTasksUnchanged() async {
    final task = (await db.select(db.tasks).get()).single;
    expect(task.id, 'existing-task');
    expect(task.title, '保留真实任务');
    expect(await db.select(db.changeOperations).get(), isEmpty);
    expect(
      await store.sql(
        'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
      ),
      initialRecords,
    );
  }

  testWidgets(
    'declared provider renders distinct real buttons and returns press events without writing tasks',
    (tester) async {
      await tester.runAsync(() async => host.install(await consumer()));
      await show(tester);
      final components = tester.widgetList<UiComponent>(
        find.byType(UiComponent),
      );
      expect(
        components.map((component) => component.ref),
        containsAll([
          'example.ui.compact.primaryButton@1',
          'example.ui.compact.outlineButton@1',
        ]),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(host.instances['example.ui.compact']!.hasWorkers, isFalse);
      expect(
        host.instances['example.ui.compact']!.package.permissions,
        isEmpty,
      );
      expect(find.text('收到 无 · 0'), findsOneWidget);
      await tester.tap(find.text('保存草稿'));
      await settle(tester);
      expect(find.text('收到 primary · 1'), findsOneWidget);
      await tester.tap(find.text('稍后处理'));
      await settle(tester);
      expect(find.text('收到 outline · 2'), findsOneWidget);
      await tester.runAsync(verifyTasksUnchanged);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('undeclared provider cannot render its exported button', (
    tester,
  ) async {
    await tester.runAsync(
      () async => host.install(await consumer(declaresProvider: false)),
    );
    await show(tester);
    expect(find.textContaining('独有 UI 组件需要声明包依赖'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await tester.runAsync(verifyTasksUnchanged);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
