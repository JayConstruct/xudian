import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show sourcePackage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  ModuleActor actor() => host.instances['app.planner']!.actor;
  Future<Object?> query(
    String service, [
    Map<String, Object?> input = const {},
  ]) => host.query(
    actor(),
    ServiceRef('app.planner', 'planner.$service', 1),
    input,
  );
  Future<Object?> taskQuery(
    String service, [
    Map<String, Object?> input = const {},
  ]) => host.query(actor(), ServiceRef('app.tasks', 'task.$service', 1), input);
  Future<Map<String, Object?>> run(
    String service,
    Map<String, Object?> input,
  ) async {
    final plan = await host.prepare(
      actor(),
      ServiceRef('app.planner', 'planner.$service', 1),
      input,
    );
    host.review(plan.id, actor());
    return object(await host.commit(actor(), plan.id));
  }

  Future<Map<String, Object?>> create(Map<String, Object?> input) async =>
      object((await run('task.create', {'title': '内容任务', ...input}))['task']);
  Future<Map<String, Object?>> content(Object? id) async =>
      object(await query('task.content', {'id': id}));
  Future<Map<String, Object?>> raw(Object? id) async =>
      object(await taskQuery('get', {'id': id}));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('creation-content-');
    db = AppDatabase(NativeDatabase(File('${directory.path}/data.sqlite')));
    store = CollectionStore(db);
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 10, 28);
    for (final id in ['app.tasks', 'app.planner']) {
      await host.install(await sourcePackage(id));
    }
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  test('explicit no-time, duration-only and deadline-only remain distinct while legacy omission retains its default', () async {
    final legacy = await create({});
    expect(legacy['estimatedMinutes'], 30);
    final noTime = await create({'estimatedMinutes': null});
    expect(noTime['estimatedMinutes'], isNull);
    expect(noTime['plannedStartAt'], isNull);
    expect(noTime['plannedEndAt'], isNull);
    expect(noTime['dueDate'], isNull);
    expect(noTime['locked'], false);
    final duration = await create({
      'estimatedMinutes': 45,
      'priority': 2,
      'notes': '逐段阅读',
    });
    expect(duration['estimatedMinutes'], 45);
    expect(duration['plannedStartAt'], isNull);
    expect(duration['dueDate'], isNull);
    expect(duration['priority'], 2);
    expect(duration['notes'], '逐段阅读');
    final deadline = await create({
      'estimatedMinutes': null,
      'dueDate': '2026-10-29',
      'dueAt': '2026-10-29T10:00:00Z',
      'dueTimezone': 'Asia/Shanghai',
    });
    expect(deadline['estimatedMinutes'], isNull);
    expect(deadline['plannedStartAt'], isNull);
    expect(deadline['dueAt'], '2026-10-29T10:00:00.000Z');
  });

  test('scheduled creation derives elapsed duration, keeps deadline independent and enforces fixed range through later commands', () async {
    final task = await create({
      'plannedStartAt': '2026-10-28T23:30:00Z',
      'plannedEndAt': '2026-10-29T00:30:00Z',
      'plannedTimezone': 'Asia/Shanghai',
      'estimatedMinutes': 15,
      'locked': true,
      'dueDate': '2026-10-30',
      'dueTimezone': 'Asia/Shanghai',
    });
    expect(task['estimatedMinutes'], 60);
    expect(task['plannedDate'], '2026-10-29');
    expect(task['locked'], true);
    expect(task['dueDate'], '2026-10-30');
    await expectLater(
      query('operation.preview', {
        'taskId': task['id'],
        'date': '2026-10-29',
        'start': '09:00',
        'end': '10:00',
        'timezone': 'Asia/Shanghai',
      }),
      throwsStateError,
    );
    await run('task.update', {
      'id': task['id'],
      'changes': {'locked': false},
    });
    final preview = object(
      await query('operation.preview', {
        'taskId': task['id'],
        'date': '2026-10-29',
        'start': '09:00',
        'end': '10:00',
        'timezone': 'Asia/Shanghai',
      }),
    );
    expect(preview['confirmable'], true);
    expect((await raw(task['id']))['dueDate'], '2026-10-30');
  });

  test('invalid fixed, incomplete, inverted or fractional ranges and invalid location never create partial records', () async {
    for (final fields in <Map<String, Object?>>[
      {'locked': true, 'estimatedMinutes': null},
      {'plannedStartAt': '2026-10-29T01:00:00Z'},
      {
        'plannedStartAt': '2026-10-29T02:00:00Z',
        'plannedEndAt': '2026-10-29T01:00:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      },
      {
        'plannedStartAt': '2026-10-29T01:00:00Z',
        'plannedEndAt': '2026-10-29T01:01:30Z',
        'plannedTimezone': 'Asia/Shanghai',
      },
      {
        'plannedStartAt': '2026-10-29T01:00:00Z',
        'plannedEndAt': '2026-10-29T02:00:00Z',
        'plannedTimezone': 'invalid/zone',
      },
      {'location': List.filled(301, '地').join()},
    ]) {
      await expectLater(create(fields), throwsA(anything));
    }
    expect(await taskQuery('list', {'view': 'raw'}), isEmpty);
    expect(await query('operation.list'), isEmpty);
  });

  test('location survives restart and appears in compact board projections without modifying the task-owned record', () async {
    final pending = await create({
      'location': '  图书馆302  ',
      'estimatedMinutes': null,
    });
    final scheduled = await create({
      'location': '会议室 B',
      'plannedStartAt': '2026-10-29T01:00:00Z',
      'plannedEndAt': '2026-10-29T02:00:00Z',
      'plannedTimezone': 'Asia/Shanghai',
    });
    expect((await content(pending['id']))['location'], '图书馆302');
    expect((await raw(pending['id'])).containsKey('location'), false);
    var board = object(
      await query('board.get', {'startDate': '2026-10-29', 'days': 1}),
    );
    final candidate = (board['candidates'] as List)
        .map(object)
        .firstWhere((c) => c['taskId'] == pending['id']);
    expect(object(candidate['task'])['location'], '图书馆302');
    expect(
      (board['scheduled'] as List).map(object).single['location'],
      '会议室 B',
    );
    expect(
      (board['tasks'] as List)
          .map(object)
          .firstWhere((t) => t['id'] == scheduled['id'])['location'],
      '会议室 B',
    );
    await host.close();
    await store.close();
    await db.close();
    db = AppDatabase(NativeDatabase(File('${directory.path}/data.sqlite')));
    store = CollectionStore(db);
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 10, 28);
    expect((await content(pending['id']))['location'], '图书馆302');
    board = object(
      await query('board.get', {'startDate': '2026-10-29', 'days': 1}),
    );
    expect(
      (board['scheduled'] as List).map(object).single['location'],
      '会议室 B',
    );
  });

  test('location-only edits advance task revision and participate in atomic conditional undo and removal', () async {
    final original = await create({'location': '原地点', 'notes': '说明保留'});
    final firstEdit = await run('task.update', {
      'id': original['id'],
      'expectedUpdatedAt': original['updatedAt'],
      'changes': {'location': '新地点'},
    });
    final edited = await raw(original['id']);
    expect({...edited, 'updatedAt': original['updatedAt']}, original);
    expect(edited['updatedAt'], isNot(original['updatedAt']));
    expect((await content(original['id']))['location'], '新地点');
    await expectLater(
      run('task.update', {
        'id': original['id'],
        'expectedUpdatedAt': original['updatedAt'],
        'changes': {'location': '过时修改'},
      }),
      throwsStateError,
    );
    await run('batch.undo', {'id': firstEdit['id']});
    expect(await raw(original['id']), original);
    expect((await content(original['id']))['location'], '原地点');
    final secondEdit = await run('task.update', {
      'id': original['id'],
      'changes': {'location': '另一地点'},
    });
    await run('task.update', {
      'id': original['id'],
      'changes': {'location': '最新地点'},
    });
    await expectLater(
      run('batch.undo', {'id': secondEdit['id']}),
      throwsStateError,
    );
    expect((await content(original['id']))['location'], '最新地点');
    final removed = await run('task.update', {
      'id': original['id'],
      'changes': {'location': null},
    });
    expect((await content(original['id']))['location'], isNull);
    await run('batch.undo', {'id': removed['id']});
    expect((await content(original['id']))['location'], '最新地点');
  });

  test(
    'undoing task creation removes task and attached content together',
    () async {
      final result = await run('task.create', {
        'title': '撤销内容',
        'location': '待删除地点',
        'estimatedMinutes': null,
      });
      final task = object(result['task']);
      await run('batch.undo', {'id': result['id']});
      expect(await taskQuery('get', {'id': task['id']}), isNull);
      expect((await content(task['id']))['location'], isNull);
    },
  );

  test('batch draft location reaches every generated and replenished task and is removed by creation undo', () async {
    final input = {
      'title': '规律阅读',
      'notes': '持续补齐保留内容',
      'location': '  安静自习室  ',
      'firstDate': '2026-10-28',
      'estimatedMinutes': 30,
      'rules': {
        'interval': {'minDays': 4, 'maxDays': 6},
      },
    };
    var preview = object(await query('creation.preview', input));
    expect(object(preview['input'])['location'], '安静自习室');
    expect(
      (preview['assigned'] as List)
          .map(object)
          .every((c) => c['location'] == '安静自习室'),
      true,
    );
    await run('creation.apply', {
      'creationKey': 'location-first',
      'preview': preview,
    });
    var tasks = (await taskQuery('list', {'view': 'raw'}) as List)
        .map(object)
        .toList();
    expect(tasks.length, greaterThan(1));
    for (final task in tasks) {
      expect((await content(task['id']))['location'], '安静自习室');
    }
    await run('batch.undo', {'id': 'location-first'});
    for (final task in tasks) {
      expect(await taskQuery('get', {'id': task['id']}), isNull);
      expect((await content(task['id']))['location'], isNull);
    }
    preview = object(await query('creation.preview', input));
    await run('creation.apply', {
      'creationKey': 'location-second',
      'preview': preview,
    });
    final initialCount =
        (await taskQuery('list', {'view': 'raw'}) as List).length;
    host.clockNow = () => DateTime.utc(2026, 11, 6);
    final rolling = object(await query('rolling.preview'));
    expect(rolling['assignedCount'], greaterThan(0));
    await run('rolling.apply', {
      'operationKey': 'location-rolling',
      'preview': rolling,
    });
    tasks = (await taskQuery('list', {'view': 'raw'}) as List)
        .map(object)
        .toList();
    expect(tasks.length, greaterThan(initialCount));
    for (final task in tasks) {
      expect((await content(task['id']))['location'], '安静自习室');
      expect(task['notes'], '持续补齐保留内容');
    }
  });
}
