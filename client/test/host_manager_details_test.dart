import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_management_widgets.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'module_catalog_test.dart' show makePackage;

class _DetailStore extends CollectionStore {
  _DetailStore(super.db);
  int snapshots = 0;
  Completer<void>? gate;
  bool failSnapshot = false;

  @override
  Future<List<Map<String, Object?>>> sql(
    String query, [
    List<Object?> args = const [],
  ]) async {
    if (query.contains('FROM host_installations AS installations')) {
      snapshots++;
      await gate?.future;
      if (failSnapshot) throw StateError('测试详情读取失败');
    }
    return super.sql(query, args);
  }
}

class _DetailHost extends ModuleHost {
  _DetailHost({required super.store, required super.directory});
  final packageReads = <String>[];

  @override
  Future<ScriptPackage> packageSource(String id, String version) {
    packageReads.add(id);
    return super.packageSource(id, version);
  }
}

class _Fixture {
  late final Directory directory;
  late final AppDatabase db;
  late final _DetailStore store;
  late final _DetailHost host;
  late final ProviderContainer container;

  Future<void> initialize() async {
    directory = await Directory.systemTemp.createTemp('manager-details-');
    db = AppDatabase(NativeDatabase.memory());
    store = _DetailStore(db);
    host = _DetailHost(store: store, directory: directory);
    await host.initialize();
    await host.install(await makePackage('test.base'));
    await host.install(
      await makePackage('test.consumer', dependencies: ['test.base']),
    );
    await host.disable('test.consumer');
    container = ProviderContainer(
      overrides: [moduleHostProvider.overrideWith((_) async => host)],
    );
    // Host restoration also uses a joined installation read. Measure only
    // work triggered by opening details after the fixture is fully prepared.
    store.snapshots = 0;
    host.packageReads.clear();
  }

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: HostManagerPage())),
    ),
  );

  Future<void> close(WidgetTester tester) async {
    if (store.gate case final gate? when !gate.isCompleted) gate.complete();
    store.gate = null;
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(() async {
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty &&
      watch.elapsed < const Duration(seconds: 8)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _detailText(String text) => find.descendant(
  of: find.byType(ModuleDetailsDialog),
  matching: find.text(text),
);

Future<void> _closeDetails(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, '关闭'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'details paint first and reuse enabled and disabled packages across navigation',
    (tester) async {
      final fixture = _Fixture();
      await tester.runAsync(fixture.initialize);
      addTearDown(() => fixture.close(tester));
      await fixture.mount(tester);
      await _waitFor(tester, find.text('test.base'));
      final store = fixture.store, host = fixture.host;
      store.gate = Completer<void>();
      await tester.tap(find.text('test.base'));
      await tester.pump();
      expect(find.text('正在读取模块详情…'), findsOneWidget);
      expect(find.byType(ModuleDetailsDialog), findsNothing);
      expect(host.packageReads, isEmpty);
      store.gate!.complete();
      store.gate = null;
      await _waitFor(tester, find.byType(ModuleDetailsDialog));
      expect(store.snapshots, 1);
      expect(host.packageReads, ['test.consumer']);
      expect(_detailText('test.consumer（已停用）'), findsOneWidget);
      await _closeDetails(tester);

      host.packageReads.clear();
      await tester.tap(find.text('test.consumer'));
      await _waitFor(tester, find.byType(ModuleDetailsDialog));
      expect(_detailText('1.0.0 · 已停用'), findsOneWidget);
      final dependency = find.descendant(
        of: find.byType(ModuleDetailsDialog),
        matching: find.widgetWithText(ListTile, 'test.base'),
      );
      await tester.ensureVisible(dependency);
      await tester.tap(dependency);
      await _waitFor(tester, _detailText('1.0.0 · 已启用'));
      expect(
        tester
            .widget<ModuleDetailsDialog>(find.byType(ModuleDetailsDialog))
            .package
            .id,
        'test.base',
      );
      expect(store.snapshots, 3);
      expect(host.packageReads, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('test.base'));
      await _waitFor(tester, find.byType(ModuleDetailsDialog));
      expect(store.snapshots, 4);
      expect(host.packageReads, isEmpty);
      await _closeDetails(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail snapshots refresh status version and provenance and reject broken sources',
    (tester) async {
      final fixture = _Fixture();
      await tester.runAsync(fixture.initialize);
      addTearDown(() => fixture.close(tester));
      await fixture.mount(tester);
      await _waitFor(tester, find.text('test.base'));
      final host = fixture.host;
      await tester.tap(find.text('test.base'));
      await _waitFor(tester, find.byType(ModuleDetailsDialog));
      await _closeDetails(tester);
      host.packageReads.clear();

      await tester.runAsync(() => host.disable('test.base'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('test.base'));
      await _waitFor(tester, _detailText('1.0.0 · 已停用'));
      expect(host.packageReads, isEmpty);
      await _closeDetails(tester);
      await tester.runAsync(() async {
        await fixture.db.customStatement(
          'UPDATE host_packages SET origin=? WHERE module_id=?',
          ['changed-source', 'test.base'],
        );
        await fixture.db.customStatement(
          'INSERT OR REPLACE INTO host_meta(key,value) VALUES(?,?)',
          ['module-repository:test.base', 'Author/updated'],
        );
      });
      await tester.tap(find.text('test.base'));
      await _waitFor(tester, _detailText('Author/updated'));
      expect(host.packageReads, ['test.base']);
      await _closeDetails(tester);

      await tester.runAsync(() async {
        await host.install(await makePackage('test.base', version: '2.0.0'));
      });
      await tester.pumpAndSettle();
      host.packageReads.clear();
      await tester.tap(find.text('test.base'));
      await _waitFor(tester, _detailText('2.0.0 · 已启用'));
      expect(host.packageReads, isEmpty);
      await _closeDetails(tester);

      final digest = host.instances['test.base']!.package.packageDigest;
      await tester.runAsync(
        () => fixture.db.customStatement(
          'UPDATE host_packages SET digest=? WHERE module_id=? AND version=?',
          ['0' * 64, 'test.base', '2.0.0'],
        ),
      );
      await tester.tap(find.text('test.base'));
      await _waitFor(tester, find.textContaining('Cannot open file'));
      expect(host.packageReads, ['test.base']);
      expect(find.byType(ModuleDetailsDialog), findsNothing);
      await _closeDetails(tester);
      await tester.runAsync(() async {
        await fixture.db.customStatement(
          'UPDATE host_packages SET digest=? WHERE module_id=? AND version=?',
          [digest, 'test.base', '2.0.0'],
        );
        await host.uninstall('test.base', cascade: true);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('test.base'));
      await _waitFor(tester, _detailText('2.0.0 · 已卸载，数据保留'));
      await _closeDetails(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing a pending detail isolates late errors and allows reopening',
    (tester) async {
      final fixture = _Fixture();
      await tester.runAsync(fixture.initialize);
      addTearDown(() => fixture.close(tester));
      await fixture.mount(tester);
      await _waitFor(tester, find.text('test.base'));
      final store = fixture.store;
      store.gate = Completer<void>();
      await tester.tap(find.text('test.base'));
      await tester.pump();
      expect(find.text('正在读取模块详情…'), findsOneWidget);
      await _closeDetails(tester);
      store.failSnapshot = true;
      store.gate!.complete();
      store.gate = null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('测试详情读取失败'), findsNothing);
      expect(tester.takeException(), isNull);
      store.failSnapshot = false;
      await tester.tap(find.text('test.base'));
      await _waitFor(tester, find.byType(ModuleDetailsDialog));
      await _closeDetails(tester);

      // Removing the page during a pending load must not publish its snapshot
      // or continue opening dependency / installation routes after completion.
      store.gate = Completer<void>();
      await tester.tap(find.text('test.consumer'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      final reads = List.of(fixture.host.packageReads);
      store.gate!.complete();
      store.gate = null;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(fixture.host.packageReads, reads);
      expect(tester.takeException(), isNull);
    },
  );
}
