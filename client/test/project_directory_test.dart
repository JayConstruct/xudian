import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'support/module_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late Directory dir;
  late ModuleHost host;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    dir = await Directory.systemTemp.createTemp('project-directory-');
    host = ModuleHost(
      store: store,
      directory: dir,
      systemTimezoneResolver: () async => 'Asia/Shanghai',
    );
    host.clockNow = () => DateTime.utc(2026, 10, 13);
    await host.initialize();
    host.interaction = (_, method, _) async =>
        method == 'ui.review' ? true : null;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<Map<String, Object?>> run(
    String id,
    Map<String, Object?> input, {
    String module = 'app.tasks',
  }) async {
    final actor = host.instances[module]!.actor;
    final plan = await host.prepare(actor, ServiceRef(module, id, 1), input);
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> page(
    String projectId, {
    Object? state,
    Object? event,
  }) async => object(
    await host.invokePage('app.tasks', 'projectPage', {
      'context': {'pageId': 'app.tasks.directory', 'projectId': projectId},
      'state': state ?? {},
      'event': event,
    }),
  );
  Future<Map<String, Object?>> board() async => nodes(
    await host.invokePage('app.planner', 'render', {
      'context': {'pageId': 'app.planner.home'},
    }),
  ).singleWhere((n) => n['type'] == 'plannerBoard');
  Future<Map<String, Object?>> root({Object? state, Object? event}) async =>
      object(
        await host.invokePage('app.tasks', 'projectPage', {
          'context': {'pageId': 'app.tasks.projects'},
          'state': state ?? {'tab': 'activity'},
          'event': event,
        }),
      );

  List<Map<String, Object?>> activityRows(Object page) =>
      nodes(page)
          .where((n) => n['key'].toString().startsWith('activity:'))
          .map((n) => object(n['child']))
          .toList();

  Future<Map<String, Object?>> saved(String collection, Object? id) async =>
      object(
        await store.get(
          host.instances['app.tasks']!.actor,
          collection,
          id as String,
        ),
      );

  group('current modules', () {
    setUp(() async {
      for (final id in ['app.tasks', 'app.planner', 'app.ai']) {
        await host.install(await sourcePackage(id));
      }
    });
    test(
      'pick from multiple folders as one edit, undo, schedule and open project',
      () async {
        final p =
            (await run('project.create', {
                  'name': '交付',
                  'importance': 2,
                  'targetDate': '2026-10-15',
                }))['id']
                as String;
        await run('project.outline', {
          'projectId': p,
          'items': [
            {'title': '评审', 'estimatedMinutes': 30},
            {
              'title': '联调',
              'path': ['部署'],
              'estimatedMinutes': 45,
            },
            {
              'title': '发布',
              'path': ['部署', '验收'],
            },
            {'title': '稍后处理'},
          ],
        });
        await run('task.create', {'title': '独立任务'});
        expect(objects((await board())['candidates']).map((t) => t['title']), [
          '独立任务',
        ]);
        final direct = nodes(await page(p)).singleWhere(
          (n) =>
              n['type'] == 'swipeActions' &&
              object(n['child'])['title'] == '评审',
        );
        final queue = objects(direct['actions'])
            .singleWhere((action) => action['label'] == '加入待安排');
        expect(direct['menuTrigger'], 'longPress');
        expect(queue['icon'], 'calendarAdd');
        final activity = nodes(await root()).singleWhere(
          (n) => n['key'] == 'activity:$p',
        );
        expect(activity['menuTrigger'], 'longPress');
        expect(object(activity['child'])['icon'], 'briefcase');
        expect(objects(activity['actions']).map((a) => a['icon']), [
          'pin',
          'sliders',
        ]);
        expect(objects(activity['actions']).map((a) => a['label']), [
          '固定到跟进', '项目设置',
        ]);
        final queued = await page(p, event: queue['event']);
        expect(object(queued['state'])['error'], isNull);
        final queuedRow = nodes(queued).singleWhere(
          (n) => n['key'] == direct['key'],
        );
        expect(objects(queuedRow['actions']).first['icon'], 'calendarRemove');
        expect(
          objects((await board())['candidates']).map((task) => task['title']),
          contains('评审'),
        );
        await page(p, state: queued['state'], event: {'type': 'undo'});
        expect(
          objects((await board())['candidates']).map((task) => task['title']),
          isNot(contains('评审')),
        );
        final picker = await page(p, event: {'type': 'pick'});
        expect(nodes(picker).map((n) => n['title']), contains('部署 / 验收'));
        var state = picker['state'];
        for (final label in ['评审', '联调', '发布']) {
          final box = nodes(picker).singleWhere(
            (n) =>
                n['type'] == 'checkbox' &&
                n['text'].toString().startsWith(label),
          );
          state = (await page(p, state: state, event: box['event']))['state'];
        }
        expect(
          nodes(await page(p, state: state)).map((n) => n['text']),
          containsAll(['已选 3 项','已知 75 分钟，1 项未估时']),
        );
        final applied = await page(p, state: state, event: {'type': 'apply'});
        expect(objects((await board())['candidates']), hasLength(4));
        final task = objects((await board())['candidates'])
            .singleWhere((t) => t['title'] == '发布');
        final id = task['id'];
        await run('task.updateFields', {
          'id': id,
          'changes': {
            'plannedStartAt': '2026-10-13T03:00:00Z',
            'plannedEndAt': '2026-10-13T03:30:00Z',
            'plannedTimezone': 'Asia/Shanghai',
          },
        });
        final block = objects((await board())['blocks'])
            .singleWhere((t) => t['id'] == id);
        final open = objects(block['actions'])
            .singleWhere((a) => a['label'] == '所属项目 · 交付');
        expect(object(open['event'])['projectId'], p);
        expect(object(open['event'])['folderId'], isNotNull);
        final rejected = await page(
          p,
          state: applied['state'],
          event: {'type': 'undo'},
        );
        expect(object(rejected['state'])['error'], isNotNull);
        expect(objects((await board())['candidates']), hasLength(3));
        await run('task.updateFields', {
          'id': id,
          'changes': {'plannedDate': null},
        });
        expect(objects((await board())['candidates']), hasLength(4));
        final ai = object(
          await host.invokePage('app.ai', 'render', {
            'context': {
              'pageId': 'app.ai.projectDraft',
              'projectId': p,
              'projectName': '交付',
            },
          }),
        );
        expect(object(ai['replaceForms'])['message'], contains('交付'));
      },
    );
    test('moving a task tree preserves ownership and evaluates delay on the local end date', () async {
      final project = await run('project.create', {
        'name': '上线',
        'targetDate': '2026-10-13',
      });
      final projectId = project['id'] as String;
      final folder = await run('project.folder.save', {
        'name': '联调',
        'projectId': projectId,
      });
      final parent = await run('task.create', {
        'title': '原有任务',
        'plannedStartAt': '2026-10-13T15:30:00Z',
        'plannedEndAt': '2026-10-13T16:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      });
      final child = await run('task.create', {
        'title': '已有子任务',
        'parentTaskId': parent['id'],
      });
      await run('project.moveTask', {
        'id': parent['id'],
        'expectedUpdatedAt': parent['updatedAt'],
        'projectId': projectId,
        'folderId': folder['id'],
      });
      for (final task in [parent, child]) {
        final saved = object(
          await store.get(
            host.instances['app.tasks']!.actor,
            'tasks',
            task['id'] as String,
          ),
        );
        expect(saved['projectId'], projectId);
        expect(saved['folderId'], folder['id']);
      }
      expect(objects((await board())['candidates']), isEmpty);
      expect(
        nodes(await page(projectId))
            .any((n) => n['text'].toString().contains('预计延期 1 天')),
        isTrue,
      );
    });
    test('folder moves reject cycles and cross-project parents', () async {
      final p = (await run('project.create', {'name': '项目'}))['id'];
      final parent = await run('project.folder.save', {
        'name': '外层',
        'projectId': p,
      });
      final child = await run('project.folder.save', {
        'name': '内层',
        'parentId': parent['id'],
        'projectId': p,
      });
      await expectLater(
        run('project.folder.save', {
          'name': '外层',
          'projectId': p,
          'id': parent['id'],
          'expectedUpdatedAt': parent['updatedAt'],
          'parentId': child['id'],
        }),
        throwsA(anything),
      );
      await expectLater(
        run('project.create', {'name': '错误位置', 'folderId': parent['id']}),
        throwsA(anything),
      );
    });
    test('closure rounds and task membership survive same-tick commits, undo and moves', () async {
      final p =
          (await run('project.create', {
                'name': '客户交接',
                'targetDate': '2026-10-14',
              }))['id']
              as String;
      final q = (await run('project.create', {'name': '外部项目'}))['id'] as String;
      final a = await run('task.create', {'title': 'A', 'projectId': p});
      final folder = await run('project.folder.save', {
        'name': '交接附件',
        'projectId': p,
      });
      final actor = host.instances['app.tasks']!.actor;
      final old = await saved('projects', p);
      final early = await host.prepare(
        actor,
        const ServiceRef('app.tasks', 'task.create', 1),
        {'title': '并行任务', 'projectId': p},
      );
      host.review(early.id, actor);
      final first = await run('project.edit', {
        'id': p,
        'expectedUpdatedAt': old['updatedAt'],
        'completedOn': '2026-10-13',
      });
      await expectLater(
        host.commit(actor, early.id),
        throwsA(isA<StateError>()),
      );
      expect(activityRows(await root()).map((n) => n['title']), ['外部项目']);

      await run('project.outline', {
        'projectId': p,
        'folderId': folder['id'],
        'items': [
          {
            'title': 'B',
            'path': ['子分类'],
          },
          {'title': 'C', 'estimatedMinutes': 15},
        ],
      });
      var rows = activityRows(await root());
      expect(rows.first['subtitle'], contains('完结 · 新增待办 2 项'));
      expect(
        nodes(await page(p)).where((n) => n['title'] == 'B'),
        hasLength(1),
      );
      expect(
        nodes(await page(p)).map((n) => n['title']),
        containsAll(['完结后新增待办', 'A']),
      );
      final all = objects(await store.query(actor, 'tasks', {'limit': 100}));
      final b = all.singleWhere((task) => task['title'] == 'B'),
          c = all.singleWhere((task) => task['title'] == 'C');
      await run('task.setCompleted', {'id': b['id'], 'completed': true});
      await run('task.setCompleted', {'id': c['id'], 'completed': true});
      expect(activityRows(await root()).map((n) => n['title']), ['外部项目']);
      await run('task.undoCompletion', {
        'id': c['id'],
        'expectedUpdatedAt': (await saved('tasks', c['id']))['updatedAt'],
      });
      expect(
        activityRows(await root()).first['subtitle'],
        contains('新增待办 1 项'),
      );
      final activeC = await saved('tasks', c['id']);
      for (final flags in [
        {'archivedAt': '2026-10-13T00:00:00.000Z'},
        {'deletedAt': '2026-10-13T00:00:00.000Z'},
      ]) {
        final inactive = {...activeC, ...flags};
        await run('task.restore', {
          'id': c['id'],
          'expected': activeC,
          'value': inactive,
        });
        expect(activityRows(await root()).map((n) => n['title']), ['外部项目']);
        await run('task.restore', {
          'id': c['id'],
          'expected': inactive,
          'value': activeC,
        });
        expect(
          activityRows(await root()).first['subtitle'],
          contains('新增待办 1 项'),
        );
      }
      await run('project.moveTask', {
        'id': c['id'],
        'expectedUpdatedAt': activeC['updatedAt'],
        'projectId': p,
        'folderId': null,
      });
      expect(
        activityRows(await root()).first['subtitle'],
        contains('新增待办 1 项'),
      );
      await run('project.moveTask', {
        'id': c['id'],
        'expectedUpdatedAt': (await saved('tasks', c['id']))['updatedAt'],
        'projectId': q,
      });
      expect(activityRows(await root()).map((n) => n['title']), ['外部项目']);
      await run('project.moveTask', {
        'id': c['id'],
        'expectedUpdatedAt': (await saved('tasks', c['id']))['updatedAt'],
        'projectId': p,
      });
      expect(
        activityRows(await root())
            .singleWhere((row) => row['title'] == '客户交接')['subtitle'],
        contains('新增待办 1 项'),
      );

      final reopened = await run('project.edit', {
        'id': p,
        'expectedUpdatedAt': first['updatedAt'],
        'completedOn': null,
      });
      final second = await run('project.edit', {
        'id': p,
        'expectedUpdatedAt': reopened['updatedAt'],
        'completedOn': '2026-10-13',
      });
      expect(second['completionRound'], isNot(first['completionRound']));
      expect(activityRows(await root()).map((n) => n['title']), ['外部项目']);
      expect((await saved('tasks', a['id']))['completedAt'], isNull);
      expect(second['completedOn'], '2026-10-13');
    });

    test('activity uses commit time, sorts both ways and restores only the undone contribution', () async {
      final p = (await run('project.create', {'name': '甲项目'}))['id'] as String;
      final q = (await run('project.create', {'name': '乙项目'}))['id'] as String;
      await run('project.create', {'name': '空项目'});
      final actor = host.instances['app.tasks']!.actor;
      host.clockNow = () => DateTime.utc(2025, 12, 31, 10);
      final plan = await host.prepare(
        actor,
        const ServiceRef('app.tasks', 'task.create', 1),
        {'title': '初始任务', 'projectId': p},
      );
      host.review(plan.id, actor);
      host.clockNow = () => DateTime.utc(2025, 12, 31, 11);
      final a = object(await host.commit(actor, plan.id));
      expect(await host.commit(actor, plan.id), a);
      host.clockNow = () => DateTime.utc(2026, 1, 1, 1);
      final b = await run('task.create', {'title': '另一项', 'projectId': q});
      expect(activityRows(await root()).map((n) => n['title']), [
        '乙项目',
        '甲项目',
        '空项目',
      ]);
      final oldest = await root(event: {'type': 'sort', 'order': 'oldest'});
      expect(activityRows(oldest).map((n) => n['title']), [
        '甲项目',
        '乙项目',
        '空项目',
      ]);
      expect(
        activityRows(await root()).first['subtitle'],
        contains('2025/12/31 19:00'),
      );
      expect(activityRows(await root()).last['subtitle'], contains('暂无推进记录'));
      host.clockNow = () => DateTime.utc(2026, 1, 1, 2);
      final pick = await run('project.pick', {
        'projectId': p,
        'queued': true,
        'tasks': [
          {'id': a['id'], 'expectedUpdatedAt': a['updatedAt']},
        ],
      });
      expect(activityRows(await root()).map((n) => n['title']), [
        '乙项目',
        '甲项目',
        '空项目',
      ]);
      host.clockNow = () => DateTime.utc(2026, 1, 1, 3);
      final later = await run('task.create', {'title': '稍后新增', 'projectId': p});
      await run('project.pick.undo', {
        'projectId': p,
        'tasks': pick['tasks'],
        'undoId': pick['undoId'],
      });
      expect(activityRows(await root()).last['title'], '空项目');
      expect(
        activityRows(await root())[1]['subtitle'],
        contains('01/01 11:00'),
      );
      final journal = objects(
        await store.query(actor, 'projectActivity', {'limit': 100}),
      );
      expect(journal.any((entry) => entry['id'] == pick['undoId']), isFalse);
      final qOriginal = await saved('projects', q);
      await run('project.edit', {
        'id': q,
        'expectedUpdatedAt': qOriginal['updatedAt'],
        'name': '乙重命名',
        'importance': 2,
      });
      await root(event: {'type': 'pin', 'kind': 'project', 'id': q});
      expect(
        activityRows(await root()).first['subtitle'],
        contains('01/01 09:00'),
      );
      host.clockNow = () => DateTime.utc(2026, 1, 1, 4);
      await run('task.updateFields', {
        'id': b['id'],
        'changes': {
          'plannedStartAt': '2026-02-05T00:00:00.000Z',
          'plannedEndAt': '2026-02-05T00:15:00.000Z',
          'plannedTimezone': 'Asia/Shanghai',
        },
      });
      expect(
        activityRows(await root())[1]['subtitle'],
        contains('01/01 12:00'),
      );
      await run('task.setCompleted', {'id': later['id'], 'completed': true});
      final completed = await saved('tasks', later['id']);
      host.clockNow = () => DateTime.utc(2026, 1, 1, 5);
      await run('task.setCompleted', {'id': later['id'], 'completed': true});
      expect(await saved('tasks', later['id']), completed);
      await run('task.undoCompletion', {
        'id': later['id'],
        'expectedUpdatedAt': completed['updatedAt'],
      });
      expect(
        activityRows(await root()).first['subtitle'],
        contains('01/01 11:00'),
      );
    });
  });

  test('legacy migration uses commit history for same-day membership and pages through tasks', () async {
    final current = await sourcePackage('app.tasks');
    final definition = Map<String, Object?>.of(current.definition)
      ..remove('migrations');
    definition['manifest'] = {
      ...object(definition['manifest']),
      'version': '1.8.1',
      'dataVersion': 1,
    };
    definition['collections'] = objects(definition['collections'])
        .where((c) => c['id'] != 'projectActivity')
        .toList();
    final old = await ScriptPackage.verify(
      await ScriptPackage.build(definition, current.scripts),
      allowUnsignedLocal: true,
    );
    await host.install(old);
    final actor = host.instances['app.tasks']!.actor;
    Future<void> write(
      String collection,
      List<Map<String, Object?>> values, {
      bool audit = true,
    }) async {
      final session = SnapshotSession(
        actor,
        'legacy-${values.first['id']}-${host.clockNow().toIso8601String()}',
      );
      await store.stage(session, actor, {
        'writes': [
          for (final value in values)
            {'collection': collection, 'id': value['id'], 'value': value},
        ],
      });
      await store.commit(
        store.seal(session).id,
        actor,
        authorize: (_) {},
        clock: host.clockNow,
        audit: audit,
      );
    }

    final p = {
      'id': 'closed',
      'name': '旧完结项目',
      'createdAt': '2026-10-12T00:00:00.000Z',
      'updatedAt': '2026-10-12T00:00:00.000Z',
    };
    await write('projects', [
      p,
      {
        'id': 'unknown',
        'name': '仅有普通更新',
        'updatedAt': '2026-10-13T22:00:00.000Z',
      },
    ]);
    final a = {
      'id': 'before',
      'projectId': 'closed',
      'title': '旧成员',
      'createdAt': '2026-10-13T00:00:00.000Z',
      'updatedAt': '2026-10-13T00:00:00.000Z',
    };
    await write('tasks', [a]);
    host.clockNow = () => DateTime.utc(2026, 10, 13, 1);
    await write('projects', [
      {
        ...p,
        'completedOn': '2026-10-13',
        'updatedAt': '2026-10-13T01:00:00.000Z',
      },
    ]);
    host.clockNow = () => DateTime.utc(2026, 10, 13, 2);
    final b = {
      ...a,
      'id': 'after',
      'title': '同日变更已有证据',
      'createdAt': '2026-10-13T02:00:00.000Z',
      'updatedAt': '2026-10-13T02:00:00.000Z',
    };
    await write('tasks', [b]);
    final queued = {
      ...a,
      'id': 'zzz-new',
      'title': '第二页任务',
      'createdAt': '2026-10-14T00:00:00.000Z',
      'updatedAt': '2026-10-14T00:00:00.000Z',
      'projectQueued': true,
    };
    await write('tasks', [
      for (var index = 0; index < 1000; index++) {...a, 'id': 'filler-$index'},
      queued,
    ], audit: false);
    await host.install(current);
    final rows = activityRows(await root());
    expect(rows.first['subtitle'], contains('新增待办 2 项'));
    expect(rows.first['subtitle'], contains('10/13 10:00'));
    expect(rows.last['subtitle'], contains('暂无推进记录'));
    expect(await saved('tasks', 'zzz-new'), queued);
    expect((await saved('projects', 'closed'))['completedOn'], '2026-10-13');
    final migrated = await saved('projectActivity', 'legacy:closed');
    expect(migrated['legacyJoins'], unorderedEquals(['after', 'zzz-new']));
    await host.install(current);
    expect(await saved('projectActivity', 'legacy:closed'), migrated);
  });
}
