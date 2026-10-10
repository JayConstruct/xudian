import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/declarative/declarative_module.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/package/module_install_provenance.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/modules/module_context.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_annotation.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/proposal/module_proposal.dart';
import 'package:task_app/features/ai/proposal/module_proposal_review.dart';
import 'package:task_app/features/ai/proposal/module_proposal_service.dart';
import 'package:task_app/features/ai/provider/openai_compatible_provider.dart';
import 'package:task_app/features/declarative_runtime/declarative_app_module.dart';
import 'package:task_app/features/declarative_runtime/declarative_runtime_controller.dart';
import 'package:task_app/features/declarative_runtime/declarative_task_page.dart';
import 'package:task_app/features/tasks/application/providers.dart';

const _parser = DeclarativeModuleParser();

class _PromptHttpOverrides extends HttpOverrides {
  final client = _PromptClient();

  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

class _PromptClient implements HttpClient {
  final request = _PromptRequest();

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => request;

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PromptRequest implements HttpClientRequest {
  final body = StringBuffer();
  String? systemPrompt;

  @override
  final HttpHeaders headers = _PromptHeaders();

  @override
  void write(Object? object) => body.write(object);

  @override
  Future<HttpClientResponse> close() async {
    final decoded = jsonDecode(body.toString()) as Map;
    systemPrompt = (decoded['messages'] as List).first['content'] as String;
    return _PromptResponse();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PromptHeaders implements HttpHeaders {
  @override
  set contentType(ContentType? value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PromptResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(_source())},
              },
            ],
          }),
        ),
      ).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _source() =>
    (jsonDecode(jsonEncode(_sourceDefinition())) as Map)
        .cast<String, Object?>();

Map<String, Object?> _sourceDefinition() => {
  'formatVersion': 2,
  'manifest': {
    'id': 'app.composition.test',
    'version': '1.0.0',
    'coreApi': '1',
    'requiresCapabilities': ['ui.registry', 'ui.composition', 'tasks.query'],
    'permissions': ['ui.register', 'tasks.read'],
  },
  'pages': [
    {
      'id': 'home',
      'title': '组合首页',
      'kind': 'container',
      'entry': {},
      'slots': [
        {'id': 'actions', 'label': '操作'},
        {'id': 'body', 'label': '内容', 'kind': 'tabs', 'public': true},
      ],
    },
    {
      'id': 'tasks',
      'title': '范围内任务',
      'view': 'list',
      'entry': false,
      'requiredContext': ['taskId', 'projectId'],
      'retainPosition': true,
    },
  ],
  'views': [
    {
      'id': 'list',
      'source': 'task.list',
      'emptyText': '范围内暂无符合条件的任务',
      'filter': {'field': 'priority', 'op': 'gte', 'value': 2},
    },
  ],
  'layouts': [
    {
      'id': 'taskTab',
      'pageId': 'tasks',
      'label': '任务页签',
      'content': true,
      'placement': 'page',
      'hostPageId': 'home',
      'slotId': 'body',
      'order': 3,
    },
  ],
};

List<Map> _pages(Map<String, Object?> source) =>
    (source['pages'] as List).cast<Map>();

Map _layout(Map<String, Object?> source) =>
    (source['layouts'] as List).single as Map;

Future<void> _pumpDatabase(WidgetTester tester) async {
  for (var iteration = 0; iteration < 6; iteration++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _seed(AppDatabase database) async {
  final now = DateTime(2026, 10, 6);
  for (final id in ['projectA', 'projectB']) {
    await database
        .into(database.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id,
            name: id,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
  for (final record in [
    ('taskA', 'projectA', '匹配任务', 3),
    ('taskB', 'projectB', '其他项目任务', 3),
    ('taskC', 'projectA', '被原过滤器排除', 0),
  ]) {
    await database
        .into(database.tasks)
        .insert(
          TasksCompanion.insert(
            id: record.$1,
            projectId: Value(record.$2),
            title: record.$3,
            priority: Value(record.$4),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}

Widget _taskWidget({
  required DeclarativeModule module,
  required AppDatabase database,
  required ValueNotifier<PageContext> pageContext,
}) => ProviderScope(
  overrides: [databaseProvider.overrideWith((ref) async => database)],
  child: MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<PageContext>(
        valueListenable: pageContext,
        builder: (_, value, _) => DeclarativeTaskPage(
          module: module,
          moduleContext: ModuleContext(
            moduleId: module.manifest.id,
            permissions: module.manifest.permissions,
          ),
          page: module.pages.last,
          pageContext: value,
        ),
      ),
    ),
  ),
);

void main() {
  test(
    'v2 creates page and entry registrations with private slot defaults',
    () {
      final module = DeclarativeAppModule(_parser.parse(_source()));
      final pages = module.ui.whereType<UiPageRegistration>().toList();
      final entries = module.ui.whereType<UiEntryRegistration>().toList();
      expect(module.ui.whereType<NavigationRegistration>(), isEmpty);
      expect(pages.map((page) => page.id), [
        'app.composition.test.home',
        'app.composition.test.tasks',
      ]);
      expect(pages.first.container, isTrue);
      expect(pages.first.slots.first.isPublic, isFalse);
      expect(pages.first.slots.first.editable, isTrue);
      expect(pages.first.slots.first.kind, PageSlotKind.entries);
      expect(pages.first.slots.last.isPublic, isTrue);
      expect(pages.last.requiredContext, ['taskId', 'projectId']);
      expect(pages.last.retainPosition, isTrue);
      expect(entries.map((entry) => entry.id), [
        'app.composition.test.home',
        'app.composition.test.taskTab',
      ]);
      expect(entries.first.defaultMount.placement, UiPlacement.main);
      expect(entries.last.pageId, 'app.composition.test.tasks');
      expect(entries.last.defaultMount.pageId, 'app.composition.test.home');
      expect(entries.last.defaultMount.slotId, 'body');
      expect(entries.last.defaultMount.order, 3);
      expect(entries.last.content, isTrue);
    },
  );

  testWidgets(
    'page factory forwards read-only context and renders empty containers',
    (tester) async {
      final runtime = DeclarativeAppModule(_parser.parse(_source()));
      final pages = runtime.ui.whereType<UiPageRegistration>().toList();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final child = pages.last.builder(
                context,
                const PageContext(taskId: 'taskA'),
              );
              expect(child, isA<DeclarativeTaskPage>());
              final taskPage = child as DeclarativeTaskPage;
              expect(taskPage.pageContext.taskId, 'taskA');
              expect(taskPage.moduleContext.moduleId, 'app.composition.test');
              expect(taskPage.moduleContext.allows('tasks.write'), isFalse);
              return pages.first.builder(context, const PageContext());
            },
          ),
        ),
      );
      expect(find.byType(SizedBox), findsOneWidget);
    },
  );

  for (final noEntry in [null, false]) {
    test('explicit entry $noEntry does not create a global shortcut', () {
      final source = _source();
      _pages(source).first['entry'] = noEntry;
      expect(
        DeclarativeAppModule(_parser.parse(source)).ui
            .whereType<UiEntryRegistration>()
            .single
            .id,
        'app.composition.test.taskTab',
      );
    });
  }

  test('omitted entries keep pages registered and allow explicit layout contributions', () {
    final source = _source();
    _pages(source).first.remove('entry');
    _pages(source).last.remove('entry');
    _layout(source)['id'] = 'home';
    final runtime = DeclarativeAppModule(_parser.parse(source));
    expect(runtime.ui.whereType<UiPageRegistration>().length, 2);
    final entry = runtime.ui.whereType<UiEntryRegistration>().single;
    expect(entry.id, 'app.composition.test.home');
    expect(entry.pageId, 'app.composition.test.tasks');
    expect(entry.defaultMount.placement, UiPlacement.page);
    source['layouts'] = [];
    expect(
      DeclarativeAppModule(_parser.parse(source)).ui
          .whereType<UiEntryRegistration>(),
      isEmpty,
    );
  });

  test(
    'page entry references a host slot without changing its target page',
    () {
      final source = _source();
      _pages(source).last['entry'] = {
        'id': 'openTasks',
        'label': '打开任务',
        'opening': 'detail',
        'placement': 'page',
        'targetPageId': 'home',
        'slotId': 'actions',
        'order': -1,
      };
      final entry = DeclarativeAppModule(_parser.parse(source)).ui
          .whereType<UiEntryRegistration>()
          .singleWhere((entry) => entry.id.endsWith('.openTasks'));
      expect(entry.pageId, 'app.composition.test.tasks');
      expect(entry.defaultMount.pageId, 'app.composition.test.home');
      expect(entry.defaultMount.slotId, 'actions');
      expect(entry.opening, UiOpening.detail);
      expect(entry.content, isFalse);
    },
  );

  test('fully qualified local and cross-module page IDs remain unchanged', () {
    final source = _source();
    _layout(source)['pageId'] = 'app.external.module.child';
    _layout(source)['hostPageId'] = 'app.external.module.home';
    final entry = DeclarativeAppModule(_parser.parse(source)).ui
        .whereType<UiEntryRegistration>()
        .last;
    expect(entry.pageId, 'app.external.module.child');
    expect(entry.defaultMount.pageId, 'app.external.module.home');
    _layout(source)['pageId'] = 'app.composition.test.tasks';
    expect(
      DeclarativeAppModule(_parser.parse(source)).ui
          .whereType<UiEntryRegistration>()
          .last
          .pageId,
      'app.composition.test.tasks',
    );
  });

  test('v1 retains navigation registration and refuses executable layouts', () {
    final source = _source()..['formatVersion'] = 1;
    source['pages'] = [
      {'id': 'tasks', 'title': '任务', 'view': 'list'},
    ];
    source['layouts'] = [];
    final module = DeclarativeAppModule(_parser.parse(source));
    expect(module.ui.single, isA<NavigationRegistration>());
    source['layouts'] = [
      {'id': 'unsupported'},
    ];
    expect(
      () => DeclarativeAppModule(_parser.parse(source)),
      throwsFormatException,
    );
    source['formatVersion'] = 3;
    expect(() => _parser.parse(source), throwsFormatException);
  });

  final invalidCases = <String, void Function(Map<String, Object?>)>{
    'non-integer format version': (source) => source['formatVersion'] = 2.0,
    'composition capability missing': (source) =>
        (source['manifest'] as Map)['requiresCapabilities'] = [
          'ui.registry',
          'tasks.query',
        ],
    'registry capability missing': (source) =>
        (source['manifest'] as Map)['requiresCapabilities'] = [
          'ui.composition',
          'tasks.query',
        ],
    'register permission missing': (source) =>
        (source['manifest'] as Map)['permissions'] = ['tasks.read'],
    'view reference missing': (source) =>
        _pages(source).last['view'] = 'missing',
    'container has view': (source) => _pages(source).first['view'] = 'list',
    'unknown page kind': (source) => _pages(source).first['kind'] = 'code',
    'unknown context': (source) =>
        _pages(source).last['requiredContext'] = ['secret'],
    'duplicate context': (source) =>
        _pages(source).last['requiredContext'] = ['taskId', 'taskId'],
    'non-boolean retainPosition': (source) =>
        _pages(source).last['retainPosition'] = 'true',
    'page visual style': (source) => _pages(source).first['color'] = '#ffffff',
    'slot visual style': (source) =>
        (_pages(source).first['slots'] as List).first['width'] = 200,
    'non-boolean public': (source) =>
        (_pages(source).first['slots'] as List).first['public'] = 1,
    'zero capacity': (source) =>
        (_pages(source).first['slots'] as List).first['capacity'] = 0,
    'unknown slot context': (source) =>
        (_pages(source).first['slots'] as List).first['requiredContext'] = [
          'token',
        ],
    'duplicate slot': (source) => (_pages(source).first['slots'] as List).add({
      'id': 'body',
      'label': '重复',
    }),
    'entry is true': (source) => _pages(source).last['entry'] = true,
    'entry duplicate': (source) =>
        _pages(source).last['entry'] = {'id': 'home'},
    'entry/layout collision': (source) =>
        _pages(source).last['entry'] = {'id': 'taskTab'},
    'unknown placement': (source) => _layout(source)['placement'] = 'floating',
    'unknown opening': (source) => _layout(source)['opening'] = 'script',
    'layout visual style': (source) => _layout(source)['css'] = 'display:none',
    'entry visual style': (source) =>
        _pages(source).last['entry'] = {'height': 20},
    'non-boolean content': (source) => _layout(source)['content'] = 'true',
    'non-integer order': (source) => _layout(source)['order'] = 0.5,
    'missing host': (source) => _layout(source).remove('hostPageId'),
    'missing slot': (source) => _layout(source).remove('slotId'),
    'unknown local target': (source) => _layout(source)['pageId'] = 'missing',
    'unknown local host': (source) =>
        _layout(source)['hostPageId'] = 'app.composition.test.missing',
    'unknown local slot': (source) => _layout(source)['slotId'] = 'missing',
    'content mounted to entries': (source) =>
        _layout(source)['slotId'] = 'actions',
    'entry mounted to tabs': (source) => _layout(source)['content'] = false,
    'global content': (source) => _layout(source)['placement'] = 'main',
  };
  for (final invalidCase in invalidCases.entries) {
    test('rejects ${invalidCase.key}', () {
      final source = _source();
      invalidCase.value(source);
      expect(() => _parser.parse(source), throwsFormatException);
    });
  }

  test(
    'runtime does not permit task views without their own read permission',
    () {
      final source = _source();
      (source['manifest'] as Map)['permissions'] = ['ui.register'];
      expect(
        () => DeclarativeAppModule(_parser.parse(source)),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'missing context and missing own permission issue no task queries',
    (tester) async {
      final module = _parser.parse(_source());
      var subscriptions = 0;
      final bus = QueryBus()
        ..register(
          'task.list',
          permission: 'tasks.read',
          handler: (_) async => [],
          watchHandler: (_) {
            subscriptions++;
            return Stream<Object?>.value([]);
          },
        );
      Future<void> mount(PageContext context, List<String> permissions) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [queryBusProvider.overrideWith((ref) async => bus)],
            child: MaterialApp(
              home: Scaffold(
                body: DeclarativeTaskPage(
                  module: module,
                  moduleContext: ModuleContext(
                    moduleId: module.manifest.id,
                    permissions: permissions,
                  ),
                  page: module.pages.last,
                  pageContext: context,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
      }

      await mount(const PageContext(), ['tasks.read']);
      expect(find.textContaining('页面上下文失效'), findsOneWidget);
      expect(subscriptions, 0);
      await mount(
        const PageContext(taskId: 'taskA', projectId: 'projectA'),
        [],
      );
      expect(find.textContaining('lacks required permission'), findsOneWidget);
      expect(subscriptions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'task annotations use template IDs and preserve field permissions',
    (tester) async {
      final source = _source();
      _pages(source).last['requiredContext'] = [];
      source['fields'] = [
        {'id': 'score', 'label': '分数', 'type': 'number'},
      ];
      final module = _parser.parse(source);
      var subscriptions = 0;
      final bus = QueryBus()
        ..register(
          'task.list',
          permission: 'tasks.read',
          handler: (_) async => [],
          watchHandler: (_) {
            subscriptions++;
            return Stream<Object?>.value([
              {
                'id': 'privateTaskId',
                'title': 'privateTaskTitle',
                'completed': false,
              },
            ]);
          },
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [queryBusProvider.overrideWith((ref) async => bus)],
          child: MaterialApp(
            home: Scaffold(
              body: DeclarativeTaskPage(
                module: module,
                moduleContext: ModuleContext(
                  moduleId: module.manifest.id,
                  permissions: ['tasks.read'],
                ),
                page: module.pages.last,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final annotations = tester
          .widgetList<UiAnnotation>(find.byType(UiAnnotation))
          .toList();
      expect(annotations.map((annotation) => annotation.id), [
        'app.composition.test.tasks.task_card',
        'app.composition.test.tasks.task_card.fields',
      ]);
      for (final annotation in annotations) {
        final metadata = [
          annotation.id,
          annotation.name,
          annotation.moduleId,
          annotation.pagePath,
          annotation.slot,
          annotation.purpose,
        ].join(' ');
        expect(metadata, isNot(contains('privateTaskId')));
        expect(metadata, isNot(contains('privateTaskTitle')));
      }
      final fieldsButton = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '编辑扩展字段',
        ),
      );
      expect(fieldsButton.onPressed, isNull);
      expect(subscriptions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'task and project contexts intersect the original filter and clear stale data',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final pageContext = ValueNotifier(
        const PageContext(taskId: 'taskA', projectId: 'projectA'),
      );
      addTearDown(pageContext.dispose);
      addTearDown(database.close);
      await tester.runAsync(() => _seed(database));
      final module = _parser.parse(_source());
      await tester.pumpWidget(
        _taskWidget(
          module: module,
          database: database,
          pageContext: pageContext,
        ),
      );
      await _pumpDatabase(tester);
      expect(find.text('匹配任务'), findsOneWidget);
      expect(find.text('其他项目任务'), findsNothing);
      expect(find.text('被原过滤器排除'), findsNothing);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.key, isA<PageStorageKey>());
      pageContext.value = const PageContext(
        taskId: 'taskC',
        projectId: 'projectA',
      );
      await tester.pump();
      expect(find.text('匹配任务'), findsNothing);
      await _pumpDatabase(tester);
      expect(find.text('范围内暂无符合条件的任务'), findsOneWidget);
      expect(find.textContaining('页面上下文失效'), findsNothing);
      pageContext.value = const PageContext(
        taskId: 'taskA',
        projectId: 'projectB',
      );
      await _pumpDatabase(tester);
      expect(find.textContaining('页面上下文失效'), findsOneWidget);
      expect(find.text('匹配任务'), findsNothing);
      pageContext.value = const PageContext(
        taskId: 'missing',
        projectId: 'projectA',
      );
      await _pumpDatabase(tester);
      expect(find.textContaining('页面上下文失效'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpDatabase(tester);
    },
  );

  testWidgets('project-only scope detects project disappearance and recovers', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final source = _source();
    _pages(source).last['requiredContext'] = ['projectId'];
    final pageContext = ValueNotifier(const PageContext(projectId: 'projectA'));
    addTearDown(pageContext.dispose);
    addTearDown(database.close);
    await tester.runAsync(() => _seed(database));
    await tester.pumpWidget(
      _taskWidget(
        module: _parser.parse(source),
        database: database,
        pageContext: pageContext,
      ),
    );
    await _pumpDatabase(tester);
    expect(find.text('匹配任务'), findsOneWidget);
    expect(find.text('其他项目任务'), findsNothing);
    await tester.runAsync(
      () =>
          (database.update(
            database.projects,
          )..where((project) => project.id.equals('projectA'))).write(
            ProjectsCompanion(archivedAt: Value(DateTime(2026, 10, 6))),
          ),
    );
    await _pumpDatabase(tester);
    expect(find.textContaining('页面上下文失效'), findsOneWidget);
    expect(find.text('匹配任务'), findsNothing);
    await tester.runAsync(
      () =>
          (database.update(database.projects)
                ..where((project) => project.id.equals('projectA')))
              .write(const ProjectsCompanion(archivedAt: Value(null))),
    );
    await _pumpDatabase(tester);
    expect(find.text('匹配任务'), findsOneWidget);
    pageContext.value = const PageContext(projectId: 'missing');
    await _pumpDatabase(tester);
    expect(find.textContaining('页面上下文失效'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpDatabase(tester);
  });

  testWidgets('task context becomes invalid after soft deletion', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final source = _source();
    _pages(source).last['requiredContext'] = ['taskId'];
    final pageContext = ValueNotifier(const PageContext(taskId: 'taskA'));
    addTearDown(pageContext.dispose);
    addTearDown(database.close);
    await tester.runAsync(() => _seed(database));
    await tester.pumpWidget(
      _taskWidget(
        module: _parser.parse(source),
        database: database,
        pageContext: pageContext,
      ),
    );
    await _pumpDatabase(tester);
    expect(find.text('匹配任务'), findsOneWidget);
    await tester.runAsync(
      () =>
          (database.update(database.tasks)
                ..where((task) => task.id.equals('taskA')))
              .write(TasksCompanion(deletedAt: Value(DateTime(2026, 10, 6)))),
    );
    await _pumpDatabase(tester);
    expect(find.textContaining('页面上下文失效'), findsOneWidget);
    expect(find.text('匹配任务'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpDatabase(tester);
  });

  test('proposal preparation includes composition diffs and cannot apply altered mounts', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final store = DeclarativeModuleStore(database);
    final registry = ModuleRegistry(
      const [],
      capabilities: CapabilityRegistry(const [
        'ui.registry',
        'ui.composition',
        'tasks.query',
      ]),
    );
    final runtime = DeclarativeRuntimeController(
      store: store,
      registry: registry,
    );
    final service = ModuleProposalService(
      store: store,
      registry: registry,
      runtime: runtime,
    );
    addTearDown(database.close);
    addTearDown(registry.dispose);
    final source = _source();
    final proposal = await service.prepare(source);
    expect(await store.getInstalled('app.composition.test'), isNull);
    expect(
      proposal.diff.resources
          .singleWhere((change) => change.kind == 'page')
          .added,
      ['home', 'tasks'],
    );
    expect(
      proposal.diff.resources
          .singleWhere((change) => change.kind == 'layout')
          .added,
      ['taskTab'],
    );
    _layout(source)['hostPageId'] = 'app.other.module.home';
    expect(_layout(proposal.source)['hostPageId'], 'home');
    _layout(proposal.source)['hostPageId'] = 'app.other.module.home';
    await expectLater(service.apply(proposal), throwsStateError);
    expect(await store.getInstalled('app.composition.test'), isNull);
    final allowed = await service.prepare(_source());
    await service.apply(allowed);
    expect(
      (await store.getInstalled('app.composition.test'))?.version,
      '1.0.0',
    );
    final updateSource = _source();
    (updateSource['manifest'] as Map)['version'] = '1.1.0';
    _pages(updateSource).last['entry'] = {'placement': 'more'};
    _layout(updateSource)['order'] = 5;
    final update = await service.prepare(updateSource);
    expect(
      update.diff.resources
          .singleWhere((change) => change.kind == 'page')
          .changed,
      ['tasks'],
    );
    expect(
      update.diff.resources
          .singleWhere((change) => change.kind == 'layout')
          .changed,
      ['taskTab'],
    );
    (updateSource['manifest'] as Map)['permissions'] = [
      'ui.register',
      'tasks.read',
      'filesystem.read',
    ];
    await expectLater(service.prepare(updateSource), throwsStateError);
  });

  testWidgets(
    'review exposes cross-module targets, context, and explicit confirmation',
    (tester) async {
      final source = _source();
      _layout(source)['hostPageId'] = 'app.other.module.home';
      final module = _parser.parse(source);
      final proposal = ModuleProposal(
        source: source,
        module: module,
        expectedCurrentVersion: null,
        provenance: const ModuleInstallProvenance(origin: 'ai'),
        diff: ModuleProposalDiff(
          moduleId: module.manifest.id,
          fromVersion: null,
          toVersion: '1.0.0',
          permissionsAdded: const ['ui.register', 'tasks.read'],
          permissionsRemoved: const [],
          resources: const [
            ModuleResourceChange(
              kind: 'page',
              added: ['home', 'tasks'],
              removed: [],
              changed: [],
            ),
            ModuleResourceChange(
              kind: 'layout',
              added: ['taskTab'],
              removed: [],
              changed: [],
            ),
          ],
        ),
      );
      bool? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  confirmed = await showModuleProposalReview(
                    context: context,
                    proposal: proposal,
                  );
                },
                child: const Text('审核'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('审核'));
      await tester.pumpAndSettle();
      expect(find.textContaining('app.other.module.home'), findsOneWidget);
      expect(find.textContaining('所需上下文：taskId、projectId'), findsOneWidget);
      expect(find.textContaining('公开给其他模块'), findsOneWidget);
      expect(find.textContaining('不继承宿主权限'), findsOneWidget);
      expect(confirmed, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
    },
  );

  test(
    'AI prompt defines v1/v2 and preserves permissions and safe output limits',
    () async {
      final overrides = _PromptHttpOverrides();
      await HttpOverrides.runWithHttpOverrides(() async {
        final result = await const OpenAiCompatibleProvider().generateModule(
          endpoint: Uri.parse('https://model.example/v1/chat/completions'),
          model: 'test-model',
          apiKey: '',
          request: '生成组合页',
          installedModules: const [],
        );
        expect(_parser.parse(result).formatVersion, 2);
        for (final term in [
          'ui.composition',
          'targetPageId',
          'hostPageId',
          'requiredContext',
          'retainPosition',
          'public',
          'v1',
          'v2',
          'tasks.read',
          '不继承宿主权限',
          '禁止生成任意代码',
          '确认',
          '仅显式 entry 对象',
          '不自动进入主导航',
        ]) {
          expect(overrides.client.request.systemPrompt, contains(term));
        }
      }, overrides);
    },
  );
}
