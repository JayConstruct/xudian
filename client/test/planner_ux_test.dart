import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/module_host/planner_board.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  ModuleActor actor() => host.instances['app.planner']!.actor;
  Future<Object?> run(
    String id,
    Map<String, Object?> input, {
    String module = 'app.planner',
  }) async {
    final caller = host.instances[module]!.actor;
    final p = await host.prepare(
      caller,
      ServiceRef(module, module == 'app.planner' ? 'planner.$id' : id, 1),
      input,
    );
    host.review(p.id, caller);
    return host.commit(caller, p.id);
  }

  Future<void> install(String id) async {
    final dir = Directory('../packages/modules/$id');
    final scripts = <String, String>{};
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.js')) {
        scripts[file.path.substring(dir.path.length + 1)] = file
            .readAsStringSync();
      }
    }
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          object(
            jsonDecode(File('${dir.path}/module.json').readAsStringSync()),
          ),
          scripts,
        ),
        allowUnsignedLocal: true,
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('planner-test-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 10, 13);
    await install('app.tasks');
    await install('app.planner');
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });
  Iterable<Map<String, Object?>> nodes(Object? value) sync* {
    if (value is Map) {
      final map = object(value);
      yield map;
      for (final child in map.values) {
        yield* nodes(child);
      }
    } else if (value is List) {
      for (final child in value) {
        yield* nodes(child);
      }
    }
  }

  Future<Map<String, Object?>> page({
    String pageId = 'app.planner.home',
    Map<String, Object?> state = const {},
    Map<String, Object?> context = const {},
    Map<String, Object?> forms = const {},
    Map<String, Object?>? event,
  }) async => object(
    await host.invokePage('app.planner', 'render', {
      'context': {'pageId': pageId, ...context},
      'state': state,
      'event': event,
      'formValues': forms,
    }),
  );

  test(
    'quick add preserves the draft through rules and saves without scheduling',
    () async {
      final interactions = <String>[];
      host.interaction = (_, method, args) async {
        interactions.add(method);
        return method == 'ui.review';
      };
      final initial = await page(pageId: 'app.planner.quickAdd');
      expect(nodes(initial['tree']).where((n) => n['key'] == 'notes'), isEmpty);
      var next = await page(
        pageId: 'app.planner.quickAdd',
        state: object(initial['state']),
        forms: {'title': '普通任务', 'notes': '保存完整描述\n第二行'},
        event: {'type': 'rules'},
      );
      expect(object(object(next['state'])['draft'])['title'], '普通任务');
      next = await page(
        pageId: 'app.planner.quickAdd',
        state: object(next['state']),
        forms: {'estimatedMinutes': '45'},
        event: {'type': 'back'},
      );
      expect(object(object(next['state'])['draft'])['notes'], '保存完整描述\n第二行');
      final saved = await page(
        pageId: 'app.planner.quickAdd',
        state: object(next['state']),
        event: {'type': 'save'},
      );
      expect(object(saved['state'])['error'], isNull);
      final raw = (await host.query(
        actor(),
        const ServiceRef('app.tasks', 'task.list', 1),
        {'view': 'raw'},
      ) as List).map(object).single;
      expect(raw['notes'], '保存完整描述\n第二行');
      expect(raw['estimatedMinutes'], 45);
      expect(raw['dueDate'], isNull);
      expect(raw['plannedStartAt'], isNull);
      expect(interactions, containsAllInOrder(['ui.review', 'ui.navigate']));
    },
  );

  test(
    'deadline candidate filter leaves all scheduled occupancy visible',
    () async {
      await run('task.create', {'title': '无截止候选'});
      await run('task.create', {'title': '有截止候选', 'dueDate': '2026-10-20'});
      await run('task.create', {
        'title': '无截止已安排',
        'plannedStartAt': '2026-10-14T10:00:00Z',
        'plannedEndAt': '2026-10-14T10:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      }, module: 'app.tasks');
      final p = await page(event: {'type': 'onlyDeadline', 'value': true});
      final board = nodes(p['tree'])
          .singleWhere((n) => n['type'] == 'plannerBoard');
      expect(board['days'], hasLength(5));
      expect((board['candidates'] as List).map(object).map((n) => n['title']), [
        '有截止候选',
      ]);
      expect((board['blocks'] as List).map(object).map((n) => n['title']), [
        '无截止已安排',
      ]);
      expect(
        object((board['blocks'] as List).single)['start'],
        '2026-10-14T18:00:00',
      );
    },
  );

  test(
    'quick add canceled review keeps the draft and does not create a task',
    () async {
      host.interaction = (_, method, args) async => false;
      final p = await page(
        pageId: 'app.planner.quickAdd',
        forms: {'title': '保留草稿', 'notes': '取消后仍保留'},
        event: {'type': 'save'},
      );
      expect(object(object(p['state'])['draft'])['title'], '保留草稿');
      expect(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.list', 1),
          {'view': 'raw'},
        ),
        isEmpty,
      );
    },
  );

  test(
    'detail restores initial deadline without changing execution times',
    () async {
      host.interaction = (_, method, args) async => method == 'ui.review';
      final created = object(
        await run('task.create', {
          'title': '恢复截止',
          'dueDate': '2026-10-15',
          'dueTimezone': 'Asia/Shanghai',
          'plannedStartAt': '2026-10-14T10:00:00Z',
          'plannedEndAt': '2026-10-14T10:30:00Z',
          'plannedTimezone': 'Asia/Shanghai',
        }, module: 'app.tasks'),
      );
      await run('task.update', {
        'id': created['id'],
        'changes': {'dueDate': '2026-10-18'},
      });
      final initial = await page(
        pageId: 'app.planner.taskDetail',
        context: {'taskId': created['id']},
      );
      final p = await page(
        pageId: 'app.planner.taskDetail',
        context: {'taskId': created['id']},
        state: object(initial['state']),
        event: {'type': 'restoreDeadline'},
      );
      expect(object(p['state'])['error'], isNull);
      final changed = object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': created['id']},
        ),
      );
      expect(changed['dueDate'], '2026-10-15');
      expect(changed['deadlineHistory'], hasLength(2));
      expect(changed['plannedStartAt'], created['plannedStartAt']);
      expect(changed['plannedEndAt'], created['plannedEndAt']);
    },
  );
  test('saving notes from detail preserves exact deadline seconds and milliseconds', () async {
    host.interaction = (_, method, args) async => method == 'ui.review';
    final created = object(
      await run('task.create', {
        'title': '精确截止',
        'dueAt': '2026-10-15T18:30:45.123Z',
        'dueTimezone': 'Asia/Shanghai',
      }, module: 'app.tasks'),
    );
    final initial = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': created['id']},
    );
    final p = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': created['id']},
      state: object(initial['state']),
      forms: {'notes': '只修改描述'},
      event: {'type': 'saveDetail'},
    );
    expect(object(p['state'])['error'], isNull);
    final changed = object(
      await host.query(actor(), const ServiceRef('app.tasks', 'task.get', 1), {
        'id': created['id'],
      }),
    );
    expect(changed['notes'], '只修改描述');
    expect(changed['dueAt'], created['dueAt']);
    expect(changed['deadlineHistory'], isEmpty);
  });
  test('each editor opening has an independent form session', () async {
    final contexts = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      if (method == 'ui.panel') contexts.add(object(args['context']));
      return true;
    };
    await page(event: {'type': 'add'});
    await page(event: {'type': 'add'});
    await page(event: {'type': 'detail', 'id': 'same-task'});
    await page(event: {'type': 'detail', 'id': 'same-task'});
    expect(contexts, hasLength(4));
    expect(contexts.map((c) => c['editorSession']).toSet(), hasLength(4));
    expect(contexts.last['taskId'], 'same-task');
    final saved = await page(
      pageId: 'app.planner.quickAdd',
      forms: {'title': '新任务', 'notes': '描述'},
      event: {'type': 'save'},
    );
    expect(
      saved['clearForms'],
      containsAll(['title', 'notes', 'dueDate', 'dueTime', 'estimatedMinutes']),
    );
  });

  test('editing notes on a fixed legacy task does not invent an estimated duration', () async {
    host.interaction = (_, method, args) async => method == 'ui.review';
    final original = object(
      await run('task.create', {
        'title': '固定旧任务',
        'locked': true,
        'plannedStartAt': '2026-10-14T10:00:00Z',
        'plannedEndAt': '2026-10-14T10:45:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      }, module: 'app.tasks'),
    );
    final initial = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': original['id']},
    );
    final saved = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': original['id']},
      state: object(initial['state']),
      forms: {'notes': '可修改描述'},
      event: {'type': 'saveDetail'},
    );
    expect(object(saved['state'])['error'], isNull);
    final updated = object(
      await host.query(actor(), const ServiceRef('app.tasks', 'task.get', 1), {
        'id': original['id'],
      }),
    );
    expect(updated['notes'], '可修改描述');
    expect(updated['estimatedMinutes'], isNull);
    expect(updated['plannedEndAt'], original['plannedEndAt']);
    expect(updated['locked'], true);
  });

  test('an old detail schedule cannot overwrite a later edit', () async {
    var reviewCount = 0;
    host.interaction = (_, method, args) async {
      if (method == 'ui.review') reviewCount++;
      return true;
    };
    final original = object(
      await run('task.create', {'title': '并发任务'}, module: 'app.tasks'),
    );
    final initial = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': original['id']},
    );
    await run('task.updateFields', {
      'id': original['id'],
      'changes': {'notes': '后来改动'},
    }, module: 'app.tasks');
    final saved = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': original['id']},
      state: object(initial['state']),
      forms: {
        'startDate': '2026-10-14',
        'start': '18:00',
        'endDate': '2026-10-14',
        'end': '18:30',
      },
      event: {'type': 'schedule'},
    );
    expect(object(saved['state'])['error'], isNotNull);
    expect(reviewCount, 0);
    final updated = object(
      await host.query(actor(), const ServiceRef('app.tasks', 'task.get', 1), {
        'id': original['id'],
      }),
    );
    expect(updated['plannedStartAt'], isNull);
    expect(updated['notes'], '后来改动');
  });

  test(
    'canceled drag retains its intent and retry preserves the task duration',
    () async {
      final original = object(
        await run('task.create', {'title': '可重试'}, module: 'app.tasks'),
      );
      host.interaction = (_, method, args) async => false;
      final first = await page(
        event: {
          'type': 'move',
          'taskId': original['id'],
          'start': '2026-10-14T18:00:00',
          'end': '2026-10-14T18:45:00',
          'intent': 'move',
        },
      );
      expect(object(first['state'])['moveIntent'], isNotNull);
      expect(object(first['state'])['error'], isNull);
      host.interaction = (_, method, args) async => true;
      final second = await page(
        state: object(first['state']),
        event: {'type': 'retryMove'},
      );
      expect(object(second['state'])['moveIntent'], isNull);
      final updated = object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': original['id']},
        ),
      );
      expect(updated['plannedEndAt'], '2026-10-14T10:30:00.000Z');
      expect(updated['estimatedMinutes'], 30);
    },
  );

  test(
    'board uses local deadline text and a compact preview query contract',
    () async {
      await run('task.create', {
        'title': '精确候选',
        'dueAt': '2026-10-14T12:30:00Z',
        'dueTimezone': 'Asia/Shanghai',
        'notes': '不应复制进预览令牌',
      });
      final rendered = await page();
      final board = nodes(rendered['tree'])
          .singleWhere((n) => n['type'] == 'plannerBoard');
      final item = object((board['candidates'] as List).single);
      expect(item['deadlineText'], '截止 2026-10-14 20:30（Asia/Shanghai）');
      expect(
        object(object(board['previewQuery'])['ref'])['serviceId'],
        'planner.operation.inspect',
      );
      expect(jsonEncode(board), isNot(contains('不应复制进预览令牌')));
    },
  );
  test(
    'resize uses the stored start even if the event carries a rounded start',
    () async {
      host.interaction = (_, method, args) async => true;
      final original = object(
        await run('task.create', {
          'title': '只拉结束',
          'plannedStartAt': '2026-10-14T10:00:00Z',
          'plannedEndAt': '2026-10-14T10:30:00Z',
          'plannedTimezone': 'Asia/Shanghai',
        }, module: 'app.tasks'),
      );
      final changed = await page(
        event: {
          'type': 'move',
          'taskId': original['id'],
          'intent': 'resize',
          'start': '2026-10-14T17:00:00',
          'end': '2026-10-14T18:45:00',
        },
      );
      expect(object(changed['state'])['error'], isNull);
      final saved = object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': original['id']},
        ),
      );
      expect(saved['plannedStartAt'], original['plannedStartAt']);
      expect(saved['plannedEndAt'], '2026-10-14T10:45:00.000Z');
      expect(saved['estimatedMinutes'], 45);
    },
  );

  testWidgets(
    'board preview bridge calls a query without saving or opening review',
    (tester) async {
      late Map<String, Object?> created;
      await tester.runAsync(() async {
        created = object(
          await run('task.create', {
            'title': '预览不落库',
            'estimatedMinutes': 30,
          }, module: 'app.tasks'),
        );
      });
      var interactionCount = 0;
      host.interaction = (_, method, args) async {
        interactionCount++;
        return true;
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'app.planner',
              handler: 'render',
              pageContext: const {'pageId': 'app.planner.home'},
            ),
          ),
        ),
      );
      for (var i = 0; i < 24; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      final board = tester.widget<PlannerBoard>(find.byType(PlannerBoard));
      expect(board.onPreview, isNotNull);
      Map<String, Object?>? preview;
      await tester.runAsync(() async {
        preview = await board.onPreview!({
          'id': created['id'],
          'intent': 'move',
          'start': '2026-10-14T18:00:00',
          'end': '2026-10-14T18:30:00',
        });
      });
      expect(preview!['valid'], true);
      expect(preview!['previewBlocks'], hasLength(1));
      expect(
        object((preview!['previewBlocks'] as List).single)['start'],
        '2026-10-14T18:00:00',
      );
      expect(interactionCount, 0);
      await tester.runAsync(() async {
        final after = await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': created['id']},
        );
        expect(after, created);
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('candidate paging retains off-page selection and never filters occupied blocks', () async {
    final taskActor = host.instances['app.tasks']!.actor;
    final session = SnapshotSession(taskActor, 'page-fixture');
    await store.stage(session, taskActor, {
      'writes': [
        for (var i = 0; i < 105; i++)
          {
            'collection': 'tasks',
            'id': 'candidate-${i.toString().padLeft(3, '0')}',
            'value': {
              'id': 'candidate-${i.toString().padLeft(3, '0')}',
              'title': '任务$i',
              'priority': 0,
              'estimatedMinutes': 30,
              'dueDate': i == 0 ? '2026-10-20' : null,
              'updatedAt': '2026-10-13T00:00:00.000Z',
              'createdAt': '2026-10-13T00:00:00.000Z',
            },
          },
      ],
    });
    await store.commit(
      store.seal(session).id,
      taskActor,
      authorize: (_) {},
      audit: false,
    );
    await run('task.create', {
      'title': '图上占用',
      'plannedStartAt': '2026-10-14T10:00:00Z',
      'plannedEndAt': '2026-10-14T10:30:00Z',
      'plannedTimezone': 'Asia/Shanghai',
    }, module: 'app.tasks');
    var rendered = await page();
    Map<String, Object?> board() =>
        nodes(rendered['tree']).singleWhere((n) => n['type'] == 'plannerBoard');
    expect(board()['candidates'], hasLength(100));
    final first = object((board()['candidates'] as List).first);
    final firstId = object(first['selectEvent'])['id'];
    rendered = await page(
      state: object(rendered['state']),
      event: {'type': 'select', 'id': firstId, 'value': true},
    );
    rendered = await page(
      state: object(rendered['state']),
      event: {'type': 'candidatePage', 'offset': 100},
    );
    expect(board()['candidates'], hasLength(5));
    expect(object(rendered['state'])['selected'], [firstId]);
    expect(
      nodes(rendered['tree']).any((n) => '${n['text']}'.contains('其他页或筛选外')),
      true,
    );
    final secondId = object(
      object((board()['candidates'] as List).first)['selectEvent'],
    )['id'];
    rendered = await page(
      state: object(rendered['state']),
      event: {'type': 'select', 'id': secondId, 'value': true},
    );
    rendered = await page(
      state: object(rendered['state']),
      event: {'type': 'onlyDeadline', 'value': true},
    );
    expect(board()['candidates'], hasLength(1));
    expect(board()['blocks'], hasLength(1));
    expect(object(rendered['state'])['candidateOffset'], 0);
    expect(object(rendered['state'])['selected'], [firstId, secondId]);
    rendered = await page(
      state: object(rendered['state']),
      event: {'type': 'auto'},
    );
    final preview = object(object(rendered['state'])['autoPreview']);
    expect(object(preview['input'])['selectedIds'], [firstId, secondId]);
    rendered = await page(
      state: object(rendered['state']),
      event: {'type': 'clearSelection'},
    );
    expect(object(rendered['state'])['selected'], isEmpty);
  });

  test(
    'invalid display period preserves the current board and explains the error',
    () async {
      host.interaction = (_, method, args) async =>
          method == 'ui.dialog' ? {'startDate': '2026-99-99', 'days': 5} : true;
      final result = await page(
        state: {'startDate': '2026-10-13', 'days': 5},
        event: {'type': 'period'},
      );
      expect(object(result['state'])['startDate'], '2026-10-13');
      expect(object(result['state'])['error'], isNotNull);
      expect(
        nodes(result['tree']).where((n) => n['type'] == 'plannerBoard'),
        hasLength(1),
      );
    },
  );

  test('graphical move preserves elapsed duration across daylight saving transitions', () async {
    host.interaction = (_, method, args) async => true;
    await run('availability.save', {
      'availability': {'timezone': 'America/New_York', 'bufferMinutes': 0},
    });
    final original = object(
      await run('task.create', {
        'title': '夏令时任务',
        'plannedStartAt': '2026-10-31T04:30:00Z',
        'plannedEndAt': '2026-10-31T06:30:00Z',
        'plannedTimezone': 'America/New_York',
      }, module: 'app.tasks'),
    );
    final result = await page(
      event: {
        'type': 'move',
        'taskId': original['id'],
        'intent': 'move',
        'start': '2026-11-01T00:30:00',
        'end': '2026-11-01T02:30:00',
      },
    );
    expect(object(result['state'])['error'], isNull);
    final saved = object(
      await host.query(actor(), const ServiceRef('app.tasks', 'task.get', 1), {
        'id': original['id'],
      }),
    );
    expect(saved['plannedStartAt'], '2026-11-01T04:30:00.000Z');
    expect(saved['plannedEndAt'], '2026-11-01T06:30:00.000Z');
    expect(saved['estimatedMinutes'], 120);
  });
}
