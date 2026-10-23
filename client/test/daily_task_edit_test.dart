import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'daily_date_browsing_test.dart' show nodes, sourcePackage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late String taskId;
  var reviews = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(database);
    directory = await Directory.systemTemp.createTemp('daily-task-edit-');
    host = ModuleHost(store: store, directory: directory)
      ..clockNow = () => DateTime.utc(2026, 10, 21, 6);
    await host.initialize();
    for (final moduleId in ['app.tasks', 'app.views.today']) {
      await host.install(await sourcePackage(moduleId));
    }
    final actor = host.instances['app.tasks']!.actor;
    final plan = await host.prepare(
      actor,
      const ServiceRef('app.tasks', 'task.create', 1),
      {
        'title': '原任务',
        'priority': 2,
        'dueDate': '2026-10-21',
        'dueAt': '2026-10-21T10:30:00.000Z',
        'dueTimezone': 'Asia/Shanghai',
        'plannedStartAt': '2026-10-21T09:00:00.000Z',
        'plannedEndAt': '2026-10-21T10:00:00.000Z',
        'plannedTimezone': 'Asia/Shanghai',
      },
    );
    host.review(plan.id, actor);
    taskId = object(await host.commit(actor, plan.id))['id'] as String;
    reviews = 0;
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> task() async => object(
    await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.get', 1),
      {'id': taskId},
    ),
  );

  Future<Map<String, Object?>> page({Object? event}) async => object(
    await host.invokePage('app.views.today', 'render', {
      'context': {
        'pageId': 'app.views.today.tasks',
        'selectedDate': '2026-10-21',
      },
      'event': event,
    }),
  );

  Future<void> edit(Map<String, Object?> values, {bool approve = true}) async {
    final before = await task();
    host.interaction = (_, method, arguments) async {
      if (method == 'ui.dialog') {
        return {
          'title': before['title'],
          'priority': '${before['priority']}',
          'dueDate': before['dueDate'],
          'plannedDate': before['plannedDate'],
          ...values,
        };
      }
      if (method == 'ui.review') {
        reviews++;
        return approve;
      }
      return null;
    };
    await page(event: {'type': 'edit', 'task': before});
  }

  test('title and priority edits retain precise deadline and plan', () async {
    final before = await task();
    await edit({'title': '新标题', 'priority': '3'});
    final after = await task();
    expect(after['title'], '新标题');
    expect(after['priority'], 3);
    for (final key in [
      'dueDate',
      'dueAt',
      'dueTimezone',
      'deadlineHistory',
      'plannedDate',
      'plannedStartAt',
      'plannedEndAt',
      'plannedTimezone',
    ]) {
      expect(after[key], before[key], reason: key);
    }
    expect(reviews, 1);
  });

  test('unchanged form does not create a review or write', () async {
    final before = await task();
    await edit({});
    expect(await task(), before);
    expect(reviews, 0);
  });

  test('explicit deadline date change still replaces exact time', () async {
    await edit({'dueDate': '2026-10-22'});
    final after = await task();
    expect(after['dueDate'], '2026-10-22');
    expect(after['dueAt'], isNull);
    expect(after['plannedStartAt'], '2026-10-21T09:00:00.000Z');
    expect(after['deadlineHistory'], hasLength(1));
  });

  test(
    'explicit clearing and cancelled review preserve intended semantics',
    () async {
      final before = await task();
      await edit({'dueDate': ''}, approve: false);
      expect(await task(), before);
      await edit({'dueDate': ''});
      final after = await task();
      expect(after['dueDate'], isNull);
      expect(after['dueAt'], isNull);
      expect(after['dueTimezone'], isNull);
      expect(after['plannedEndAt'], before['plannedEndAt']);
    },
  );

  test('same-day labels keep local time without showing timezone', () async {
    final result = await page();
    final row = nodes(result['tree'])
        .singleWhere((node) => node['type'] == 'taskItem');
    expect(row['subtitle'], contains('今天 18:30截止'));
    expect(row['subtitle'], contains('计划 17:00–18:00'));
    expect(row['subtitle'], isNot(contains('2026-10-21')));
    expect(row['subtitle'], isNot(contains('Asia/Shanghai')));
  });

  test(
    'precise overdue status follows the instant, not the browsing date',
    () async {
      host.clockNow = () => DateTime.utc(2026, 10, 21, 11);
      final result = await page();
      final row = nodes(result['tree'])
          .singleWhere((node) => node['type'] == 'taskItem');
      expect(row['subtitle'], startsWith('已逾期 · 今天 18:30截止'));
    },
  );
}
