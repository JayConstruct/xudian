import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/core/ui/workspace_header.dart';
import 'package:task_app/core/ui/ui_pack_providers.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('ui-page-state-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    final script = await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': 'test.page',
          'version': '1.0.0',
          'hostApi': '^1.6.0',
          'dataVersion': 1,
          'permissions': ['ui'],
          'dependencies': [],
        },
        'entryPoint': 'main.js',
        'pages': [],
        'services': [],
        'collections': [
          {
            'id': 'records',
            'schema': {'type': 'object'},
          },
        ],
      },
      {
        'main.js': r'''
import {data,ui} from '@xudian/sdk';
let stableRenders=0;
export async function renderStable({state={},context={}}) {
  await data.query('records',{});
  if(context.notify) await ui.notify({message:'foreground'});
  return {state,tree:{type:'text',text:'stable '+(++stableRenders)+' date '+context.selectedDate}};
}
export function renderDisclosure({state={},event}) {
  return {state,tree:{type:'disclosure',text:'详细安排',children:[
    {type:'text',text:'折叠正文'},
    {type:'button',text:'确认安排',event:{type:'confirm'}},
    ...(event?.type==='confirm'?[{type:'text',text:'已确认'}]:[])
  ]}};
}
export async function renderConversation({state={},event,formValues={}}) {
  const messages=state.messages||Array.from({length:16},(_,i)=>'历史消息 '+i);
  if(event?.type==='send') {
    await ui.dialog({title:'等待回复',fields:[{key:'answer',label:'回复'}]});
    messages.push(formValues.message);
  }
  return {state:{messages},clearForms:event?.type==='send'?['message']:[],tree:{
    type:'column',compact:true,spacing:12,followEnd:messages.length,
    header:{type:'pageHeader',title:'测试对话',subtitle:'当前模型',actions:[{label:'对话设置',icon:'settings',event:{type:'settings'}}]},
    children:messages.map((text,i)=>({type:'chatMessage',key:'message:'+i,text,role:i%2?'assistant':'user',label:'助手'})),
    footer:{type:'messageComposer',key:'message',text:'输入消息…',event:{type:'send'}}
  }};
}
export async function render({state={},event,context={}}) {
  await data.query('records',{});
  state={...state,count:(state.count||0)+1};
  const items=[{type:'text',text:'render '+state.count},{type:'text',text:'date '+(context.selectedDate||'none')},
    {type:'input',key:'draft',text:'草稿'},
    {type:'button',text:'执行',event:{type:'execute'}},
    ...Array.from({length:1000},(_,i)=>({type:'text',key:'row-'+i,text:'记录 '+i}))];
  return {state,header:{title:'Cached header'},tree:ui.component('ui.page.list@1',{key:'records',slots:{items}})};
}
''',
      },
    );
    await host.install(
      await ScriptPackage.verify(script, allowUnsignedLocal: true),
    );
  });
  tearDown(() async {
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

  Future<ProviderContainer> show(
    WidgetTester tester, {
    bool active = true,
    bool waitForRender = true,
    Map<String, Object?> pageContext = const {},
    WorkspaceHeaderController? headers,
    String handler = 'render',
  }) async {
    Widget page = ScriptPage(
      host: host,
      moduleId: 'test.page',
      handler: handler,
      pageContext: pageContext,
    );
    if (headers != null) {
      page = WorkspaceHeaderScope(
        controller: headers,
        lease: headers.lease,
        child: page,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: MaterialApp(
          home: UiPackScope(
            child: Scaffold(
              body: TickerMode(enabled: active, child: page),
            ),
          ),
        ),
      ),
    );
    if (waitForRender) await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ScriptPage)));
  }

  testWidgets(
    'conversation pins header and protects an edited draft during send',
    (tester) async {
      final response = Completer<Object?>();
      host.interaction = (_, method, args) async {
        expect(method, 'ui.dialog');
        return response.future;
      };
      await show(tester, handler: 'renderConversation');
      expect(find.text('历史消息 15').hitTestable(), findsOneWidget);
      expect(find.text('测试对话').hitTestable(), findsOneWidget);
      final input = find.byType(TextField);
      await tester.enterText(input, '发送的消息');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await settle(tester);
      await tester.enterText(input, '下一条草稿');
      response.complete({'answer': 'OK'});
      await settle(tester);
      expect(tester.widget<TextField>(input).controller!.text, '下一条草稿');
      expect(find.text('发送的消息'), findsOneWidget);
      expect(find.text('测试对话').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disclosure shares continuous shape and retains expansion and actions',
    (tester) async {
      await show(tester, handler: 'renderDisclosure');
      final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
      expect(tile.shape, isA<RoundedSuperellipseBorder>());
      expect(tile.collapsedShape, tile.shape);
      await tester.tap(find.text('详细安排'));
      await tester.pumpAndSettle();
      expect(find.text('折叠正文').hitTestable(), findsOneWidget);
      await tester.tap(find.text('确认安排'));
      await settle(tester);
      expect(find.text('已确认'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a successful foreground date is replayed after an unrelated write',
    (tester) =>
        withClock(Clock.fixed(DateTime.utc(2026, 10, 15, 12)), () async {
          await show(
            tester,
            handler: 'renderStable',
            pageContext: {'selectedDate': '2026-10-01'},
          );
          expect(find.text('stable 1 date 2026-10-01'), findsOneWidget);
          await show(
            tester,
            handler: 'renderStable',
            pageContext: {'selectedDate': '2026-10-05'},
          );
          expect(find.text('stable 2 date 2026-10-05'), findsOneWidget);
          store.recordDataChange({'unrelated.module'});
          final gate = Completer<void>();
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          host.instances['test.page']!.workflowTail = gate.future;
          await show(
            tester,
            handler: 'renderStable',
            pageContext: {'selectedDate': '2026-10-01'},
          );
          expect(find.text('stable 1 date 2026-10-01'), findsOneWidget);
          gate.complete();
          await tester.pumpWidget(const SizedBox.shrink());
        }),
  );

  testWidgets('foreground effects remain visible on every date visit', (
    tester,
  ) async {
    var notifications = 0;
    host.interaction = (_, method, _) async {
      if (method == 'ui.notify') notifications++;
      return null;
    };
    for (final date in ['2026-10-01', '2026-10-05', '2026-10-01']) {
      await show(
        tester,
        handler: 'renderStable',
        pageContext: {'selectedDate': date, 'notify': true},
      );
    }
    expect(notifications, 3);
    expect(find.text('stable 3 date 2026-10-01'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a write without stream notification invalidates a visited date',
    (tester) async {
      await show(
        tester,
        handler: 'renderStable',
        pageContext: {'selectedDate': '2026-10-01'},
      );
      await show(
        tester,
        handler: 'renderStable',
        pageContext: {'selectedDate': '2026-10-05'},
      );
      await tester.runAsync(() async {
        final actor = host.instances['test.page']!.actor;
        final session = SnapshotSession(actor, 'no-notification');
        await store.stage(session, actor, {
          'writes': [
            {
              'collection': 'records',
              'id': 'new',
              'value': {'id': 'new'},
            },
          ],
        });
        await store.commit(
          store.seal(session).id,
          actor,
          authorize: (_) {},
          audit: false,
        );
      });
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['test.page']!.workflowTail = gate.future;
      await show(
        tester,
        handler: 'renderStable',
        waitForRender: false,
        pageContext: {'selectedDate': '2026-10-01'},
      );
      expect(
        find.text('stable 1 date 2026-10-01', skipOffstage: false),
        findsNothing,
      );
      gate.complete();
      await settle(tester);
      expect(find.text('stable 3 date 2026-10-01'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'first script frame keeps fast loading quiet and only shows feedback after 500ms',
    (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['test.page']!.workflowTail = gate.future;
      await show(tester, waitForRender: false);
      expect(find.text('正在加载页面…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 501));
      expect(find.text('正在加载页面…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      gate.complete();
      await settle(tester);
      expect(find.text('render 1'), findsOneWidget);
      expect(find.text('正在加载页面…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'normal refresh keeps real content and delays progress feedback',
    (tester) async {
      await show(tester);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['test.page']!.workflowTail = gate.future;
      await tester.tap(find.widgetWithText(FilledButton, '执行'));
      await tester.pump();
      expect(find.text('render 1'), findsOneWidget);
      expect(find.text('正在加载页面…'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 501));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(find.text('render 2'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retained inactive pages defer changes and resume without losing content or drafts',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), '保留草稿');
      final retained = tester.state(find.byType(ScriptPage));
      await show(tester, active: false);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      host.instances['test.page']!.workflowTail = gate.future;
      host.store.changes.add({'test.page'});
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('render 1'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await show(tester, waitForRender: false);
      expect(tester.state(find.byType(ScriptPage)), same(retained));
      expect(find.text('render 1'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留草稿',
      );
      expect(find.text('正在加载页面…'), findsNothing);
      gate.complete();
      await settle(tester);
      expect(find.text('render 2'), findsOneWidget);
      expect(find.text('render 3'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a retained script restores its header under the new active lease without rerendering',
    (tester) async {
      final headers = WorkspaceHeaderController();
      addTearDown(headers.dispose);
      var active = true;
      void activate(String identity, {String moduleId = 'test.page'}) =>
          headers.activate(
            identity: identity,
            moduleId: moduleId,
            pageId: 'test.page.main',
            enabled: true,
            isActive: () => active,
          );
      activate('first');
      const pageContext = {'pageId': 'test.page.main'};
      await show(tester, pageContext: pageContext, headers: headers);
      expect(headers.content?.spec['title'], 'Cached header');
      final retained = tester.state(find.byType(ScriptPage));
      active = false;
      activate('other', moduleId: 'other.page');
      await show(
        tester,
        active: false,
        pageContext: pageContext,
        headers: headers,
      );
      expect(headers.content, isNull);
      active = true;
      activate('return');
      await show(
        tester,
        waitForRender: false,
        pageContext: pageContext,
        headers: headers,
      );
      expect(tester.state(find.byType(ScriptPage)), same(retained));
      expect(headers.content?.spec['title'], 'Cached header');
      expect(find.text('render 1'), findsOneWidget);
      await settle(tester);
      expect(find.text('render 2'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a changed date never paints the previous date while its render is pending',
    (tester) async {
      await show(tester, pageContext: {'selectedDate': '2026-10-01'});
      expect(find.text('date 2026-10-01'), findsOneWidget);
      final previousElement = tester.element(find.text('date 2026-10-01'));
      final draft = tester.widget<TextField>(find.byType(TextField));
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      // Exercise a genuinely cold date: a prepared neighbor can otherwise
      // answer without entering the blocked foreground workflow.
      final dynamic renderer = tester.state(find.byType(ScriptPage));
      renderer.dateCache.clear();
      host.instances['test.page']!.workflowTail = gate.future;
      await show(
        tester,
        waitForRender: false,
        pageContext: {'selectedDate': '2026-10-02'},
      );
      expect(find.text('date 2026-10-01'), findsNothing);
      expect(
        tester.element(find.text('date 2026-10-01', skipOffstage: false)),
        same(previousElement),
        reason: 'Pending records stay mounted without being painted',
      );
      expect(find.text('date 2026-10-01').hitTestable(), findsNothing);
      expect(find.text('正在加载页面…'), findsNothing);
      gate.complete();
      await settle(tester);
      expect(find.text('date 2026-10-02'), findsOneWidget);
      expect(
        tester.element(find.text('date 2026-10-02')),
        same(previousElement),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(draft.controller),
      );
      expect(find.text('date 2026-10-01'), findsNothing);
      expect(find.text('正在加载页面…'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> installUi(WidgetTester tester) async {
    await tester.runAsync(() async {
      final bytes = await ScriptPackage.build({
        'formatVersion': 3,
        'manifest': {
          'id': 'test.presentation',
          'kind': 'uiPack',
          'version': '1.0.0',
          'hostApi': '^1.6.0',
          'dataVersion': 1,
          'permissions': [],
          'dependencies': [],
        },
        'collections': [],
        'services': [],
        'pages': [],
        'uiPack': {
          'contractVersion': 1,
          'components': {
            'ui.input@1': {
              'tree': {
                'type': 'primitive',
                'name': 'padding',
                'props': {'padding': 20},
                'children': [
                  {'type': 'base'},
                ],
              },
            },
            'ui.button@1': {
              'tree': {
                'type': 'primitive',
                'name': 'button',
                'props': {
                  'variant': 'outlined',
                  'label': {
                    'bind': ['props', 'label'],
                  },
                },
                'event': 'press',
              },
            },
          },
          'templates': {
            'ui.page.list@1': {
              'tree': {
                'type': 'primitive',
                'name': 'card',
                'props': {'padding': 10},
                'children': [
                  {'type': 'base'},
                ],
              },
            },
          },
        },
      }, {});
      await host.install(
        await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
      );
    });
    await settle(tester);
  }

  for (final packed in [false, true]) {
    testWidgets(
      'legacy button retains enabled appearance during execution, UI pack=$packed',
      (tester) async {
        final container = await show(tester);
        if (packed) {
          await installUi(tester);
          await tester.runAsync(
            () => container
                .read(uiSelectionProvider.notifier)
                .save(UiSelection(globalPackId: 'test.presentation')),
          );
          await settle(tester);
        }
        final button = packed
            ? find.widgetWithText(OutlinedButton, '执行')
            : find.widgetWithText(FilledButton, '执行');
        final before = tester.state(button);
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        host.instances['test.page']!.workflowTail = gate.future;
        await tester.tap(button);
        await tester.pump();
        expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
        expect(identical(tester.state(button), before), isTrue);
        await tester.tap(button);
        await tester.pump();
        gate.complete();
        await settle(tester);
        expect(find.text('render 2'), findsOneWidget);
        expect(find.text('render 3'), findsNothing);
        expect(identical(tester.state(button), before), isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'live recipe switch preserves production input state without executing page scripts',
    (tester) async {
      final container = await show(tester);
      expect(find.text('render 1'), findsOneWidget);
      expect(find.text('记录 999'), findsNothing);
      expect(find.byType(Text).evaluate().length, lessThan(40));
      await tester.enterText(find.byType(TextField), '未提交的草稿');
      final before = tester.widget<TextField>(find.byType(TextField));
      before.controller!.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      await installUi(tester);
      await tester.runAsync(
        () => container
            .read(uiSelectionProvider.notifier)
            .save(UiSelection(globalPackId: 'test.presentation')),
      );
      await settle(tester);
      final after = tester.widget<TextField>(find.byType(TextField));
      expect(identical(before.controller, after.controller), isTrue);
      expect(identical(before.focusNode, after.focusNode), isTrue);
      expect(after.controller!.text, '未提交的草稿');
      expect(
        after.controller!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(after.focusNode!.hasFocus, isTrue);
      expect(find.text('render 1'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(tester.takeException(), isNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'only read module changes refresh a page and template switches preserve scroll position',
    (tester) async {
      final container = await show(tester);
      store.changes.add({'other.module'});
      await settle(tester);
      expect(find.text('render 1'), findsOneWidget);
      store.changes.add({'test.page'});
      await settle(tester);
      expect(find.text('render 2'), findsOneWidget);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(600);
      await tester.pump();
      await installUi(tester);
      await tester.runAsync(
        () => container
            .read(uiSelectionProvider.notifier)
            .save(UiSelection(globalPackId: 'test.presentation')),
      );
      await settle(tester);
      final after = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(identical(scroll, after), isTrue);
      expect(after.position.pixels, 600);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
