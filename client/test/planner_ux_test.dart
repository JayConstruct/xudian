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
import 'package:task_app/core/performance/ui_load_trace.dart';
import 'package:task_app/core/ui/workspace_header.dart';
import 'package:task_app/app/workspace_popup_menu.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show table;

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

  Map<String, Object?> boardOptions(Map<String, Object?> rendered) => object(
    nodes(rendered['tree'])
        .singleWhere((n) => n['type'] == 'plannerBoard')['options'],
  );

  Future<void> scheduled(String title, String start, String end) async {
    await run('task.create', {
      'title': title,
      'plannedStartAt': start,
      'plannedEndAt': end,
      'plannedTimezone': 'Asia/Shanghai',
    }, module: 'app.tasks');
  }

  test(
    'automatic display fits visible tasks with an hour of padding',
    () async {
      expect(boardOptions(await page())['startMinute'], 480);
      expect(boardOptions(await page())['endMinute'], 1320);
      await scheduled('上午', '2026-10-13T01:15:00Z', '2026-10-13T02:30:00Z');
      await scheduled('晚上', '2026-10-14T12:00:00Z', '2026-10-14T13:15:00Z');
      final options = boardOptions(await page());
      expect(options['startMinute'], 480);
      expect(options['endMinute'], 1380);
      final empty = boardOptions(
        await page(state: {'startDate': '2026-11-01'}),
      );
      expect(empty['startMinute'], 480);
      expect(empty['endMinute'], 1320);
    },
  );

  test('automatic display includes both sides of overnight tasks', () async {
    await scheduled('跨夜', '2026-10-13T15:30:00Z', '2026-10-13T17:00:00Z');
    final options = boardOptions(await page());
    expect(options['startMinute'], 0);
    expect(options['endMinute'], 1440);
    final firstDay = boardOptions(
      await page(state: {'startDate': '2026-10-13', 'days': 1}),
    );
    expect(firstDay['startMinute'], 1320);
    expect(firstDay['endMinute'], 1440);
    final secondDay = boardOptions(
      await page(state: {'startDate': '2026-10-14', 'days': 1}),
    );
    expect(secondDay['startMinute'], 0);
    expect(secondDay['endMinute'], 120);
  });

  test(
    'manual bounds and full day persist across fresh page sessions',
    () async {
      var mode = 'manual';
      var bounds = <String, Object?>{'start': '07:30', 'end': '24:00'};
      host.interaction = (_, method, args) async {
        if (method != 'ui.dialog') {
          fail('Display settings must not request a business review');
        }
        return args['title'] == '表格显示时段' ? {'mode': mode} : bounds;
      };
      var result = await page(event: {'type': 'displayHours'});
      expect(boardOptions(result)['startMinute'], 450);
      expect(boardOptions(result)['endMinute'], 1440);
      expect(boardOptions(await page())['startMinute'], 450);
      bounds = {'start': '22:00', 'end': '08:00'};
      result = await page(event: {'type': 'displayHours'});
      expect(object(result['state'])['error'], contains('结束必须晚于开始'));
      expect(boardOptions(await page())['startMinute'], 450);
      mode = 'full';
      await page(event: {'type': 'displayHours'});
      expect(boardOptions(await page())['startMinute'], 0);
      expect(boardOptions(await page())['endMinute'], 1440);
      mode = 'auto';
      await page(event: {'type': 'displayHours'});
      expect(boardOptions(await page())['startMinute'], 480);
    },
  );

  test('canceling manual bounds leaves the saved display unchanged', () async {
    host.interaction = (_, method, args) async =>
        args['title'] == '表格显示时段' ? {'mode': 'manual'} : null;
    await page(event: {'type': 'displayHours'});
    expect(boardOptions(await page())['displayHoursLabel'], startsWith('自动'));
  });

  test('render bridge counts stay bounded by the visible workload', () async {
    final taskActor = host.instances['app.tasks']!.actor;
    final fixture = SnapshotSession(taskActor, 'render-workload');
    await store.stage(fixture, taskActor, {
      'writes': [
        for (var i = 0; i < 130; i++)
          {
            'collection': 'tasks',
            'id': 'render-task-$i',
            'value': {
              'id': 'render-task-$i',
              'title': '性能任务$i',
              'priority': 0,
              'estimatedMinutes': 30,
              'dueDate': '2026-10-20',
              'dueAt': '2026-10-20T12:00:00Z',
              'dueTimezone': 'UTC',
              'createdAt': '2026-10-13T00:00:00Z',
              'updatedAt': '2026-10-13T00:00:00Z',
              if (i < 100) ...{
                'plannedDate': '2026-10-14',
                'plannedStartAt': '2026-10-14T01:00:00Z',
                'plannedEndAt': '2026-10-14T01:30:00Z',
                'plannedTimezone': 'Asia/Shanghai',
              },
            },
          },
      ],
    });
    await store.commit(
      store.seal(fixture).id,
      taskActor,
      authorize: (_) {},
      audit: false,
    );
    final counts = <String, Map<String, int>>{};
    final samples = <UiLoadSample>[];
    await host.close();
    await UiLoadTrace.observe(() async {
      host = ModuleHost(store: store, directory: folder);
      host.clockNow = () => DateTime.utc(2026, 10, 13);
      await host.initialize();
      for (final workload in <String, Map<String, Object?>>{
        'board': {},
        'history': {
          'history': true,
          'boardVersions': {
            'prior-task': {'revisionToken': 'prior-revision'},
          },
        },
        'preview': {
          'autoPreview': {
            'assigned': [],
            'unassigned': [],
            'warnings': [],
            'conflicts': [],
          },
        },
      }.entries) {
        samples.clear();
        final rendered = await page(state: workload.value);
        if (workload.key == 'history') {
          expect(
            object(rendered['state'])['boardVersions'],
            workload.value['boardVersions'],
          );
        }
        final methods = <String, int>{};
        for (final sample in samples.where((s) => s.name == 'page.bridge')) {
          final method =
              '${sample.arguments['moduleId']}/${sample.arguments['method']}';
          methods.update(method, (n) => n + 1, ifAbsent: () => 1);
        }
        counts[workload.key] = methods;
      }
    }, samples.add);
    debugPrint('planner render bridge counts: ${jsonEncode(counts)}');
    expect(counts['board']!['app.planner/services.query'], 3);
    expect(counts['board']!['app.tasks/data.query'], 1);
    expect(counts['board']!['app.planner/clock.today'], 2);
    expect(counts['board']!['app.planner/clock.toUtc'], 2);
    for (final name in ['history', 'preview']) {
      expect(
        counts[name]!.keys.any((key) => key.startsWith('app.tasks/')),
        false,
      );
      expect(counts[name]!['app.planner/clock.toLocalMany'], isNull);
      expect(counts[name]!['app.planner/clock.toUtc'], isNull);
    }
    expect(counts['history']!['app.planner/services.query'], 2);
    expect(counts['preview']!['app.planner/services.query'], 1);
  });

  test(
    'course metadata reaches board blocks without copying task descriptions',
    () async {
      await install('app.schedule');
      await run('schedule.timetable.save', {
        'timetable': table('metadata-table'),
      }, module: 'app.schedule');
      await run('schedule.course.save', {
        'course': {
          'id': 'metadata-course',
          'timetableId': 'metadata-table',
          'name': '真实地点课程',
        },
        'meeting': {
          'id': 'metadata-meeting',
          'weekday': 2,
          'startPeriod': 1,
          'endPeriod': 1,
          'weeks': [2],
          'location': ' 教学楼 A301 ',
          'teacher': ' 陈老师 ',
        },
      }, module: 'app.schedule');
      await run('schedule.course.save', {
        'course': {
          'id': 'empty-course',
          'timetableId': 'metadata-table',
          'name': '没有地点课程',
        },
        'meeting': {
          'id': 'empty-meeting',
          'weekday': 3,
          'startPeriod': 1,
          'endPeriod': 1,
          'weeks': [2],
        },
      }, module: 'app.schedule');
      await run('task.create', {
        'title': '真实任务',
        'notes': '任意详细描述不作为块内地点',
        'plannedStartAt': '2026-10-13T10:00:00Z',
        'plannedEndAt': '2026-10-13T11:00:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      }, module: 'app.tasks');
      final busy = object(
        await host.query(
          actor(),
          const ServiceRef('app.schedule', 'schedule.query.busy', 1),
          {'startDate': '2026-10-13', 'endDate': '2026-10-14'},
        ),
      );
      final course = (busy['items'] as List)
          .map(object)
          .singleWhere((item) => item['title'] == '真实地点课程');
      expect(course['location'], '教学楼 A301');
      expect(course['teacher'], '陈老师');
      final boardData = object(
        await host.query(
          actor(),
          const ServiceRef('app.planner', 'planner.board.get', 1),
          {'startDate': '2026-10-13', 'days': 5},
        ),
      );
      final storedBlock = (boardData['busy'] as List)
          .map(object)
          .singleWhere((item) => item['title'] == '真实地点课程');
      expect(storedBlock['location'], course['location']);
      expect(storedBlock['teacher'], course['teacher']);
      final rendered = await page();
      final board = nodes(rendered['tree'])
          .singleWhere((n) => n['type'] == 'plannerBoard');
      final blocks = (board['blocks'] as List).map(object).toList();
      final block = blocks.singleWhere((item) => item['title'] == '真实地点课程');
      expect(block['location'], course['location']);
      expect(block['teacher'], course['teacher']);
      expect(block['readOnly'], true);
      final empty = blocks.singleWhere((item) => item['title'] == '没有地点课程');
      expect(empty.containsKey('location'), false);
      expect(empty.containsKey('teacher'), false);
      final taskBlock = blocks.singleWhere((item) => item['title'] == '真实任务');
      expect(taskBlock.containsKey('location'), false);
      expect(taskBlock.containsKey('notes'), false);
      expect(jsonEncode(board), isNot(contains('任意详细描述不作为块内地点')));
    },
  );

  Future<void> settlePlanner(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<WorkspaceHeaderController> showPlanner(
    WidgetTester tester, {
    bool withMenu = false,
  }) async {
    final headers = WorkspaceHeaderController();
    addTearDown(headers.dispose);
    headers.activate(
      identity: 'planner-widget-test',
      moduleId: 'app.planner',
      pageId: 'app.planner.home',
      enabled: true,
      isActive: () => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: withMenu
              ? AppBar(
                  actions: [
                    AnimatedBuilder(
                      animation: headers,
                      builder: (context, _) => WorkspacePopupMenu(
                        headerController: headers,
                        headerOwner: headers.content?.owner,
                        headerLease: headers.lease,
                        items: const [
                          PopupMenuItem(value: -1, child: Text('设置')),
                        ],
                        onSelected: (_) {},
                      ),
                    ),
                  ],
                )
              : null,
          body: WorkspaceHeaderScope(
            controller: headers,
            lease: headers.lease,
            child: ScriptPage(
              host: host,
              moduleId: 'app.planner',
              handler: 'render',
              pageContext: const {'pageId': 'app.planner.home'},
            ),
          ),
        ),
      ),
    );
    await settlePlanner(tester);
    return headers;
  }

  testWidgets(
    'real planner updates open submenu and preserves rapid zoom steps',
    (tester) async {
      final headers = await showPlanner(tester, withMenu: true);
      await tester.tap(find.byTooltip('页面菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('视图与显示'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3列'));
      await settlePlanner(tester);
      final board = tester.widget<PlannerBoard>(find.byType(PlannerBoard));
      expect(board.days, hasLength(21));
      expect(board.options['visibleDays'], 3);
      final view = (headers.content!.spec['actions'] as List)
          .map(object)
          .singleWhere((action) => action['label'] == '视图与显示');
      final grid = (view['children'] as List).map(object).first;
      expect(
        (grid['children'] as List)
            .map(object)
            .singleWhere((choice) => choice['label'] == '3列')['selected'],
        isTrue,
      );
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('放大时间轴'));
      }
      // Each preference write also invalidates the real page. Wait for the
      // serialized actions and their refreshes rather than a fixed one-frame
      // timing assumption on a busy test worker.
      for (var attempt = 0; attempt < 8; attempt++) {
        await settlePlanner(tester);
        if (tester
                .widget<PlannerBoard>(find.byType(PlannerBoard))
                .options['pixelsPerMinute'] ==
            3) {
          break;
        }
      }
      expect(
        tester
            .widget<PlannerBoard>(find.byType(PlannerBoard))
            .options['pixelsPerMinute'],
        3,
      );
      expect(find.text('最大'), findsOneWidget);
      expect(find.text('显示列数'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('history renders a real move and clicking undo restores it', (
    tester,
  ) async {
    late Map<String, Object?> original;
    await tester.runAsync(() async {
      original = object(
        await run('task.create', {
          'title': '可视历史撤销',
          'plannedStartAt': '2026-10-14T10:00:00Z',
          'plannedEndAt': '2026-10-14T10:30:00Z',
          'plannedTimezone': 'Asia/Shanghai',
        }, module: 'app.tasks'),
      );
      final preview = object(
        await host.query(
          actor(),
          const ServiceRef('app.planner', 'planner.operation.preview', 1),
          {
            'kind': 'move',
            'taskId': original['id'],
            'date': '2026-10-14',
            'start': '19:00',
            'endDate': '2026-10-14',
            'end': '19:30',
            'timezone': 'Asia/Shanghai',
          },
        ),
      );
      await run('operation.apply', {
        'operationKey': 'visible-move',
        'preview': preview,
      });
    });
    var reviews = 0;
    host.interaction = (_, method, args) async {
      if (method == 'ui.review') reviews++;
      return true;
    };
    final headers = await showPlanner(tester);
    final historyAction = (headers.content!.spec['actions'] as List)
        .map(object)
        .singleWhere((action) => action['label'] == '操作历史');
    await tester.runAsync(
      () => headers.content!.dispatch(historyAction['event']),
    );
    await settlePlanner(tester);
    expect(headers.content!.spec['title'], '操作历史');
    expect(find.text('点击撤销整次操作'), findsOneWidget);
    expect(find.textContaining('模块界面无效'), findsNothing);
    await tester.tap(find.text('点击撤销整次操作'));
    await settlePlanner(tester);
    expect(find.text('已撤销'), findsOneWidget);
    expect(reviews, 1);
    await tester.runAsync(() async {
      final restored = object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': original['id']},
        ),
      );
      expect(restored['plannedStartAt'], original['plannedStartAt']);
      expect(restored['plannedEndAt'], original['plannedEndAt']);
    });
    expect(object(headers.content!.spec['backEvent'])['type'], 'board');
    await tester.runAsync(
      () => headers.content!.dispatch(headers.content!.spec['backEvent']),
    );
    await settlePlanner(tester);
    expect(find.byType(PlannerBoard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('candidate selection and arrangement preview render and apply', (
    tester,
  ) async {
    late Map<String, Object?> original;
    await tester.runAsync(() async {
      await run('availability.save', {
        'availability': {
          'bufferMinutes': 0,
          'weekly': {
            for (var day = 1; day <= 7; day++)
              '$day': [
                {'start': '09:00', 'end': '17:00'},
              ],
          },
        },
      });
      original = object(
        await run('task.create', {
          'title': '真实预览任务',
          'dueDate': '2026-10-17',
        }, module: 'app.tasks'),
      );
    });
    host.interaction = (_, method, args) async => method == 'ui.review';
    final headers = await showPlanner(tester);
    final autoAction = (headers.content!.spec['actions'] as List)
        .map(object)
        .singleWhere((action) => action['label'] == '自动安排');
    await tester.runAsync(() => headers.content!.dispatch(autoAction['event']));
    await settlePlanner(tester);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.textContaining('模块界面无效'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await settlePlanner(tester);
    await tester.tap(find.text('预览安排（1项）'));
    await settlePlanner(tester);
    expect(headers.content!.spec['title'], '安排预览');
    expect(find.text('建议预览 · 1项安排 · 0项待安排'), findsOneWidget);
    expect(find.text('真实预览任务'), findsOneWidget);
    expect(find.textContaining('模块界面无效'), findsNothing);
    await tester.tap(find.text('确认安排'));
    await settlePlanner(tester);
    expect(find.byType(PlannerBoard), findsOneWidget);
    await tester.runAsync(() async {
      final arranged = object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': original['id']},
        ),
      );
      expect(arranged['plannedStartAt'], isNotNull);
      expect(arranged['plannedEndAt'], isNotNull);
      expect(arranged['dueDate'], original['dueDate']);
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'quick-add requests a compact panel and preserves expanded fields',
    () async {
      final presentations = <Map<String, Object?>>[];
      host.interaction = (_, method, arguments) async {
        if (method == 'ui.panel') {
          presentations.add(object(arguments['presentation']));
        }
        return true;
      };
      await page(event: {'type': 'add'});
      expect(presentations.single['heightFactor'], .94);
      var result = await page(pageId: 'app.planner.quickAdd');
      expect(object(result['tree'])['compact'], isTrue);
      expect(object(result['tree'])['spacing'], 8);
      result = await page(
        pageId: 'app.planner.quickAdd',
        state: object(result['state']),
        forms: {'title': '保留草稿'},
        event: {'type': 'description'},
      );
      expect(object(object(result['state'])['draft'])['title'], '保留草稿');
      expect(
        nodes(result['tree']).any((node) => node['key'] == 'notes'),
        isTrue,
      );
    },
  );

  testWidgets('quick-add save button fills the panel width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: const ValueKey('quick-add-panel'),
              width: 380,
              child: ScriptPage(
                host: host,
                moduleId: 'app.planner',
                handler: 'render',
                pageContext: const {'pageId': 'app.planner.quickAdd'},
              ),
            ),
          ),
        ),
      ),
    );
    await settlePlanner(tester);
    final save = find.widgetWithText(FilledButton, '保存任务');
    expect(save, findsOneWidget);
    final panelWidth = tester
        .getSize(find.byKey(const ValueKey('quick-add-panel')))
        .width;
    expect(tester.getSize(save).width, greaterThan(panelWidth * .85));
    expect(find.textContaining('模块界面无效'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'compact quick-add retains its draft in a short large-text viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                height: 330,
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: ScriptPage(
                    host: host,
                    moduleId: 'app.planner',
                    handler: 'render',
                    pageContext: const {'pageId': 'app.planner.quickAdd'},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settlePlanner(tester);
      await tester.enterText(find.byType(TextField).first, '窄屏草稿');
      await settlePlanner(tester);
      expect(
        find.widgetWithText(FilledButton, '保存任务').hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('添加规则'));
      expect(find.text('添加规则').hitTestable(), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '窄屏草稿',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'dashboard is the only home layout with compact header actions',
    () async {
      final rendered = await page(state: {'legacy': true});
      final tree = object(rendered['tree']);
      expect(tree['fillHeight'], true);
      expect(tree['footer'], isNull);
      final all = nodes(tree).toList();
      expect(all.where((n) => n['type'] == 'plannerBoard'), hasLength(1));
      expect(all.where((n) => n['type'] == 'checkbox'), isEmpty);
      expect(all.where((n) => n['type'] == 'tabs'), isEmpty);
      final board = all.singleWhere((n) => n['type'] == 'plannerBoard');
      final options = object(board['options']);
      expect(options['dashboard'], true);
      expect(options['rangeLabel'], '10月12日—14日');
      expect(options['periodLabel'], isNull);
      expect(options['visibleDays'], 3);
      expect(object(options['todayEvent'])['type'], 'today');
      expect(object(options['filterEvent'])['type'], 'onlyDeadline');
      final actions = (object(rendered['header'])['actions'] as List)
          .map(object)
          .toList();
      expect(
        actions
            .where((a) => a['presentation'] == 'inline')
            .map((a) => a['icon']),
        ['add'],
      );
      expect(actions.first['iconOnly'], true);
      expect(actions.first['overflowOnly'], true);
      expect(
        actions
            .where((a) => a['presentation'] == 'menu')
            .map((a) => a['label']),
        ['自动安排', '操作历史', '视图与显示', '待安排筛选', '规划规则', '规划设置'],
      );
      final view = actions.singleWhere((a) => a['label'] == '视图与显示');
      final choices = nodes(view).singleWhere((n) => n['kind'] == 'choiceGrid');
      expect((choices['children'] as List).map(object).map((c) => c['label']), [
        '1列',
        '3列',
        '5列',
        '7列',
      ]);
      expect(
        (choices['children'] as List)
            .map(object)
            .singleWhere((c) => c['selected'] == true)['label'],
        '3列',
      );
      expect(
        nodes(view).singleWhere((n) => n['label'] == '每日显示时段')['subtitle'],
        options['displayHoursLabel'],
      );
      expect(jsonEncode(rendered), isNot(contains('规划设置与持续规则')));
    },
  );

  test(
    'day shortcuts validate their bounds and keep the visible start date',
    () async {
      host.interaction = (_, method, args) async {
        fail('A day shortcut must not open a dialog or request a review');
      };
      var rendered = await page(
        state: {
          'startDate': '2026-10-18',
          'selected': ['preserved-selection'],
        },
      );
      for (final days in [1, 3, 5, 7]) {
        rendered = await page(
          state: object(rendered['state']),
          event: {'type': 'periodShortcut', 'days': days},
        );
        final board = nodes(rendered['tree'])
            .singleWhere((n) => n['type'] == 'plannerBoard');
        expect(board['days'], hasLength(21));
        expect(object(board['options'])['visibleDays'], days);
        expect(object(rendered['state'])['startDate'], '2026-10-18');
        expect(object(rendered['state'])['selected'], ['preserved-selection']);
      }
      for (final days in [0, 2, 28, 29, 1.5, '5']) {
        rendered = await page(
          state: object(rendered['state']),
          event: {'type': 'periodShortcut', 'days': days},
        );
        expect(object(rendered['state'])['error'], contains('1、3、5或7列'));
        expect(object(rendered['state'])['days'], 7);
      }
    },
  );

  test('zoom steps persist and stop at both bounds', () async {
    host.interaction = (_, method, args) async {
      fail('Zoom must not open a dialog or request a business review');
    };
    Map<String, Object?> zoomControl(Map<String, Object?> rendered) =>
        nodes(rendered['header']).singleWhere((n) => n['kind'] == 'stepper');
    expect(boardOptions(await page())['pixelsPerMinute'], 1.1);
    var rendered = await page(event: {'type': 'zoom', 'delta': -1});
    expect(boardOptions(rendered)['pixelsPerMinute'], .75);
    expect(zoomControl(rendered)['decreaseEnabled'], false);
    rendered = await page(event: {'type': 'zoom', 'delta': -1});
    expect(boardOptions(rendered)['pixelsPerMinute'], .75);
    for (final scale in [1.1, 1.5, 2, 3]) {
      rendered = await page(event: {'type': 'zoom', 'delta': 1});
      expect(boardOptions(rendered)['pixelsPerMinute'], scale);
    }
    expect(zoomControl(rendered)['increaseEnabled'], false);
    rendered = await page(event: {'type': 'zoom', 'delta': 1});
    expect(boardOptions(rendered)['pixelsPerMinute'], 3);
    expect(boardOptions(await page())['pixelsPerMinute'], 3);
    rendered = await page(event: {'type': 'zoom', 'delta': 99});
    expect(object(rendered['state'])['error'], contains('放大或缩小'));
    expect(boardOptions(rendered)['pixelsPerMinute'], 3);
  });

  test(
    'view and filter menu actions preserve task data and scheduled blocks',
    () async {
      final original = object(
        await run('task.create', {
          'title': '安排与截止保持',
          'dueDate': '2026-10-17',
          'dueTimezone': 'Asia/Shanghai',
          'plannedStartAt': '2026-10-13T02:00:00Z',
          'plannedEndAt': '2026-10-13T03:00:00Z',
          'plannedTimezone': 'Asia/Shanghai',
        }, module: 'app.tasks'),
      );
      await run('task.create', {'title': '无截止候选'});
      await run('task.create', {'title': '有截止候选', 'dueDate': '2026-10-17'});
      host.interaction = (_, method, args) async {
        if (method == 'ui.dialog') return {'mode': 'full'};
        fail('View and filter actions must not request a business review');
      };
      var rendered = await page();
      for (final event in [
        {'type': 'periodShortcut', 'days': 3},
        {'type': 'zoom', 'delta': 1},
        {'type': 'displayHours'},
        {'type': 'onlyDeadline', 'value': true},
      ]) {
        rendered = await page(state: object(rendered['state']), event: event);
        expect(object(rendered['state'])['error'], isNull);
      }
      final board = nodes(rendered['tree'])
          .singleWhere((n) => n['type'] == 'plannerBoard');
      expect(
        (board['blocks'] as List).map(object).map((b) => b['title']),
        contains('安排与截止保持'),
      );
      expect((board['candidates'] as List).map(object).map((c) => c['title']), [
        '有截止候选',
      ]);
      final filter = nodes(rendered['header'])
          .singleWhere((n) => n['label'] == '待安排筛选');
      expect(filter['valueLabel'], '仅有截止');
      expect(
        nodes(filter).singleWhere((n) => n['label'] == '仅有截止')['selected'],
        true,
      );
      final current = object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': original['id']},
        ),
      );
      expect(current, original);
    },
  );

  test(
    'candidate summaries use deadline, duration, and overdue status',
    () async {
      await run('task.create', {
        'title': '有截止',
        'dueDate': '2026-10-17',
        'estimatedMinutes': 45,
      });
      await run('task.create', {'title': '长任务', 'estimatedMinutes': 150});
      await run('task.create', {'title': '过期任务', 'dueDate': '2026-10-12'});
      final rendered = await page();
      final board = nodes(rendered['tree'])
          .singleWhere((n) => n['type'] == 'plannerBoard');
      final candidates = {
        for (final item in (board['candidates'] as List).map(object))
          item['title']: item,
      };
      expect(candidates['有截止']!['preferredSummary'], '10/17截止');
      expect(candidates['长任务']!['preferredSummary'], '耗时2.5h');
      expect(candidates['过期任务']!['preferredSummary'], '已逾期');
      final filtered = await page(
        state: object(rendered['state']),
        event: {'type': 'onlyDeadline'},
      );
      expect(object(filtered['state'])['onlyDeadline'], true);
      final reset = await page(
        state: {...object(filtered['state']), 'startDate': '2026-10-20'},
        event: {'type': 'today'},
      );
      expect(object(reset['state'])['startDate'], '2026-10-12');
    },
  );

  test('automatic arrangement offers explicit selection for tasks without deadline', () async {
    final created = object(
      await run('task.create', {'title': '无截止也可选中'}, module: 'app.tasks'),
    );
    var rendered = await page(event: {'type': 'chooseAuto'});
    expect(object(rendered['header'])['title'], '自动安排');
    final select = nodes(rendered['tree'])
        .singleWhere((n) => n['type'] == 'checkbox');
    expect(select['text'], contains('无截止也可选中'));
    rendered = await page(
      state: object(rendered['state']),
      event: {...object(select['event']), 'value': true},
    );
    rendered = await page(
      state: object(rendered['state']),
      event: {'type': 'auto'},
    );
    final preview = object(object(rendered['state'])['autoPreview']);
    expect(
      object(preview['input'])['selectedIds'],
      contains('task:${created['id']}'),
    );
  });

  test('edit-time action opens the precise editor directly', () async {
    final contexts = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      if (method == 'ui.panel') contexts.add(object(args['context']));
      return true;
    };
    final created = object(
      await run('task.create', {'title': '编辑安排'}, module: 'app.tasks'),
    );
    await page(event: {'type': 'editTime', 'id': created['id']});
    expect(contexts.single['step'], 'time');
    final detail = await page(
      pageId: 'app.planner.taskDetail',
      context: contexts.single,
    );
    final visible = nodes(detail['tree']).toList();
    expect(
      visible.where((n) => n['type'] == 'timeInput' && n['key'] == 'start'),
      hasLength(1),
    );
    expect(visible.where((n) => n['key'] == 'dueDate'), isEmpty);
    expect(visible.where((n) => n['text'] == '应用安排'), hasLength(1));
  });

  test('detail completes and reopens a task without changing its schedule or deadline', () async {
    final original = object(
      await run('task.create', {
        'title': '完成后重新打开',
        'dueDate': '2026-10-15',
        'dueTimezone': 'Asia/Shanghai',
        'plannedStartAt': '2026-10-14T10:00:00Z',
        'plannedEndAt': '2026-10-14T10:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      }, module: 'app.tasks'),
    );
    var completed = true;
    var reviews = 0;
    host.interaction = (_, method, args) async {
      if (method == 'ui.dialog') {
        // The dialog retains its date field when completion is switched off.
        return {'completed': completed, 'actualCompletedOn': '2026-10-12'};
      }
      if (method == 'ui.review') reviews++;
      return true;
    };
    Future<Map<String, Object?>> currentTask() async => object(
      await host.query(actor(), const ServiceRef('app.tasks', 'task.get', 1), {
        'id': original['id'],
      }),
    );
    Future<void> applyCompletion() async {
      final initial = await page(
        pageId: 'app.planner.taskDetail',
        context: {'taskId': original['id']},
      );
      final saved = await page(
        pageId: 'app.planner.taskDetail',
        context: {'taskId': original['id']},
        state: object(initial['state']),
        event: {'type': 'complete'},
      );
      expect(object(saved['state'])['error'], isNull);
      final task = await currentTask();
      expect(task['dueDate'], original['dueDate']);
      expect(task['plannedStartAt'], original['plannedStartAt']);
      expect(task['plannedEndAt'], original['plannedEndAt']);
    }

    await applyCompletion();
    final finished = await currentTask();
    expect(finished['completedAt'], isNotNull);
    expect(finished['actualCompletedOn'], '2026-10-12');
    expect(finished['completedTimezone'], 'Asia/Shanghai');
    completed = false;
    await applyCompletion();
    final reopened = await currentTask();
    expect(reopened['completedAt'], isNull);
    expect(reopened['actualCompletedOn'], isNull);
    expect(reopened['completedTimezone'], isNull);
    expect(reviews, 2);
  });

  test(
    'rules retain draft across categories and save through existing service',
    () async {
      host.interaction = (_, method, args) async => method == 'ui.review';
      var rendered = await page(
        pageId: 'app.planner.tools',
        context: {'screen': 'rules'},
        event: {'type': 'editRule'},
      );
      rendered = await page(
        pageId: 'app.planner.tools',
        state: object(rendered['state']),
        forms: {'titles': '新的持续规则'},
        event: {'type': 'ruleStep', 'step': 'repeat'},
      );
      expect(
        nodes(rendered['tree']).singleWhere(
          (n) => n['type'] == 'select' && n['key'] == 'kind',
        )['items'],
        hasLength(4),
      );
      rendered = await page(
        pageId: 'app.planner.tools',
        state: object(rendered['state']),
        event: {'type': 'field', 'key': 'kind', 'value': 'daily'},
      );
      rendered = await page(
        pageId: 'app.planner.tools',
        state: object(rendered['state']),
        event: {'type': 'ruleBack'},
      );
      expect(object(object(rendered['state'])['draft'])['titles'], '新的持续规则');
      rendered = await page(
        pageId: 'app.planner.tools',
        state: object(rendered['state']),
        event: {'type': 'saveRule'},
      );
      expect(object(rendered['state'])['error'], isNull);
      final rules = (await host.query(
        actor(),
        const ServiceRef('app.planner', 'planner.rules.list', 1),
        {},
      ) as List).map(object);
      expect(rules, hasLength(1));
      expect(object((rules.single['versions'] as List).last)['kind'], 'daily');
    },
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
      expect(board['days'], hasLength(21));
      expect(object(board['options'])['visibleDays'], 3);
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

  test('drag confirmation describes the validated schedule and cancel keeps the task untouched', () async {
    final original = object(
      await run('task.create', {
        'title': '普通安排',
        'estimatedMinutes': 30,
      }, module: 'app.tasks'),
    );
    final calls = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      calls.add({'method': method, ...args});
      return false;
    };
    final rendered = await page(
      event: {
        'type': 'move',
        'taskId': original['id'],
        'start': '2026-10-14T18:00:00',
        'end': '2026-10-14T18:45:00',
        'intent': 'move',
      },
    );
    expect(object(rendered['state'])['error'], isNull);
    expect(calls, hasLength(1));
    expect(calls.single['method'], 'ui.review');
    final confirmation = object(calls.single['confirmation']);
    expect(confirmation['title'], '确认安排任务');
    expect(confirmation['confirmLabel'], '确认安排');
    final message = confirmation['message'] as String;
    expect(message, contains('普通安排\n原安排：待安排'));
    expect(message, contains('2026-10-14 18:00 — 18:30'));
    expect(message, contains('时长30分钟'));
    expect(message, isNot(contains('18:45')));
    expect(message, isNot(contains('plannedStartAt')));
    expect(confirmation['acknowledgement'], isNull);
    expect(
      object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': original['id']},
        ),
      ),
      original,
    );
  });

  test(
    'overdue drag uses one acknowledged confirmation and retains its deadline',
    () async {
      final original = object(
        await run('task.create', {
          'title': '超出截止',
          'dueDate': '2026-10-13',
          'estimatedMinutes': 30,
        }, module: 'app.tasks'),
      );
      final calls = <Map<String, Object?>>[];
      host.interaction = (_, method, args) async {
        calls.add({'method': method, ...args});
        return true;
      };
      final rendered = await page(
        event: {
          'type': 'move',
          'taskId': original['id'],
          'start': '2026-10-14T18:00:00',
          'end': '2026-10-14T18:30:00',
          'intent': 'move',
        },
      );
      expect(object(rendered['state'])['error'], isNull);
      expect(calls, hasLength(1));
      expect(calls.single['method'], 'ui.review');
      expect(
        object(calls.single['confirmation'])['acknowledgement'],
        contains('安排超出截止时间'),
      );
      final saved = object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': original['id']},
        ),
      );
      expect(saved['plannedStartAt'], '2026-10-14T10:00:00.000Z');
      expect(saved['dueDate'], original['dueDate']);
    },
  );

  test('swap confirmation includes both real schedules and resize keeps the original start', () async {
    final first = object(
      await run('task.create', {
        'title': '交换甲',
        'plannedStartAt': '2026-10-14T10:00:00Z',
        'plannedEndAt': '2026-10-14T10:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      }, module: 'app.tasks'),
    );
    final second = object(
      await run('task.create', {
        'title': '交换乙',
        'plannedStartAt': '2026-10-14T12:00:00Z',
        'plannedEndAt': '2026-10-14T13:00:00Z',
        'plannedTimezone': 'Asia/Shanghai',
      }, module: 'app.tasks'),
    );
    final confirmations = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      confirmations.add(object(args['confirmation']));
      return false;
    };
    await page(
      event: {
        'type': 'move',
        'taskId': first['id'],
        'targetId': second['id'],
        'intent': 'swap',
      },
    );
    expect(confirmations.single['title'], '确认交换时间');
    final message = confirmations.single['message'] as String;
    expect(
      message,
      contains(
        '交换甲\n原安排：2026-10-14 18:00 — 18:30\n调整为：2026-10-14 20:00 — 20:30',
      ),
    );
    expect(
      message,
      contains(
        '交换乙\n原安排：2026-10-14 20:00 — 21:00\n调整为：2026-10-14 18:00 — 19:00',
      ),
    );
    confirmations.clear();
    await page(
      event: {
        'type': 'move',
        'taskId': first['id'],
        'intent': 'resize',
        'start': '2026-10-14T17:55:00',
        'end': '2026-10-14T18:45:00',
      },
    );
    expect(confirmations.single['title'], '确认调整时长');
    expect(
      confirmations.single['message'],
      contains('调整为：2026-10-14 18:00 — 18:45'),
    );
    expect(confirmations.single['message'], contains('时长45分钟'));
  });

  test(
    'a task changed during compact confirmation still rejects the frozen plan',
    () async {
      final original = object(
        await run('task.create', {'title': '确认时被改动'}, module: 'app.tasks'),
      );
      host.interaction = (_, method, args) async {
        expect(args['confirmation'], isNotNull);
        await run('task.updateFields', {
          'id': original['id'],
          'changes': {'notes': '后来更新'},
        }, module: 'app.tasks');
        return true;
      };
      final rendered = await page(
        event: {
          'type': 'move',
          'taskId': original['id'],
          'intent': 'move',
          'start': '2026-10-14T18:00:00',
          'end': '2026-10-14T18:30:00',
        },
      );
      expect(object(rendered['state'])['error'], isNotNull);
      final saved = object(
        await host.query(
          actor(),
          const ServiceRef('app.tasks', 'task.get', 1),
          {'id': original['id']},
        ),
      );
      expect(saved['plannedStartAt'], isNull);
      expect(saved['notes'], '后来更新');
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
      '${object(board()['options'])['noticeText']}'.contains('其他页或筛选外'),
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
