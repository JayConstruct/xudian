import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/core/performance/ui_load_trace.dart';

import 'planner_task_schedule_test.dart' show sourcePackage, objects, table;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  Future<Object?> query(String id, [Map<String, Object?> input = const {}]) =>
      host.query(
        host.instances['app.planner']!.actor,
        ServiceRef('app.planner', 'planner.$id', 1),
        input,
      );
  Future<Map<String, Object?>> run(
    String id,
    Map<String, Object?> input, {
    String module = 'app.planner',
  }) async {
    final actor = host.instances[module]!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef(module, module == 'app.planner' ? 'planner.$id' : id, 1),
      input,
    );
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> create(
    String title, [
    Map<String, Object?> fields = const {},
  ]) async => fields.containsKey('plannedStartAt')
      ? run('task.create', {'title': title, ...fields}, module: 'app.tasks')
      : object((await run('task.create', {'title': title, ...fields}))['task']);
  Future<Map<String, Object?>> raw(Object? id) async => object(
    await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.get', 1),
      {'id': id},
    ),
  );
  Future<Map<String, Object?>> preview(Map<String, Object?> input) async =>
      object(await query('operation.preview', input));
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('planner-redesign-');
    host = ModuleHost(store: store, directory: folder);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    for (final id in ['app.tasks', 'app.planner']) {
      await host.install(await sourcePackage(id));
    }
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  test(
    'quick create saves description without schedule or invented deadline',
    () async {
      final task = await create('读书', {'notes': '章节一'});
      expect(task['notes'], '章节一');
      expect(task['dueDate'], isNull);
      expect(task['plannedStartAt'], isNull);
      expect(task['estimatedMinutes'], 30);
      await run('availability.save', {
        'availability': {
          'bufferMinutes': 0,
          'weekly': {
            for (var n = 1; n <= 7; n++)
              '$n': [
                {'start': '18:00', 'end': '22:00'},
              ],
          },
        },
      });
      expect(objects(object(await query('plan.preview'))['assigned']), isEmpty);
      final p = object(
        await query('plan.preview', {
          'selectedIds': ['task:${task['id']}'],
        }),
      );
      expect(objects(p['assigned']), hasLength(1));
      await run('batch.apply', {'batchKey': 'selected', 'preview': p});
      final saved = await raw(task['id']);
      expect(saved['plannedStartAt'], isNotNull);
      expect(saved['dueDate'], isNull);
      expect(saved['dueAt'], isNull);
    },
  );

  test(
    'move crosses midnight, preserves deadline, and undo restores one task',
    () async {
      final task = await create('跨夜', {'dueDate': '2026-10-11', 'notes': '保留'});
      final p = await preview({
        'taskId': task['id'],
        'date': '2026-10-10',
        'start': '23:45',
        'endDate': '2026-10-11',
        'end': '00:30',
        'timezone': 'Asia/Shanghai',
      });
      expect(p['confirmable'], true);
      await run('operation.apply', {'operationKey': 'cross', 'preview': p});
      final saved = await raw(task['id']);
      expect(saved['plannedDate'], '2026-10-10');
      expect(saved['estimatedMinutes'], 45);
      expect(saved['dueDate'], '2026-10-11');
      final board = object(
        await query('board.get', {'startDate': '2026-10-11', 'days': 1}),
      );
      expect(objects(board['scheduled']).single['startDate'], '2026-10-10');
      await run('batch.undo', {'id': 'cross'});
      expect(await raw(task['id']), task);
    },
  );

  test(
    'unequal swap preserves durations and rejects partial conflicts',
    () async {
      final a = await create('A', {
        'plannedStartAt': '2026-10-10T10:00:00Z',
        'plannedEndAt': '2026-10-10T10:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      });
      final b = await create('B', {
        'plannedStartAt': '2026-10-11T10:00:00Z',
        'plannedEndAt': '2026-10-11T11:00:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      });
      final p = await preview({
        'kind': 'swap',
        'taskId': a['id'],
        'targetTaskId': b['id'],
      });
      await run('operation.apply', {'operationKey': 'swap', 'preview': p});
      expect((await raw(a['id']))['plannedEndAt'], '2026-10-11T10:30:00.000Z');
      expect((await raw(b['id']))['plannedEndAt'], '2026-10-10T11:00:00.000Z');
      await run('batch.undo', {'id': 'swap'});
      await create('block', {
        'plannedStartAt': '2026-10-10T10:30:00Z',
        'plannedEndAt': '2026-10-10T11:00:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      });
      final blocked = await preview({
        'kind': 'swap',
        'taskId': a['id'],
        'targetTaskId': b['id'],
      });
      expect(blocked['confirmable'], false);
      await expectLater(
        run('operation.apply', {'operationKey': 'blocked', 'preview': blocked}),
        throwsStateError,
      );
      expect(await raw(a['id']), a);
      expect(await raw(b['id']), b);
    },
  );

  test('overdue move requires one explicit confirmation and never rewrites deadline', () async {
    final task = await create('截止', {'dueDate': '2026-10-10'});
    final p = await preview({
      'taskId': task['id'],
      'date': '2026-10-11',
      'start': '18:00',
    });
    expect(objects(p['overdue']), hasLength(1));
    await expectLater(
      run('operation.apply', {'operationKey': 'late', 'preview': p}),
      throwsStateError,
    );
    await run('operation.apply', {
      'operationKey': 'late',
      'preview': p,
      'allowOverdue': true,
    });
    expect((await raw(task['id']))['dueDate'], '2026-10-10');
  });

  test('notes and deadline edits use persistent protected undo', () async {
    final task = await create('详情', {'dueDate': '2026-10-11'});
    final edit = await run('task.update', {
      'id': task['id'],
      'expectedUpdatedAt': task['updatedAt'],
      'changes': {'notes': '新描述', 'dueDate': '2026-10-12'},
    });
    final saved = await raw(task['id']);
    expect(saved['notes'], '新描述');
    expect(object(saved['initialDeadline'])['dueDate'], '2026-10-11');
    await host.close();
    host = ModuleHost(store: store, directory: folder);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    expect(
      objects(await query('batch.list')).any((b) => b['id'] == edit['id']),
      true,
    );
    await run('batch.undo', {'id': edit['id']});
    expect(await raw(task['id']), task);
    final changed = await run('task.update', {
      'id': task['id'],
      'changes': {'notes': 'again'},
    });
    await run('task.setCompleted', {
      'id': task['id'],
      'completed': true,
    }, module: 'app.tasks');
    await expectLater(
      run('batch.undo', {'id': changed['id']}),
      throwsStateError,
    );
  });

  test(
    'course occupancy remains read only and invalidates stale moves atomically',
    () async {
      final task = await create('course conflict');
      final p = await preview({
        'taskId': task['id'],
        'date': '2026-10-11',
        'start': '08:15',
      });
      await host.install(await sourcePackage('app.schedule'));
      await run('schedule.timetable.save', {
        'timetable': table('t'),
      }, module: 'app.schedule');
      await run('schedule.course.save', {
        'course': {'id': 'c', 'timetableId': 't', 'name': '课程名称'},
        'meeting': {
          'id': 'm',
          'weekday': 7,
          'startPeriod': 1,
          'endPeriod': 1,
          'weeks': [1],
        },
      }, module: 'app.schedule');
      await expectLater(
        run('operation.apply', {'operationKey': 'stale-course', 'preview': p}),
        throwsStateError,
      );
      expect(await raw(task['id']), task);
      final fresh = await preview({
        'taskId': task['id'],
        'date': '2026-10-11',
        'start': '08:15',
      });
      expect(fresh['confirmable'], false);
      final board = object(
        await query('board.get', {'startDate': '2026-10-11', 'days': 1}),
      );
      expect(objects(board['busy']).single['readOnly'], true);
      expect(objects(board['busy']).single['title'], '课程名称');
      expect(objects(board['busy']).single['id'], startsWith('course:'));
      expect(objects(board['busy']).single['sourceId'], isNotNull);
    },
  );

  test('precise deadlines block automatic plans and stale versions block manual apply', () async {
    final task = await create('precise deadline', {
      'dueDate': '2026-10-10',
      'dueAt': '2026-10-10T10:15:00Z',
      'dueTimezone': 'Asia/Shanghai',
    });
    await run('availability.save', {
      'availability': {
        'weekly': {
          '6': [
            {'start': '18:00', 'end': '22:00'},
          ],
        },
      },
    });
    final automatic = object(
      await query('plan.preview', {
        'selectedIds': ['task:${task['id']}'],
      }),
    );
    expect(automatic['confirmable'], false);
    final p = await preview({
      'taskId': task['id'],
      'date': '2026-10-10',
      'start': '18:00',
    });
    expect(objects(p['overdue']), hasLength(1));
    await run('task.update', {
      'id': task['id'],
      'changes': {'notes': 'new version'},
    });
    await expectLater(
      run('operation.apply', {
        'operationKey': 'stale',
        'preview': p,
        'allowOverdue': true,
      }),
      throwsStateError,
    );
    expect((await raw(task['id']))['plannedStartAt'], isNull);
  });

  test(
    'date-only deadline uses its own timezone during automatic planning',
    () async {
      final task = await create('island deadline', {
        'dueDate': '2026-10-10',
        'dueTimezone': 'Pacific/Kiritimati',
      });
      await run('availability.save', {
        'availability': {
          'timezone': 'Asia/Shanghai',
          'weekly': {
            '6': [
              {'start': '18:00', 'end': '22:00'},
            ],
          },
        },
      });
      final p = object(
        await query('plan.preview', {
          'selectedIds': ['task:${task['id']}'],
        }),
      );
      expect(p['confirmable'], false);
      await expectLater(
        run('batch.apply', {'batchKey': 'island', 'preview': p}),
        throwsStateError,
      );
      expect((await raw(task['id']))['plannedStartAt'], isNull);
    },
  );

  test(
    'skip or cancellation cannot remove fixed generated task occupancy',
    () async {
      await run('availability.save', {
        'availability': {
          'weekly': {
            '6': [
              {'start': '18:00', 'end': '22:00'},
            ],
          },
        },
      });
      await run('rules.save', {
        'rules': [
          {
            'id': 'fixed-rule',
            'title': 'generated',
            'kind': 'once',
            'startDate': '2026-10-10',
            'endDate': '2026-10-10',
            'timezone': 'Asia/Shanghai',
          },
        ],
      });
      final p = object(await query('plan.preview'));
      await run('batch.apply', {'batchKey': 'generated', 'preview': p});
      final board = object(await query('board.get'));
      final task = objects(board['tasks']).single;
      await run('task.update', {
        'id': task['id'],
        'changes': {'locked': true},
      });
      for (final status in ['skipped', 'cancelled']) {
        await expectLater(
          run('occurrence.update', {
            'id': 'fixed-rule:once',
            'changes': {'status': status},
          }),
          throwsStateError,
        );
      }
      expect((await raw(task['id']))['locked'], true);
      expect((await raw(task['id']))['plannedStartAt'], task['plannedStartAt']);
    },
  );

  test('board batches only visible positions and omits task descriptions and history', () async {
    final actor = host.instances['app.tasks']!.actor;
    final session = SnapshotSession(actor, 'seed-board');
    await store.stage(session, actor, {
      'writes': [
        for (var n = 0; n < 330; n++)
          {
            'collection': 'tasks',
            'id': 'board-$n',
            'value': {
              'id': 'board-$n',
              'title': '任务$n',
              'priority': 0,
              'locked': false,
              'notes': 'x' * 1000,
              'deadlineHistory': List.filled(30, {'large': 'history'}),
              'plannedDate': n < 130 ? '2026-10-11' : '2027-01-11',
              'plannedStartAt': n < 130
                  ? '2026-10-11T10:00:00Z'
                  : '2027-01-11T10:00:00Z',
              'plannedEndAt': n < 130
                  ? '2026-10-11T11:00:00Z'
                  : '2027-01-11T11:00:00Z',
              'plannedTimezone': 'Asia/Shanghai',
              'updatedAt': '2026-10-10T06:00:00Z',
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
    final samples = <UiLoadSample>[];
    late Map<String, Object?> board;
    await host.close();
    await UiLoadTrace.observe(() async {
      host = ModuleHost(store: store, directory: folder);
      host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
      await host.initialize();
      samples.clear();
      board = object(
        await query('board.get', {'startDate': '2026-10-11', 'days': 1}),
      );
    }, samples.add);
    expect(objects(board['scheduled']), hasLength(130));
    expect(objects(board['tasks']), hasLength(130));
    final encoded = jsonEncode(board);
    expect(encoded, isNot(contains('deadlineHistory')));
    expect(encoded, isNot(contains('xxxxxxxx')));
    final bridges = samples.where((s) => s.name == 'page.bridge');
    expect(
      bridges.where((s) => s.arguments['method'] == 'clock.toLocalMany'),
      hasLength(2),
    );
    expect(
      bridges.where((s) => s.arguments['method'] == 'clock.toLocal'),
      isEmpty,
    );
    // One raw task-list read supplies candidates and scheduled occupancy.
    // Board display must not read task.range again for the same snapshot.
    expect(
      bridges.where(
        (s) =>
            s.arguments['moduleId'] == 'app.planner' &&
            s.arguments['method'] == 'services.query',
      ),
      hasLength(1),
    );
  });

  test(
    'board task snapshot preserves range and visibility filtering',
    () async {
      final actor = host.instances['app.tasks']!.actor;
      final seed = SnapshotSession(actor, 'board-range-visibility');
      await store.stage(seed, actor, {
        'writes': [
          for (final entry in <String, Map<String, Object?>>{
            'cross-midnight': {
              'plannedStartAt': '2026-10-10T15:30:00Z',
              'plannedEndAt': '2026-10-10T17:00:00Z',
            },
            'before-window': {
              'plannedStartAt': '2026-10-10T06:00:00Z',
              'plannedEndAt': '2026-10-10T07:00:00Z',
            },
            'deleted': {'deletedAt': '2026-10-10T06:00:00Z'},
            'archived': {'archivedAt': '2026-10-10T06:00:00Z'},
            'completed': {'completedAt': '2026-10-10T06:00:00Z'},
          }.entries)
            {
              'collection': 'tasks',
              'id': entry.key,
              'value': {
                'id': entry.key,
                'title': entry.key,
                'priority': 0,
                'plannedDate': '2026-10-11',
                'plannedStartAt': '2026-10-11T01:00:00Z',
                'plannedEndAt': '2026-10-11T02:00:00Z',
                'plannedTimezone': 'Asia/Shanghai',
                'updatedAt': '2026-10-10T06:00:00Z',
                ...entry.value,
              },
            },
        ],
      });
      await store.commit(
        store.seal(seed).id,
        actor,
        authorize: (_) {},
        audit: false,
      );
      final board = object(
        await query('board.get', {'startDate': '2026-10-11', 'days': 1}),
      );
      final block = objects(board['scheduled']).single;
      expect(block['id'], 'cross-midnight');
      expect(block['startDate'], '2026-10-10');
      expect(block['endDate'], '2026-10-11');
      expect(objects(board['tasks']).single['id'], 'cross-midnight');
    },
  );

  test(
    'same clock edits invalidate board tokens and raw detail snapshots',
    () async {
      final task = await create('stale draft', {'notes': 'first'});
      final board = object(await query('board.get'));
      final token = objects(board['tasks']).single['revisionToken'];
      await run('task.update', {
        'id': task['id'],
        'changes': {'notes': 'other'},
      });
      final intent = {
        'taskId': task['id'],
        'date': '2026-10-11',
        'start': '18:00',
      };
      await expectLater(
        preview({
          ...intent,
          'expectedTasks': {
            task['id'] as String: {'revisionToken': token},
          },
        }),
        throwsStateError,
      );
      await expectLater(
        preview({
          ...intent,
          'expectedTasks': {task['id'] as String: task},
        }),
        throwsStateError,
      );
      final inspect = object(
        await query('operation.inspect', {
          'proposal': {
            'id': task['id'],
            'intent': 'move',
            'start': '2026-10-11T18:00:00',
            'end': '2026-10-11T18:30:00',
          },
          'timezone': 'Asia/Shanghai',
          'expectedTasks': {
            task['id'] as String: {'revisionToken': token},
          },
        }),
      );
      expect(inspect['valid'], false);
      expect(inspect.containsKey('basis'), false);
      expect(inspect.containsKey('changes'), false);
    },
  );

  test(
    'lightweight inspect previews unequal swaps and invalid insert intents',
    () async {
      final a = await create('short', {
        'plannedStartAt': '2026-10-11T10:00:00Z',
        'plannedEndAt': '2026-10-11T10:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      });
      final b = await create('long', {
        'plannedStartAt': '2026-10-12T10:00:00Z',
        'plannedEndAt': '2026-10-12T11:00:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      });
      final inspect = object(
        await query('operation.inspect', {
          'proposal': {'id': a['id'], 'intent': 'swap', 'targetId': b['id']},
          'timezone': 'Asia/Shanghai',
          'expectedTasks': {a['id'] as String: a, b['id'] as String: b},
        }),
      );
      expect(inspect['valid'], true);
      final blocks = objects(inspect['previewBlocks']);
      expect(blocks[0]['start'], '2026-10-12T18:00:00');
      expect(blocks[0]['end'], '2026-10-12T18:30:00');
      expect(blocks[1]['end'], '2026-10-11T19:00:00');
      expect(jsonEncode(inspect), isNot(contains('updatedAt')));
      final insert = object(
        await query('operation.inspect', {
          'proposal': {'id': a['id'], 'intent': 'insert'},
        }),
      );
      expect(insert['valid'], false);
    },
  );

  test('durable receipts prevent plan recreation and movement after history eviction and restart', () async {
    await run('availability.save', {
      'availability': {
        'weekly': {
          '6': [
            {'start': '18:00', 'end': '22:00'},
          ],
        },
      },
    });
    await run('rules.save', {
      'rules': [
        {
          'id': 'receipt-rule',
          'title': 'generated',
          'kind': 'once',
          'startDate': '2026-10-10',
          'endDate': '2026-10-10',
          'timezone': 'Asia/Shanghai',
        },
      ],
    });
    final plan = object(await query('plan.preview'));
    await run('batch.apply', {'batchKey': 'durable-plan', 'preview': plan});
    final legacyBatch = objects(await query('batch.list')).single;
    final migration = SnapshotSession(
      host.instances['app.planner']!.actor,
      'legacy-receipt',
    );
    await store.stage(migration, host.instances['app.planner']!.actor, {
      'writes': [
        {
          'collection': 'batches',
          'id': 'durable-plan',
          'value': {...legacyBatch, 'request': jsonEncode(plan)},
        },
        {'collection': 'receipts', 'id': 'durable-plan', 'value': null},
      ],
    });
    await store.commit(
      store.seal(migration).id,
      host.instances['app.planner']!.actor,
      authorize: (_) {},
      audit: false,
    );
    final first = objects(object(await query('board.get'))['tasks']).single;
    final move = await preview({
      'taskId': first['id'],
      'date': '2026-10-11',
      'start': '18:00',
    });
    await run('operation.apply', {
      'operationKey': 'durable-move',
      'preview': move,
    });
    final later = await preview({
      'taskId': first['id'],
      'date': '2026-10-12',
      'start': '19:00',
    });
    await run('operation.apply', {
      'operationKey': 'later-move',
      'preview': later,
    });
    for (var n = 0; n < 51; n++) {
      await create('evict$n');
    }
    expect(
      objects(await query('batch.list'))
          .any((b) => b['id'] == 'durable-plan' || b['id'] == 'durable-move'),
      false,
    );
    await host.close();
    host = ModuleHost(store: store, directory: folder);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    expect(
      (await run('batch.apply', {
        'batchKey': 'durable-plan',
        'preview': plan,
      }))['alreadyApplied'],
      true,
    );
    expect(
      (await run('operation.apply', {
        'operationKey': 'durable-move',
        'preview': move,
      }))['alreadyApplied'],
      true,
    );
    expect(
      (await raw(first['id']))['plannedStartAt'],
      '2026-10-12T11:00:00.000Z',
    );
    final tasks = await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.list', 1),
      {'view': 'raw'},
    );
    expect(objects(tasks), hasLength(52));
    await expectLater(
      run('operation.apply', {
        'operationKey': 'durable-move',
        'preview': later,
      }),
      throwsStateError,
    );
    final receipts = await store.sql(
      "SELECT value FROM host_records WHERE module_id='app.planner' AND collection='receipts' AND deleted=0",
    );
    expect(jsonEncode(receipts), isNot(contains('basis')));
    expect(jsonEncode(receipts), isNot(contains('deadlineHistory')));
  });

  test('manual availability occupancy is visible, read only, and blocks manual moves', () async {
    final task = await create('blocked task');
    await run('availability.save', {
      'availability': {
        'busy': [
          {'date': '2026-10-11', 'start': '18:00', 'end': '19:00'},
          {'date': '2026-10-11', 'start': '18:00', 'end': '19:00'},
          {'date': '2027-01-11', 'start': '18:00', 'end': '19:00'},
        ],
      },
    });
    final board = object(
      await query('board.get', {'startDate': '2026-10-11', 'days': 1}),
    );
    final busy = objects(board['busy']);
    expect(busy, hasLength(2));
    expect(busy.map((b) => b['id']).toSet(), hasLength(2));
    expect(
      busy.every((b) => b['readOnly'] == true && b['sourceLabel'] == '忙碌时段'),
      true,
    );
    expect(busy.first['startDate'], '2026-10-11');
    expect(busy.first['start'], '18:00');
    final p = await preview({
      'taskId': task['id'],
      'date': '2026-10-11',
      'start': '18:15',
    });
    expect(p['confirmable'], false);
    await expectLater(
      run('operation.apply', {'operationKey': 'manual-conflict', 'preview': p}),
      throwsStateError,
    );
    expect((await raw(task['id']))['plannedStartAt'], isNull);
  });

  test('resize preserves the exact start instant and rejects fractional-minute duration atomically', () async {
    final task = await create('seconds', {
      'plannedStartAt': '2026-10-11T10:00:30Z',
      'plannedEndAt': '2026-10-11T10:30:30Z',
      'plannedTimezone': 'Asia/Shanghai',
    });
    final p = await preview({
      'kind': 'resize',
      'taskId': task['id'],
      'plannedStartAt': '2026-10-11T10:00:00Z',
      'plannedEndAt': '2026-10-11T11:00:30Z',
    });
    expect(
      object(objects(p['changes']).single['fields'])['plannedStartAt'],
      task['plannedStartAt'],
    );
    await run('operation.apply', {
      'operationKey': 'seconds-resize',
      'preview': p,
    });
    expect((await raw(task['id']))['plannedStartAt'], task['plannedStartAt']);
    expect((await raw(task['id']))['estimatedMinutes'], 60);
    await run('batch.undo', {'id': 'seconds-resize'});
    expect(await raw(task['id']), task);
    await expectLater(
      preview({
        'kind': 'resize',
        'taskId': task['id'],
        'date': '2026-10-11',
        'start': '18:00',
        'end': '19:00',
      }),
      throwsStateError,
    );
    final inspected = object(
      await query('operation.inspect', {
        'timezone': 'Asia/Shanghai',
        'proposal': {
          'intent': 'resize',
          'id': task['id'],
          'start': '2026-10-11T18:00:00',
          'end': '2026-10-11T19:00:00',
        },
      }),
    );
    expect(inspected['valid'], false);
    expect(await raw(task['id']), task);
  });

  test('ordinary integer-minute resize ignores the supplied start and keeps task timezone', () async {
    final task = await create('resize', {
      'plannedStartAt': '2026-10-11T10:00:00Z',
      'plannedEndAt': '2026-10-11T10:30:00Z',
      'plannedTimezone': 'Asia/Shanghai',
    });
    final p = await preview({
      'kind': 'resize',
      'taskId': task['id'],
      'date': '2026-10-11',
      'start': '17:00',
      'endDate': '2026-10-11',
      'end': '19:00',
      'timezone': 'Asia/Shanghai',
    });
    expect(p['previewLabel'], '调整时长 · 1项');
    expect(objects(p['previewBlocks']).single['start'], '2026-10-11T18:00:00');
    await run('operation.apply', {
      'operationKey': 'normal-resize',
      'preview': p,
    });
    final saved = await raw(task['id']);
    expect(saved['plannedStartAt'], task['plannedStartAt']);
    expect(saved['plannedTimezone'], task['plannedTimezone']);
    expect(saved['estimatedMinutes'], 60);
  });

  test('candidate pages sort deadlines stably without omissions or occupancy changes', () async {
    final actor = host.instances['app.tasks']!.actor;
    final session = SnapshotSession(actor, 'seed-candidate-pages');
    await store.stage(session, actor, {
      'writes': [
        for (var n = 0; n < 207; n++)
          {
            'collection': 'tasks',
            'id': 'page-${n.toString().padLeft(3, '0')}',
            'value': {
              'id': 'page-${n.toString().padLeft(3, '0')}',
              'title': '候选$n',
              'priority': 0,
              'dueDate': n < 103
                  ? (n.isEven ? '2026-10-10' : '2026-10-11')
                  : null,
              'dueTimezone': n < 103
                  ? (n.isEven ? 'Pacific/Kiritimati' : 'America/New_York')
                  : null,
              'createdAt': '2026-10-10T06:00:00Z',
              'updatedAt': '2026-10-10T06:00:00Z',
            },
          },
        {
          'collection': 'tasks',
          'id': 'visible-plan',
          'value': {
            'id': 'visible-plan',
            'title': '已有安排',
            'plannedStartAt': '2026-10-10T10:00:00Z',
            'plannedEndAt': '2026-10-10T11:00:00Z',
            'plannedTimezone': 'Asia/Shanghai',
            'priority': 0,
            'updatedAt': '2026-10-10T06:00:00Z',
          },
        },
        for (final status in ['completedAt', 'deletedAt', 'archivedAt'])
          {
            'collection': 'tasks',
            'id': status,
            'value': {
              'id': status,
              'title': status,
              status: '2026-10-10T06:00:00Z',
              'dueDate': '2026-10-09',
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
    await run('rules.save', {
      'rules': [
        {
          'id': 'page-rule',
          'title': '规则候选',
          'kind': 'once',
          'startDate': '2026-10-10',
          'endDate': '2026-10-11',
          'timezone': 'Asia/Shanghai',
        },
      ],
    });
    await run('availability.save', {
      'availability': {
        'busy': [
          {'date': '2026-10-10', 'start': '20:00', 'end': '21:00'},
        ],
      },
    });
    final first = object(await query('board.get'));
    final second = object(await query('board.get', {'candidateOffset': 100}));
    final last = object(await query('board.get', {'candidateOffset': 200}));
    expect(first['candidateTotal'], 208);
    expect(first['candidateOffset'], 0);
    expect(first['candidateLimit'], 100);
    expect(first['hasMoreCandidates'], true);
    expect(last['hasMoreCandidates'], false);
    final all = [
      ...objects(first['candidates']),
      ...objects(second['candidates']),
      ...objects(last['candidates']),
    ];
    expect(all, hasLength(208));
    expect(all.map((c) => c['id']).toSet(), hasLength(208));
    final expected = [...all]
      ..sort((a, b) {
        final aDate = a['task'] == null
            ? null
            : object(a['task'])['dueDate'] as String?;
        final bDate = b['task'] == null
            ? null
            : object(b['task'])['dueDate'] as String?;
        final present = (aDate == null ? 1 : 0).compareTo(
          bDate == null ? 1 : 0,
        );
        if (present != 0) return present;
        final date = (aDate ?? '').compareTo(bDate ?? '');
        return date != 0
            ? date
            : (a['id'] as String).compareTo(b['id'] as String);
      });
    expect(all.map((c) => c['id']), expected.map((c) => c['id']));
    expect(objects(first['tasks']), hasLength(101));
    expect(objects(last['tasks']), hasLength(9));
    final only = object(
      await query('board.get', {
        'onlyDeadline': true,
        'candidateOffset': 100,
        'candidateLimit': 2,
      }),
    );
    expect(only['candidateTotal'], 103);
    expect(objects(only['candidates']), hasLength(2));
    expect(only['hasMoreCandidates'], true);
    expect(
      objects(only['candidates'])
          .every((c) => object(c['task'])['dueDate'] != null),
      true,
    );
    expect(only['scheduled'], first['scheduled']);
    expect(only['busy'], first['busy']);
    final empty = object(
      await query('board.get', {
        'onlyDeadline': true,
        'candidateOffset': 999,
        'candidateLimit': 200,
      }),
    );
    expect(empty['candidateOffset'], 999);
    expect(empty['hasMoreCandidates'], false);
    expect(objects(empty['candidates']), isEmpty);
    expect(objects(empty['tasks']).map((t) => t['id']), ['visible-plan']);
    expect(empty['scheduled'], first['scheduled']);
    expect(empty['busy'], first['busy']);
    final zones = all
        .where((c) => c['task'] != null)
        .map((c) => object(c['task'])['dueTimezone'])
        .toSet();
    expect(zones, containsAll(['Pacific/Kiritimati', 'America/New_York']));
    final legacy = object(await query('candidates.list'));
    expect(objects(legacy['candidates']), hasLength(209));
  });

  test(
    'candidate pagination rejects invalid offsets limits and filters',
    () async {
      for (final input in [
        {'candidateOffset': -1},
        {'candidateOffset': 0.5},
        {'candidateLimit': 0},
        {'candidateLimit': 201},
        {'onlyDeadline': 'true'},
      ]) {
        await expectLater(
          query('board.get', input),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
        );
      }
    },
  );

  test('graphical moves preserve elapsed duration through both sides of DST fall-back', () async {
    await run('availability.save', {
      'availability': {'timezone': 'America/New_York'},
    });
    final task = await create('two hours', {
      'plannedStartAt': '2026-10-31T04:30:00Z',
      'plannedEndAt': '2026-10-31T06:30:00Z',
      'plannedTimezone': 'America/New_York',
    });
    final input = {
      'kind': 'move',
      'taskId': task['id'],
      'date': '2026-11-01',
      'start': '00:30',
      'endDate': '2026-11-01',
      'end': '02:30',
      'timezone': 'America/New_York',
      'preserveDuration': true,
    };
    final p = await preview(input);
    final fields = object(objects(p['changes']).single['fields']);
    expect(fields['plannedStartAt'], '2026-11-01T04:30:00.000Z');
    expect(fields['plannedEndAt'], '2026-11-01T06:30:00.000Z');
    expect(fields['estimatedMinutes'], 120);
    expect(objects(p['previewBlocks']).single['end'], '2026-11-01T01:30:00');
    final inspect = object(
      await query('operation.inspect', {
        'timezone': 'America/New_York',
        'proposal': {
          'id': task['id'],
          'intent': 'move',
          'start': '2026-11-01T00:30:00',
          'end': '2026-11-01T02:30:00',
        },
      }),
    );
    expect(inspect['valid'], true);
    expect(objects(inspect['previewBlocks']).single['durationMinutes'], 120);
    await run('operation.apply', {
      'operationKey': 'dst-preserve',
      'preview': p,
    });
    expect((await raw(task['id']))['estimatedMinutes'], 120);
    await run('batch.undo', {'id': 'dst-preserve'});
    final explicit = await preview({...input, 'preserveDuration': false});
    expect(
      object(objects(explicit['changes']).single['fields'])['estimatedMinutes'],
      180,
    );
    final long = await create('three elapsed hours', {
      'plannedStartAt': '2026-11-01T04:30:00Z',
      'plannedEndAt': '2026-11-01T07:30:00Z',
      'plannedTimezone': 'America/New_York',
    });
    final out = await preview({
      ...input,
      'taskId': long['id'],
      'date': '2026-11-02',
      'endDate': '2026-11-02',
    });
    expect(
      object(objects(out['changes']).single['fields'])['estimatedMinutes'],
      180,
    );
    expect(objects(out['previewBlocks']).single['end'], '2026-11-02T03:30:00');
  });

  test('duration-preserving moves keep whole elapsed minutes from second-precision plans', () async {
    final task = await create('second precision duration', {
      'plannedStartAt': '2026-10-11T10:00:30Z',
      'plannedEndAt': '2026-10-11T10:30:30Z',
      'plannedTimezone': 'Asia/Shanghai',
    });
    final p = await preview({
      'kind': 'move',
      'taskId': task['id'],
      'date': '2026-10-12',
      'start': '18:00',
      'end': '21:00',
      'timezone': 'Asia/Shanghai',
      'preserveDuration': true,
    });
    final fields = object(objects(p['changes']).single['fields']);
    expect(fields['estimatedMinutes'], 30);
    expect(fields['plannedEndAt'], '2026-10-12T10:30:00.000Z');
    final fractional = await create('fractional duration', {
      'plannedStartAt': '2026-10-13T10:00:30Z',
      'plannedEndAt': '2026-10-13T10:30:00Z',
      'plannedTimezone': 'Asia/Shanghai',
    });
    await expectLater(
      preview({
        'kind': 'move',
        'taskId': fractional['id'],
        'date': '2026-10-14',
        'start': '18:00',
        'end': '19:00',
        'preserveDuration': true,
      }),
      throwsStateError,
    );
    expect(await raw(fractional['id']), fractional);
  });

  test('unchanged details do not create operation history', () async {
    final task = await create('unchanged', {'notes': 'same'});
    final before = objects(await query('operation.list')).length;
    final saved = await run('task.update', {
      'id': task['id'],
      'expectedValues': task,
      'changes': {},
    });
    expect(saved['unchanged'], true);
    expect(object(saved['task']), task);
    expect(objects(await query('operation.list')), hasLength(before));
    final identical = await run('task.update', {
      'id': task['id'],
      'changes': {'notes': 'same'},
    });
    expect(identical['unchanged'], true);
    expect(objects(await query('operation.list')), hasLength(before));
  });

  test(
    'latest 50 operations persist and fixed tasks reject movement',
    () async {
      for (var n = 0; n < 52; n++) {
        await create('task$n');
      }
      expect(objects(await query('batch.list')), hasLength(50));
      expect(
        await store.sql(
          "SELECT id FROM host_records WHERE module_id='app.planner' AND collection='batches' AND deleted=0",
        ),
        hasLength(50),
      );
      final fixed = await create('固定', {'locked': true});
      await expectLater(
        preview({
          'taskId': fixed['id'],
          'date': '2026-10-11',
          'start': '18:00',
        }),
        throwsStateError,
      );
    },
  );
}
