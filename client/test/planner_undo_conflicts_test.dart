import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show sourcePackage, table;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  Future<Map<String, Object?>> run(
    String service,
    Map<String, Object?> input, {
    String module = 'app.planner',
  }) async {
    final actor = host.instances[module]!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef(
        module,
        module == 'app.planner' ? 'planner.$service' : service,
        1,
      ),
      input,
    );
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> raw(Object? id) async => object(
    await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.get', 1),
      {'id': id},
    ),
  );
  Future<Map<String, Object?>> create(String title, String date) =>
      run('task.create', {
        'title': title,
        'plannedStartAt': '${date}T10:00:00Z',
        'plannedEndAt': '${date}T11:00:00Z',
        'plannedTimezone': 'UTC',
        'estimatedMinutes': 60,
      }, module: 'app.tasks');
  Future<void> move(Object? id, String key, String date) async {
    final preview = await host.query(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.planner', 'planner.operation.preview', 1),
      {
        'kind': 'move',
        'taskId': id,
        'date': date,
        'start': '10:00',
        'end': '11:00',
        'timezone': 'UTC',
      },
    );
    await run('operation.apply', {'operationKey': key, 'preview': preview});
  }

  Future<void> course({bool invalidDst = false}) async {
    await host.install(await sourcePackage('app.schedule'));
    final timetable = invalidDst
        ? table(
            'timetable',
            zone: 'America/New_York',
            monday: '2026-10-26',
            start: '01:15',
            end: '02:15',
          )
        : table(
            'timetable',
            zone: 'UTC',
            monday: '2026-10-12',
            start: '10:00',
            end: '11:00',
          );
    await run('schedule.timetable.save', {
      'timetable': timetable,
    }, module: 'app.schedule');
    await run('schedule.course.save', {
      'course': {'id': 'course', 'timetableId': 'timetable', 'name': '新增课程'},
      'meeting': {
        'id': 'meeting',
        'weekday': invalidDst ? 7 : 4,
        'startPeriod': 1,
        'endPeriod': 1,
        'weeks': [1],
      },
    }, module: 'app.schedule');
  }

  Future<List<Map<String, Object?>>> records() =>
      store.sql('SELECT * FROM host_records ORDER BY module_id,collection,id');
  Future<void> rejectUnchanged(String key) async {
    final before = await records();
    await expectLater(run('batch.undo', {'id': key}), throwsStateError);
    expect(await records(), before);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('planner-undo-conflicts-');
    host = ModuleHost(store: store, directory: folder);
    host.clockNow = () => DateTime.utc(2026, 10, 10);
    await host.initialize();
    for (final id in ['app.tasks', 'app.planner']) {
      await host.install(await sourcePackage(id));
    }
    await run('availability.save', {
      'availability': {'timezone': 'UTC', 'bufferMinutes': 0},
    });
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  test('undo rejects a newly occupied original position without any persisted writes', () async {
    final task = await create('返回原位', '2026-10-15');
    await move(task['id'], 'move', '2026-10-16');
    await create('后来占用原位', '2026-10-15');
    await rejectUnchanged('move');
    expect((await raw(task['id']))['plannedDate'], '2026-10-16');
  });

  test('undo rejects a course added at the original position', () async {
    final task = await create('原位后来有课', '2026-10-15');
    await move(task['id'], 'course-blocked', '2026-10-16');
    await course();
    await rejectUnchanged('course-blocked');
  });

  test(
    'undo rejects a manual busy interval added at the original position',
    () async {
      final task = await create('原位后来忙碌', '2026-10-15');
      await move(task['id'], 'manual-blocked', '2026-10-16');
      await run('availability.save', {
        'availability': {
          'timezone': 'UTC',
          'busy': [
            {'date': '2026-10-15', 'start': '10:30', 'end': '11:30'},
          ],
        },
      });
      await rejectUnchanged('manual-blocked');
    },
  );

  test('undo returns to an empty original position even when it is now in the past', () async {
    final task = await create('可以恢复过去', '2026-10-15');
    await move(task['id'], 'past-allowed', '2026-10-16');
    host.clockNow = () => DateTime.utc(2026, 10, 17);
    await run('batch.undo', {'id': 'past-allowed'});
    expect(await raw(task['id']), task);
  });

  test(
    'whole swap undo excludes both current positions from external occupancy',
    () async {
      final first = await create('第一项', '2026-10-15');
      final second = await create('第二项', '2026-10-16');
      final preview = await host.query(
        host.instances['app.planner']!.actor,
        const ServiceRef('app.planner', 'planner.operation.preview', 1),
        {'kind': 'swap', 'taskId': first['id'], 'targetTaskId': second['id']},
      );
      await run('operation.apply', {
        'operationKey': 'swap',
        'preview': preview,
      });
      await run('batch.undo', {'id': 'swap'});
      expect(await raw(first['id']), first);
      expect(await raw(second['id']), second);
    },
  );

  test(
    'notes-only undo does not reject an existing scheduling conflict',
    () async {
      final task = await create('仅描述修改', '2026-10-15');
      final edited = await run('task.update', {
        'id': task['id'],
        'changes': {'notes': '新描述'},
      });
      await create('已有重叠', '2026-10-15');
      await run('batch.undo', {'id': edited['id']});
      expect(await raw(task['id']), task);
    },
  );

  test('unreadable installed courses block range restoration but do not block deleting a new task', () async {
    final task = await create('恢复需可靠课表', '2026-11-01');
    await move(task['id'], 'unreadable-courses', '2026-11-02');
    await course(invalidDst: true);
    await rejectUnchanged('unreadable-courses');
    final created = await run('task.create', {'title': '撤销新增无需占用检查'});
    final createdTask = object(created['task']);
    await run('batch.undo', {'id': created['id']});
    expect(
      await host.query(
        host.instances['app.tasks']!.actor,
        const ServiceRef('app.tasks', 'task.get', 1),
        {'id': createdTask['id']},
      ),
      isNull,
    );
  });
}
