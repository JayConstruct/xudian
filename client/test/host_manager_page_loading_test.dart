import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/data/app_database.dart';

class _TrackedStore extends CollectionStore {
  _TrackedStore(super.db);

  int listReads = 0;
  String name = '测试模块';
  bool failNextListRead = false;

  @override
  Future<List<Map<String, Object?>>> sql(
    String query, [
    List<Object?> args = const [],
  ]) async {
    if (query.contains('AS package_name')) {
      listReads++;
      if (failNextListRead) {
        failNextListRead = false;
        throw StateError('测试查询失败');
      }
      return [
        {
          'module_id': 'app.source.sample',
          'version': '1.0.0',
          'installed': 1,
          'enabled': 0,
          'package_kind': 'script',
          'package_name': name,
          'package_description': '列表说明',
        },
      ];
    }
    return super.sql(query, args);
  }
}

void main() {
  testWidgets(
    'list reads once across category and viewport changes, refreshes on registry or host changes',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = _TrackedStore(db);
      final replacementStore = _TrackedStore(db)..name = '替换宿主模块';
      final host = ModuleHost(
        store: store,
        directory: Directory('/tmp/source-host-test'),
      );
      final replacement = ModuleHost(
        store: replacementStore,
        directory: Directory('/tmp/source-host-replacement-test'),
      );
      var currentHost = host;
      final container = ProviderContainer(
        overrides: [moduleHostProvider.overrideWith((_) async => currentHost)],
      );
      addTearDown(() async {
        container.dispose();
        await host.close();
        await replacement.close();
        await store.close();
        await replacementStore.close();
        await db.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: HostManagerPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.listReads, 1);
      expect(find.text('测试模块'), findsOneWidget);
      await tester.tap(find.text('UI 包'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1100, 900);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(store.listReads, 1);
      store.name = '刷新后的模块';
      host.registryChanges.add(null);
      await tester.pumpAndSettle();
      expect(store.listReads, 2);
      expect(find.text('刷新后的模块'), findsOneWidget);
      store.failNextListRead = true;
      host.registryChanges.add(null);
      // Deliver the stream event and SQL failure before FutureBuilder gets its
      // next frame. There must be no unhandled asynchronous error in this gap.
      await tester.idle();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.textContaining('无法读取模块列表'), findsOneWidget);
      expect(store.listReads, 3);
      await tester.tap(find.text('重试读取模块列表'));
      await tester.pumpAndSettle();
      expect(store.listReads, 4);
      expect(find.textContaining('无法读取模块列表'), findsNothing);
      expect(find.text('刷新后的模块'), findsOneWidget);
      currentHost = replacement;
      container.invalidate(moduleHostProvider);
      await tester.pumpAndSettle();
      expect(replacementStore.listReads, 1);
      expect(find.text('替换宿主模块'), findsOneWidget);
      host.registryChanges.add(null);
      await tester.pumpAndSettle();
      expect(store.listReads, 4);
      expect(replacementStore.listReads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
