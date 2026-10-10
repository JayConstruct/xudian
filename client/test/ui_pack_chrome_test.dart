import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/core/module_host/host_settings_page.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/builtin_module_registration.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/ui/app_destination.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/core/ui/ui_pack_providers.dart';
import 'package:task_app/core/ui/ui_pack_settings_page.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

UiPackDefinition _pack({bool hideHeaderContent = false}) =>
    UiPackDefinition.parse(
      moduleId: 'test.ui',
      version: '1.0.0',
      digest: 'test-digest',
      source: {
        'contractVersion': 1,
        'tokens': {
          'light': {'primary': '#006633', 'canvas': '#EEEECC'},
        },
        'chrome': {
          'ui.chrome.bottomNav@1': {
            'tree': {
              'type': 'primitive',
              'name': 'padding',
              'props': {'padding': 20},
              'children': [
                {'type': 'base'},
              ],
            },
          },
          'ui.chrome.sidebar@1': {
            'tree': {
              'type': 'primitive',
              'name': 'column',
              'props': {'width': 216, 'fill': true},
              'children': [
                {
                  'type': 'primitive',
                  'name': 'text',
                  'props': {'text': '自定义侧栏'},
                },
                {
                  'type': 'primitive',
                  'name': 'expanded',
                  'children': [
                    {'type': 'slot', 'name': 'navigation'},
                  ],
                },
                {'type': 'slot', 'name': 'settings'},
              ],
            },
          },
          'ui.chrome.header@1': {
            'tree': hideHeaderContent
                ? {
                    'type': 'primitive',
                    'name': 'column',
                    'children': [
                      {
                        'type': 'primitive',
                        'name': 'text',
                        'props': {'text': '仅自定义标题'},
                      },
                      {'type': 'slot', 'name': 'title'},
                      {'type': 'slot', 'name': 'actions'},
                    ],
                  }
                : {
                    'type': 'primitive',
                    'name': 'column',
                    'children': [
                      {
                        'type': 'primitive',
                        'name': 'text',
                        'props': {'text': '自定义顶栏'},
                      },
                      {'type': 'base'},
                    ],
                  },
          },
        },
      },
    );

class _Workspace implements AppModule {
  _Workspace({this.extraEntries = false});
  final bool extraEntries;
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'test.workspace',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );
  @override
  List<UiRegistration> get ui => [
    UiPageRegistration(
      id: 'test.page',
      moduleId: manifest.id,
      title: '测试工作区',
      builder: (context, _) => ListView(
        key: const ValueKey('test-list'),
        children: [
          for (var i = 0; i < 40; i++) ListTile(title: Text('记录 $i')),
          SizedBox(
            key: const ValueKey('test-bottom-inset'),
            height: WorkspaceContentInsets.bottomOf(context),
          ),
        ],
      ),
    ),
    UiEntryRegistration(
      id: 'test.entry',
      moduleId: manifest.id,
      pageId: 'test.page',
      label: '测试工作区',
      icon: Icons.list,
    ),
    if (extraEntries)
      for (var i = 0; i < 5; i++) ...[
        UiPageRegistration(
          id: 'test.menu.page.$i',
          moduleId: manifest.id,
          title: '模块页面 $i',
          builder: (_, _) => Text('模块入口内容 $i'),
        ),
        UiEntryRegistration(
          id: 'test.menu.entry.$i',
          moduleId: manifest.id,
          pageId: 'test.menu.page.$i',
          label: i == 4 ? '模块入口 4：完整显示的较长选项名称' : '模块入口 $i',
          icon: Icons.extension_outlined,
          defaultMount: const UiMount(placement: UiPlacement.header),
          opening: UiOpening.detail,
        ),
      ],
  ];
}

void main() {
  testWidgets('custom dock reports added height and retains native selection', (
    tester,
  ) async {
    final sizes = <Size>[];
    var selected = -1;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: UiPackScope(
            previewPacks: {'test.ui': _pack()},
            previewSelection: UiSelection(globalPackId: 'test.ui'),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 360,
                  child: MobileBottomDock(
                    destinations: [
                      for (var i = 0; i < 2; i++)
                        AppDestination(
                          id: '$i',
                          label: '导航 $i',
                          icon: Icons.circle,
                          selectedIcon: Icons.circle,
                          builder: (_) => const SizedBox.shrink(),
                        ),
                    ],
                    selectedIndex: 0,
                    onSelected: (value) => selected = value,
                    showNavigation: true,
                    onSizeChanged: sizes.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sizes.last.height, 112);
    await tester.tap(find.text('导航 1'));
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  group('production chrome', () {
    late AppDatabase db;
    late CollectionStore store;
    late Directory directory;
    late ModuleHost host;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = CollectionStore(db);
      directory = await Directory.systemTemp.createTemp('ui-chrome-');
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: UiSelectionController.storageKey,
              value: jsonEncode(UiSelection(globalPackId: 'test.ui').toJson()),
            ),
          );
    });
    tearDown(() async {
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });
    for (final width in [320.0, 1280.0]) {
      testWidgets(
        'one protected menu retains all module entries and host settings at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final app = XudianApp();
          app.registry.registerBuiltin(
            BuiltinModuleRegistration(
              module: _Workspace(extraEntries: true),
              title: '测试',
              description: '含多个菜单入口的工作区',
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
                uiPackRegistryProvider.overrideWith(
                  (_) =>
                      Stream.value({'test.ui': _pack(hideHeaderContent: true)}),
                ),
              ],
              child: app,
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pumpAndSettle();
          expect(find.text('仅自定义标题'), findsOneWidget);
          final header = find.byKey(const ValueKey('workspace-header-region'));
          expect(
            find.descendant(of: header, matching: find.byType(IconButton)),
            findsOneWidget,
          );
          expect(find.byTooltip('打开设置'), findsNothing);
          expect(find.byTooltip('界面风格与恢复'), findsNothing);
          await tester.tap(find.byTooltip('页面菜单'));
          await tester.pumpAndSettle();
          for (var i = 0; i < 5; i++) {
            expect(find.textContaining('模块入口 $i'), findsOneWidget);
          }
          final last = find.text('模块入口 4：完整显示的较长选项名称');
          await tester.ensureVisible(last);
          await tester.tap(last);
          await tester.pumpAndSettle();
          expect(find.text('模块入口内容 4'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('页面菜单'));
          await tester.pumpAndSettle();
          final settings = find.widgetWithText(PopupMenuItem<int>, '设置');
          await tester.ensureVisible(settings);
          await tester.tap(settings);
          await tester.pumpAndSettle();
          expect(find.byType(HostSettingsPage), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'production custom chrome leaves default recovery available and measures inset',
      (tester) async {
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = XudianApp();
        app.registry.registerBuiltin(
          BuiltinModuleRegistration(
            module: _Workspace(),
            title: '测试',
            description: '测试工作区',
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
              uiPackRegistryProvider.overrideWith(
                (_) => Stream.value({'test.ui': _pack()}),
              ),
            ],
            child: app,
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
        expect(find.text('自定义顶栏'), findsOneWidget);
        final workspace = tester.element(
          find.byKey(const ValueKey('test-list')),
        );
        expect(WorkspaceContentInsets.bottomOf(workspace), closeTo(136, .01));
        expect(AppDesign.canvas(workspace), const Color(0xFFEEEECC));
        await tester.tap(find.byKey(const ValueKey('workspace-menu')));
        await tester.pumpAndSettle();
        expect(find.text('界面风格与恢复'), findsNothing);
        await tester.tap(find.widgetWithText(PopupMenuItem<int>, '设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('外观与交互'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('界面风格'));
        await tester.pumpAndSettle();
        expect(find.byType(UiPackSettingsPage), findsOneWidget);
        final restore = find.text('恢复默认界面');
        await tester.ensureVisible(restore);
        await tester.tap(restore);
        await tester.pumpAndSettle();
        expect(find.text('已恢复默认界面，业务数据保留'), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        expect(find.text('自定义顶栏'), findsNothing);
        expect(find.text('记录 0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'desktop custom sidebar preserves host entries and protected recovery',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = XudianApp();
        app.registry.registerBuiltin(
          BuiltinModuleRegistration(
            module: _Workspace(),
            title: '测试',
            description: '测试',
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
              uiPackRegistryProvider.overrideWith(
                (_) => Stream.value({'test.ui': _pack()}),
              ),
            ],
            child: app,
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
        expect(find.text('自定义侧栏'), findsOneWidget);
        expect(find.text('设置'), findsOneWidget);
        await tester.tap(find.text('更多'));
        await tester.pumpAndSettle();
        expect(find.text('模块'), findsOneWidget);
        await tester.tap(find.text('模块'));
        await tester.pumpAndSettle();
        expect(find.byType(HostManagerPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('workspace-menu')));
        await tester.pumpAndSettle();
        expect(find.text('界面风格与恢复'), findsNothing);
        await tester.tap(find.widgetWithText(PopupMenuItem<int>, '设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('外观与交互'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('界面风格'));
        await tester.pumpAndSettle();
        expect(find.byType(UiPackSettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
