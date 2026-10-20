import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/planner_board.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/workspace_header.dart';
import 'package:task_app/core/ui/workspace_header_action.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

const _adjustKey = ValueKey<(String, Object?)>((
  'workspace-inline-action',
  '调整',
));

Future<void> _settle(WidgetTester tester) async {
  for (var iteration = 0; iteration < 24; iteration++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late AppDatabase database;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(database);
    directory = await Directory.systemTemp.createTemp('planner-header-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.timeline',
              'name': '规划顶栏测试',
              'version': '1.0.0',
              'hostApi': '^1.18.0',
              'dataVersion': 1,
              'permissions': ['ui'],
              'dependencies': [],
            },
            'entryPoint': 'main.js',
            'collections': [],
            'services': [],
            'pages': [
              for (final (page, title, order) in [
                ('home', '任务规划', 0),
                ('other', '其他页面', 1),
              ])
                {
                  'id': 'test.timeline.$page',
                  'title': title,
                  'handler': 'render',
                  'headerMode': 'contributed',
                  'entry': {
                    'id': 'test.timeline.$page',
                    'opening': 'workspace',
                    'placement': 'main',
                    'order': order,
                  },
                },
            ],
          },
          {
            'main.js': r'''
export function render({state={},event,context}) {
  state={...state,renders:(state.renders||0)+1};
  if(event?.type==='history')state.history=true;
  if(event?.type==='back')state.history=false;
  if(event?.type==='legacy')state.legacy=!state.legacy;
  const home=context.pageId==='test.timeline.home';
  return {state,header:{
    title:state.history?'操作历史':home?'任务规划':'其他标题',compact:true,
    ...(!state.legacy&&home?{layout:'plannerTimeline'}:{}),
    ...(state.history?{backEvent:{type:'back'}}:{}),
    actions:state.history?[]:[
      {label:'新建',icon:'add',iconOnly:true,presentation:'inline',overflowOnly:true,event:{type:'add'}},
      {label:'操作历史',icon:'history',presentation:'menu',event:{type:'history'}},
      {label:'旧顶栏',presentation:'menu',event:{type:'legacy'}}
    ]},tree:{type:'column',children:[
      {type:'text',text:'JS render '+state.renders+' event '+(event?.type||'none')},
      ...(!state.history?[{type:'plannerBoard',key:'board',
        days:[{date:'2026-10-20',label:'周二'}],candidates:[],blocks:[],
        quickAdjustment:{taskModuleId:'app.tasks',applyServiceId:'planner.operation.apply',undoServiceId:'planner.batch.undo'}
      }]:[])
    ]}};
}
''',
          },
        ),
        allowUnsignedLocal: true,
      ),
    );
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, {double width = 390}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = XudianApp();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      app.registry.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => database),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: app,
      ),
    );
    await _settle(tester);
  }

  WorkspaceHeaderController headers(WidgetTester tester) =>
      WorkspaceHeaderScope.read(tester.element(find.byType(ScriptPage).first))!
          .controller;

  PlannerBoard board(WidgetTester tester) =>
      tester.widget<PlannerBoard>(find.byType(PlannerBoard).first);

  testWidgets('planner has a single 48dp row and preserves native chrome', (
    tester,
  ) async {
    await show(tester);
    final title = tester.widget<Text>(find.text('任务规划').first);
    expect(title.style!.fontSize, 20);
    expect(title.maxLines, 1);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('workspace-header-region')))
          .height,
      48,
    );
    expect(find.byKey(_adjustKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey('planner-standalone-quick-adjust')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(_adjustKey),
        matching: find.byWidgetPredicate(
          (widget) => widget is UiComponent && widget.ref == 'ui.button@1',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('调整'), findsOneWidget);
    expect(find.byTooltip('快速调整'), findsOneWidget);
    final add = find.byTooltip('新建');
    expect(tester.getSize(add), const Size(44, 44));
    final iconButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '新建',
      ),
    );
    expect(iconButton.isSelected, isNull);
    expect(iconButton.style!.backgroundColor?.resolve({}), isNull);
    expect(find.byType(MobileBottomDock), findsOneWidget);
    final headerComponent = find.byWidgetPredicate(
      (widget) => widget is UiComponent && widget.ref == 'ui.chrome.header@1',
    );
    expect(headerComponent, findsOneWidget);
    await tester.tap(find.byTooltip('页面菜单'));
    await _settle(tester);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('操作历史'), findsOneWidget);
    expect(find.text('调整'), findsOneWidget);
    expect(find.text('新建'), findsNothing);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.tap(add);
    await _settle(tester);
    expect(find.text('JS render 2 event add'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick adjust is bidirectional, semantic and never invokes JS', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    final controller = headers(tester);
    final initial = controller.content!;
    final event = (initial.spec['actions'] as List).first['event'];
    expect(board(tester).quickAdjust, isFalse);
    await tester.tap(find.byKey(_adjustKey));
    await tester.pump();
    await tester.pump();
    expect(board(tester).quickAdjust, isTrue);
    expect(
      (controller.content!.spec['actions'] as List).first['selected'],
      true,
    );
    final toggle = tester.getSemantics(find.bySemanticsLabel('快速调整'));
    expect(toggle.flagsCollection.isToggled, Tristate.isTrue);
    expect(find.text('JS render 1 event none'), findsOneWidget);
    board(tester).onQuickAdjustChanged!(false);
    await tester.pump();
    expect(board(tester).quickAdjust, isFalse);
    expect(
      (controller.content!.spec['actions'] as List).first['selected'],
      false,
    );
    await initial.dispatch(event);
    await initial.dispatch(event);
    await tester.pump();
    expect(board(tester).quickAdjust, isFalse);
    expect(find.text('JS render 1 event none'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.content, isNull);
    await initial.dispatch(event);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('retained pages keep toggle but stale leases cannot change it', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(_adjustKey));
    await tester.pump();
    final oldHeader = headers(tester).content!;
    final event = (oldHeader.spec['actions'] as List).first['event'];
    await tester.tap(find.text('其他页面').last);
    await _settle(tester);
    expect(find.byKey(_adjustKey), findsNothing);
    final title = tester.widget<Text>(find.text('其他标题'));
    expect(title.style!.fontSize, 24);
    expect(title.maxLines, 3);
    expect(board(tester).quickAdjust, isFalse);
    await oldHeader.dispatch(event);
    await tester.tap(find.text('任务规划').last);
    await _settle(tester);
    expect(board(tester).quickAdjust, isTrue);
    await oldHeader.dispatch(event);
    await tester.pump();
    expect(board(tester).quickAdjust, isTrue);
    expect(find.text('JS render 1 event none'), findsOneWidget);
    await tester.tap(find.byTooltip('页面菜单'));
    await _settle(tester);
    await tester.tap(find.text('操作历史'));
    await _settle(tester);
    expect(find.byKey(_adjustKey), findsNothing);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(board(tester).quickAdjust, isTrue);
    expect(find.byKey(_adjustKey), findsOneWidget);
    final legacyRender = headers(tester).content!.dispatch({'type': 'legacy'});
    await _settle(tester);
    await legacyRender;
    expect(find.byKey(_adjustKey), findsNothing);
    expect(tester.widget<Text>(find.text('任务规划').first).style!.fontSize, 24);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('large text fits the planner header at ${width}dp', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(tester, width: width);
      final bounds = tester.getRect(
        find.byKey(const ValueKey('workspace-header-region')),
      );
      expect(bounds.height, greaterThanOrEqualTo(48));
      expect(bounds.height, lessThan(80));
      final title = tester.widget<Text>(find.text('任务规划').first);
      expect(title.maxLines, 1);
      for (final action in find.byType(WorkspaceHeaderAction).evaluate()) {
        final rectangle = tester.getRect(find.byWidget(action.widget));
        expect(rectangle.width, greaterThanOrEqualTo(44));
        expect(rectangle.height, greaterThanOrEqualTo(44));
        expect(rectangle.left, greaterThanOrEqualTo(bounds.left));
        expect(rectangle.right, lessThanOrEqualTo(bounds.right));
        expect(rectangle.bottom, lessThanOrEqualTo(bounds.bottom));
      }
      expect(find.byTooltip('页面菜单'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
