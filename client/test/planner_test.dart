import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:task_app/core/module_host/script_page.dart';
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
  Future<Object?> query(String id, [Map<String, Object?> input = const {}]) =>
      host.query(actor(), ServiceRef('app.planner', 'planner.$id', 1), input);
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

  Map<String, Object?> rule(
    String id, {
    String kind = 'once',
    int minutes = 30,
  }) => {
    'id': id,
    'title': id,
    'kind': kind,
    'startDate': '2026-10-13',
    'endDate': '2026-10-26',
    'timezone': 'Asia/Shanghai',
    'estimatedMinutes': minutes,
    'times': [
      {'start': '18:00', 'end': '22:00'},
    ],
  };
  Future<void> available() async {
    await run('availability.save', {
      'availability': {
        'timezone': 'Asia/Shanghai',
        'bufferMinutes': 10,
        'weekly': {
          for (var i = 1; i <= 7; i++)
            '$i': [
              {'start': '18:00', 'end': '22:00'},
            ],
        },
      },
    });
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
  test(
    'no availability is not all-day free; limit and stable weekly expansion',
    () async {
      await run('rules.save', {
        'rules': [
          {
            ...rule('weekly', kind: 'weekly'),
            'perWeek': 2,
            'weekdays': [2, 3, 4, 5, 6],
          },
        ],
      });
      final p = object(await query('plan.preview', {'days': 6}));
      expect(p['assigned'], isEmpty);
      expect(p['unassigned'], hasLength(2));
      expect(p['warnings'], contains('未计入课程'));
      await available();
      final a = object(await query('plan.preview', {'days': 6}));
      final b = object(await query('plan.preview', {'days': 6}));
      expect(a, b);
      final items = (a['assigned'] as List).map(object).toList();
      expect(items, hasLength(2));
      expect(items[0]['date'], isNot(items[1]['date']));
      await expectLater(query('plan.preview', {'days': 29}), throwsA(anything));
    },
  );
  test('interval recalibrates from actual completion and reopening restores original anchor', () async {
    await available();
    await run('rules.save', {
      'rules': [
        {
          ...rule('interval', kind: 'interval'),
          'lastCompletedOn': '2026-10-13',
          'maxGapDays': 6,
          'earlyDays': 2,
        },
      ],
    });
    var candidates =
        object(await query('candidates.list', {'days': 7}))['candidates']
            as List;
    expect(object(candidates.first)['startDate'], '2026-10-17');
    expect(object(candidates.first)['endDate'], '2026-10-19');
    final id = object(candidates.first)['id'];
    final preview = object(
      await query('plan.preview', {
        'days': 7,
        'selectedIds': [id],
        'overrides': {
          id: {'date': '2026-10-17', 'start': '18:00', 'end': '18:30'},
        },
      }),
    );
    await run('batch.apply', {
      'batchKey': 'interval-batch',
      'preview': preview,
    });
    candidates =
        object(await query('candidates.list', {'days': 7}))['candidates']
            as List;
    final taskId = object(candidates.first)['taskId'];
    await run('task.setCompleted', {
      'id': taskId,
      'completed': true,
      'actualCompletedOn': '2026-10-17',
      'completedTimezone': 'Asia/Shanghai',
    }, module: 'app.tasks');
    candidates =
        object(await query('candidates.list', {'days': 14}))['candidates']
            as List;
    final pending = candidates
        .map(object)
        .firstWhere((c) => c['status'] == 'pending');
    expect(pending['startDate'], '2026-10-21');
    expect(pending['endDate'], '2026-10-23');
    await run('task.setCompleted', {
      'id': taskId,
      'completed': false,
    }, module: 'app.tasks');
    candidates =
        object(await query('candidates.list', {'days': 7}))['candidates']
            as List;
    expect(
      candidates.map(object).firstWhere((c) => c['id'] == id)['endDate'],
      '2026-10-19',
    );
  });
  test('batch is idempotent across restart, atomic, and conditional undo protects edits', () async {
    await available();
    await run('rules.save', {
      'rules': [rule('a'), rule('b')],
    });
    final p = object(await query('plan.preview'));
    await run('batch.apply', {'batchKey': 'batch', 'preview': p});
    await host.close();
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 10, 13);
    await run('batch.apply', {'batchKey': 'batch', 'preview': p});
    var tasks = await host.query(
      actor(),
      ServiceRef('app.tasks', 'task.list', 1),
      {'view': 'raw'},
    );
    expect(tasks, hasLength(2));
    final batch = object((await query('batch.list') as List).single);
    expect(
      (batch['changes'] as List)
          .map(object)
          .every((x) => object(x['after'])['id'] == x['taskId']),
      isTrue,
    );
    await run('batch.undo', {'id': 'batch'});
    tasks = await host.query(actor(), ServiceRef('app.tasks', 'task.list', 1), {
      'view': 'raw',
    });
    expect(tasks, isEmpty);
    final p2 = object(await query('plan.preview'));
    await run('batch.apply', {'batchKey': 'batch2', 'preview': p2});
    final rows = await host.query(
      actor(),
      ServiceRef('app.tasks', 'task.list', 1),
      {'view': 'raw'},
    ) as List;
    await run('task.updateFields', {
      'id': object(rows.first)['id'],
      'changes': {'title': 'edited'},
    }, module: 'app.tasks');
    await expectLater(run('batch.undo', {'id': 'batch2'}), throwsA(anything));
    expect(
      await host.query(actor(), ServiceRef('app.tasks', 'task.list', 1), {
        'view': 'raw',
      }),
      hasLength(2),
    );
  });
  test('existing tasks retain IDs and date-only undo; stale previews reject whole batch', () async {
    await available();
    final t = object(
      await run('task.create', {
        'title': 'existing',
        'plannedDate': '2026-10-14',
      }, module: 'app.tasks'),
    );
    await run('occurrence.update', {
      'taskId': t['id'],
      'window': {
        'startDate': '2026-10-13',
        'endDate': '2026-10-19',
        'times': [
          {'start': '18:00', 'end': '22:00'},
        ],
      },
    });
    final p = object(
      await query('plan.preview', {
        'selectedIds': ['task:${t['id']}'],
      }),
    );
    await run('task.updateFields', {
      'id': t['id'],
      'changes': {'priority': 2},
    }, module: 'app.tasks');
    await expectLater(
      run('batch.apply', {'batchKey': 'stale', 'preview': p}),
      throwsA(anything),
    );
    expect(await query('batch.list'), isEmpty);
    final fresh = object(
      await query('plan.preview', {
        'selectedIds': ['task:${t['id']}'],
      }),
    );
    await run('batch.apply', {'batchKey': 'existing', 'preview': fresh});
    var current = object(
      await host.query(actor(), ServiceRef('app.tasks', 'task.get', 1), {
        'id': t['id'],
      }),
    );
    expect(current['plannedStartAt'], isNotNull);
    expect(
      await host.query(actor(), ServiceRef('app.tasks', 'task.list', 1), {
        'view': 'raw',
      }),
      hasLength(1),
    );
    await run('batch.undo', {'id': 'existing'});
    current = object(
      await host.query(actor(), ServiceRef('app.tasks', 'task.get', 1), {
        'id': t['id'],
      }),
    );
    expect(current['plannedDate'], '2026-10-14');
    expect(current['plannedStartAt'], isNull);
  });
  test('200 item real QuickJS preview and prepare stay within host execution budget', () async {
    await available();
    await run('rules.save', {
      'rules': [for (var i = 0; i < 200; i++) rule('rule-$i', minutes: 5)],
    });
    final watch = Stopwatch()..start();
    final p = object(await query('plan.preview', {'days': 28}));
    expect(p['assigned'], hasLength(200));
    expect(watch.elapsedMilliseconds, lessThan(10000));
    watch.reset();
    await run('batch.apply', {'batchKey': 'capacity', 'preview': p});
    expect(watch.elapsedMilliseconds, lessThan(10000));
  });
  test(
    'daily expiry, pause and version history preserve materialized instances',
    () async {
      await available();
      await run('rules.save', {
        'rules': [rule('daily', kind: 'daily')],
      });
      final p = object(await query('plan.preview', {'days': 1}));
      await run('batch.apply', {'batchKey': 'daily', 'preview': p});
      await run('rules.save', {
        'rules': [
          {
            ...rule('daily', kind: 'daily'),
            'status': 'paused',
            'expectedVersion': 1,
          },
        ],
      });
      final rules = await query('rules.list') as List;
      expect(object(rules.single)['versions'], hasLength(2));
      final cs =
          object(await query('candidates.list', {'days': 2}))['candidates']
              as List;
      expect(cs, hasLength(1));
      expect(object(cs.single)['status'], 'confirmed');
      host.clockNow = () => DateTime.utc(2026, 10, 14);
      expect(
        await host.query(actor(), ServiceRef('app.tasks', 'task.list', 1), {
          'view': 'today',
        }),
        isEmpty,
      );
    },
  );
  test(
    'commit after concurrent change rejects all staged task and planner writes',
    () async {
      await available();
      await run('rules.save', {
        'rules': [rule('atomic-a'), rule('atomic-b')],
      });
      final preview = object(await query('plan.preview'));
      final plan = await host.prepare(
        actor(),
        const ServiceRef('app.planner', 'planner.batch.apply', 1),
        {'batchKey': 'atomic', 'preview': preview},
      );
      await run('task.create', {'title': 'concurrent'}, module: 'app.tasks');
      host.review(plan.id, actor());
      await expectLater(host.commit(actor(), plan.id), throwsA(anything));
      expect(await query('batch.list'), isEmpty);
      final tasks = await host.query(
        actor(),
        const ServiceRef('app.tasks', 'task.list', 1),
        {'view': 'raw'},
      ) as List;
      expect(tasks, hasLength(1));
      expect(object(tasks.single)['title'], 'concurrent');
    },
  );
  test('new course occupancy invalidates preview, persists conflict, and is optional', () async {
    await available();
    await run('rules.save', {
      'rules': [rule('course-task')],
    });
    final preview = object(await query('plan.preview', {'days': 1}));
    await install('app.schedule');
    await run('schedule.timetable.save', {
      'timetable': {
        'id': 't',
        'name': '课程',
        'firstMonday': '2026-10-12',
        'totalWeeks': 2,
        'timezone': 'Asia/Shanghai',
        'displayWeekStart': 1,
        'periods': [
          {'number': 1, 'start': '18:00', 'end': '19:00'},
        ],
      },
    }, module: 'app.schedule');
    await run('schedule.course.save', {
      'course': {'id': 'course', 'timetableId': 't', 'name': '晚课'},
      'meeting': {
        'id': 'meeting',
        'weekday': 2,
        'startPeriod': 1,
        'endPeriod': 1,
        'weeks': [1],
      },
    }, module: 'app.schedule');
    await expectLater(
      run('batch.apply', {'batchKey': 'old-course', 'preview': preview}),
      throwsA(anything),
    );
    final revised = object(await query('plan.preview', {'days': 1}));
    expect(object((revised['assigned'] as List).single)['start'], '19:10');
    await run('batch.apply', {'batchKey': 'course', 'preview': revised});
    await run('schedule.timetable.save', {
      'timetable': {
        'id': 't',
        'name': '课程',
        'firstMonday': '2026-10-12',
        'totalWeeks': 2,
        'timezone': 'Asia/Shanghai',
        'displayWeekStart': 1,
        'periods': [
          {'number': 1, 'start': '18:00', 'end': '20:00'},
        ],
      },
    }, module: 'app.schedule');
    expect(
      object(await query('candidates.list', {'days': 1}))['conflicts'],
      isNotEmpty,
    );
  });
  test('confirmed skip removes generated schedule, keeps interval debt, and protects batch undo', () async {
    await available();
    await run('rules.save', {
      'rules': [
        {
          ...rule('skip-interval', kind: 'interval'),
          'lastCompletedOn': '2026-10-13',
          'maxGapDays': 6,
          'earlyDays': 2,
        },
      ],
    });
    final p = object(await query('plan.preview', {'days': 7}));
    await run('batch.apply', {'batchKey': 'skip-batch', 'preview': p});
    final candidates =
        object(await query('candidates.list', {'days': 7}))['candidates']
            as List;
    final c = object(candidates.first);
    await run('occurrence.update', {
      'id': c['id'],
      'changes': {'status': 'skipped'},
    });
    final refreshed =
        object(await query('candidates.list', {'days': 7}))['candidates']
            as List;
    final pending = object(refreshed.first);
    expect(pending['skipRecorded'], true);
    expect(pending['status'], 'pending');
    expect(pending['endDate'], '2026-10-19');
    expect(pending['taskId'], isNull);
    expect(
      await host.query(actor(), const ServiceRef('app.tasks', 'task.list', 1), {
        'view': 'raw',
      }),
      isEmpty,
    );
    await expectLater(
      run('batch.undo', {'id': 'skip-batch'}),
      throwsA(anything),
    );
  });
  test('editing only title in today retains confirmed precise plan', () async {
    await install('app.views.today');
    final t = object(
      await run('task.create', {
        'title': 'before',
        'plannedStartAt': '2026-10-13T10:00:00Z',
        'plannedEndAt': '2026-10-13T10:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      }, module: 'app.tasks'),
    );
    host.interaction = (_, method, args) async => method == 'ui.dialog'
        ? {
            'title': 'after',
            'priority': '0',
            'dueDate': '',
            'plannedDate': '2026-10-13',
          }
        : method == 'ui.review';
    await host.invokePage('app.views.today', 'render', {
      'state': {},
      'context': {'pageId': 'app.views.today.tasks'},
      'event': {'type': 'edit', 'task': t},
    });
    final changed = object(
      await host.query(actor(), const ServiceRef('app.tasks', 'task.get', 1), {
        'id': t['id'],
      }),
    );
    expect(changed['title'], 'after');
    expect(changed['plannedStartAt'], t['plannedStartAt']);
    expect(changed['plannedEndAt'], t['plannedEndAt']);
  });
  for (final width in [320.0, 1100.0]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
        'planner shared UI width $width $brightness with large text',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
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
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(
            find.text('待安排 · 0'),
            findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((x) => x.data ?? '')
                .join(' | '),
          );
          expect(find.text('统一安排'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  test('render uses the graphical board and stable root key', () async {
    final page = object(
      await host.invokePage('app.planner', 'render', {
        'state': {},
        'context': {'pageId': 'app.planner.home'},
      }),
    );
    expect(object(page['tree'])['type'], 'column');
    expect(object(page['header'])['title'], '任务规划');
  });
}
