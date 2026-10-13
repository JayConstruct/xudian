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
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('planner-ai-undo-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    for (final id in ['app.tasks', 'app.ai']) {
      await host.install(await sourcePackage(id));
    }
    final actor = host.instances['app.ai']!.actor;
    final plan = await host.prepare(
      actor,
      const ServiceRef('app.ai', 'ai.connection.save', 1),
      {
        'connection': {
          'endpoint': 'https://model.example/v1',
          'model': 'test',
          'credential': 'opaque',
        },
      },
    );
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Map<String, Object?>> command(
    String id,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances['app.tasks']!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef('app.tasks', id, 1),
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
  Future<Map<String, Object?>> editWithAi(
    String serviceId,
    Map<String, Object?> input,
  ) async {
    final toolIndex = host
        .directoryServices()
        .map(object)
        .where(
          (service) =>
              service['tool'] != null && service['moduleId'] != 'app.ai',
        )
        .toList()
        .indexWhere((service) => service['id'] == serviceId);
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
                              'name': 'service_$toolIndex',
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
    final page = object(
      await host.invokePage('app.ai', 'render', {
        'state': {},
        'event': {'type': 'send'},
        'formValues': {'message': 'edit task'},
      }),
    );
    return object(page['state']);
  }

  Future<void> undo(Map<String, Object?> state) async {
    await host.invokePage('app.ai', 'render', {
      'state': state,
      'event': {'type': 'undo'},
    });
  }

  const precise = {
    'plannedStartAt': '2026-10-10T18:00:00Z',
    'plannedEndAt': '2026-10-10T19:00:00Z',
    'plannedTimezone': 'Asia/Shanghai',
  };

  test('generic AI undo restores precision implicitly cleared by a date-only update', () async {
    final created = await command('task.create', {
      'title': 'precise',
      ...precise,
    });
    final state = await editWithAi('task.updateFields', {
      'id': created['id'],
      'changes': {'plannedDate': '2026-10-12'},
    });
    expect((await raw(created['id']))['plannedStartAt'], isNull);
    final changes = object(
      object(object(state['lastUndo'])['input'])['changes'],
    );
    expect(changes, {
      'plannedDate': '2026-10-11',
      for (final key in precise.keys) key: created[key],
    });
    await undo(state);
    final restored = await raw(created['id']);
    for (final key in ['plannedDate', ...precise.keys]) {
      expect(restored[key], created[key]);
    }
  });

  test('generic AI undo restores corrected completion date and timezone while preserving audit timestamp', () async {
    final created = await command('task.create', {'title': 'completed'});
    await command('task.setCompleted', {
      'id': created['id'],
      'completed': true,
      'actualCompletedOn': '2026-10-07',
      'completedTimezone': 'Asia/Shanghai',
    });
    final before = await raw(created['id']);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 7);
    final state = await editWithAi('task.setCompleted', {
      'id': created['id'],
      'completed': true,
      'actualCompletedOn': '2026-10-09',
      'completedTimezone': 'America/New_York',
    });
    final changed = await raw(created['id']);
    expect(changed['actualCompletedOn'], '2026-10-09');
    expect(changed['completedAt'], before['completedAt']);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 8);
    await undo(state);
    final restored = await raw(created['id']);
    for (final key in [
      'completedAt',
      'actualCompletedOn',
      'completedTimezone',
    ]) {
      expect(restored[key], before[key]);
    }
  });

  test('generic AI undo of first completion reopens without completion-date arguments', () async {
    final created = await command('task.create', {'title': 'pending'});
    final state = await editWithAi('task.setCompleted', {
      'id': created['id'],
      'completed': true,
      'actualCompletedOn': '2026-10-09',
      'completedTimezone': 'UTC',
    });
    final input = object(object(state['lastUndo'])['input']);
    expect(input['completed'], false);
    expect(input.containsKey('actualCompletedOn'), false);
    expect(input.containsKey('completedTimezone'), false);
    await undo(state);
    final restored = await raw(created['id']);
    expect(restored['completedAt'], isNull);
    expect(restored['actualCompletedOn'], isNull);
    expect(restored['completedTimezone'], isNull);
  });

  test('legacy completion metadata and missing precision fields undo as explicit nullable values', () async {
    final created = await command('task.create', {
      'title': 'legacy',
      'plannedDate': '2026-10-08',
    });
    final legacy = {...created, 'completedAt': '2026-10-08T06:00:00.000Z'};
    for (final key in [
      ...precise.keys,
      'actualCompletedOn',
      'completedTimezone',
    ]) {
      legacy.remove(key);
    }
    await command('task.restore', {
      'id': created['id'],
      'expected': created,
      'value': legacy,
    });
    var state = await editWithAi('task.setCompleted', {
      'id': created['id'],
      'completed': true,
      'actualCompletedOn': '2026-10-09',
      'completedTimezone': 'UTC',
    });
    final completionUndo = object(object(state['lastUndo'])['input']);
    expect(completionUndo.containsKey('actualCompletedOn'), true);
    expect(completionUndo['actualCompletedOn'], isNull);
    expect(completionUndo['completedTimezone'], isNull);
    await undo(state);
    var restored = await raw(created['id']);
    expect(restored['completedAt'], legacy['completedAt']);
    expect(restored['actualCompletedOn'], isNull);
    expect(restored['completedTimezone'], isNull);
    state = await editWithAi('task.updateFields', {
      'id': created['id'],
      'changes': {'plannedDate': '2026-10-09'},
    });
    await undo(state);
    restored = await raw(created['id']);
    expect(restored['plannedDate'], '2026-10-08');
    for (final key in precise.keys) {
      expect(restored[key], isNull);
    }
  });

  test('generic precision undo rejects later user modifications', () async {
    final created = await command('task.create', {
      'title': 'precise',
      ...precise,
    });
    final state = await editWithAi('task.updateFields', {
      'id': created['id'],
      'changes': {'plannedDate': '2026-10-12'},
    });
    await command('task.updateFields', {
      'id': created['id'],
      'changes': {'title': 'edited later'},
    });
    await expectLater(undo(state), throwsStateError);
    final restored = await raw(created['id']);
    expect(restored['title'], 'edited later');
    expect(restored['plannedDate'], '2026-10-12');
    expect(restored['plannedStartAt'], isNull);
  });
}
