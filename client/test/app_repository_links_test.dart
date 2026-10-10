import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/host_settings_page.dart';
import 'package:task_app/core/module_host/module_catalog_page.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/app_repository_links.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

const _projectUrl = 'https://github.com/JayConstruct/xudian';
const _modulesUrl = 'https://github.com/JayConstruct/xudian-modules';

Future<void> _showLinks(
  WidgetTester tester, {
  required Future<bool> Function(Uri) launch,
  VoidCallback? onBrowseModules,
  bool largeText = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [externalUrlLauncherProvider.overrideWithValue(launch)],
      child: MaterialApp(
        builder: largeText
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              )
            : null,
        home: Scaffold(
          body: ListView(
            children: [
              AppRepositoryLinks(onBrowseModules: onBrowseModules ?? () {}),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('repository links open their exact public URLs', (tester) async {
    final launched = <Uri>[];
    await _showLinks(
      tester,
      launch: (uri) async {
        launched.add(uri);
        return true;
      },
    );
    expect(find.text('关于序点'), findsOneWidget);
    expect(find.text(_projectUrl), findsOneWidget);
    expect(find.text(_modulesUrl), findsOneWidget);
    await tester.tap(find.text('项目地址'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模块仓库'));
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse(_projectUrl), Uri.parse(_modulesUrl)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy buttons copy exact project and module addresses', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _showLinks(tester, launch: (_) async => true);
    await tester.tap(find.byTooltip('复制项目地址'));
    await tester.pumpAndSettle();
    expect(copied, [_projectUrl]);
    expect(find.text('地址已复制'), findsOneWidget);
    await tester.tap(find.byTooltip('复制模块仓库地址'));
    await tester.pumpAndSettle();
    expect(copied, [_projectUrl, _modulesUrl]);
    expect(find.text('地址已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final throws in [false, true]) {
    testWidgets(
      throws
          ? 'launcher exception offers copy fallback'
          : 'launcher false result offers copy fallback',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await _showLinks(
          tester,
          launch: (_) async {
            if (throws) throw PlatformException(code: 'unavailable');
            return false;
          },
        );
        await tester.tap(find.text('模块仓库'));
        await tester.pumpAndSettle();
        expect(find.text('无法打开链接，请复制地址'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('复制模块仓库地址'));
        await tester.pumpAndSettle();
        expect(copied, _modulesUrl);
        expect(find.text('地址已复制'), findsOneWidget);
      },
    );
  }

  testWidgets('browse modules invokes the existing catalog entry callback', (
    tester,
  ) async {
    var opened = 0;
    await _showLinks(
      tester,
      launch: (_) async => true,
      onBrowseModules: () => opened++,
    );
    await tester.tap(find.text('打开模块商店'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('links and actions remain readable at 320px with doubled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final launched = <Uri>[];
    var opened = 0;
    await _showLinks(
      tester,
      launch: (uri) async {
        launched.add(uri);
        return true;
      },
      onBrowseModules: () => opened++,
      largeText: true,
    );
    expect(tester.takeException(), isNull);
    for (final (title, url) in [('项目地址', _projectUrl), ('模块仓库', _modulesUrl)]) {
      expect(find.text(url), findsOneWidget);
      await tester.ensureVisible(find.text(title));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.text('打开模块商店'));
    await tester.tap(find.text('打开模块商店'));
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse(_projectUrl), Uri.parse(_modulesUrl)]);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings opens published modules using the configured directory',
    (tester) async {
      const repository = 'Example/module-directory';
      final catalogUrl =
          'https://raw.githubusercontent.com/$repository/main/catalog.json';
      late AppDatabase db;
      late CollectionStore store;
      late ModuleHost host;
      late ModuleCatalogClient client;
      late Directory directory;
      late int moduleCount;
      final requested = <String>[];
      final registry = ModuleRegistry(
        const [],
        capabilities: CapabilityRegistry(const []),
      );
      await tester.runAsync(() async {
        db = AppDatabase(NativeDatabase.memory());
        store = CollectionStore(db);
        directory = await Directory.systemTemp.createTemp('settings-catalog-');
        host = ModuleHost(
          store: store,
          directory: Directory('${directory.path}/host'),
        );
        await host.initialize();
        await db.customStatement(
          "INSERT OR REPLACE INTO host_meta(key,value) VALUES('module-catalog-repository',?)",
          [repository],
        );
        final catalogBytes = await File('../packages/catalog/catalog.json')
            .readAsBytes();
        final catalog = jsonDecode(utf8.decode(catalogBytes)) as Map;
        final modules = catalog['modules'] as List;
        moduleCount = modules.length;
        expect(
          modules.map((module) => module['id']),
          containsAll(['app.import.shiguang', 'app.schedule']),
        );
        expect(
          modules.map((module) => module['id']),
          isNot(contains('app.import.zhengfang')),
        );
        final fixtures = <String, List<int>>{catalogUrl: catalogBytes};
        for (final module in catalog['modules'] as List) {
          fixtures[module['indexUrl'] as String] = await File(
            '../module-index/${module['id']}.json',
          ).readAsBytes();
        }
        client = ModuleCatalogClient(
          repository: repository,
          cacheDirectory: Directory('${directory.path}/cache'),
          networkRetries: 0,
          transport:
              (url, {cancellation, onProgress, required maximumBytes}) async {
                requested.add(url.toString());
                final bytes = fixtures[url.toString()];
                if (bytes == null) {
                  throw StateError('Unexpected catalog request: $url');
                }
                onProgress?.call(bytes.length, bytes.length);
                return bytes;
              },
        );
      });
      addTearDown(() async {
        client.dispose();
        registry.dispose();
        await host.close();
        await store.close();
        await db.close();
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
            moduleCatalogClientProvider.overrideWith((_) async => client),
          ],
          child: MaterialApp(home: HostSettingsPage(registry: registry)),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.text('关于序点'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('打开模块商店'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('打开模块商店'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('打开模块商店')));
      for (var i = 0; i < 48; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byType(ModuleCatalogPage), findsOneWidget);
      expect(find.text('模块商店'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('商店设置'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('商店设置')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('商店设置'));
      await tester.pumpAndSettle();
      expect(find.text('目录：$repository'), findsOneWidget);
      expect(requested, contains(catalogUrl));
      for (final name in ['拾光教务导入兼容', '大学课表']) {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump();
        await tester.enterText(find.byType(TextField), name);
        await tester.pumpAndSettle();
        final moduleName = find.descendant(
          of: find.byType(Card),
          matching: find.text(name),
        );
        await tester.scrollUntilVisible(
          moduleName,
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(moduleName, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(
        requested.where((url) => url.contains('/module-index/')),
        hasLength(moduleCount),
      );
      expect(find.text('版本索引不可用'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
