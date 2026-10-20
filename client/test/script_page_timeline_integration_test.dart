import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/json_values.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/planner_board.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/module_host/ui_preferences.dart';
import 'package:task_app/data/app_database.dart';

class _ReplyBarrier {
  _ReplyBarrier({required this.range});
  final bool range;
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _TimelineHost extends ModuleHost {
  _TimelineHost({required super.store, required super.directory});
  final calls = <BoardItem>[];
  _ReplyBarrier? nextReply;
  Object? preferenceBeforeEvent;
  bool failRange = false;

  @override
  Future<Object?> invokePage(
    String moduleId,
    String handler,
    Object? input, {
    void Function(Set<String>)? onReads,
    void Function(bool)? onReplayable,
    bool readOnly = false,
    bool Function()? shouldRun,
    PagePlanReview? onReview,
    InlinePagePlanReview? onInlineReview,
    void Function(ChangePlan plan)? onCommit,
  }) async {
    final arguments = object(freezeJson(input));
    final range = object(arguments['context'])['timelineRange'] != null;
    calls.add({
      'moduleId': moduleId,
      'handler': handler,
      'input': arguments,
      'readOnly': readOnly,
    });
    if (arguments['event'] != null) {
      preferenceBeforeEvent = await ModuleUiPreferences(store)
          .get(instances[moduleId]!.actor, 'board.viewport');
    }
    if (range && failRange) throw StateError('range temporarily unavailable');
    final barrier = nextReply;
    final delayReply = barrier != null && barrier.range == range;
    if (delayReply) nextReply = null;
    final result = await super.invokePage(
      moduleId,
      handler,
      input,
      onReads: onReads,
      onReplayable: onReplayable,
      readOnly: readOnly,
      shouldRun: shouldRun,
      onReview: onReview,
      onInlineReview: onInlineReview,
      onCommit: onCommit,
    );
    if (delayReply) {
      barrier.entered.complete();
      await barrier.release.future;
    }
    return result;
  }
}

Future<ScriptPackage> _timelinePackage() async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': 'test.timeline',
        'version': '1.0.0',
        'hostApi': '^1.12.0',
        'dataVersion': 1,
        'permissions': ['ui'],
      },
      'entryPoint': 'main.js',
      'collections': [],
      'pages': [],
      'services': [],
    },
    {
      'main.js': '''
import {ui} from '@xudian/sdk';
const add = (date, days) => new Date(Date.parse(date + 'T00:00:00Z') + days * 86400000).toISOString().slice(0, 10);
export async function render(input) {
  const context = input.context || {};
  const saved = await ui.preferences.get('board.viewport') || {};
  const state = {startDate: '2026-10-10', days: 3, selectedDate: '2026-10-11', scrollRequest: 0, ...saved, ...input.state};
  if (input.event?.type === 'jump') {
    state.startDate = '2026-11-11';
    state.selectedDate = '2026-11-12';
    state.scrollRequest++;
  }
  if (input.event?.type === 'columns') state.days = input.event.days;
  const range = context.timelineRange;
  if (range && context.writeDuringRange) await ui.preferences.set('forbidden', true);
  const startDate = range?.startDate || add(state.startDate, -7);
  const days = range?.days || 21;
  const board = {
    type: 'plannerBoard', key: range && context.missingBoard ? 'wrong-board' : 'board',
    days: Array.from({length: days}, (_, index) => ({date: add(startDate, index)})),
    blocks: [], candidates: [],
    options: {
      dashboard: true, continuousDates: true, visibleDays: state.days,
      initialDate: state.startDate, today: '2026-10-11', scrollRequest: state.scrollRequest,
      startMinute: 480, endMinute: 1320, pixelsPerMinute: 1,
      viewportEvent: {type: 'legacyViewport'},
      ...(context.legacy ? {} : {timeline: {
        rangeContextKey: 'timelineRange', preferenceKey: 'board.viewport',
        stateKeys: {startDate: 'startDate', visibleDays: 'days'}
      }})
    }
  };
  return {
    state: range ? {...state, startDate: '1900-01-01', days: 7, selectedDate: '1900-01-02'} : state,
    header: {title: range ? 'range header must not publish' : 'timeline header'},
    ...(range ? {runtimeContextPatch: {selectedDate: '1900-01-02'}, clearForms: ['draft']} : {}),
    tree: {type: 'column', key: 'root', fillHeight: true, children: [board]}
  };
}
''',
    },
  ),
  allowUnsignedLocal: true,
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 100 && !ready(); frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue);
}

void main() {
  late AppDatabase database;
  late CollectionStore store;
  late Directory directory;
  late _TimelineHost host;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(database);
    directory = await Directory.systemTemp.createTemp('script-page-timeline-');
    host = _TimelineHost(store: store, directory: directory);
    await host.initialize();
    await host.install(await _timelinePackage());
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  dynamic renderer(WidgetTester tester) =>
      tester.state(find.byType(ScriptPage));
  PlannerBoard board(WidgetTester tester) =>
      tester.widget<PlannerBoard>(find.byType(PlannerBoard));
  Future<Object?> preference() =>
      ModuleUiPreferences(store)
          .get(host.instances['test.timeline']!.actor, 'board.viewport');

  Future<void> mount(
    WidgetTester tester, {
    BoardItem pageContext = const {'pageId': 'timeline'},
    bool active = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: active,
            child: ScriptPage(
              key: const ValueKey('script-page'),
              host: host,
              moduleId: 'test.timeline',
              handler: 'render',
              pageContext: pageContext,
            ),
          ),
        ),
      ),
    );
    await _until(
      tester,
      () =>
          find.byType(PlannerBoard).evaluate().isNotEmpty &&
          renderer(tester).busy == false,
    );
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    });
  }

  void viewport(WidgetTester tester, String startDate, {int days = 3}) {
    board(tester)
        .onViewportChanged!({'startDate': startDate, 'visibleDays': days});
  }

  testWidgets(
    'in-window scroll stays local and saves only the latest viewport',
    (tester) async {
      await mount(tester);
      final initialCalls = host.calls.length;
      final initialTree = renderer(tester).tree;
      final notifications = <Set<String>>[];
      final subscription = store.changes.stream.listen(notifications.add);
      addTearDown(subscription.cancel);
      final revision = store.dataRevision;
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      final offset = horizontal.offset;
      horizontal.jumpTo(offset + horizontal.position.viewportDimension / 3);
      await tester.pump();
      expect(renderer(tester).state['startDate'], '2026-10-11');
      expect(renderer(tester).busy, isFalse);
      expect(renderer(tester).showProgress, isFalse);
      expect(board(tester).enabled, isTrue);
      expect(host.calls, hasLength(initialCalls));
      expect(identical(renderer(tester).tree, initialTree), isTrue);
      viewport(tester, '2026-10-12', days: 5);
      await tester.pump(const Duration(milliseconds: 299));
      expect(await tester.runAsync(preference), isNull);
      await tester.pump(const Duration(milliseconds: 1));
      await _until(tester, () => store.dataRevision > revision);
      expect(await tester.runAsync(preference), {
        'startDate': '2026-10-12',
        'days': 5,
        'selectedDate': '2026-10-11',
      });
      expect(notifications, isEmpty);
      expect(
        store.moduleDataRevisions[uiPreferencesReadDependency('test.timeline')],
        greaterThan(revision),
      );
      expect(host.calls, hasLength(initialCalls));
      expect(renderer(tester).busy, isFalse);
    },
  );

  testWidgets(
    'delayed range permits another slide and never applies page output',
    (tester) async {
      await mount(tester);
      final initialTree = renderer(tester).tree;
      final initialHeader = renderer(tester).renderedHeader;
      renderer(tester).formValues['draft'] = 'keep this draft';
      final barrier = host.nextReply = _ReplyBarrier(range: true);
      final pending = board(tester).onLoadRange!('2026-12-01', 21);
      await _until(tester, () => barrier.entered.isCompleted);
      expect(renderer(tester).busy, isFalse);
      await tester.pump(const Duration(milliseconds: 600));
      expect(renderer(tester).showProgress, isFalse);
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('planner-horizontal')),
          )
          .controller!;
      final offset = horizontal.offset;
      horizontal.jumpTo(offset + horizontal.position.viewportDimension / 3);
      await tester.pump();
      expect(renderer(tester).state['startDate'], '2026-10-11');
      expect(renderer(tester).busy, isFalse);
      viewport(tester, '2026-10-13');
      viewport(tester, '2026-10-14', days: 5);
      expect(renderer(tester).state['startDate'], '2026-10-14');
      expect(board(tester).enabled, isTrue);
      final revision = store.dataRevision;
      await tester.pump(const Duration(milliseconds: 300));
      await _until(tester, () => store.dataRevision > revision);
      expect(host.calls, hasLength(2));
      barrier.release.complete();
      final result = await tester.runAsync(() => pending);
      expect(result!.keys.toSet(), {'days', 'blocks', 'options'});
      expect((result['days'] as List).first, {'date': '2026-12-01'});
      expect(result['days'], hasLength(21));
      expect(renderer(tester).state['startDate'], '2026-10-14');
      expect(renderer(tester).state['days'], 5);
      expect(renderer(tester).state['selectedDate'], '2026-10-11');
      expect(renderer(tester).formValues['draft'], 'keep this draft');
      expect(identical(renderer(tester).tree, initialTree), isTrue);
      expect(identical(renderer(tester).renderedHeader, initialHeader), isTrue);
      expect(renderer(tester).pageContext['selectedDate'], isNull);
      final call = host.calls.last;
      expect(call['moduleId'], 'test.timeline');
      expect(call['handler'], 'render');
      expect(call['readOnly'], isTrue);
      final input = object(call['input']);
      expect(input['event'], isNull);
      expect(input['context'], {
        'pageId': 'timeline',
        'timelineRange': {'startDate': '2026-12-01', 'days': 21},
      });
    },
  );

  testWidgets(
    'foreground render retains a viewport updated after its request',
    (tester) async {
      await mount(tester);
      final barrier = host.nextReply = _ReplyBarrier(range: false);
      store.changes.add({uiPreferencesReadDependency('test.timeline')});
      await _until(tester, () => barrier.entered.isCompleted);
      viewport(tester, '2026-10-17', days: 7);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async => await preference());
      final calls = host.calls.length;
      barrier.release.complete();
      await _until(tester, () => renderer(tester).busy == false);
      expect(renderer(tester).state['startDate'], '2026-10-17');
      expect(renderer(tester).state['days'], 7);
      expect(host.calls, hasLength(calls));
    },
  );

  testWidgets('business events flush prefs and explicit scroll requests win', (
    tester,
  ) async {
    await mount(tester);
    final oldViewport = board(tester).onViewportChanged!;
    viewport(tester, '2026-10-16', days: 5);
    board(tester).onEvent({'type': 'jump'});
    await _until(
      tester,
      () =>
          renderer(tester).state['scrollRequest'] == 1 &&
          renderer(tester).busy == false,
    );
    expect(host.preferenceBeforeEvent, {
      'startDate': '2026-10-16',
      'days': 5,
      'selectedDate': '2026-10-11',
    });
    final input = object(host.calls.last['input']);
    expect(object(input['state'])['startDate'], '2026-10-16');
    expect(object(input['state'])['days'], 5);
    expect(renderer(tester).state['startDate'], '2026-11-11');
    expect(renderer(tester).state['selectedDate'], '2026-11-12');
    expect(board(tester).options['initialDate'], '2026-11-11');
    oldViewport({'startDate': '2026-10-16', 'visibleDays': 5});
    expect(renderer(tester).state['startDate'], '2026-11-11');
  });

  testWidgets(
    'leaving a page flushes before debounce and restores preferences',
    (tester) async {
      await mount(tester);
      viewport(tester, '2026-10-18', days: 7);
      final calls = host.calls.length;
      final revision = store.dataRevision;
      await tester.pumpWidget(const SizedBox.shrink());
      await _until(tester, () => store.dataRevision > revision);
      expect(await tester.runAsync(preference), {
        'startDate': '2026-10-18',
        'days': 7,
        'selectedDate': '2026-10-11',
      });
      expect(host.calls, hasLength(calls));
      host.pageSessions.clear();
      await mount(tester);
      expect(renderer(tester).state['startDate'], '2026-10-18');
      expect(renderer(tester).state['days'], 7);
      viewport(tester, '2026-10-19', days: 5);
      await mount(tester, pageContext: const {'pageId': 'another-page'});
      expect(await tester.runAsync(preference), {
        'startDate': '2026-10-19',
        'days': 5,
        'selectedDate': '2026-10-11',
      });
    },
  );

  testWidgets(
    'business column changes are not overwritten by a saved viewport',
    (tester) async {
      await mount(tester);
      viewport(tester, '2026-10-16', days: 5);
      board(tester).onEvent({'type': 'columns', 'days': 1});
      await _until(
        tester,
        () =>
            renderer(tester).state['days'] == 1 &&
            renderer(tester).busy == false,
      );
      expect(renderer(tester).state['startDate'], '2026-10-16');
      expect(board(tester).options['visibleDays'], 1);
    },
  );

  testWidgets(
    'workspace deactivation flushes and refuses stale native actions',
    (tester) async {
      await mount(tester);
      final previousBoard = board(tester);
      viewport(tester, '2026-10-16', days: 5);
      final calls = host.calls.length;
      final revision = store.dataRevision;
      await mount(tester, active: false);
      await _until(tester, () => store.dataRevision > revision);
      expect(await tester.runAsync(preference), {
        'startDate': '2026-10-16',
        'days': 5,
        'selectedDate': '2026-10-11',
      });
      previousBoard.onViewportChanged!({
        'startDate': '2026-10-25',
        'visibleDays': 7,
      });
      previousBoard.onEvent({'type': 'jump'});
      await expectLater(
        previousBoard.onLoadRange!('2026-12-01', 21),
        completion(isNull),
      );
      expect(renderer(tester).state['startDate'], '2026-10-16');
      expect(host.calls, hasLength(calls));
    },
  );

  testWidgets(
    'store notifications invalidate a range before refresh debounce',
    (tester) async {
      await mount(tester);
      final barrier = host.nextReply = _ReplyBarrier(range: true);
      final pending = board(tester).onLoadRange!('2026-12-01', 21);
      await _until(tester, () => barrier.entered.isCompleted);
      final rejected = expectLater(pending, completion(isNull));
      final revision = store.dataRevision;
      store.changes.add({'test.business'});
      await tester.pump();
      expect(store.dataRevision, revision);
      barrier.release.complete();
      await tester.runAsync(() => rejected);
      expect(host.calls, hasLength(2));
      expect(renderer(tester).busy, isFalse);
      expect(renderer(tester).state['startDate'], '2026-10-10');
    },
  );

  testWidgets('business changes and context switches reject delayed ranges', (
    tester,
  ) async {
    await mount(tester);
    for (final contextChange in [false, true]) {
      final barrier = host.nextReply = _ReplyBarrier(range: true);
      final pending = board(tester).onLoadRange!('2026-12-01', 21);
      await _until(tester, () => barrier.entered.isCompleted);
      final rejected = expectLater(pending, completion(isNull));
      if (contextChange) {
        await mount(tester, pageContext: const {'pageId': 'other-context'});
      } else {
        store.recordDataChange({'test.business'});
      }
      barrier.release.complete();
      await tester.runAsync(() => rejected);
      expect(renderer(tester).busy, isFalse);
      expect(renderer(tester).state['startDate'], '2026-10-10');
    }
  });

  testWidgets(
    'business epoch and instance replacement reject old range output',
    (tester) async {
      await mount(tester);
      final barrier = host.nextReply = _ReplyBarrier(range: true);
      final pending = board(tester).onLoadRange!('2026-12-01', 21);
      await _until(tester, () => barrier.entered.isCompleted);
      final rejected = expectLater(pending, completion(isNull));
      board(tester).onEvent({'type': 'jump'});
      await _until(
        tester,
        () =>
            renderer(tester).state['scrollRequest'] == 1 &&
            renderer(tester).busy == false,
      );
      barrier.release.complete();
      await tester.runAsync(() => rejected);
      expect(renderer(tester).state['startDate'], '2026-11-11');
      final oldLoad = board(tester).onLoadRange!;
      await tester.runAsync(() => host.disable('test.timeline'));
      await tester.runAsync(() => host.enable('test.timeline'));
      await expectLater(oldLoad('2026-12-01', 21), completion(isNull));
    },
  );

  testWidgets(
    'range failures are observable and retry does not reload the page',
    (tester) async {
      await mount(tester);
      host.failRange = true;
      final failed = board(tester).onLoadRange!('2026-12-01', 21);
      await expectLater(failed, throwsStateError);
      expect(renderer(tester).busy, isFalse);
      expect(renderer(tester).error, isNull);
      host.failRange = false;
      final loaded = await tester.runAsync(
        () => board(tester).onLoadRange!('2026-12-01', 21),
      );
      expect(loaded!['days'], hasLength(21));
      expect(
        host.calls.where((call) => call['readOnly'] == false),
        hasLength(1),
      );
      await mount(
        tester,
        pageContext: const {'pageId': 'timeline', 'missingBoard': true},
      );
      await tester.runAsync(
        () => expectLater(
          board(tester).onLoadRange!('2026-12-01', 21),
          throwsFormatException,
        ),
      );
    },
  );

  testWidgets(
    'read-only ranges and inactive viewport writes retain authorization',
    (tester) async {
      await mount(
        tester,
        pageContext: const {'pageId': 'timeline', 'writeDuringRange': true},
      );
      await tester.runAsync(
        () => expectLater(
          board(tester).onLoadRange!('2026-12-01', 21),
          throwsStateError,
        ),
      );
      final actor = host.instances['test.timeline']!.actor;
      expect(
        await tester.runAsync(
          () => ModuleUiPreferences(store).get(actor, 'forbidden'),
        ),
        isNull,
      );
      viewport(tester, '2026-10-20');
      store.deactivate(actor.moduleId);
      addTearDown(() => store.activate(actor));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      expect(
        await tester.runAsync(
          () => store.sql('SELECT * FROM host_ui_preferences'),
        ),
        isEmpty,
      );
      expect(renderer(tester).busy, isFalse);
    },
  );

  testWidgets('modules without timeline retain their event-driven viewport', (
    tester,
  ) async {
    await mount(
      tester,
      pageContext: const {'pageId': 'timeline', 'legacy': true},
    );
    expect(board(tester).onViewportChanged, isNull);
    expect(board(tester).onLoadRange, isNull);
    final calls = host.calls.length;
    board(tester)
        .onEvent({'type': 'legacyViewport', 'startDate': '2026-10-12'});
    await _until(
      tester,
      () => host.calls.length > calls && renderer(tester).busy == false,
    );
    expect(
      object(object(host.calls.last['input'])['event'])['type'],
      'legacyViewport',
    );
    expect(host.calls.last['readOnly'], isFalse);
  });
}
