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
                  'entry': {
                    'id': 'test.navigation.$id',
                    'opening': 'workspace',
                    'placement': placement,
                    'order': order,
                  },
                },
            ],
          },
          {
            'main.js': """
import {ui} from '@xudian/sdk';
export async function render({event,context}) {
  if(event?.type==='schedule')await ui.navigate('test.navigation.schedule',{source:'daily'});
  return {tree:{type:'column',children:[
    {type:'text',text:'正文 '+context.pageId},
    ...(context.pageId.endsWith('.home')?[{type:'button',text:'查看课表',event:{type:'schedule'}}]:[]),
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
