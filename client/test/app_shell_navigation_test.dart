import 'package:task_app/core/ui/workspace_interaction.dart';
import 'package:task_app/core/ui/ui_surfaces.dart';
import 'package:task_app/core/module_host/script_page.dart';

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/app/more_workspace_page.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/ui/module_detail_page.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/builtin_module_registration.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/features/settings/ui_layout.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class TestAssistantModule implements AppModule {
  TestAssistantModule(this.registration);
  final WorkspaceAssistantRegistration registration;
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'test.assistant',
    version: '1.0.0',
    coreApi: '^1.0.0',
    permissions: ['ui.register'],
  );
  @override
  List<UiRegistration> get ui => [registration];
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late Directory dir;
  late ModuleHost host;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    dir = await Directory.systemTemp.createTemp('shell-navigation-');
    host = ModuleHost(store: store, directory: dir);
    await host.initialize();
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.navigation',
              'name': '导航测试',
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
              for (final (id, label, placement, order) in [
                ('home', '日程测试', 'main', 0),
                ('schedule', '课表测试', 'main', 1),
                ('tool', '目录工具', 'more', 2),
              ])
                {
                  'id': 'test.navigation.$id',
                  'title': label,
                  'handler': 'render',
                  if (id == 'home') 'headerMode': 'contributed',
                  'entry': {
                    'id': 'test.navigation.$id',
                    'opening': 'workspace',
                    'placement': placement,
                    'order': order,
                  },
                },
              for (final id in ['detail', 'importer', 'preview'])
                {
                  'id': 'test.navigation.$id',
                  'title': id,
                  'handler': 'render',
                  if (id == 'importer') 'headerMode': 'contributed',
                },
            ],
          },
          {
            'main.js': """
import {ui} from '@xudian/sdk';
export async function render({event,context,state={}}) {
  if(event?.type==='schedule')await ui.navigate('test.navigation.schedule',{source:'daily'});
  if(event?.type==='detail')await ui.navigate('test.navigation.detail');
  if(event?.type==='panel')await ui.panel('test.navigation.importer',{}, {adaptive:true,wide:'center'});
  if(event?.type==='importer')await ui.navigate('test.navigation.importer');
  if(event?.type==='handoff')await ui.navigate('test.navigation.schedule',{source:'importer',importPlanId:'review-plan'});
  if(event?.type==='invalid')await ui.navigate('test.navigation.missing');
  if(context.pageId.endsWith('.schedule')&&context.importPlanId&&!state.routed) {
    state.routed=true;await ui.navigate('test.navigation.preview',{importPlanId:context.importPlanId});
  }
  return {state,...(context.pageId.endsWith('.home')?{header:{title:'日程测试',compact:true,actions:[
    {label:'操作历史',icon:'history',presentation:'inline',event:{type:'history'}},
    {label:'新建',icon:'add',variant:'filled',presentation:'inline',event:{type:'panel'}}
  ]}}:{}),...(context.pageId.endsWith('.importer')?{header:{title:'导入详情',backEvent:{type:'internalBack'}}}:{}),tree:{type:'column',children:[
    {type:'text',text:'正文 '+context.pageId},
    ...(context.pageId.endsWith('.home')?[
      {type:'button',text:'查看课表',event:{type:'schedule'}},
      {type:'button',text:'打开详情',event:{type:'detail'}},
      {type:'button',text:'打开面板',event:{type:'panel'}}
    ]:[]),
    ...(context.pageId.endsWith('.detail')?[{type:'button',text:'打开导入器',event:{type:'importer'}}]:[]),
    ...(context.pageId.endsWith('.importer')?[
      {type:'button',text:'交接预览',event:{type:'handoff'}},
      {type:'button',text:'无效目标',event:{type:'invalid'}}
    ]:[]),
    ...(context.pageId.endsWith('.preview')?[{type:'text',text:'确认预览 '+context.importPlanId}]:[]),
    ...(context.source?[{type:'text',text:'来自 '+context.source}]:[])
  ]}};
}
""",
          },
        ),
        allowUnsignedLocal: true,
      ),
    );
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  testWidgets(
    'active workspace drag hides only the dock and navigation invalidates old drag callbacks',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
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
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: app,
        ),
      );
      await settle(tester);
      final pageContext = tester.element(find.byType(ScriptPage).first);
      final scope = WorkspaceInteractionScope.maybeOf(pageContext)!;
      final owner = Object();
      final pageBounds = tester.getRect(find.byType(ScriptPage).first);
      final inset = WorkspaceContentInsets.bottomOf(pageContext);
      final headerBounds = tester.getRect(
        find.byKey(const ValueKey('workspace-header-region')).first,
      );
      scope.controller.setDragging(scope.lease, owner, true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('workspace-drag-dock-opacity')),
            )
            .opacity,
        0,
      );
      expect(tester.getRect(find.byType(ScriptPage).first), pageBounds);
      expect(
        WorkspaceContentInsets.bottomOf(
          tester.element(find.byType(ScriptPage).first),
        ),
        inset,
      );
      expect(
        tester.getRect(
          find.byKey(const ValueKey('workspace-header-region')).first,
        ),
        headerBounds,
      );
      expect(find.text('新建').hitTestable(), findsOneWidget);
      scope.controller.setDragging(scope.lease, owner, false);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('workspace-drag-dock-opacity')),
            )
            .opacity,
        1,
      );
      scope.controller.setDragging(scope.lease, owner, true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看课表'));
      await settle(tester);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('workspace-drag-dock-opacity')),
            )
            .opacity,
        1,
      );
      scope.controller.setDragging(scope.lease, owner, true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('workspace-drag-dock-opacity')),
            )
            .opacity,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile script panel owns a title and closes independently of internal back',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
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
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: app,
        ),
      );
      await settle(tester);
      expect(find.text('新建').hitTestable(), findsOneWidget);
      await tester.tap(find.text('新建'));
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('导入详情').hitTestable(), findsOneWidget);
      expect(find.byTooltip('关闭面板').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('关闭面板'));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('新建').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'adaptive centered panel uses a wide dialog and closes on workspace navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 900);
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
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: app,
        ),
      );
      await settle(tester);
      await tester.tap(find.text('打开面板'));
      await settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final bounds = tester.getRect(find.byType(Dialog));
      expect(bounds.center.dx, closeTo(550, 1));
      await tester.tap(find.text('交接预览'));
      await settle(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('确认预览 review-plan').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final fromPanel in [false, true]) {
    testWidgets(
      'workspace handoff from ${fromPanel ? 'panel' : 'nested detail with internal back'} reveals the provider preview',
      (tester) async {
        final app = XudianApp();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          app.registry.dispose();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWith((_) async => db),
              moduleHostProvider.overrideWith((_) async => host),
            ],
            child: app,
          ),
        );
        await settle(tester);
        await tester.tap(find.text(fromPanel ? '打开面板' : '打开详情'));
        await settle(tester);
        if (!fromPanel) {
          await tester.tap(find.text('打开导入器'));
          await settle(tester);
        }
        expect(find.text('交接预览').hitTestable(), findsOneWidget);
        // An unavailable target must leave the current detail/panel visible.
        await tester.tap(find.text('无效目标'));
        await settle(tester);
        expect(find.text('Page unavailable'), findsOneWidget);
        expect(find.textContaining('Bad state:'), findsNothing);
        expect(find.text('交接预览').hitTestable(), findsOneWidget);
        await tester.tap(find.text('交接预览'));
        await settle(tester);
        await tester.pumpAndSettle();
        expect(find.text('确认预览 review-plan').hitTestable(), findsOneWidget);
        expect(find.text('交接预览'), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        final dock = tester.widget<MobileBottomDock>(
          find.byType(MobileBottomDock, skipOffstage: false),
        );
        expect(
          dock.destinations[dock.selectedIndex].id,
          'test.navigation.schedule',
        );
        await tester.tap(find.byTooltip('返回'));
        await settle(tester);
        expect(find.text('来自 importer').hitTestable(), findsOneWidget);
        expect(find.byType(ModuleDetailPage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'More is a workspace, AI follows support and navigation reuses a dock page',
    (tester) async {
      final app = XudianApp();
      var assistantCalls = 0;
      app.registry.registerBuiltin(
        BuiltinModuleRegistration(
          title: '测试助手',
          description: '导航测试',
          module: TestAssistantModule(
            WorkspaceAssistantRegistration(
              id: 'test.assistant',
              label: 'AI',
              supports: (modules) => modules.contains('test.navigation'),
              onOpen: (_, _) async {
                assistantCalls++;
              },
            ),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        app.registry.dispose();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: app,
        ),
      );
      await settle(tester);
      Finder dockLabel(String label) => find.descendant(
        of: find.byType(MobileBottomDock),
        matching: find.text(label),
      );
      expect(
        tester
            .widget<MobileBottomDock>(find.byType(MobileBottomDock))
            .destinations
            .first
            .id,
        'app.shell.more',
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile-navigation-assistant')),
      );
      expect(assistantCalls, 1);
      await tester.tap(find.text('查看课表'));
      await settle(tester);
      final dock = tester.widget<MobileBottomDock>(
        find.byType(MobileBottomDock),
      );
      expect(
        dock.destinations[dock.selectedIndex].id,
        'test.navigation.schedule',
      );
      expect(find.byType(ModuleDetailPage), findsNothing);
      expect(find.text('来自 daily'), findsOneWidget);
      await tester.tap(dockLabel('更多'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(MoreWorkspacePage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-navigation-assistant')),
        findsNothing,
      );
      expect(find.byType(BottomSheet), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileBottomDock)),
      );
      await tester.runAsync(
        () => container
            .read(uiLayoutProvider.notifier)
            .save(UiLayout(narrow: UiLayoutProfile(morePageEnabled: false))),
      );
      await settle(tester);
      expect(dockLabel('更多'), findsNothing);
      await tester.tap(find.byTooltip('页面菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部入口'));
      await settle(tester);
      expect(find.byType(MoreWorkspacePage), findsOneWidget);
      expect(find.text('目录工具'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
