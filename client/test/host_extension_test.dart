import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';
import 'package:task_app/core/module_host/legacy_converter.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/ui/ui_composition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('extension-host-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    for (final id in ['app.tasks', 'app.views.today']) {
      await host.install(
        await ScriptPackage.verify(
          await File('../dist/modules/$id.xmodule').readAsBytes(),
          allowUnsignedLocal: true,
        ),
      );
    }
    await host.install(
      await convertLegacyModule({
        'formatVersion': 1,
        'manifest': {
          'id': 'example.fields',
          'version': '1.0.0',
          'coreApi': '1',
          'permissions': ['fields.write'],
        },
        'fields': [
          {'id': 'score', 'label': '成绩', 'type': 'number'},
          {
            'id': 'subjects',
            'label': '科目',
            'type': 'multiSelect',
            'config': {
              'options': ['数学', '英语'],
            },
          },
        ],
      }),
    );
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Object?> commit(
    ModuleActor actor,
    ServiceRef service,
    Object? input,
  ) async {
    final plan = await host.prepare(actor, service, input);
    host.review(plan.id, actor);
    return host.commit(actor, plan.id);
  }

  test('view can edit scoped extension fields, clear them, and lose visibility on disable', () async {
    final tasks = host.instances['app.tasks']!.actor,
        view = host.instances['app.views.today']!.actor;
    final id = object(
      await commit(tasks, const ServiceRef('app.tasks', 'task.create', 1), {
        'title': '考试',
      }),
    )['id'];
    final entity = {'moduleId': 'app.tasks', 'collection': 'tasks', 'id': id};
    await commit(view, const ServiceRef('example.fields', 'fields.set', 1), {
      'entity': entity,
      'fieldKey': 'score',
      'value': 92,
    });
    var rows = await host.query(
      view,
      const ServiceRef('app.tasks', 'task.list', 1),
      {},
    );
    expect(
      object(object((rows as List).single)['fields'])['example.fields:score'],
      92,
    );
    await expectLater(
      host.prepare(view, const ServiceRef('example.fields', 'fields.set', 1), {
        'entity': entity,
        'fieldKey': 'score',
        'value': '错误类型',
      }),
      throwsStateError,
    );
    await commit(view, const ServiceRef('example.fields', 'fields.clear', 1), {
      'entity': entity,
      'fieldKey': 'score',
    });
    await commit(view, const ServiceRef('example.fields', 'fields.set', 1), {
      'entity': entity,
      'fieldKey': 'subjects',
      'value': ['数学', '英语'],
    });
    await host.disable('example.fields');
    rows = await host.query(
      view,
      const ServiceRef('app.tasks', 'task.list', 1),
      {},
    );
    expect(object((rows as List).single)['fieldDefinitions'], isEmpty);
    await host.enable('example.fields');
    rows = await host.query(
      view,
      const ServiceRef('app.tasks', 'task.list', 1),
      {},
    );
    expect(object(object((rows as List).single)['fields']), {
      'example.fields:subjects': ['数学', '英语'],
    });
  });
  test('extension permission does not authorize arbitrary services or entity scopes', () async {
    final view = host.instances['app.views.today']!.actor;
    await expectLater(
      host.prepare(view, const ServiceRef('example.fields', 'fields.set', 1), {
        'entity': {
          'moduleId': 'app.schedule',
          'collection': 'courses',
          'id': 'forged',
        },
        'fieldKey': 'score',
        'value': 10,
      }),
      throwsStateError,
    );
  });
  test('packaged UI examples preserve entry IDs, nested contributions and simulated interactions', () async {
    final packages = <String, ScriptPackage>{};
    for (final id in ['app.ui.examples', 'app.ui.contributions']) {
      final package = await ScriptPackage.verify(
        await File('../dist/modules/$id.xmodule').readAsBytes(),
        allowUnsignedLocal: true,
      );
      packages[id] = package;
      await host.install(package);
    }
    final entries = ScriptAppModule(
      host,
      packages['app.ui.contributions']!,
    ).ui.whereType<UiEntryRegistration>().map((entry) => entry.id).toSet();
    expect(entries, {
      'app.ui.contributions.tab',
      'app.ui.contributions.section',
      'app.ui.contributions.invalid',
    });
    final initial = object(
      await host.invokePage('app.ui.examples', 'render', {
        'context': {'pageId': 'app.ui.examples.page'},
      }),
    );
    final updated = object(
      await host.invokePage('app.ui.examples', 'render', {
        'state': initial['state'],
        'event': {'type': 'done', 'id': 'plan', 'value': true},
        'context': {'pageId': 'app.ui.examples.page'},
      }),
    );
    expect(object(updated['state'])['completed'], ['done', 'plan']);
    expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
  });
  testWidgets('invalid typed form retains entered values until corrected', (
    tester,
  ) async {
    Object? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog(
                context: context,
                builder: (_) => const HostFormDialog(
                  title: '类型检查',
                  fields: [
                    {
                      'key': 'number',
                      'label': '成绩',
                      'type': 'number',
                      'value': '92',
                    },
                    {
                      'key': 'date',
                      'label': '日期',
                      'type': 'date',
                      'value': '2026-10-07',
                    },
                  ],
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'NaN');
    await tester.enterText(find.byType(TextField).last, '2026-02-30');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效数字'), findsOneWidget);
    expect(find.text('请输入有效 YYYY-MM-DD 日期'), findsOneWidget);
    expect(result, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'NaN',
    );
    await tester.enterText(find.byType(TextField).first, '98.5');
    await tester.enterText(find.byType(TextField).last, '2026-02-28');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(result, {'number': 98.5, 'date': '2026-02-28'});
  });
}
