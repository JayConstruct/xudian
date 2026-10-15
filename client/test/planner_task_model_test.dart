import 'dart:convert';
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

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planner-task-model-');
    db = AppDatabase(NativeDatabase(File('${directory.path}/model.sqlite')));
    store = CollectionStore(db);
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 15, 6);
    await host.initialize();
    for (final id in ['app.tasks', 'app.ai']) {
      await host.install(await sourcePackage(id));
    }
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> command(
    String service,
    Map<String, Object?> input, {
    String module = 'app.tasks',
  }) async {
    final actor = host.instances[module]!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef(module, service, 1),
      input,
    );
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Object?> query(String service, Map<String, Object?> input) =>
      host.query(
        host.instances['app.tasks']!.actor,
        ServiceRef('app.tasks', service, 1),
        input,
      );
  Future<Map<String, Object?>> raw(Object? id) async =>
      object(await query('task.get', {'id': id}));
  Map<String, Object?> deadline(Map<String, Object?> task) => {
    for (final key in ['dueDate', 'dueAt', 'dueTimezone']) key: task[key],
  };

  Future<Map<String, Object?>> editWithAi(Map<String, Object?> input) async {
    await command('ai.connection.save', {
      'connection': {
        'endpoint': 'https://model.example/v1',
        'model': 'test',
        'credential': 'opaque',
      },
    }, module: 'app.ai');
    final index = host
        .directoryServices()
        .map(object)
        .where((s) => s['tool'] != null && s['moduleId'] != 'app.ai')
        .toList()
        .indexWhere((s) => s['id'] == 'task.updateFields');
    var requests = 0;
    host.interaction = (_, method, args) async {
      if (method == 'ui.review' || method == 'grants.request') return true;
      if (method == 'http.request') {
        requests++;
        return {
          'status': 200,
          'body': jsonEncode({
            'choices': [
              {
                'message': requests == 1
                    ? {
                        'role': 'assistant',
                        'content': null,
                        'tool_calls': [
                          {
                            'id': 'edit',
                            'type': 'function',
                            'function': {
                              'name': 'service_$index',
                              'arguments': jsonEncode(input),
                            },
                          },
                        ],
                      }
                    : {'role': 'assistant', 'content': 'done'},
              },
            ],
          }),
        };
      }
      throw StateError('Unexpected bridge $method');
    };
    return object(
      object(
        await host.invokePage('app.ai', 'render', {
          'state': {},
          'event': {'type': 'send'},
          'formValues': {'message': 'edit task'},
        }),
      )['state'],
    );
  }

  Future<void> undo(Map<String, Object?> state) async {
    await host.invokePage('app.ai', 'render', {
      'state': state,
      'event': {'type': 'undo'},
    });
  }

  test('description participates in frozen review, persisted reads and optimistic updates', () async {
    final actor = host.instances['app.tasks']!.actor;
    final plan = await host.prepare(
      actor,
      const ServiceRef('app.tasks', 'task.create', 1),
      {'title': '短名称', 'notes': '详细描述\n第二行保留空白  '},
    );
    final created = object(plan.result);
    expect(
      object(object(plan.writes.single)['value'])['notes'],
      created['notes'],
    );
    expect(await query('task.get', {'id': created['id']}), isNull);
    await expectLater(host.commit(actor, plan.id), throwsStateError);
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
    expect(await raw(created['id']), created);
    final listed = (await query('task.list', {})) as List;
    expect(object(listed.single)['notes'], created['notes']);
    expect(created['dueDate'], isNull);
    expect(created['plannedDate'], isNull);

    final changed = await command('task.updateFields', {
      'id': created['id'],
      'expectedValues': created,
      'changes': {
        'notes': '更新后的描述',
        'dueDate': '2026-10-20',
        'dueTimezone': 'Asia/Shanghai',
      },
    });
    expect(changed['notes'], '更新后的描述');
    expect((await raw(created['id']))['notes'], changed['notes']);
    await expectLater(
      command('task.updateFields', {
        'id': created['id'],
        'expectedValues': created,
        'changes': {'notes': '过时描述'},
      }),
      throwsStateError,
    );
    await host.close();
    await store.close();
    await db.close();
    db = AppDatabase(NativeDatabase(File('${directory.path}/model.sqlite')));
    store = CollectionStore(db);
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    final persisted = await raw(created['id']);
    expect(persisted['notes'], '更新后的描述');
    expect(persisted['dueDate'], '2026-10-20');
    expect(persisted['dueTimezone'], 'Asia/Shanghai');
    expect(persisted['initialDeadline'], created['initialDeadline']);
    expect(persisted['deadlineHistory'], changed['deadlineHistory']);
  });

  test('generic description undo restores the complete text and rejects later edits', () async {
    final created = await command('task.create', {
      'title': '名称',
      'notes': '初始\n描述  ',
    });
    var state = await editWithAi({
      'id': created['id'],
      'changes': {'notes': '新描述'},
    });
    expect(
      object(
        object(object(state['lastUndo'])['input'])['expectedValues'],
      )['notes'],
      '新描述',
    );
    await undo(state);
    expect((await raw(created['id']))['notes'], created['notes']);
    state = await editWithAi({
      'id': created['id'],
      'changes': {'notes': '再修改'},
    });
    await command('task.setCompleted', {
      'id': created['id'],
      'completed': true,
    });
    await expectLater(undo(state), throwsStateError);
    expect((await raw(created['id']))['notes'], '再修改');
  });

  test('current deadline retains date precision and timezone, initial deadline and append-only adjustments', () async {
    final created = await command('task.create', {
      'title': '截止',
      'dueDate': '2026-10-15',
      'dueTimezone': 'Asia/Shanghai',
    });
    expect(created['initialDeadline'], deadline(created));
    expect(created['deadlineHistory'], isEmpty);
    final moved = await command('task.updateFields', {
      'id': created['id'],
      'changes': {'dueDate': '2026-10-18'},
    });
    expect(moved['dueTimezone'], 'Asia/Shanghai');
    expect(moved['dueAt'], isNull);
    expect(moved['initialDeadline'], created['initialDeadline']);
    final history = moved['deadlineHistory'] as List;
    expect(object(history.single)['before'], deadline(created));
    expect(object(history.single)['after'], deadline(moved));
    final restored = await command('task.updateFields', {
      'id': created['id'],
      'changes': object(created['initialDeadline']),
    });
    expect(deadline(restored), deadline(created));
    expect(restored['initialDeadline'], created['initialDeadline']);
    expect(restored['deadlineHistory'], hasLength(2));
    for (final field in ['initialDeadline', 'deadlineHistory']) {
      await expectLater(
        command('task.updateFields', {
          'id': created['id'],
          'changes': {field: null},
        }),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
    }
    final noDeadline = await command('task.create', {'title': '无截止'});
    final firstDeadline = await command('task.updateFields', {
      'id': noDeadline['id'],
      'changes': {'dueDate': '2026-10-20'},
    });
    expect(firstDeadline['initialDeadline'], deadline(noDeadline));
  });

  test('precise deadline edits and generic undo retain the full deadline independently of schedule', () async {
    final created = await command('task.create', {
      'title': '两个时间',
      'dueAt': '2026-10-15T18:30:00Z',
      'dueTimezone': 'Asia/Shanghai',
      'plannedStartAt': '2026-10-15T15:30:00Z',
      'plannedEndAt': '2026-10-15T17:00:00Z',
      'plannedTimezone': 'Asia/Shanghai',
      'estimatedMinutes': 90,
    });
    expect(created['dueDate'], '2026-10-16');
    expect(created['plannedDate'], '2026-10-15');
    final state = await editWithAi({
      'id': created['id'],
      'changes': {'dueDate': '2026-10-18'},
    });
    final updated = await raw(created['id']);
    expect(updated['dueAt'], isNull);
    expect(updated['dueTimezone'], 'Asia/Shanghai');
    for (final key in [
      'plannedStartAt',
      'plannedEndAt',
      'plannedTimezone',
      'plannedDate',
    ]) {
      expect(updated[key], created[key]);
    }
    await undo(state);
    final restored = await raw(created['id']);
    expect(deadline(restored), deadline(created));
    expect(restored['initialDeadline'], created['initialDeadline']);
    expect(restored['deadlineHistory'], hasLength(2));
    await command('task.updateFields', {
      'id': created['id'],
      'changes': {
        'plannedStartAt': '2026-10-20T15:30:00Z',
        'plannedEndAt': '2026-10-20T17:00:00Z',
      },
    });
    expect(deadline(await raw(created['id'])), deadline(created));
    final range = (await query('task.range', {
      'startAt': '2026-10-20T16:00:00Z',
      'endAt': '2026-10-20T17:00:00Z',
    })) as List;
    expect(object(range.single)['id'], created['id']);
  });

  test('due instant undo restores implicitly derived date and timezone-only edit also records civil change', () async {
    final created = await command('task.create', {
      'title': '精确截止',
      'dueAt': '2026-10-15T18:00:00Z',
      'dueTimezone': 'UTC',
    });
    final state = await editWithAi({
      'id': created['id'],
      'changes': {'dueAt': '2026-10-18T18:00:00Z'},
    });
    expect((await raw(created['id']))['dueDate'], '2026-10-18');
    await undo(state);
    expect(deadline(await raw(created['id'])), deadline(created));
    final changed = await command('task.updateFields', {
      'id': created['id'],
      'changes': {'dueTimezone': 'Asia/Shanghai'},
    });
    expect(changed['dueDate'], '2026-10-16');
    expect(changed['dueAt'], created['dueAt']);
  });

  test('one fixed-time flag protects cross-midnight start, end and duration with explicit unlock', () async {
    final created = await command('task.create', {
      'title': '跨午夜',
      'locked': true,
      'plannedStartAt': '2026-10-15T15:30:00Z',
      'plannedEndAt': '2026-10-15T17:00:00Z',
      'plannedTimezone': 'Asia/Shanghai',
      'estimatedMinutes': 90,
    });
    for (final changes in [
      {'plannedEndAt': '2026-10-15T17:30:00Z'},
      {'estimatedMinutes': 30},
      {'plannedDate': null},
    ]) {
      await expectLater(
        command('task.updateFields', {'id': created['id'], 'changes': changes}),
        throwsStateError,
      );
    }
    final edited = await command('task.updateFields', {
      'id': created['id'],
      'changes': {'notes': '固定仍允许改描述', 'dueDate': '2026-10-20'},
    });
    expect(edited['locked'], true);
    final unlocked = await command('task.updateFields', {
      'id': created['id'],
      'changes': {'locked': false, 'estimatedMinutes': 60},
    });
    expect(unlocked['locked'], false);
    expect(unlocked['estimatedMinutes'], 60);
  });

  test('same-clock edits advance optimistic tokens and unchanged writes keep theirs', () async {
    final created = await command('task.create', {
      'title': '并发',
      'notes': '初始',
    });
    final first = await command('task.updateFields', {
      'id': created['id'],
      'expectedUpdatedAt': created['updatedAt'],
      'changes': {'notes': '第一项修改'},
    });
    expect(
      DateTime.parse(first['updatedAt'] as String)
          .isAfter(DateTime.parse(created['updatedAt'] as String)),
      isTrue,
    );
    await expectLater(
      command('task.updateFields', {
        'id': created['id'],
        'expectedUpdatedAt': created['updatedAt'],
        'changes': {'notes': '过时覆盖'},
      }),
      throwsStateError,
    );
    expect((await raw(created['id']))['notes'], '第一项修改');
    final unchanged = await command('task.updateFields', {
      'id': created['id'],
      'expectedUpdatedAt': first['updatedAt'],
      'changes': {'notes': '第一项修改'},
    });
    expect(unchanged['updatedAt'], first['updatedAt']);
    final second = await command('task.updateFields', {
      'id': created['id'],
      'expectedUpdatedAt': first['updatedAt'],
      'changes': {'notes': '第二项修改'},
    });
    expect(
      DateTime.parse(second['updatedAt'] as String)
          .isAfter(DateTime.parse(first['updatedAt'] as String)),
      isTrue,
    );
    host.clockNow = () => DateTime.utc(2026, 10, 15, 5);
    final backwardsClock = await command('task.updateFields', {
      'id': created['id'],
      'changes': {'notes': '时钟回拨仍递增'},
    });
    expect(
      DateTime.parse(backwardsClock['updatedAt'] as String)
          .isAfter(DateTime.parse(second['updatedAt'] as String)),
      isTrue,
    );
  });

  test(
    'same-clock completion and reopening invalidate old snapshot undo',
    () async {
      final created = await command('task.create', {'title': '撤销保护'});
      final edited = await command('task.updateFields', {
        'id': created['id'],
        'changes': {'notes': '已修改'},
      });
      final expectedUndo = await raw(created['id']);
      final completed = await command('task.setCompleted', {
        'id': created['id'],
        'completed': true,
        'expectedUpdatedAt': edited['updatedAt'],
      });
      expect(
        DateTime.parse(completed['updatedAt'] as String)
            .isAfter(DateTime.parse(edited['updatedAt'] as String)),
        isTrue,
      );
      final unchanged = await command('task.setCompleted', {
        'id': created['id'],
        'completed': true,
      });
      expect(unchanged['updatedAt'], completed['updatedAt']);
      final reopened = await command('task.setCompleted', {
        'id': created['id'],
        'completed': false,
        'expectedUpdatedAt': completed['updatedAt'],
      });
      expect(reopened['completedAt'], isNull);
      expect(
        DateTime.parse(reopened['updatedAt'] as String)
            .isAfter(DateTime.parse(completed['updatedAt'] as String)),
        isTrue,
      );
      final current = await raw(created['id']);
      expect(
        {...current}..remove('updatedAt'),
        {...expectedUndo}..remove('updatedAt'),
      );
      await expectLater(
        command('task.restore', {
          'id': created['id'],
          'expected': expectedUndo,
          'value': created,
        }),
        throwsStateError,
      );
      expect(await raw(created['id']), current);
    },
  );

  test('invalid deadline formats never persist partial changes', () async {
    for (final input in [
      {'notes': 1},
      {'dueAt': '2026-10-15T18:00:00Z'},
      {'dueAt': '2026-02-30T18:00:00Z', 'dueTimezone': 'UTC'},
      {'dueAt': '2026-10-15T18:00:00+00:00', 'dueTimezone': 'UTC'},
      {'dueDate': '2026-10-15', 'dueTimezone': 'Invalid/Zone'},
      {'locked': 'yes'},
    ]) {
      await expectLater(
        command('task.create', {'title': 'invalid', ...input}),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
    }
    expect(await query('task.list', {'view': 'raw'}), isEmpty);
  });
}
