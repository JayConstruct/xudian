import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'support/module_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ModuleHost host;
  late CollectionStore store;
  late AppDatabase db;
  late Directory dir;
  const module = 'app.ideas';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    dir = await Directory.systemTemp.createTemp('ideas-');
    host = ModuleHost(
      store: store,
      directory: dir,
      systemTimezoneResolver: () async => 'Asia/Shanghai',
    );
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 11, 23, 15, 55);
    for (final id in ['app.tasks', module]) {
      await host.install(await sourcePackage(id));
    }
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<Map<String, Object?>> command(
    String id,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances[module]!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef(module, 'idea.$id', 1),
      input,
    );
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> read(String id) async =>
      object(await store.get(host.instances[module]!.actor, 'ideas', id));
  Future<List<Map<String, Object?>>> page(
    String name, {
    Map<String, Object?> forms = const {},
    Map<String, Object?> state = const {},
    Map<String, Object?> context = const {},
  }) async => nodes(
    await host.invokePage(module, 'render', {
      'context': {'pageId': 'app.ideas.$name', ...context},
      'state': state,
      'formValues': forms,
    }),
  );

  testWidgets('day toolbar and its adjacent-date controls fit a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScriptPage(
            host: host,
            moduleId: module,
            handler: 'render',
            pageContext: const {
              'pageId': 'app.ideas.day',
              'date': '2026-11-23',
            },
          ),
        ),
      ),
    );
    Future<void> waitFor(String label) async {
      for (var i = 0; i < 60 && find.text(label).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await waitFor('11月23日');
    await tester.tap(find.byTooltip('上一天'));
    await waitFor('11月22日');
    await tester.tap(find.byTooltip('下一天'));
    await waitFor('11月23日');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'record, search and edit across local midnight without moving the original',
    () async {
      expect(
        await page('home'),
        contains(predicate((n) => n is Map && n['title'] == '还没有想法')),
      );
      await expectLater(command('record', {'body': '  '}), throwsA(anything));
      final id =
          (await command('record', {'body': '  声音地图  '}))['id'] as String;
      host.clockNow = () => DateTime.utc(2026, 11, 23, 16, 15);
      await command('record', {'body': '公园'});
      await command('favorite', {'id': id, 'revision': 1, 'favorite': true});
      await command('edit', {'id': id, 'revision': 2, 'body': '校园声音地图'});
      final idea = await read(id);
      expect(object(idea['created'])['date'], '2026-11-23');
      expect(object(idea['modified'])['date'], '2026-11-24');
      expect(
        (await page('home'))
            .where((n) => n['type'] == 'timelineItem')
            .map((n) => n['time']),
        ['23:55', '00:15'],
      );
      expect(
        (await page(
          'day',
          context: {'date': '2026-11-23'},
        )).where((n) => n['type'] == 'timelineItem'),
        hasLength(1),
      );
      expect(
        (await page(
          'search',
          forms: {'query': '声音'},
        )).where((n) => n['highlight'] == '声音').single['text'],
        '校园声音地图',
      );
      expect(
        (await page(
          'home',
          state: {'favorite': true},
        )).where((n) => n['type'] == 'timelineItem'),
        hasLength(1),
      );
      await expectLater(
        command('edit', {'id': id, 'revision': 1, 'body': '覆盖'}),
        throwsA(anything),
      );
    },
  );

  test('older pages prepend to the newest window and search respects the active filter', () async {
    for (var minute = 0; minute < 42; minute++) {
      host.clockNow = () => DateTime.utc(2026, 11, 23, 1, minute);
      final id = (await command('record', {'body': '同词 $minute'}))['id'];
      if (minute == 1 || minute == 41) {
        await command('favorite', {'id': id, 'revision': 1, 'favorite': true});
      }
    }
    List<Object?> times(List<Map<String, Object?>> view) => view
        .where((n) => n['type'] == 'timelineItem')
        .map((n) => n['time'])
        .toList();
    final recent = await page('home');
    expect(times(recent), hasLength(40));
    expect(times(recent).first, '09:02');
    expect(times(recent).last, '09:41');
    expect(
      recent.indexWhere((n) => n['text'] == '查看更早的想法'),
      lessThan(recent.indexWhere((n) => n['type'] == 'timelineItem')),
    );
    final expanded = times(await page('home', state: {'limit': 80}));
    expect(expanded.take(2), ['09:00', '09:01']);
    expect(expanded.skip(2), times(recent));
    expect(
      times(
        await page(
          'search',
          forms: {'query': '同词'},
          context: {'favorite': true},
        ),
      ),
      ['09:01', '09:41'],
    );
    expect(times(await page('search', forms: {'query': '同词 20'})), ['09:20']);
    expect(
      times(
        await page(
          'search',
          forms: {'query': '同词 20'},
          context: {'favorite': true},
        ),
      ),
      isEmpty,
    );
  });

  test('one composite commit per target, idempotent retry, independent task and project lifetimes', () async {
    final id = (await command('record', {'body': '校园声音地图'}))['id'] as String;
    Map<String, Object?> request(
      int revision,
      String token,
      String name,
      String kind,
    ) => {
      'id': id,
      'revision': revision,
      'kind': kind,
      'name': name,
      'requestId': token,
    };
    final first = request(1, 'a', '录音', 'task');
    final actor = host.instances[module]!.actor;
    final prepared = await host.prepare(
      actor,
      ServiceRef(module, 'idea.createTarget', 1),
      first,
    );
    expect(prepared.writes, hasLength(2));
    expect((await read(id))['history'], isEmpty);
    final taskId = (await command('createTarget', first))['id'] as String;
    expect((await command('createTarget', first))['id'], taskId);
    await command('createTarget', request(2, 'b', '剪辑', 'task'));
    final projectId =
        (await command(
              'createTarget',
              request(3, 'c', '声音地图', 'project'),
            ))['id']
            as String;
    final history = objects((await read(id))['history']);
    expect(history.map((r) => r['name']), ['声音地图', '剪辑', '录音']);
    await command('delete', {'id': id, 'revision': 4});
    final tasks = host.instances['app.tasks']!.actor;
    final task = object(await store.get(tasks, 'tasks', taskId));
    expect(task['title'], '录音');
    expect([
      task['dueDate'],
      task['plannedDate'],
      task['plannedStartAt'],
      task['projectId'],
    ], everyElement(isNull));
    expect(
      object(await store.get(tasks, 'projects', projectId))['folderId'],
      isNull,
    );
    expect(await store.get(actor, 'ideas', id), isNull);
  });
  test('failed capture keeps the draft; edit and target forms preserve cancellation and retry', () async {
    Future<Map<String, Object?>> event(
      String type, {
      Map<String, Object?> details = const {},
      Map<String, Object?> forms = const {},
    }) async => object(
      await host.invokePage(module, 'render', {
        'context': {'pageId': 'app.ideas.home'},
        'event': {'type': type, ...details},
        'formValues': forms,
      }),
    );
    final failed = await event('record', forms: {'body': 'x' * 4001});
    expect(object(failed['state'])['saveError'], contains('暂未保存'));
    expect(failed.containsKey('clearForms'), isFalse);
    final id = (await command('record', {'body': '测试想法'}))['id'] as String;
    final item = {'id': id, 'revision': 1};
    final dialogs = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      if (method == 'ui.dialog') {
        dialogs.add(args);
        return null;
      }
      return true;
    };
    await event('edit', details: item);
    expect(
      objects(objects(dialogs.single['fields']).single['metadata'])
          .map((row) => row['text']),
      ['创建于 11 月 23 日 23:55', '修改于 11 月 23 日 23:55'],
    );
    expect(objects(dialogs.single['fields']).single['value'], '测试想法');
    await event('target', details: {...item, 'kind': 'task'});
    expect(objects(dialogs.last['fields']).single['value'], '');
    expect((await read(id))['history'], isEmpty);
    final entered = <String>[];
    host.interaction = (_, method, args) async {
      if (method == 'ui.dialog') {
        final field = objects(args['fields']).single;
        entered.add(field['value'] as String);
        return {'name': entered.length == 1 ? '  ' : '有效名称'};
      }
      return true;
    };
    await event('target', details: {...item, 'kind': 'project'});
    expect(entered, ['', '  ']);
    expect(objects((await read(id))['history']).single['name'], '有效名称');
  });

  test(
    'completion preserves the idea and is reversible in every view',
    () async {
      const body = '校园声音地图\n公园的晚钟';
      final id = (await command('record', {'body': body}))['id'] as String;
      await command('favorite', {'id': id, 'revision': 1, 'favorite': true});
      await command('createTarget', {
        'id': id,
        'revision': 2,
        'kind': 'project',
        'name': '晚钟',
        'requestId': 'bells',
      });
      final original = await read(id);
      expect(original.containsKey('completed'), isFalse);
      await command('complete', {'id': id, 'revision': 3, 'completed': true});
      expect(await read(id), {...original, 'completed': true, 'revision': 4});
      await expectLater(
        command('complete', {'id': id, 'revision': 3, 'completed': false}),
        throwsA(anything),
      );
      for (final view in [
        await page('home'),
        await page('home', state: {'favorite': true}),
        await page('day', context: {'date': '2026-11-23'}),
        await page('search', forms: {'query': '校园'}),
      ]) {
        expect(view.any((node) => node['text'] == '已完成'), isTrue);
        final menu = view.singleWhere((node) => node['type'] == 'swipeActions');
        final actions = objects(menu['actions']);
        expect(actions, hasLength(7));
        expect(
          actions.singleWhere(
            (action) => action['label'] == '复制文本',
          )['copyText'],
          body,
        );
        final reopen = actions.singleWhere(
          (action) => action['label'] == '标为未完成',
        );
        expect(object(reopen['command'])['input'], {
          'id': id,
          'revision': 4,
          'completed': false,
        });
      }
      await command('complete', {'id': id, 'revision': 4, 'completed': false});
      expect(await read(id), {...original, 'completed': false, 'revision': 5});
    },
  );
}
