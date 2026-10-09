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
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => FilledButton(
                    onPressed: () => installResolvedModules(
                      context,
                      ref,
                      host,
                      requests: {
                        official ? 'app.import.shiguang' : 'private.schedule':
                            'any',
                      },
                    ),
                    child: const Text('安装课表'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() => tester.tap(find.text('安装课表')));
        await settleNative(tester);
        expect(find.text('下载并验证模块'), findsOneWidget);
        if (cancel) {
          await tester.tap(find.text('取消下载'));
          await settleNative(tester);
          expect(find.text('确认模块安装计划'), findsNothing);
        } else {
          expect(find.text('重试'), findsOneWidget);
          await tester.runAsync(() => tester.tap(find.text('重试')));
          await settleNative(tester);
          expect(find.text('确认模块安装计划'), findsOneWidget);
          expect(find.text('确认安装'), findsOneWidget);
          await tester.runAsync(() => tester.tap(find.text('确认安装')));
          await settleNative(tester);
          expect(find.text('模块安装完成'), findsOneWidget);
          if (official) {
            expect(find.text('打开模块'), findsOneWidget);
            await tester.runAsync(() => tester.tap(find.text('打开模块')));
            await settleNative(tester);
            expect(find.text('按学校导入'), findsOneWidget);
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
