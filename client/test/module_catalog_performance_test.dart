import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_catalog_page.dart';
import 'package:task_app/core/module_host/module_catalog_widgets.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_management_widgets.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/data/app_database.dart';

import 'module_catalog_filter_test.dart' show waitForCatalog;
import 'module_catalog_test.dart' show Fixture, makePackage;

class _TrackingStore extends CollectionStore {
  _TrackingStore(super.db);
  int snapshots = 0;
  Completer<void>? snapshotGate;

  @override
  Future<List<Map<String, Object?>>> sql(
    String query, [
    List<Object?> args = const [],
  ]) async {
    if (query.contains('FROM host_installations AS installations')) {
      snapshots++;
      await snapshotGate?.future;
    }
    return super.sql(query, args);
  }
}

class _TrackingHost extends ModuleHost {
  _TrackingHost({required super.store, required super.directory});
  final packageReads = <String>[];

  @override
  Future<ScriptPackage> packageSource(String id, String version) {
    packageReads.add(id);
    return super.packageSource(id, version);
  }
}

Future<void> _finishIo(WidgetTester tester) async {
  final watch = Stopwatch()..start();
  while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
      watch.elapsed < const Duration(seconds: 8)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}

Future<void> _closeDetail(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, '关闭'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (width, scale, columns) in [
    (320.0, 2.0, 1),
    (800.0, 1.0, 2),
    (1280.0, 1.0, 3),
  ]) {
    testWidgets('large catalog builds viewport rows at $width/$scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final built = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: ModuleCatalogSliverGrid(
                    itemCount: 1000,
                    itemBuilder: (context, index) {
                      built.add(index);
                      return ModuleCatalogCard(
                        key: ValueKey(index),
                        name: '校园课程导入与任务安排模块 $index',
                        description: '按学校导入课程，并在每天的计划中查看上课时间和教室。',
                        status: '可安装',
                        version: '1.0.0',
                        action: '安装',
                        onDetails: () {},
                        onAction: () {},
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(built.length, lessThan(30));
      expect(find.byKey(const ValueKey(999)), findsNothing);
      final first = tester.getTopLeft(find.byKey(const ValueKey(0)));
      for (var i = 1; i < columns; i++) {
        final point = tester.getTopLeft(find.byKey(ValueKey(i)));
        expect(point.dy, closeTo(first.dy, .1));
        expect(point.dx, greaterThan(first.dx));
      }
      final next = tester.getTopLeft(find.byKey(ValueKey(columns)));
      expect(next.dx, closeTo(first.dx, .1));
      expect(next.dy, greaterThan(first.dy));
      if (scale == 2) {
        final text = tester.widget<Text>(find.text('校园课程导入与任务安排模块 0'));
        expect(text.maxLines, isNull);
      }
      final before = Set<int>.of(built);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(built.difference(before), isNotEmpty);
      expect(built.length, lessThan(60));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'detail paints first, reuses verified packages and refreshes identity',
    (tester) async {
      late AppDatabase db;
      late _TrackingStore store;
      late _TrackingHost host;
      late Directory directory;
      late Fixture fixture;
      late ScriptPackage active;
      late WidgetRef pageRef;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('catalog-perf-');
        db = AppDatabase(NativeDatabase.memory());
        store = _TrackingStore(db);
        host = _TrackingHost(
          store: store,
          directory: Directory('${directory.path}/host'),
        );
        await host.initialize();
        fixture = Fixture(Directory('${directory.path}/cache'));
        active = await makePackage('test.enabled');
        final disabled = await makePackage('test.disabled');
        await host.install(active);
        await host.install(disabled);
        await host.disable(disabled.id);
        await fixture.add(active);
        await fixture.add(disabled);
        store.snapshots = 0;
      });
      addTearDown(() async {
        store.snapshotGate?.complete();
        store.snapshotGate = null;
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.client.dispose();
        await tester.runAsync(() async {
          await host.close();
          await store.close();
          await db.close();
          await directory.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moduleCatalogClientProvider.overrideWith(
              (_) async => fixture.client,
            ),
          ],
          child: MaterialApp(
            theme: AppDesign.theme(Brightness.light),
            home: Consumer(
              builder: (context, ref, _) {
                pageRef = ref;
                return ModuleCatalogPage(host: host);
              },
            ),
          ),
        ),
      );
      expect(find.text('模块商店'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await waitForCatalog(tester, find.byType(ModuleCatalogSliverGrid));
      await _finishIo(tester);
      expect(store.snapshots, 1);
      expect(host.packageReads, ['test.disabled']);
      host.packageReads.clear();
      // Installing must retain full on-disk verification, even though the
      // visible shop already has validated objects for both installed modules.
      await tester.runAsync(
        () => installResolvedModules(
          tester.element(find.byType(ModuleCatalogPage)),
          pageRef,
          host,
          requests: {active.id: 'any'},
          offline: true,
        ),
      );
      expect(host.packageReads, ['test.enabled', 'test.disabled']);
      host.packageReads.clear();
      store.snapshots = 0;
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      store.snapshotGate = Completer<void>();
      await tester.tap(find.text('test.enabled'));
      await tester.pump();
      expect(find.text('正在读取模块详情…'), findsOneWidget);
      expect(find.byType(ModuleDetailsDialog), findsNothing);
      store.snapshotGate!.complete();
      store.snapshotGate = null;
      await waitForCatalog(tester, find.byType(ModuleDetailsDialog));
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.packageReads, isEmpty);
      expect(store.snapshots, 1);
      expect(find.text('1.0.0 · 已启用'), findsOneWidget);
      await _closeDetail(tester);

      // Refresh SQL status even when the previously verified package is reused.
      await tester.runAsync(() => host.disable(active.id));
      await tester.tap(find.text('test.enabled'));
      await waitForCatalog(tester, find.text('1.0.0 · 已停用'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.packageReads, isEmpty);
      await _closeDetail(tester);
      await tester.runAsync(() => host.enable(active.id));
      await tester.tap(find.text('test.enabled'));
      await waitForCatalog(tester, find.text('1.0.0 · 已启用'));
      await tester.pump(const Duration(milliseconds: 300));
      await _closeDetail(tester);

      await tester.runAsync(() async {
        final updated = await makePackage(active.id, version: '2.0.0');
        await host.install(updated);
        await fixture.add(updated);
      });
      await tester.tap(find.text('test.enabled'));
      await waitForCatalog(tester, find.text('2.0.0 · 已启用'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.packageReads, isEmpty);
      await _closeDetail(tester);

      // Matching version alone cannot authorize reuse after persisted digest changes.
      await tester.runAsync(
        () => db.customStatement(
          'UPDATE host_packages SET digest=? WHERE module_id=? AND version=?',
          ['0' * 64, active.id, '2.0.0'],
        ),
      );
      await tester.tap(find.text('test.enabled'));
      await waitForCatalog(tester, find.textContaining('Cannot open file'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.packageReads, [active.id]);
      await _closeDetail(tester);
      await tester.runAsync(() async {
        await db.customStatement(
          'UPDATE host_packages SET digest=? WHERE module_id=? AND version=?',
          [
            host.instances[active.id]!.package.packageDigest,
            active.id,
            '2.0.0',
          ],
        );
        await host.uninstall(active.id);
      });
      await tester.tap(find.text('test.enabled'));
      await waitForCatalog(tester, find.text('解析依赖并安装'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ModuleDetailsDialog), findsNothing);
      await _closeDetail(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'slow refresh does not reuse an old same-ID repository index from details',
    (tester) async {
      late AppDatabase db;
      late CollectionStore store;
      late ModuleHost host;
      late Directory directory;
      late Fixture previous, updated;
      late ModuleCatalogClient client;
      final catalogGate = Completer<void>();
      final staleIndexGate = Completer<void>();
      var catalogRequests = 0, oldIndexRequests = 0, newIndexRequests = 0;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'catalog-source-race-',
        );
        db = AppDatabase(NativeDatabase.memory());
        store = CollectionStore(db);
        host = ModuleHost(
          store: store,
          directory: Directory('${directory.path}/host'),
        );
        await host.initialize();
        previous = Fixture(Directory('${directory.path}/previous'));
        updated = Fixture(Directory('${directory.path}/updated'));
        await previous.add(
          await makePackage('test.shared'),
          repository: 'Alice/modules',
        );
        await updated.add(
          await makePackage('test.shared', version: '2.0.0'),
          repository: 'Bob/modules',
        );
        client = ModuleCatalogClient(
          cacheDirectory: Directory('${directory.path}/cache'),
          transport:
              (url, {cancellation, onProgress, required maximumBytes}) async {
                Fixture source;
                if (url.path.endsWith('/catalog.json')) {
                  catalogRequests++;
                  if (catalogRequests > 1) await catalogGate.future;
                  source = catalogRequests == 1 ? previous : updated;
                } else if (url.pathSegments.first == 'Alice') {
                  oldIndexRequests++;
                  if (oldIndexRequests > 1) await staleIndexGate.future;
                  source = previous;
                } else {
                  newIndexRequests++;
                  source = updated;
                }
                return source.fetch(
                  url,
                  cancellation: cancellation,
                  onProgress: onProgress,
                  maximumBytes: maximumBytes,
                );
              },
        );
      });
      addTearDown(() async {
        if (!catalogGate.isCompleted) catalogGate.complete();
        if (!staleIndexGate.isCompleted) staleIndexGate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        client.dispose();
        previous.client.dispose();
        updated.client.dispose();
        await tester.runAsync(() async {
          await host.close();
          await store.close();
          await db.close();
          await directory.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moduleCatalogClientProvider.overrideWith((_) async => client),
          ],
          child: MaterialApp(home: ModuleCatalogPage(host: host)),
        ),
      );
      await _finishIo(tester);
      expect(find.text('可安装 · 1.0.0'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新 / 重试'));
      await tester.pump();
      // The old card remains available while the new catalog is delayed.
      await tester.tap(find.text('test.shared'));
      await tester.pump();
      expect(find.text('正在读取模块详情…'), findsOneWidget);
      final watch = Stopwatch()..start();
      while (oldIndexRequests < 2 &&
          watch.elapsed < const Duration(seconds: 8)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(oldIndexRequests, 2);
      catalogGate.complete();
      // The fresh repository must resolve while the old detail index is pending.
      await waitForCatalog(tester, find.text('可安装 · 2.0.0'));
      expect(newIndexRequests, 1);
      staleIndexGate.complete();
      await waitForCatalog(tester, find.text('版本：1.0.0 · 可安装'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('可安装 · 2.0.0'), findsOneWidget);
      await _closeDetail(tester);
      await tester.tap(find.text('test.shared'));
      await waitForCatalog(tester, find.text('发布仓库：Bob/modules'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('版本：2.0.0 · 可安装'), findsOneWidget);
      expect(newIndexRequests, 1);
      await _closeDetail(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'index prefetch is bounded and closing the page cancels the queue',
    (tester) async {
      late AppDatabase db;
      late CollectionStore store;
      late ModuleHost host;
      late Directory directory;
      late Fixture fixture;
      late ModuleCatalogClient client;
      final gate = Completer<void>();
      var active = 0, peak = 0, started = 0;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('catalog-prefetch-');
        db = AppDatabase(NativeDatabase.memory());
        store = CollectionStore(db);
        host = ModuleHost(
          store: store,
          directory: Directory('${directory.path}/host'),
        );
        await host.initialize();
        fixture = Fixture(Directory('${directory.path}/cache'));
        for (var i = 0; i < 12; i++) {
          await fixture.add(await makePackage('test.module$i'));
        }
        client = ModuleCatalogClient(
          cacheDirectory: fixture.directory,
          transport:
              (url, {cancellation, onProgress, required maximumBytes}) async {
                if (url.path.contains('/module-index/')) {
                  started++;
                  active++;
                  if (active > peak) peak = active;
                  await gate.future;
                  active--;
                }
                return fixture.fetch(
                  url,
                  cancellation: cancellation,
                  onProgress: onProgress,
                  maximumBytes: maximumBytes,
                );
              },
        );
      });
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        client.dispose();
        fixture.client.dispose();
        await tester.runAsync(() async {
          await host.close();
          await store.close();
          await db.close();
          await directory.delete(recursive: true);
        });
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            moduleCatalogClientProvider.overrideWith((_) async => client),
          ],
          child: MaterialApp(home: ModuleCatalogPage(host: host)),
        ),
      );
      await waitForCatalog(tester, find.text('找到 12 个模块 · 目录共 12 个'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      expect(started, 4);
      expect(peak, 4);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(started, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
