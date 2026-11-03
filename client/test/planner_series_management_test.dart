import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show sourcePackage, objects;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  final draft = <String, Object?>{
    'title': '阅读论文',
    'notes': '原始说明',
    'estimatedMinutes': 30,
    'firstDate': '2026-10-21',
    'timezone': 'UTC',
    'rules': {
      'interval': {'minDays': 4, 'maxDays': 6},
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'timeWindow': {'start': '18:00', 'end': '22:00'},
    },
  };
  Future<Map<String, Object?>> query(
    String service, [
    Map<String, Object?> input = const {},
  ]) async => object(
    await host.query(
      host.instances['app.planner']!.actor,
      ServiceRef('app.planner', 'planner.$service', 1),
      input,
    ),
  );
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

  Future<List<Map<String, Object?>>> tasks() async => objects(
    await host.query(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.tasks', 'task.list', 1),
      {'view': 'raw', 'limit': 1000},
    ),
  );
  Future<void> create(String id, {String? title}) async {
    final preview = await query('creation.preview', {
      ...draft,
      'title': ?title,
    });
    expect(preview['confirmable'], true);
    await run('creation.apply', {'creationKey': id, 'preview': preview});
  }

  Future<Map<String, Object?>> detail(String id) =>
      query('series.get', {'id': id});
  Future<void> status(String id, String state, String key) async {
    final series = await detail(id);
    await run('series.status', {
      'id': id,
      'status': state,
      'operationKey': key,
      'expectedRevision': series['revision'],
    });
  }

  Future<void> cancel(
    String id,
    List<Map<String, Object?>> rows,
    String key,
  ) async {
    await run('series.tasks.cancel', {
      'id': id,
      'taskIds': rows.map((r) => r['taskId']).toList(),
      'expectedTasks': {
        for (final row in rows) row['taskId'] as String: row['updatedAt'],
      },
      'operationKey': key,
    });
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('planner-series-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 21, 8);
    await host.initialize();
    await host.install(await sourcePackage('app.tasks'));
    await host.install(await sourcePackage('app.planner'));
    await run('availability.save', {
      'availability': {
        'timezone': 'UTC',
        'bufferMinutes': 0,
        'weekly': {
          for (var i = 1; i <= 7; i++)
            '$i': [
              {'start': '18:00', 'end': '22:00'},
            ],
        },
      },
    });
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  test('list groups by stable series identity and counts real completion/cancellation', () async {
    await create('one');
    await create('two'); // Same title must not collapse two distinct series.
    final first = await detail('one');
    final rows = objects(first['rows']);
    await run('task.setCompleted', {
      'id': rows.first['taskId'],
      'completed': true,
      'actualCompletedOn': '2026-10-21',
      'completedTimezone': 'UTC',
      'expectedUpdatedAt': rows.first['updatedAt'],
    }, module: 'app.tasks');
    await cancel('one', [rows[1]], 'cancel-one');
    final updated = await detail('one');
    expect(updated['completedCount'], 1);
    expect(updated['cancelledCount'], 1);
    expect(updated['pendingCount'], rows.length - 2);
    expect(object(updated['next'])['taskId'], rows[2]['taskId']);
    final list = await query('series.list', {'search': '论文'});
    expect(objects(list['items']), hasLength(2));
    expect(object(list['counts']), {
      'all': 2,
      'active': 2,
      'paused': 0,
      'ended': 0,
    });
    expect(objects(list['items']).every((s) => !s.containsKey('rows')), true);
    expect(
      objects((await query('series.list', {'search': '不存在'}))['items']),
      isEmpty,
    );
  });

  test('pause/resume/end preserve every task and only control future replenishment', () async {
    await create('pause');
    final before = await tasks();
    final original = await detail('pause');
    final input = {
      'id': 'pause',
      'status': 'paused',
      'expectedRevision': original['revision'],
      'operationKey': 'pause-op',
    };
    await run('series.status', input);
    expect((await run('series.status', input))['alreadyApplied'], true);
    expect((await detail('pause'))['status'], 'paused');
    expect(
      (await query('series.list', {'status': 'paused'}))['items'],
      hasLength(1),
    );
    host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
    expect((await query('rolling.preview'))['plans'], isEmpty);
    expect(await tasks(), before);
    await expectLater(
      query('series.retry.preview', {'id': 'pause'}),
      throwsA(anything),
    );
    await status('pause', 'active', 'resume-op');
    expect((await query('rolling.preview'))['assignedCount'], greaterThan(0));
    expect(await tasks(), before);
    await status('pause', 'ended', 'end-op');
    expect((await detail('pause'))['status'], 'ended');
    expect((await query('rolling.preview'))['plans'], isEmpty);
    await expectLater(
      status('pause', 'active', 'invalid-resume'),
      throwsA(anything),
    );
    expect(await tasks(), before);
  });

  test(
    'stale series revisions and conflicting operation keys are rejected',
    () async {
      await create('revisions');
      final before = await detail('revisions');
      await status('revisions', 'paused', 'pause-revision');
      await expectLater(
        run('series.status', {
          'id': 'revisions',
          'status': 'active',
          'expectedRevision': before['revision'],
          'operationKey': 'stale',
        }),
        throwsA(anything),
      );
      final current = await detail('revisions');
      await expectLater(
        run('series.status', {
          'id': 'revisions',
          'status': 'active',
          'expectedRevision': current['revision'],
          'operationKey': 'pause-revision',
        }),
        throwsA(anything),
      );
      await run('batch.undo', {'id': 'pause-revision'});
      expect((await detail('revisions'))['status'], 'active');
    },
  );

  test('rule editing is read only until reviewed and preserves existing/manual tasks', () async {
    await create('edit');
    final second = objects((await detail('edit'))['rows'])[1];
    final move = await query('operation.preview', {
      'kind': 'move',
      'taskId': second['taskId'],
      'date': second['date'],
      'start': '18:30',
      'end': '19:00',
    });
    expect(move['confirmable'], true);
    await run('operation.apply', {'operationKey': 'manual', 'preview': move});
    final before = await tasks();
    final series = await detail('edit');
    expect(objects(series['rows'])[1]['manual'], true);
    final preview = await query('series.update.preview', {
      'id': 'edit',
      'expectedRevision': series['revision'],
      'changes': {'title': '新版论文阅读', 'estimatedMinutes': 45},
    });
    expect(preview['affectedExisting'], 0);
    expect(preview['confirmable'], true);
    expect(await tasks(), before);
    final apply = {'operationKey': 'edit-rules', 'preview': preview};
    await run('series.update.apply', apply);
    expect((await run('series.update.apply', apply))['alreadyApplied'], true);
    expect((await detail('edit'))['title'], '新版论文阅读');
    expect(await tasks(), before);
    host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
    final retry = await query('series.retry.preview', {'id': 'edit'});
    expect(retry['assignedCount'], greaterThan(0));
    await run('series.retry.apply', {
      'operationKey': 'after-edit',
      'preview': retry,
    });
    final all = await tasks();
    for (final task in before) {
      expect(all.singleWhere((t) => t['id'] == task['id']), task);
    }
    final added = all.where((t) => !before.any((b) => b['id'] == t['id']));
    expect(added, isNotEmpty);
    expect(
      added.every((t) => t['title'] == '新版论文阅读' && t['estimatedMinutes'] == 45),
      true,
    );
  });

  test(
    'stale rule previews cannot apply and undo refuses later changed series',
    () async {
      await create('edit-stale');
      final series = await detail('edit-stale');
      final preview = await query('series.update.preview', {
        'id': 'edit-stale',
        'expectedRevision': series['revision'],
        'changes': {'notes': '新版说明'},
      });
      await status('edit-stale', 'paused', 'pause-before-edit');
      await expectLater(
        run('series.update.apply', {
          'operationKey': 'stale-edit',
          'preview': preview,
        }),
        throwsA(anything),
      );
      final current = await detail('edit-stale');
      final fresh = await query('series.update.preview', {
        'id': 'edit-stale',
        'expectedRevision': current['revision'],
        'changes': {'notes': '新版说明'},
      });
      await run('series.update.apply', {
        'operationKey': 'fresh-edit',
        'preview': fresh,
      });
      await expectLater(
        run('batch.undo', {'id': 'pause-before-edit'}),
        throwsA(anything),
      );
      await run('batch.undo', {'id': 'fresh-edit'});
      expect(object((await detail('edit-stale'))['draft'])['notes'], '原始说明');
    },
  );

  test('multi-cancel rejects foreign/completed/stale rows atomically and undo restores counts', () async {
    await create('cancel');
    await create('foreign');
    final rows = objects((await detail('cancel'))['rows']);
    final other = objects((await detail('foreign'))['rows']).first;
    await expectLater(
      cancel('cancel', [rows.first, other], 'foreign-cancel'),
      throwsA(anything),
    );
    expect((await detail('cancel'))['cancelledCount'], 0);
    await run('task.setCompleted', {
      'id': rows.first['taskId'],
      'completed': true,
      'actualCompletedOn': '2026-10-21',
      'completedTimezone': 'UTC',
    }, module: 'app.tasks');
    await expectLater(
      cancel('cancel', [rows[1], rows.first], 'completed-cancel'),
      throwsA(anything),
    );
    expect((await detail('cancel'))['cancelledCount'], 0);
    final before = await tasks();
    await cancel('cancel', [rows[1], rows[2]], 'two-cancel');
    expect((await detail('cancel'))['cancelledCount'], 2);
    await expectLater(
      cancel('cancel', [rows[1]], 'stale-cancel'),
      throwsA(anything),
    );
    await run('batch.undo', {'id': 'two-cancel'});
    expect((await detail('cancel'))['cancelledCount'], 0);
    expect(await tasks(), before);
  });

  test('undoing cancellation checks newly occupied restored time', () async {
    await create('occupancy');
    final row = objects((await detail('occupancy'))['rows']).first;
    await cancel('occupancy', [row], 'cancel-slot');
    await run('task.create', {
      'title': '后来占用',
      'plannedStartAt': row['plannedStartAt'],
      'plannedEndAt': '${row['date']}T18:30:00Z',
      'plannedTimezone': 'UTC',
    });
    await expectLater(
      run('batch.undo', {'id': 'cancel-slot'}),
      throwsA(anything),
    );
    expect((await detail('occupancy'))['cancelledCount'], 1);
  });

  test(
    'retry targets one active batch and records genuine blocked reasons',
    () async {
      await create('retry');
      await create('untouched');
      final untouched = await detail('untouched');
      host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
      final before = await tasks();
      final preview = await query('series.retry.preview', {'id': 'retry'});
      expect(preview['assignedCount'], greaterThan(0));
      expect(await tasks(), before);
      final input = {'operationKey': 'retry-one', 'preview': preview};
      await run('series.retry.apply', input);
      expect((await run('series.retry.apply', input))['alreadyApplied'], true);
      expect((await detail('untouched'))['revision'], untouched['revision']);
      await run('availability.save', {
        'availability': {
          'timezone': 'UTC',
          'weekly': {
            for (var i = 1; i <= 7; i++)
              '$i': [
                {'start': '08:00', 'end': '09:00'},
              ],
          },
        },
      });
      final blocked = await query('series.retry.preview', {'id': 'untouched'});
      expect(blocked['blocked'], isNotEmpty);
      final result = await run('series.retry.apply', {
        'operationKey': 'record-blocked',
        'preview': blocked,
      });
      expect(result['applied'], 0);
      expect(result['blocked'], isNotEmpty);
      expect((await detail('untouched'))['blocked'], isNotEmpty);
    },
  );

  test(
    'no-op status and no-op retry keep durable operation receipts',
    () async {
      await create('noop');
      final first = await detail('noop');
      final statusInput = {
        'id': 'noop',
        'status': 'active',
        'expectedRevision': first['revision'],
        'operationKey': 'noop-active',
      };
      expect((await run('series.status', statusInput))['unchanged'], true);
      final preview = await query('series.retry.preview', {'id': 'noop'});
      expect(preview['assignedCount'], 0);
      final retryInput = {'operationKey': 'noop-retry', 'preview': preview};
      expect((await run('series.retry.apply', retryInput))['skipped'], true);
      await status('noop', 'paused', 'noop-pause');
      expect((await run('series.status', statusInput))['alreadyApplied'], true);
      expect((await detail('noop'))['status'], 'paused');
      host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
      expect(
        (await run('series.retry.apply', retryInput))['alreadyApplied'],
        true,
      );
      expect((await detail('noop'))['status'], 'paused');
    },
  );

  test('preferred minute round trips through creation, future-rule edits, clear and rolling', () async {
    final rules = {...object(draft['rules']), 'preferredTime': '20:03'};
    final preview = await query('creation.preview', {...draft, 'rules': rules});
    expect(preview['confirmable'], true);
    expect(
      objects(preview['assigned']).every((row) => row['start'] == '20:03'),
      true,
    );
    expect(await tasks(), isEmpty);
    await run('creation.apply', {
      'creationKey': 'preferred',
      'preview': preview,
    });
    final created = await detail('preferred');
    expect(object(object(created['draft'])['rules'])['preferredTime'], '20:03');
    expect(
      objects(created['rows']).every((row) => row['start'] == '20:03'),
      true,
    );
    final listed = objects((await query('series.list'))['items']).single;
    expect(object(object(listed['draft'])['rules'])['preferredTime'], '20:03');
    final second = objects(created['rows'])[1];
    final moved = await query('operation.preview', {
      'kind': 'move',
      'taskId': second['taskId'],
      'date': second['date'],
      'start': '19:07',
      'end': '19:37',
    });
    expect(moved['confirmable'], true);
    await run('operation.apply', {
      'operationKey': 'preferred-manual',
      'preview': moved,
    });
    final originalTasks = await tasks();
    final current = await detail('preferred');
    expect(objects(current['rows'])[1]['manual'], true);
    final changedRules = {...rules, 'preferredTime': '21:03'};
    final edit = await query('series.update.preview', {
      'id': 'preferred',
      'expectedRevision': current['revision'],
      'changes': {'rules': changedRules},
    });
    expect(edit['affectedExisting'], 0);
    await run('series.update.apply', {
      'operationKey': 'preferred-edit',
      'preview': edit,
    });
    expect(await tasks(), originalTasks);
    host.clockNow = () => DateTime.utc(2026, 10, 31, 8);
    final rolling = await query('rolling.preview');
    final planned = objects(
      object(objects(rolling['plans']).single['preview'])['assigned'],
    );
    expect(planned, isNotEmpty);
    expect(planned.every((row) => row['start'] == '21:03'), true);
    await run('rolling.apply', {
      'operationKey': 'preferred-roll',
      'preview': rolling,
    });
    final afterRoll = await tasks();
    for (final old in originalTasks) {
      expect(afterRoll.singleWhere((task) => task['id'] == old['id']), old);
    }
    final beforeClear = await detail('preferred');
    final clear = await query('series.update.preview', {
      'id': 'preferred',
      'expectedRevision': beforeClear['revision'],
      'changes': {
        'rules': {...changedRules, 'preferredTime': null},
      },
    });
    expect(
      object(object(clear['draft'])['rules']).containsKey('preferredTime'),
      false,
    );
    await run('series.update.apply', {
      'operationKey': 'preferred-clear',
      'preview': clear,
    });
    expect(
      object(object((await detail('preferred'))['draft'])['rules'])
          .containsKey('preferredTime'),
      false,
    );
    expect(await tasks(), afterRoll);
    host.clockNow = () => DateTime.utc(2026, 11, 10, 8);
    final clearedRolling = await query('rolling.preview');
    final clearedPlanned = objects(
      object(objects(clearedRolling['plans']).single['preview'])['assigned'],
    );
    expect(clearedPlanned, isNotEmpty);
    expect(clearedPlanned.every((row) => row['start'] == '18:00'), true);
  });

  test('invalid preferred point or duration is rejected without persisting changes', () async {
    await expectLater(
      query('creation.preview', {
        ...draft,
        'rules': {...object(draft['rules']), 'preferredTime': '22:00'},
      }),
      throwsA(anything),
    );
    expect(await tasks(), isEmpty);
    await create('preferred-invalid');
    final before = await detail('preferred-invalid');
    final beforeTasks = await tasks();
    await expectLater(
      query('series.update.preview', {
        'id': 'preferred-invalid',
        'expectedRevision': before['revision'],
        'changes': {
          'estimatedMinutes': 90,
          'rules': {...object(draft['rules']), 'preferredTime': '21:03'},
        },
      }),
      throwsA(anything),
    );
    expect((await detail('preferred-invalid'))['revision'], before['revision']);
    expect(await tasks(), beforeTasks);
  });
}
