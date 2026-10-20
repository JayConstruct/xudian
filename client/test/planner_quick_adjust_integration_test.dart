import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/planner_board.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/module_host/ui_preferences.dart';
import 'package:task_app/core/ui/workspace_header.dart';
import 'package:task_app/core/ui/workspace_header_action.dart';
import 'package:task_app/data/app_database.dart';

class _CommitBarrier {
  _CommitBarrier({this.fail = false});
  final bool fail;
  final entered = Completer<ChangePlan>();
  final release = Completer<void>();
}

// Pause a real, reviewed operation immediately before its database commit.
// Module execution, service validation, review policy and persistence remain real.
class _DelayedCommitStore extends CollectionStore {
  _DelayedCommitStore(super.db);
  _CommitBarrier? next;

  @override
  Future<Object?> commit(
    String id,
    ModuleActor caller, {
    required void Function(ChangePlan) authorize,
    bool audit = true,
  }) async {
    final barrier = next;
    if (barrier != null && caller.moduleId == 'app.planner') {
      next = null;
      barrier.entered.complete(plan(id, caller));
      await barrier.release.future;
      if (barrier.fail) throw StateError('测试保存失败');
    }
    return super.commit(id, caller, authorize: authorize, audit: audit);
  }
}

class _PlannerHeaderHarness extends StatefulWidget {
  const _PlannerHeaderHarness({required this.host});
  final ModuleHost host;

  @override
  State<_PlannerHeaderHarness> createState() => _PlannerHeaderHarnessState();
}

class _PlannerHeaderHarnessState extends State<_PlannerHeaderHarness> {
  final header = WorkspaceHeaderController();

  @override
  void initState() {
    super.initState();
    header.activate(
      identity: 'planner-integration',
      moduleId: 'app.planner',
      pageId: 'app.planner.home',
      enabled: true,
      isActive: () => mounted,
    );
  }

  @override
  void dispose() {
    header.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspaceHeaderScope(
    controller: header,
    lease: header.lease,
    child: Column(
      children: [
        AnimatedBuilder(
          animation: header,
          builder: (context, _) {
            final content = header.content;
            final actions = (content?.spec['actions'] as List? ?? const [])
                .map(object)
                .where((action) => action['presentation'] == 'inline');
            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${content?.spec['title'] ?? ''}',
                      maxLines: 1,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  for (final action in actions)
                    WorkspaceHeaderAction(
                      action: action,
                      compact: true,
                      onPressed: () =>
                          unawaited(content!.dispatch(action['event'])),
                    ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: ScriptPage(
            host: widget.host,
            moduleId: 'app.planner',
            handler: 'render',
            pageContext: const {'pageId': 'app.planner.home'},
          ),
        ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _DelayedCommitStore store;
  late ModuleHost host;
  late Directory folder;

  Future<void> install(String id) async {
    final directory = Directory('../packages/modules/$id');
    final scripts = <String, String>{};
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.js')) {
        scripts[file.path.substring(directory.path.length + 1)] = file
            .readAsStringSync();
      }
    }
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          object(
            jsonDecode(
              File('${directory.path}/module.json').readAsStringSync(),
            ),
          ),
          scripts,
        ),
        allowUnsignedLocal: true,
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = _DelayedCommitStore(db);
    folder = await Directory.systemTemp.createTemp('planner-quick-adjust-');
    host = ModuleHost(store: store, directory: folder);
    host.clockNow = () => DateTime.utc(2026, 10, 13);
    await host.initialize();
    await install('app.tasks');
    await install('app.planner');
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<Map<String, Object?>> createTask(
    String title, {
    String? dueDate,
  }) async {
    final actor = host.instances['app.tasks']!.actor;
    final plan = await host.prepare(
      actor,
      const ServiceRef('app.tasks', 'task.create', 1),
      {
        'title': title,
        'plannedStartAt': '2026-10-14T01:00:00Z',
        'plannedEndAt': '2026-10-14T01:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
        'dueDate': ?dueDate,
      },
    );
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> raw(Object? id) async => object(
    await host.query(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.tasks', 'task.get', 1),
      {'id': id},
    ),
  );

  Map<String, Object?> move(
    Object? id, {
    String start = '10:00',
    String end = '10:30',
  }) => {
    'type': 'move',
    'taskId': id,
    'intent': 'move',
    'start': '2026-10-14T$start:00',
    'end': '2026-10-14T$end:00',
  };

  Future<Map<String, Object?>> page({
    Map<String, Object?>? event,
    PagePlanReview? onReview,
  }) async => object(
    await host.invokePage('app.planner', 'render', {
      'context': {'pageId': 'app.planner.home'},
      'state': {},
      'event': event,
    }, onReview: onReview),
  );

  test('page review sees the top-level frozen operation and skips interaction only for its invocation', () async {
    final original = await createTask('真实快速调整');
    var interactions = 0;
    host.interaction = (_, method, args) async {
      if (method == 'ui.review') interactions++;
      return false;
    };
    var callbackCount = 0;
    final result = await page(
      event: move(original['id']),
      onReview: (ref, input, plan, confirmation) {
        callbackCount++;
        expect(ref.key, 'app.planner/planner.operation.apply@1');
        final operation = object(input);
        expect(operation['operationKey'], isNotEmpty);
        final preview = object(operation['preview']);
        expect(object(preview['input'])['taskId'], original['id']);
        expect(preview['kind'], 'move');
        expect(plan.caller.moduleId, 'app.planner');
        expect(plan.writes, isNotEmpty);
        expect(plan.result, isNotNull);
        expect(confirmation?.message, contains('真实快速调整'));
        expect(confirmation?.acknowledgement, isNull);
        return true;
      },
    );
    expect(object(result['state'])['error'], isNull);
    expect(callbackCount, 1);
    expect(interactions, 0);
    expect(
      (await raw(original['id']))['plannedStartAt'],
      '2026-10-14T02:00:00.000Z',
    );

    // A subsequent invocation without a callback must return to normal review.
    await page(
      event: move(original['id'], start: '11:00', end: '11:30'),
    );
    expect(interactions, 1);
    expect(callbackCount, 1);
    expect(
      (await raw(original['id']))['plannedStartAt'],
      '2026-10-14T02:00:00.000Z',
    );
  });

  for (final useCallback in [false, true]) {
    test(
      'normal review remains required with ${useCallback ? 'a declining callback' : 'no callback'}',
      () async {
        final original = await createTask('需要确认');
        var callbacks = 0, reviews = 0;
        host.interaction = (_, method, args) async {
          if (method == 'ui.review') reviews++;
          return false;
        };
        final rendered = await page(
          event: move(original['id']),
          onReview: useCallback
              ? (ref, input, plan, confirmation) {
                  callbacks++;
                  return false;
                }
              : null,
        );
        expect(object(rendered['state'])['error'], isNull);
        expect(reviews, 1);
        expect(callbacks, useCallback ? 1 : 0);
        expect(await raw(original['id']), original);
      },
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> showPlanner(
    WidgetTester tester, {
    bool withHeader = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withHeader
              ? _PlannerHeaderHarness(host: host)
              : ScriptPage(
                  host: host,
                  moduleId: 'app.planner',
                  handler: 'render',
                  pageContext: const {'pageId': 'app.planner.home'},
                ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('快速调整'));
    await settle(tester);
  }

  String snackMessage(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
      )
      .map((text) => text.data ?? '')
      .join(' ');

  testWidgets(
    'standalone planner keeps a native adjustment entry without writes',
    (tester) async {
      late Map<String, Object?> original;
      await tester.runAsync(() async {
        original = await createTask('独立页面开关');
      });
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return false;
      };
      await showPlanner(tester, withHeader: false);
      expect(
        find.byKey(const ValueKey('planner-standalone-quick-adjust')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('planner-quick-adjust')), findsNothing);
      expect(
        tester.widget<PlannerBoard>(find.byType(PlannerBoard)).quickAdjust,
        true,
      );
      await tester.tap(find.byTooltip('快速调整'));
      await settle(tester);
      expect(
        tester.widget<PlannerBoard>(find.byType(PlannerBoard)).quickAdjust,
        false,
      );
      expect(reviews, 0);
      await tester.runAsync(() async {
        expect(await raw(original['id']), original);
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a real delayed commit keeps one pending landing card and leaves the timeline scrollable',
    (tester) async {
      late Map<String, Object?> original;
      await tester.runAsync(() async {
        original = await createTask('等待保存任务');
        // Keep a scrollable full-day viewport for this scrolling regression.
        await ModuleUiPreferences(store).set(
          host.instances['app.planner']!.actor,
          'board.displayHours',
          {'mode': 'full', 'start': '08:00', 'end': '22:00'},
        );
      });
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return false;
      };
      await showPlanner(tester);
      final viewport = find.byKey(const ValueKey('planner-vertical'));
      final initialRect = tester.getRect(viewport);
      final barrier = _CommitBarrier();
      store.next = barrier;
      addTearDown(() {
        if (!barrier.release.isCompleted) barrier.release.complete();
      });
      tester
          .widget<PlannerBoard>(find.byType(PlannerBoard))
          .onEvent(move(original['id']));
      await settle(tester);
      expect(barrier.entered.isCompleted, true);
      expect(reviews, 0);
      expect(
        find.byKey(ValueKey('planner-saving:${original['id']}')),
        findsOneWidget,
      );
      final pending = tester
          .widget<PlannerBoard>(find.byType(PlannerBoard))
          .pendingAdjustment!;
      expect(pending['id'], original['id']);
      expect(pending['start'], '2026-10-14T10:00:00');
      expect(pending['end'], '2026-10-14T10:30:00');
      final landing = find.byKey(
        ValueKey('block:${original['id']}:2026-10-14'),
      );
      expect(landing, findsOneWidget);
      final positioned = tester.widget<Positioned>(landing);
      expect(positioned.top, closeTo(600 * 1.1, .01));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.getRect(viewport), initialRect);
      final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
      final beforeScroll = scroll.offset;
      await tester.drag(viewport, const Offset(0, -90));
      await tester.pump(const Duration(milliseconds: 120));
      expect(scroll.offset, greaterThan(beforeScroll));
      await tester.runAsync(() async {
        expect(
          (await raw(original['id']))['plannedStartAt'],
          original['plannedStartAt'],
        );
      });
      barrier.release.complete();
      await settle(tester);
      expect(
        find.byKey(ValueKey('planner-saving:${original['id']}')),
        findsNothing,
      );
      expect(
        tester
            .widget<PlannerBoard>(find.byType(PlannerBoard))
            .pendingAdjustment,
        isNull,
      );
      expect(snackMessage(tester), contains('等待保存任务'));
      expect(snackMessage(tester), contains('10:00'));
      await tester.runAsync(() async {
        expect(
          (await raw(original['id']))['plannedStartAt'],
          '2026-10-14T02:00:00.000Z',
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'commit failure restores the original card and retry applies the requested move',
    (tester) async {
      late Map<String, Object?> original;
      await tester.runAsync(() async {
        original = await createTask('失败后重试');
      });
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return false;
      };
      await showPlanner(tester);
      final barrier = _CommitBarrier(fail: true);
      store.next = barrier;
      addTearDown(() {
        if (!barrier.release.isCompleted) barrier.release.complete();
      });
      tester
          .widget<PlannerBoard>(find.byType(PlannerBoard))
          .onEvent(move(original['id']));
      await settle(tester);
      expect(barrier.entered.isCompleted, true);
      expect(
        find.byKey(ValueKey('planner-saving:${original['id']}')),
        findsOneWidget,
      );
      barrier.release.complete();
      await settle(tester);
      final failed = tester.widget<PlannerBoard>(find.byType(PlannerBoard));
      expect(failed.pendingAdjustment, isNull);
      final originalBlock = failed.blocks.singleWhere(
        (block) => block['id'] == original['id'],
      );
      expect(originalBlock['start'], '2026-10-14T09:00:00');
      expect(find.text('重试'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.runAsync(() async {
        expect(await raw(original['id']), original);
      });
      await tester.tap(find.text('重试'));
      await settle(tester);
      await tester.runAsync(() async {
        expect(
          (await raw(original['id']))['plannedStartAt'],
          '2026-10-14T02:00:00.000Z',
        );
      });
      expect(find.text('重试'), findsNothing);
      expect(reviews, 0);
      expect(snackMessage(tester), contains('失败后重试'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'success replaces the current snack and undo targets only the latest operation',
    (tester) async {
      late Map<String, Object?> original;
      await tester.runAsync(() async {
        original = await createTask('连续调整任务');
      });
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return false;
      };
      await showPlanner(tester);
      tester
          .widget<PlannerBoard>(find.byType(PlannerBoard))
          .onEvent(move(original['id']));
      await settle(tester);
      expect(snackMessage(tester), contains('10:00'));
      tester
          .widget<PlannerBoard>(find.byType(PlannerBoard))
          .onEvent(move(original['id'], start: '11:00', end: '11:30'));
      await settle(tester);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(snackMessage(tester), contains('连续调整任务'));
      expect(snackMessage(tester), contains('11:00'));
      expect(snackMessage(tester), isNot(contains('10:00')));
      await tester.tap(find.text('撤销'));
      await settle(tester);
      expect(reviews, 0);
      await tester.runAsync(() async {
        expect(
          (await raw(original['id']))['plannedStartAt'],
          '2026-10-14T02:00:00.000Z',
        );
        final history = (await host.query(
          host.instances['app.planner']!.actor,
          const ServiceRef('app.planner', 'planner.operation.list', 1),
          {},
        ) as List).map(object).toList();
        expect(history, hasLength(2));
        expect(history.first['undone'], true);
        expect(history.last['undone'], false);
      });
      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'leaving the planner clears its success snack without queuing it on return',
    (tester) async {
      late Map<String, Object?> original;
      await tester.runAsync(() async {
        original = await createTask('离开页面');
      });
      host.interaction = (_, method, args) async => false;
      final messenger = GlobalKey<ScaffoldMessengerState>();
      Widget screen(bool planner) => MaterialApp(
        scaffoldMessengerKey: messenger,
        home: Scaffold(
          body: planner
              ? _PlannerHeaderHarness(host: host)
              : const Center(child: Text('其他页面')),
        ),
      );
      await tester.pumpWidget(screen(true));
      await settle(tester);
      await tester.tap(find.byTooltip('快速调整'));
      await settle(tester);
      tester
          .widget<PlannerBoard>(find.byType(PlannerBoard))
          .onEvent(move(original['id']));
      await settle(tester);
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpWidget(screen(false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('其他页面'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(screen(true));
      await settle(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester.widget<PlannerBoard>(find.byType(PlannerBoard)).quickAdjust,
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'real planner quick adjustment saves and undoes without dialogs, then closing it restores review',
    (tester) async {
      late Map<String, Object?> original;
      await tester.runAsync(() async {
        original = await createTask('Widget 快速调整');
      });
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return false;
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: _PlannerHeaderHarness(host: host)),
        ),
      );
      await settle(tester);
      expect(
        tester.widget<PlannerBoard>(find.byType(PlannerBoard)).quickAdjust,
        false,
      );
      await tester.tap(find.byTooltip('快速调整'));
      await settle(tester);
      final board = tester.widget<PlannerBoard>(find.byType(PlannerBoard));
      expect(board.quickAdjust, true);
      board.onEvent(move(original['id']));
      await settle(tester);
      expect(reviews, 0);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);
      await tester.runAsync(() async {
        expect(
          (await raw(original['id']))['plannedStartAt'],
          '2026-10-14T02:00:00.000Z',
        );
      });
      await tester.tap(find.text('撤销'));
      await settle(tester);
      expect(reviews, 0);
      await tester.runAsync(() async {
        final restored = await raw(original['id']);
        expect(restored['plannedStartAt'], original['plannedStartAt']);
        expect(restored['plannedEndAt'], original['plannedEndAt']);
      });
      await tester.tap(find.byTooltip('快速调整'));
      await settle(tester);
      final normal = tester.widget<PlannerBoard>(find.byType(PlannerBoard));
      expect(normal.quickAdjust, false);
      normal.onEvent(move(original['id'], start: '11:00', end: '11:30'));
      await settle(tester);
      expect(reviews, 1);
      await tester.runAsync(() async {
        expect(
          (await raw(original['id']))['plannedStartAt'],
          original['plannedStartAt'],
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final intent in ['resize', 'swap', 'overdue']) {
    testWidgets(
      'quick adjustment ${intent == 'resize' ? 'applies resize' : 'keeps $intent confirmation'}',
      (tester) async {
        late Map<String, Object?> original;
        Object? targetId;
        await tester.runAsync(() async {
          original = await createTask(
            '边界任务',
            dueDate: intent == 'overdue' ? '2026-10-13' : null,
          );
          if (intent == 'swap') {
            final actor = host.instances['app.tasks']!.actor;
            final plan = await host.prepare(
              actor,
              const ServiceRef('app.tasks', 'task.create', 1),
              {
                'title': '交换目标',
                'plannedStartAt': '2026-10-14T03:00:00Z',
                'plannedEndAt': '2026-10-14T03:30:00Z',
                'plannedTimezone': 'Asia/Shanghai',
              },
            );
            host.review(plan.id, actor);
            targetId = object(await host.commit(actor, plan.id))['id'];
          }
        });
        var reviews = 0;
        host.interaction = (_, method, args) async {
          if (method == 'ui.review') reviews++;
          return false;
        };
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: _PlannerHeaderHarness(host: host)),
          ),
        );
        await settle(tester);
        await tester.tap(find.byTooltip('快速调整'));
        await settle(tester);
        final event = intent == 'resize'
            ? {
                ...move(original['id'], start: '09:00', end: '09:45'),
                'intent': 'resize',
              }
            : intent == 'swap'
            ? {
                ...move(original['id'], start: '11:00', end: '11:30'),
                'intent': 'swap',
                'targetId': targetId,
              }
            : move(original['id']);
        tester.widget<PlannerBoard>(find.byType(PlannerBoard)).onEvent(event);
        await settle(tester);
        expect(reviews, intent == 'resize' ? 0 : 1);
        await tester.runAsync(() async {
          final changed = await raw(original['id']);
          expect(changed['plannedStartAt'], original['plannedStartAt']);
          expect(
            changed['plannedEndAt'],
            intent == 'resize'
                ? '2026-10-14T01:45:00.000Z'
                : original['plannedEndAt'],
          );
        });
        expect(
          find.byType(SnackBar),
          intent == 'resize' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
