import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_catalog_page.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/core/module_host/module_management_widgets.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

Future<void> settleNative(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> waitForNativeWidget(
  WidgetTester tester,
  Finder target, {
  bool hitTestable = false,
}) async {
  final ready = hitTestable ? target.hitTestable() : target;
  final elapsed = Stopwatch()..start();
  while (ready.evaluate().isEmpty &&
      elapsed.elapsed < const Duration(seconds: 10)) {
    // Catalog resolution, cache flushes and package verification use real I/O.
    // Wait for the observable phase instead of assuming a fixed disk speed.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready,
    findsOneWidget,
    reason:
        tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | ') +
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((w) => w.data)
            .join(' | '),
  );
}

Future<ScriptPackage> package(
  String id, {
  String? dependency,
  String? name,
  bool metadata = true,
  List<String> permissions = const [],
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': id,
        'name': name ?? id,
        if (metadata) 'description': '导入课程所需的兼容服务',
        if (metadata) 'author': '测试作者',
        'version': '1.0.0',
        'hostApi': '^1.0.0',
        'dataVersion': 1,
        'permissions': permissions,
        'dependencies': [
          if (dependency != null) {'moduleId': dependency, 'version': '^1.0.0'},
        ],
      },
      'entryPoint': 'main.js',
      'collections': [],
      'pages': [],
      'services': [],
    },
    {'main.js': 'export function ready(){return true;}'},
  ),
  allowUnsignedLocal: true,
);

void main() {
  testWidgets(
    'erase removes an uninstalled legacy module from the list, cancellation keeps it',
    (tester) async {
      late AppDatabase db;
      late CollectionStore store;
      late ModuleHost host;
      late Directory dir;
      const id = 'app.import.zhengfang';
      const name = '正方教务导入（通用）';
      await tester.runAsync(() async {
        db = AppDatabase(NativeDatabase.memory());
        store = CollectionStore(db);
        dir = await Directory.systemTemp.createTemp('legacy-erasure-ui-');
        host = ModuleHost(store: store, directory: dir);
        await host.initialize();
        await host.install(await package(id, name: name));
        await host.uninstall(id);
      });
      addTearDown(() async {
        await host.close();
        await store.close();
        await db.close();
        await dir.delete(recursive: true);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((_) async => db),
            moduleHostProvider.overrideWith((_) async => host),
          ],
          child: const MaterialApp(home: Scaffold(body: HostManagerPage())),
        ),
      );
      await settleNative(tester);
      expect(find.text(name), findsOneWidget);
      expect(find.text('1.0.0 · 已卸载，数据保留'), findsOneWidget);
      for (final cancel in [true, false]) {
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('彻底删除数据与历史'));
        await settleNative(tester);
        expect(find.text('彻底删除模块数据和历史'), findsOneWidget);
        await tester.runAsync(
          () => tester.tap(find.text(cancel ? '取消' : '确认')),
        );
        await settleNative(tester);
        expect(find.text(name), cancel ? findsOneWidget : findsNothing);
      }
      await tester.runAsync(() async {
        expect(
          await store.sql(
            'SELECT * FROM host_installations WHERE module_id=?',
            [id],
          ),
          isEmpty,
        );
        expect(
          await store.sql('SELECT * FROM host_packages WHERE module_id=?', [
            id,
          ]),
          isEmpty,
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'module list and complete impact stay readable at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                ModuleSummaryTile(
                  name: '正方通用课程导入模块',
                  description: '作者未提供说明',
                  version: '1.0.0',
                  status: '已停用',
                  onTap: () {},
                  trailing: const Icon(Icons.more_vert),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('作者未提供说明'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(ModuleSummaryTile));
      final confirmation = confirmModuleImpact(
        context,
        title: '停用模块',
        moduleId: 'private.foundation',
        affected: ['private.compat', 'private.schedule'],
        dataEffect: '数据保留',
      );
      await tester.pumpAndSettle();
      expect(find.text('private.compat'), findsOneWidget);
      expect(find.text('private.schedule'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await confirmation, isFalse);
    },
  );

  testWidgets(
    'legacy metadata fallback and clickable dependencies in details',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = await package(
        'private.schedule',
        dependency: 'private.compat',
        metadata: false,
        permissions: [
          'services.query:private.compat/compile@2',
          'services.query:app.host/packages.catalog@1',
        ],
      );
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ModuleDetailsDialog(
              package: source,
              dependents: const ['private.viewer'],
              onDependency: (id) => selected = id,
            ),
          ),
        ),
      );
      expect(find.text('作者未提供说明'), findsOneWidget);
      expect(find.textContaining('未签名包'), findsOneWidget);
      await tester.ensureVisible(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText && widget.data == source.packageDigest,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('compile @ 2 query'), findsOneWidget);
      await tester.ensureVisible(find.text('private.compat').first);
      await tester.tap(find.text('private.compat').first);
      expect(selected, 'private.compat');
      expect(tester.takeException(), isNull);
    },
  );

  for (final (cancel, official) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    testWidgets(
      cancel
          ? 'cancel download leaves installation and data untouched'
          : official
          ? 'distributed official importer installs after one confirmation and opens import flow'
          : 'download retry installs recursive author repositories after one confirmation',
      (tester) async {
        late AppDatabase db;
        late CollectionStore store;
        late ModuleHost host;
        late Directory dir;
        late ModuleCatalogClient client;
        late String importerName;
        final navigatorKey = GlobalKey<NavigatorState>();
        Future<void>? installation;
        final gate = Completer<List<int>>();
        var downloads = 0;
        await tester.runAsync(() async {
          db = AppDatabase(NativeDatabase.memory());
          store = CollectionStore(db);
          dir = await Directory.systemTemp.createTemp('module-management-ui-');
          host = ModuleHost(
            store: store,
            directory: Directory('${dir.path}/host'),
          );
          await host.initialize();
          final foundation = official
              ? await ScriptPackage.verify(
                  await File('../dist/modules/app.schedule.xmodule')
                      .readAsBytes(),
                  allowUnsignedLocal: true,
                )
              : await package('private.foundation', name: '正方通用');
          final compat = official
              ? await ScriptPackage.verify(
                  await File('../dist/modules/app.import.shiguang.xmodule')
                      .readAsBytes(),
                  allowUnsignedLocal: true,
                )
              : await package(
                  'private.compat',
                  dependency: foundation.id,
                  name: '拾光兼容',
                );
          final schedule = official
              ? null
              : await package(
                  'private.schedule',
                  dependency: compat.id,
                  name: '课表',
                );
          importerName = compat.title;
          final fixtures = <String, List<int>>{};
          final catalog = <Object?>[];
          final sources = [foundation, compat, ?schedule];
          for (final (i, source) in sources.indexed) {
            final repository = 'author$i/modules';
            final indexUrl =
                'https://raw.githubusercontent.com/$repository/main/index.json';
            final url =
                'https://github.com/$repository/releases/download/v1.0.0/${source.id}.xmodule';
            catalog.add({
              'id': source.id,
              'name': source.title,
              'description': source.description,
              'author': '作者$i',
              'repository': repository,
              'indexUrl': indexUrl,
            });
            fixtures[indexUrl] = utf8.encode(
              jsonEncode({
                'indexFormat': 1,
                'moduleId': source.id,
                'repository': repository,
                'versions': [
                  {
                    'version': source.version,
                    'manifest': source.manifest,
                    'services': source.definition['services'],
                    'url': url,
                    'size': source.bytes.length,
                    'sha256': source.packageDigest,
                  },
                ],
              }),
            );
            fixtures[url] = source.bytes;
          }
          fixtures['https://raw.githubusercontent.com/JayConstruct/xudian-modules/main/catalog.json'] =
              utf8.encode(jsonEncode({'catalogFormat': 1, 'modules': catalog}));
          client = ModuleCatalogClient(
            cacheDirectory: Directory('${dir.path}/cache'),
            networkRetries: 0,
            preinstalledDigests: official
                ? {
                    for (final source in sources)
                      source.id: source.packageDigest,
                  }
                : {},
            transport:
                (url, {cancellation, onProgress, required maximumBytes}) async {
                  if (url.path.endsWith('/catalog.json')) {
                    // Resolution can outlast the dialog animation and the old
                    // 360 ms fixture wait, even before package downloads begin.
                    await Future<void>.delayed(
                      const Duration(milliseconds: 450),
                    );
                  }
                  if (url.host == 'github.com') {
                    downloads++;
                    if (cancel) {
                      cancellation?.listen(() {
                        if (!gate.isCompleted) {
                          gate.completeError(const DownloadCancelled());
                        }
                      });
                      return gate.future;
                    }
                    if (downloads == 1) throw const SocketException('网络暂时不可用');
                  }
                  final bytes = fixtures[url.toString()]!;
                  onProgress?.call(bytes.length, bytes.length);
                  return bytes;
                },
          );
        });
        addTearDown(() async {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          await tester.pumpWidget(const SizedBox.shrink());
          // Resolver cache writes may still be running if an assertion fails.
          // Unmount first so resolution exits, then drain before deleting cache.
          await tester.runAsync(() async => await installation);
          client.dispose();
          await host.close();
          await store.close();
          await db.close();
          await dir.delete(recursive: true);
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWith((_) async => db),
              moduleHostProvider.overrideWith((_) async => host),
              moduleCatalogClientProvider.overrideWith((_) async => client),
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => Column(
                    children: [
                      FilledButton(
                        onPressed: () {
                          installation = installResolvedModules(
                            context,
                            ref,
                            host,
                            requests: {
                              official
                                      ? 'app.import.shiguang'
                                      : 'private.schedule':
                                  'any',
                            },
                          );
                        },
                        child: const Text('安装课表'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ModuleCatalogPage(host: host),
                          ),
                        ),
                        child: const Text('查看商店'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() => tester.tap(find.text('安装课表')));
        await waitForNativeWidget(tester, find.text('下载并验证模块'));
        if (cancel) {
          await tester.tap(find.text('取消下载'));
          await tester.runAsync(() async => await installation);
          await tester.pumpAndSettle();
          expect(find.text('确认模块安装计划'), findsNothing);
        } else {
          await waitForNativeWidget(tester, find.text('重试'), hitTestable: true);
          await tester.runAsync(() => tester.tap(find.text('重试')));
          await waitForNativeWidget(tester, find.text('确认模块安装计划'));
          await waitForNativeWidget(
            tester,
            find.text('确认安装'),
            hitTestable: true,
          );
          await tester.runAsync(() => tester.tap(find.text('确认安装')));
          await waitForNativeWidget(
            tester,
            find.text('模块安装完成，共 ${official ? 2 : 3} 个'),
          );
          expect(find.byType(SnackBar), findsNothing);
          // The launch action belongs to the store and survives the Toast.
          await tester.pump(const Duration(seconds: 4));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.textContaining('模块安装完成'), findsNothing);
          if (official) {
            await tester.runAsync(() => tester.tap(find.text('查看商店')));
            await waitForNativeWidget(tester, find.text(importerName));
            final importerCard = find.ancestor(
              of: find.text(importerName),
              matching: find.byType(Card),
            );
            final openImporter = find.descendant(
              of: importerCard,
              matching: find.text('打开模块'),
            );
            await tester.ensureVisible(openImporter);
            await waitForNativeWidget(tester, openImporter, hitTestable: true);
            await tester.runAsync(() => tester.tap(openImporter));
            await waitForNativeWidget(tester, find.text('按学校导入'));
          }
        }
        await tester.runAsync(() async {
          final rows = await host.store.sql(
            'SELECT module_id FROM host_installations WHERE installed=1',
          );
          expect(
            rows.length,
            cancel
                ? 0
                : official
                ? 2
                : 3,
          );
          if (!cancel) {
            expect(host.instances.keys.toSet(), {
              official ? 'app.schedule' : 'private.foundation',
              official ? 'app.import.shiguang' : 'private.compat',
              if (!official) 'private.schedule',
            });
            expect(
              await host.repositoryFor(
                official ? 'app.schedule' : 'private.foundation',
              ),
              'author0/modules',
            );
            expect(
              await host.repositoryFor(
                official ? 'app.import.shiguang' : 'private.compat',
              ),
              'author1/modules',
            );
            if (!official) {
              expect(
                await host.repositoryFor('private.schedule'),
                'author2/modules',
              );
            }
          }
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
