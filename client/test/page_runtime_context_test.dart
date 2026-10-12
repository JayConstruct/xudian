import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/page_runtime_context.dart';
import 'package:task_app/core/ui/module_detail_page.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_page_host.dart';
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/core/ui/workspace_header.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

class _ContainerModule implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'test.container',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );
  @override
  List<UiRegistration> get ui => [
    UiPageRegistration(
      id: 'test.container.home',
      moduleId: 'test.container',
      title: 'Shared',
      headerMode: 'date',
      container: true,
      builder: (_, _) => const SizedBox.shrink(),
      slots: const [
        PageSlotDefinition(
          id: 'daily',
          label: 'Contributions',
          kind: PageSlotKind.sections,
          isPublic: true,
          inline: true,
        ),
      ],
    ),
    UiPageRegistration(
      id: 'test.container.nested',
      moduleId: 'test.container',
      title: 'Nested',
      headerMode: 'date',
      container: true,
      builder: (_, _) => const SizedBox.shrink(),
      slots: const [
        PageSlotDefinition(
          id: 'daily',
          label: 'Nested',
          kind: PageSlotKind.sections,
          inline: true,
        ),
      ],
    ),
    UiEntryRegistration(
      id: 'test.container.nested.entry',
      moduleId: 'test.container',
      pageId: 'test.container.nested',
      label: 'Nested',
      icon: Icons.pages,
      content: true,
      defaultMount: const UiMount(
        placement: UiPlacement.page,
        pageId: 'test.container.home',
        slotId: 'daily',
        order: 200,
      ),
    ),
    UiPageRegistration(
      id: 'test.container.future',
      moduleId: 'test.container',
      title: 'Future',
      builder: (_, context) =>
          Text('future ${context.values['selectedDate'] ?? 'none'}'),
    ),
    UiEntryRegistration(
      id: 'test.container.future.entry',
      moduleId: 'test.container',
      pageId: 'test.container.future',
      label: 'Future',
      icon: Icons.pages,
      content: true,
      defaultMount: const UiMount(
        placement: UiPlacement.page,
        pageId: 'test.container.nested',
        slotId: 'daily',
      ),
    ),
    UiPageRegistration(
      id: 'test.container.other',
      moduleId: 'test.container',
      title: 'Other',
      headerMode: 'date',
      builder: (context, values) => Column(
        children: [
          Text('other ${values.values['selectedDate'] ?? 'none'}'),
          TextButton(
            onPressed: () =>
                PageRuntimeContextScope.read(context)!
                    .update({'selectedDate': '2030-01-01'}),
            child: const Text('Change other'),
          ),
        ],
      ),
    ),
  ];
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late ModuleRegistry registry;
  late WorkspaceHeaderController header;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('page-runtime-');
    header = WorkspaceHeaderController();
    header.activate(
      identity: 'container-root',
      moduleId: 'test.container',
      pageId: 'test.container.home',
      enabled: true,
      mode: 'date',
      isActive: () => true,
    );
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    for (final id in ['navigation', 'tasks']) {
      final bytes = await ScriptPackage.build(
        {
          'formatVersion': 3,
          'manifest': {
            'id': 'test.$id',
            'version': '1.0.0',
            'hostApi': '^1.16.0',
            'dataVersion': 1,
            'permissions': [],
            'dependencies': [],
          },
          'entryPoint': 'main.js',
          'services': [],
          'collections': [],
          'pages': [
            {
              'id': 'test.$id.page',
              'title': id,
              'handler': 'render',
              'entry': {
                'id': 'test.$id.feed',
                'placement': 'page',
                'targetPageId': 'test.container.home',
                'slotId': 'daily',
                'content': true,
                'order': id == 'navigation' ? 0 : 100,
              },
            },
          ],
        },
        {
          'main.js': id == 'navigation'
              ? r'''
import {ui} from '@xudian/sdk';
export function render({context={},state={},event}) {
  const selectedDate = event?.type==='selectDate' ? event.value : context.selectedDate||'2026-10-01';
  state={...state,renders:(state.renders||0)+1};
  return {state,runtimeContextPatch:ui.runtimeContextPatch({selectedDate}),tree:{type:'column',children:[
    {type:'text',text:'overview renders '+state.renders},
    {type:'dayOverview',date:selectedDate,selectedDate,todayDate:'2026-10-01',dateHeading:false,
      days:['2026-10-01','2026-10-02','2026-10-03'].map(date=>({date,label:'日期'})),event:{type:'selectDate'}}]}};
}
'''
              : r'''
import {ui} from '@xudian/sdk';
export function render({context={},state={},event}) {
  if(event?.type==='expand') state={...state,open:true};
  if(event?.type==='increment') state={...state,count:(state.count||0)+1};
  return {state,...(context.selectedDate ? {runtimeContextPatch:ui.runtimeContextPatch({selectedDate:context.selectedDate})}:{}),tree:{type:'column',children:[
    {type:'text',text:'tasks date '+(context.selectedDate||'none')},
    {type:'text',text:'retained count '+(state.count||0)},
    {type:'button',text:'Increment',event:{type:'increment'}},
    state.open ? {type:'input',key:'quickDraft',text:'Quick draft'} : {type:'button',text:'Expand quick draft',event:{type:'expand'}}]}};
}
''',
        },
      );
      await host.install(
        await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
      );
    }
    registry = ModuleRegistry([
      _ContainerModule(),
      for (final instance in host.instances.values)
        ScriptAppModule(host, instance.package),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
  });
  tearDown(() async {
    header.dispose();
    registry.dispose();
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(
    WidgetTester tester, {
    PageContext pageContext = const PageContext(),
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: WorkspaceHeaderScope(
            controller: header,
            lease: header.lease,
            child: Scaffold(
              body: Row(
                children: [
                  Expanded(
                    child: UiPageHost(
                      registry: registry,
                      pageId: 'test.container.home',
                      pageContext: pageContext,
                    ),
                  ),
                  Expanded(
                    child: UiPageHost(
                      registry: registry,
                      pageId: 'test.container.other',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'one composition shares dates including nested contributions without replacing draft or state; other roots stay isolated',
    (tester) async {
      final records = await store.sql('SELECT * FROM host_records');
      final operations = await store.sql('SELECT * FROM host_operations');
      final preferences = await store.sql('SELECT * FROM host_ui_preferences');
      await show(tester);
      expect(header.content!.spec['title'], '10月1日 周四');
      expect(find.text('tasks date 2026-10-01'), findsOneWidget);
      expect(find.text('future 2026-10-01'), findsOneWidget);
      expect(find.text('other none'), findsOneWidget);
      await tester.tap(find.text('Increment'));
      await settle(tester);
      await tester.tap(find.text('Expand quick draft'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'unfinished quick draft');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      final pageStates = find
          .byType(ScriptPage)
          .evaluate()
          .map((element) => (element as StatefulElement).state)
          .toList();
      await tester.tap(find.byTooltip('后一天'));
      await settle(tester);
      expect(header.content!.spec['title'], '10月2日 周五');
      expect(find.text('tasks date 2026-10-02'), findsOneWidget);
      expect(find.text('future 2026-10-02'), findsOneWidget);
      expect(find.text('retained count 1'), findsOneWidget);
      final updated = tester.widget<TextField>(find.byType(TextField));
      expect(updated.controller, same(field.controller));
      expect(updated.focusNode, same(field.focusNode));
      expect(updated.controller!.text, 'unfinished quick draft');
      expect(
        updated.controller!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(
        find
            .byType(ScriptPage)
            .evaluate()
            .map((element) => (element as StatefulElement).state),
        orderedEquals(pageStates),
      );
      await tester.tap(find.text('Change other'));
      await settle(tester);
      expect(find.text('other 2030-01-01'), findsOneWidget);
      expect(header.content!.spec['title'], '10月2日 周五');
      expect(find.text('tasks date 2026-10-02'), findsOneWidget);
      final overview = tester.widget<Text>(
        find.textContaining('overview renders'),
      );
      await settle(tester);
      expect(
        tester.widget<Text>(find.textContaining('overview renders')).data,
        overview.data,
      );
      expect(
        await tester.runAsync(() => store.sql('SELECT * FROM host_records')),
        records,
      );
      expect(
        await tester.runAsync(() => store.sql('SELECT * FROM host_operations')),
        operations,
      );
      expect(
        await tester.runAsync(
          () => store.sql('SELECT * FROM host_ui_preferences'),
        ),
        preferences,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an external date navigation supersedes a local choice without replacing state, draft or scroll',
    (tester) async {
      await show(
        tester,
        pageContext: const PageContext(values: {'selectedDate': '2026-10-01'}),
      );
      await tester.tap(find.byTooltip('后一天'));
      await settle(tester);
      expect(find.text('tasks date 2026-10-02'), findsOneWidget);
      await tester.tap(find.text('Increment'));
      await settle(tester);
      await tester.tap(find.text('Expand quick draft'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'draft across navigation');
      final field = tester.widget<TextField>(find.byType(TextField));
      final pageStates = find
          .byType(ScriptPage)
          .evaluate()
          .map((element) => (element as StatefulElement).state)
          .toList();
      final root = find.byWidgetPredicate(
        (widget) =>
            widget is UiPageHost && widget.pageId == 'test.container.home',
      );
      final rootState = tester.state(root);
      final scrollable = find.ancestor(
        of: find.text('tasks date 2026-10-02'),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      final offset = position.pixels;

      await show(
        tester,
        pageContext: const PageContext(values: {'selectedDate': '2026-10-03'}),
      );
      expect(find.text('tasks date 2026-10-03'), findsOneWidget);
      expect(find.text('future 2026-10-03'), findsOneWidget);
      expect(header.content!.spec['title'], '10月3日 周六');
      expect(find.text('retained count 1'), findsOneWidget);
      expect(tester.state(root), same(rootState));
      expect(
        find
            .byType(ScriptPage)
            .evaluate()
            .map((element) => (element as StatefulElement).state),
        orderedEquals(pageStates),
      );
      final updated = tester.widget<TextField>(find.byType(TextField));
      expect(updated.controller, same(field.controller));
      expect(updated.focusNode, same(field.focusNode));
      expect(updated.controller!.text, 'draft across navigation');
      final updatedPosition = tester
          .state<ScrollableState>(
            find.ancestor(
              of: find.text('tasks date 2026-10-03'),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(updatedPosition, same(position));
      expect(updatedPosition.pixels, offset);

      // Subsequent inherited runtime updates retain priority over the unchanged
      // navigation input, including through nested inline contributions.
      await tester.tap(find.byTooltip('后一天'));
      await settle(tester);
      expect(find.text('tasks date 2026-10-04'), findsOneWidget);
      expect(find.text('future 2026-10-04'), findsOneWidget);
      expect(find.text('other none'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an older render cannot restore its date after rapid context changes',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Expand quick draft'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'retained while querying');
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['test.tasks']!.workflowTail = gate.future;
      await tester.tap(find.byTooltip('后一天'));
      await settle(tester);
      await tester.tap(find.byTooltip('后一天'));
      await settle(tester);
      expect(find.text('future 2026-10-03'), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(find.text('tasks date 2026-10-03'), findsOneWidget);
      expect(find.text('future 2026-10-03'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'retained while querying',
      );
      await tester.tap(find.text('回到今天'));
      await settle(tester);
      expect(find.text('tasks date 2026-10-01'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rapid explicit date choices queue the latest selection during an overview render',
    (tester) async {
      await show(tester);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['test.navigation']!.workflowTail = gate.future;
      Finder date(String value) => find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == value,
      );
      await tester.tap(date('2026-10-02'));
      await tester.pump();
      await tester.tap(date('2026-10-03'));
      await tester.pump();
      gate.complete();
      await settle(tester);
      expect(find.text('tasks date 2026-10-03'), findsOneWidget);
      expect(find.text('future 2026-10-03'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'date-mode script pages supply date context but cannot forge their leased header',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.leaf',
              'version': '1.0.0',
              'hostApi': '^1.17.0',
              'dataVersion': 1,
              'permissions': [],
              'dependencies': [],
            },
            'entryPoint': 'main.js',
            'services': [],
            'collections': [],
            'pages': [
              {
                'id': 'test.leaf.home',
                'title': 'Leaf date',
                'handler': 'render',
                'headerMode': 'date',
              },
            ],
          },
          {
            'main.js': r"export function render(){return {state:{},runtimeContextPatch:{selectedDate:'2027-01-01'},header:{title:'forged title',autoHideChrome:true},tree:{type:'text',text:'Leaf body'}};}",
          },
        );
        await host.install(
          await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
        );
        registry.addOrReplace(
          ScriptAppModule(host, host.instances['test.leaf']!.package),
        );
      });
      header.activate(
        identity: 'leaf-date',
        moduleId: 'test.leaf',
        pageId: 'test.leaf.home',
        enabled: true,
        mode: 'date',
        isActive: () => true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: MaterialApp(
            home: WorkspaceHeaderScope(
              controller: header,
              lease: header.lease,
              child: Scaffold(
                body: UiPageHost(registry: registry, pageId: 'test.leaf.home'),
              ),
            ),
          ),
        ),
      );
      expect(header.content, isNull);
      await settle(tester);
      expect(find.text('Leaf body'), findsOneWidget);
      expect(header.content!.spec['title'], '2027年1月1日 周五');
      expect(header.content!.spec['autoHideChrome'], isNull);
      expect(
        header.content!.owner,
        isNot(same(tester.state(find.byType(ScriptPage)))),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ModuleDetailPage(
              registry: registry,
              pageId: 'test.leaf.home',
              title: 'Temporary entry title',
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.widgetWithText(AppBar, '2027年1月1日 周五'), findsOneWidget);
      expect(find.text('Temporary entry title'), findsNothing);
      expect(find.text('Leaf body'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('runtime patches accept civil dates and reject identities or invalid values atomically', () {
    expect(validateRuntimeContextPatch({'selectedDate': '2024-02-29'}), {
      'selectedDate': '2024-02-29',
    });
    for (final patch in [
      null,
      [],
      {'selectedDate': '2026-02-30'},
      {'selectedDate': null},
      {'selectedDate': '0000-01-01'},
      {'taskId': 'other'},
      {'projectId': 'other'},
      {'entities': []},
      {'pageId': 'other'},
      {'selectedDate': '2026-10-02', 'taskId': 'other'},
    ]) {
      expect(() => validateRuntimeContextPatch(patch), throwsFormatException);
    }
    expect(
      const PageContext(values: {'selectedDate': '2026-10-01', 'filter': 'a'})
          .navigationIdentity,
      const PageContext(values: {'selectedDate': '2026-10-02', 'filter': 'a'})
          .navigationIdentity,
    );
    expect(
      packWithoutEvents().components['ui.dayOverview@1']!.contract.events,
      contains('change'),
    );
  });
}

UiPackDefinition packWithoutEvents() => UiPackDefinition.parse(
  moduleId: 'test.legacy',
  version: '1.0.0',
  digest: 'x',
  source: {
    'contractVersion': 1,
    'components': {
      'ui.dayOverview@1': {
        'tree': {
          'type': 'primitive',
          'name': 'text',
          'props': {'text': 'legacy overview'},
        },
      },
    },
  },
);
