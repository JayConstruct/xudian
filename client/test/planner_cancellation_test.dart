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
  late Directory folder;
  ModuleActor actor() => host.instances['app.planner']!.actor;
  Future<Object?> query(
    String service, [
    Map<String, Object?> input = const {},
  ]) => host.query(
    actor(),
    ServiceRef('app.planner', 'planner.$service', 1),
    input,
  );
  Future<Map<String, Object?>> raw(Object? id) async => object(
    await host.query(actor(), const ServiceRef('app.tasks', 'task.get', 1), {
      'id': id,
    }),
  );
  Future<Map<String, Object?>> run(
    String service,
    Map<String, Object?> input, {
    String module = 'app.planner',
  }) async {
    final caller = host.instances[module]!.actor;
    final plan = await host.prepare(
      caller,
      ServiceRef(
        module,
        module == 'app.planner' ? 'planner.$service' : service,
        1,
      ),
      input,
    );
    host.review(plan.id, caller);
    return object(await host.commit(caller, plan.id));
  }

  Future<Map<String, Object?>> page({
    String pageId = 'app.planner.home',
    Map<String, Object?> state = const {},
    Map<String, Object?> context = const {},
    Map<String, Object?>? event,
  }) async => object(
    await host.invokePage('app.planner', 'render', {
      'context': {'pageId': pageId, ...context},
      'state': state,
      'event': event,
    }),
  );
  Iterable<Map<String, Object?>> nodes(Object? value) sync* {
    if (value is Map) {
      yield object(value);
      for (final child in value.values) {
        yield* nodes(child);
      }
    } else if (value is List) {
      for (final child in value) {
        yield* nodes(child);
      }
    }
  }

  Future<Map<String, Object?>> create({
    bool scheduled = true,
    bool locked = false,
  }) => run('task.create', {
    'title': scheduled ? '保留原安排' : '未安排也保留',
    'notes': '任务说明\n第二行',
    'dueDate': '2026-10-16',
    'dueTimezone': 'Asia/Shanghai',
    'locked': locked,
    if (scheduled) ...{
      'plannedStartAt': '2026-10-15T01:00:00Z',
      'plannedEndAt': '2026-10-15T01:30:00Z',
      'plannedTimezone': 'Asia/Shanghai',
    },
  }, module: 'app.tasks');
  Future<void> cancel(
    Map<String, Object?> task, [
    bool cancelled = true,
  ]) async {
    await run('task.setCancelled', {
      'id': task['id'],
      'cancelled': cancelled,
      'expectedUpdatedAt': task['updatedAt'],
    });
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('planner-cancel-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 10, 15);
    for (final id in ['app.tasks', 'app.planner']) {
      await host.install(await sourcePackage(id));
    }
    host.interaction = (_, _, _) async => true;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  test('cancelling one generated task keeps its occurrence, later tasks and rolling sequence', () async {
    final preview = object(
      await query('creation.preview', {
        'title': '周期安排',
        'firstDate': '2026-10-15',
        'estimatedMinutes': 30,
        'rules': {
          'interval': {'minDays': 4, 'maxDays': 6},
        },
      }),
    );
    await run('creation.apply', {
      'creationKey': 'cancel-series',
      'preview': preview,
    });
    final before = object(
      await query('board.get', {'startDate': '2026-10-15', 'days': 28}),
    );
    final scheduled = (before['scheduled'] as List).map(object).toList();
    expect(scheduled.length, greaterThan(2));
    final first = await raw(scheduled.first['id']);
    final second = await raw(scheduled[1]['id']);
    final candidate =
        (object(
                  await query('candidates.list', {
                    'startDate': '2026-10-15',
                    'days': 28,
                  }),
                )['candidates']
                as List)
            .map(object)
            .firstWhere((c) => c['taskId'] == first['id']);
    await run('occurrence.update', {
      'id': candidate['id'],
      'changes': {'status': 'cancelled'},
    });
    expect({...await raw(first['id']), 'updatedAt': first['updatedAt']}, first);
    expect(await raw(second['id']), second);
    final after = object(
      await query('board.get', {'startDate': '2026-10-15', 'days': 28}),
    );
    expect((after['scheduled'] as List).length, scheduled.length);
    final candidates =
        (object(
                  await query('candidates.list', {
                    'startDate': '2026-10-15',
                    'days': 28,
                  }),
                )['candidates']
                as List)
            .map(object);
    expect(
      candidates.firstWhere((c) => c['id'] == candidate['id'])['status'],
      'cancelled',
    );
    final rolling = object(await query('rolling.preview'));
    expect(rolling['assignedCount'], 0);
    await expectLater(
      run('batch.undo', {'id': 'cancel-series'}),
      throwsStateError,
    );
    await cancel(await raw(first['id']), false);
    expect(
      object(await query('task.state', {'id': first['id']}))['cancelled'],
      false,
    );
  });

  test('a concurrent edit rejects the frozen cancellation without partial state writes', () async {
    final task = await create();
    final plan = await host.prepare(
      actor(),
      const ServiceRef('app.planner', 'planner.task.setCancelled', 1),
      {
        'id': task['id'],
        'cancelled': true,
        'expectedUpdatedAt': task['updatedAt'],
      },
    );
    await run('task.update', {
      'id': task['id'],
      'changes': {'notes': '审核期间修改'},
    });
    host.review(plan.id, actor());
    await expectLater(host.commit(actor(), plan.id), throwsStateError);
    expect(
      object(await query('task.state', {'id': task['id']}))['cancelled'],
      false,
    );
    expect((await raw(task['id']))['notes'], '审核期间修改');
  });

  test('cancel keeps all task data, greys its block, removes controls and persists across restart; restore retains identity', () async {
    final original = await create(locked: true);
    await cancel(original);
    final cancelled = await raw(original['id']);
    expect({...cancelled, 'updatedAt': original['updatedAt']}, original);
    expect(cancelled['updatedAt'], isNot(original['updatedAt']));
    final rendered = await page();
    final board = nodes(rendered['tree'])
        .singleWhere((n) => n['type'] == 'plannerBoard');
    final block = object((board['blocks'] as List).single);
    expect(block['title'], '保留原安排');
    expect(block['color'], '#858B95');
    expect(block['sourceLabel'], '已取消');
    expect(object(block['appearance']), {
      'borderStyle': 'dashed',
      'titleDecoration': 'lineThrough',
      'cornerIcon': 'slash',
      'badgeText': '已取消',
    });
    final action = object((block['actions'] as List).single);
    expect(action['label'], '恢复任务');
    expect(object(action['event'])['type'], 'restoreTask');
    expect(block['selectionNote'], '原安排已保留，此时段可重新安排');
    for (final key in ['moveEvent', 'editTimeEvent']) {
      expect(block[key], isNull);
    }
    expect(object(block['event'])['type'], 'detail');
    await host.close();
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 10, 15);
    expect(
      object(await query('task.state', {'id': original['id']}))['cancelled'],
      true,
    );
    final detail = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': original['id']},
    );
    final texts = nodes(detail['tree']).map((n) => n['text']).toList();
    expect(texts, contains('已取消 · 2026-10-15 08:00'));
    expect(texts, contains('恢复任务'));
    expect(texts, contains('任务说明\n第二行'));
    expect(texts, contains('原安排：2026-10-15 09:00—09:30'));
    expect(texts, isNot(contains('标记已完成')));
    await cancel(await raw(original['id']), false);
    final restored = await raw(original['id']);
    expect({...restored, 'updatedAt': original['updatedAt']}, original);
    expect(
      object(await query('task.state', {'id': original['id']}))['cancelled'],
      false,
    );
  });

  test('unscheduled cancellation leaves active candidates and is visible in the cancelled view, including empty state and return', () async {
    final empty = await page(event: {'type': 'cancelledTasks'});
    expect(nodes(empty['tree']).any((n) => n['text'] == '暂无已取消的任务'), true);
    final task = await create(scheduled: false);
    await cancel(task);
    final board = object(
      await query('board.get', {'startDate': '2026-10-15', 'days': 1}),
    );
    expect(board['candidateTotal'], 0);
    final list = await page(event: {'type': 'cancelledTasks'});
    expect(object(list['header'])['title'], '已取消任务');
    expect(
      nodes(list['tree']).any(
        (n) => n['title'] == task['title'] && n['subtitle'] == '已取消 · 尚未安排时间',
      ),
      true,
    );
    expect((await query('task.cancelled.list') as List).length, 1);
    final back = await page(
      state: object(list['state']),
      event: {'type': 'board'},
    );
    expect(nodes(back['tree']).any((n) => n['type'] == 'plannerBoard'), true);
    await cancel(await raw(task['id']), false);
    expect((await query('task.cancelled.list') as List), isEmpty);
    expect(
      object(
        await query('board.get', {'startDate': '2026-10-15', 'days': 1}),
      )['candidateTotal'],
      1,
    );
  });

  test('cancel confirmation can be dismissed and stale details cannot cancel later edits', () async {
    final task = await create();
    final context = {'taskId': task['id']};
    final detail = await page(
      pageId: 'app.planner.taskDetail',
      context: context,
    );
    host.interaction = (_, method, args) async {
      if (method == 'ui.review') {
        expect(args.toString(), contains('确认取消任务'));
        return false;
      }
      return true;
    };
    final dismissed = await page(
      pageId: 'app.planner.taskDetail',
      context: context,
      state: object(detail['state']),
      event: {'type': 'cancelTask'},
    );
    expect(object(dismissed['state'])['error'], isNull);
    expect(await raw(task['id']), task);
    expect(
      object(await query('task.state', {'id': task['id']}))['cancelled'],
      false,
    );
    await run('task.update', {
      'id': task['id'],
      'changes': {'title': '已修改'},
    });
    final stale = await page(
      pageId: 'app.planner.taskDetail',
      context: context,
      state: object(detail['state']),
      event: {'type': 'cancelTask'},
    );
    expect(object(stale['state'])['error'].toString(), contains('其他操作修改'));
    expect(
      object(await query('task.state', {'id': task['id']}))['cancelled'],
      false,
    );
  });

  test('cancelled time is free for scheduling; cancelled task cannot move, complete or edit and old commands are invalidated', () async {
    final first = await create();
    final other = await run('task.create', {
      'title': '占用释放的时间',
    }, module: 'app.tasks');
    final move = {
      'taskId': other['id'],
      'date': '2026-10-15',
      'start': '09:00',
      'end': '09:30',
      'timezone': 'Asia/Shanghai',
    };
    expect(
      object(await query('operation.preview', move))['confirmable'],
      false,
    );
    await cancel(first);
    expect(object(await query('operation.preview', move))['confirmable'], true);
    await expectLater(
      query('operation.preview', {...move, 'taskId': first['id']}),
      throwsStateError,
    );
    await expectLater(
      run('task.update', {
        'id': first['id'],
        'changes': {'title': '修改取消任务'},
      }),
      throwsStateError,
    );
    await expectLater(
      run('task.setCompleted', {
        'id': first['id'],
        'completed': true,
        'expectedUpdatedAt': first['updatedAt'],
      }, module: 'app.tasks'),
      throwsStateError,
    );
    final completion = await page(
      event: {'type': 'completeTask', 'id': first['id']},
    );
    expect(object(completion['state'])['error'].toString(), contains('任务已取消'));
    final auto = object(
      await query('plan.preview', {'startDate': '2026-10-15', 'days': 1}),
    );
    expect(
      (auto['assigned'] as List).any((c) => object(c)['taskId'] == first['id']),
      false,
    );
    expect(
      (auto['unassigned'] as List).any(
        (c) => object(c)['taskId'] == first['id'],
      ),
      false,
    );
    final completed = await create(scheduled: false);
    await run('task.setCompleted', {
      'id': completed['id'],
      'completed': true,
    }, module: 'app.tasks');
    await expectLater(cancel(await raw(completed['id'])), throwsStateError);
  });
}
