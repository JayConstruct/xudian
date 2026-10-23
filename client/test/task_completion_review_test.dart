import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'daily_date_browsing_test.dart' show nodes, objects, sourcePackage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(database);
    directory = await Directory.systemTemp.createTemp('completion-review-');
    host = ModuleHost(
      store: store,
      directory: directory,
      systemTimezoneResolver: () async => 'Asia/Shanghai',
    )..clockNow = () => DateTime.utc(2026, 10, 21, 18, 30);
    await host.initialize();
    for (final moduleId in ['app.tasks', 'app.views.today']) {
      await host.install(await sourcePackage(moduleId));
    }
    host.interaction = (_, method, _) async =>
        method == 'ui.review' ? true : null;
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> command(
    String service,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances['app.tasks']!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef('app.tasks', service, 1),
      input,
    );
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> task(String id) async => object(
    await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.get', 1),
      {'id': id},
    ),
  );

  Future<Map<String, Object?>> page(
    String pageId, {
    Object? event,
    Object? state,
  }) async => object(
    await host.invokePage('app.views.today', 'render', {
      'context': {
        'pageId': 'app.views.today.$pageId',
        'selectedDate': '2026-10-21',
      },
      'event': event,
      'state': state ?? {},
    }),
  );

  test('daily completion records the actual instant and device civil date; review reopens it', () async {
    final created = await command('task.create', {
      'title': '跨午夜复盘任务',
      'plannedDate': '2026-10-21',
    });
    final pendingRow = nodes((await page('tasks'))['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    final boundInput = object(object(pendingRow['command'])['input']);
    expect(boundInput['completedTimezone'], 'Asia/Shanghai');
    expect(boundInput['completed'], true);
    host.systemTimezoneResolver = () async => 'America/New_York';
    await page('tasks', event: {...object(pendingRow['event']), 'value': true});
    final completed = await task(created['id'] as String);
    expect(completed['completedAt'], '2026-10-21T18:30:00.000Z');
    expect(completed['actualCompletedOn'], '2026-10-22');
    expect(completed['completedTimezone'], 'Asia/Shanghai');

    final review = await page('review');
    final row = nodes(review['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    expect(row['completed'], true);
    expect(row['subtitle'], contains('已完成 · 2026-10-22 02:30'));
    expect(row['subtitle'], isNot(contains('Asia/Shanghai')));
    await page('review', event: {...object(row['event']), 'value': false});
    final reopened = await task(created['id'] as String);
    expect(reopened['completedAt'], isNull);
    expect(reopened['actualCompletedOn'], isNull);
    expect(
      nodes((await page('review'))['tree'])
          .where((node) => node['type'] == 'taskItem'),
      isEmpty,
    );
  });

  test('completion query sorts by recorded time and excludes pending, deleted and archived tasks', () async {
    final older = await command('task.create', {'title': '较早完成'});
    await command('task.setCompleted', {'id': older['id'], 'completed': true});
    host.clockNow = () => DateTime.utc(2026, 10, 22, 6);
    final newer = await command('task.create', {'title': '最近完成'});
    await command('task.setCompleted', {'id': newer['id'], 'completed': true});
    await command('task.create', {'title': '待办不在复盘内'});
    final actor = host.instances['app.tasks']!.actor;
    final session = SnapshotSession(actor, 'review-exclusions');
    for (final field in ['deletedAt', 'archivedAt']) {
      await store.stage(session, actor, {
        'writes': [
          {
            'collection': 'tasks',
            'id': field,
            'value': {
              'id': field,
              'title': field,
              'completedAt': '2026-10-23T06:00:00.000Z',
              field: '2026-10-23T06:00:00.000Z',
            },
          },
        ],
      });
    }
    await store.commit(
      store.seal(session).id,
      actor,
      authorize: (_) {},
      audit: false,
    );
    final completed = objects(
      await host.query(actor, const ServiceRef('app.tasks', 'task.list', 1), {
        'view': 'completed',
        'limit': 1,
      }),
    );
    expect(completed.single['id'], newer['id']);
    final next = objects(
      await host.query(actor, const ServiceRef('app.tasks', 'task.list', 1), {
        'view': 'completed',
        'offset': 1,
        'limit': 1,
      }),
    );
    expect(next.single['id'], older['id']);
  });

  test('corrected completion date is distinguished from the original recorded timestamp', () async {
    final created = await command('task.create', {'title': '补记完成日期'});
    final completed = await command('task.setCompleted', {
      'id': created['id'],
      'completed': true,
      'completedTimezone': 'Asia/Shanghai',
    });
    host.clockNow = () => DateTime.utc(2026, 10, 23, 6);
    await command('task.setCompleted', {
      'id': created['id'],
      'completed': true,
      'actualCompletedOn': '2026-10-20',
    });
    expect(
      (await task(created['id'] as String))['completedAt'],
      completed['completedAt'],
    );
    final row = nodes((await page('review'))['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    expect(row['subtitle'], contains('完成日期 2026-10-20 · 记录于 2026-10-22 02:30'));
  });

  test('isolated module preview can display pending tasks without external timezone access', () async {
    await command('task.create', {
      'title': '预览中的待办',
      'plannedDate': '2026-10-21',
    });
    host.preview = true;
    final row = nodes((await page('tasks'))['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    expect(row['title'], '预览中的待办');
    expect(object(object(row['command'])['input'])['completedTimezone'], 'UTC');
  });

  test('legacy completion display stays stable when its planned timezone is cleared', () async {
    final created = await command('task.create', {
      'title': '旧完成记录',
      'plannedStartAt': '2026-10-21T09:00:00.000Z',
      'plannedEndAt': '2026-10-21T10:00:00.000Z',
      'plannedTimezone': 'America/New_York',
    });
    final actor = host.instances['app.tasks']!.actor;
    final session = SnapshotSession(actor, 'legacy-completion');
    await store.stage(session, actor, {
      'writes': [
        {
          'collection': 'tasks',
          'id': created['id'],
          'value': {
            ...created,
            'completedAt': '2026-10-21T18:30:00.000Z',
            'completedTimezone': null,
            'actualCompletedOn': null,
          },
        },
      ],
    });
    await store.commit(
      store.seal(session).id,
      actor,
      authorize: (_) {},
      audit: false,
    );
    final before = nodes((await page('review'))['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    expect(before['subtitle'], startsWith('已完成 · 2026-10-22 02:30'));
    await command('task.updateFields', {
      'id': created['id'],
      'changes': {'plannedDate': null},
    });
    final after = nodes((await page('review'))['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    expect(after['subtitle'], '已完成 · 2026-10-22 02:30');
  });
}
