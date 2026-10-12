import 'dart:convert';
import 'dart:io';

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
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/builtin_module_registration.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/ui/app_navigation.dart';
import 'package:task_app/core/ui/module_detail_page.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/features/settings/ui_layout.dart';

Future<void> _settleNative(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('gallery-workspace-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    final source = Directory('../packages/modules/app.ui.examples');
    final files = <String, String>{};
    for (final file in source.listSync().whereType<File>()) {
      if (file.path.endsWith('.js')) {
        files[file.uri.pathSegments.last] = await file.readAsString();
      }
    }
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          object(
            jsonDecode(await File('${source.path}/module.json').readAsString()),
          ),
          files,
        ),
        allowUnsignedLocal: true,
      ),
    );
    final layout = UiLayout(
      narrow: UiLayoutProfile(
        mainLimit: null,
        mounts: {
          'app.ui.examples.entry': const UiMount(
            placement: UiPlacement.main,
            order: 1,
          ),
        },
      ),
    );
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: UiLayoutController.storageKey,
            value: jsonEncode(layout.toJson()),
          ),
        );
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'dock gallery switches workspace; demos push detail and return to retained search',
    (tester) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigation = _CountingNavigation();
      final app = XudianApp();
      app.registry.registerBuiltin(
        const BuiltinModuleRegistration(
          module: _HomeModule(),
          title: '测试工作区',
          description: 'UI 示例入口导航回归',
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
            appNavigationProvider.overrideWithValue(navigation),
          ],
          child: app,
        ),
      );
      await _settleNative(tester);
      Finder dockEntry(String label) => find.descendant(
        of: find.byType(MobileBottomDock),
        matching: find.text(label),
      );
      final initialPushes = navigation.pushes;
      expect(find.text('测试正文'), findsOneWidget);
      await tester.tap(dockEntry('UI 示例'));
      await _settleNative(tester);
      expect(navigation.pushes, initialPushes);
      expect(find.byType(ModuleDetailPage), findsNothing);
      final dock = tester.widget<MobileBottomDock>(
        find.byType(MobileBottomDock),
      );
      expect(dock.destinations[dock.selectedIndex].id, 'app.ui.examples.entry');
      expect(find.text('测试正文'), findsNothing);

      final directoryPage = find.byWidgetPredicate(
        (widget) =>
            widget is ScriptPage &&
            widget.pageContext['pageId'] == 'app.ui.examples.page',
      );
      final retainedDirectory = tester.state(directoryPage);
      await tester.enterText(find.byType(TextField), '日期选择器');
      await _settleNative(tester);
      final demo = find.widgetWithText(ListTile, '日期选择器');
      await tester.scrollUntilVisible(
        demo,
        150,
        scrollable: find.descendant(
          of: find.descendant(
            of: directoryPage,
            matching: find.byType(ListView),
          ),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
      );
      await tester.tap(demo);
      await _settleNative(tester);
      expect(navigation.pushes, initialPushes + 1);
      expect(find.byType(ModuleDetailPage), findsOneWidget);
      expect(find.text('固定到首页'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await _settleNative(tester);
      expect(find.byType(ModuleDetailPage), findsNothing);
      expect(tester.state(directoryPage), same(retainedDirectory));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '日期选择器',
      );
      expect(find.widgetWithText(ListTile, '日期选择器'), findsOneWidget);

      await tester.tap(dockEntry('测试首页'));
      await _settleNative(tester);
      expect(find.text('测试正文'), findsOneWidget);
      await tester.tap(dockEntry('UI 示例'));
      await _settleNative(tester);
      expect(navigation.pushes, initialPushes + 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '日期选择器',
      );
      expect(find.widgetWithText(ListTile, '日期选择器'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _CountingNavigation extends AppNavigation {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

class _HomeModule implements AppModule {
  const _HomeModule();

  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'test.gallery.home',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );

  @override
  List<UiRegistration> get ui => [
    UiPageRegistration(
      id: 'test.gallery.home.page',
      moduleId: manifest.id,
      title: '测试首页',
      builder: (_, _) => const Center(child: Text('测试正文')),
    ),
    UiEntryRegistration(
      id: 'test.gallery.home.entry',
      moduleId: manifest.id,
      pageId: 'test.gallery.home.page',
      label: '测试首页',
      icon: Icons.home,
      defaultMount: const UiMount(placement: UiPlacement.main, order: 0),
    ),
  ];
}
