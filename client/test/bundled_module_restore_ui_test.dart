import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_catalog_page.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

import 'module_management_ui_test.dart' as fixtures;

void main() {
  testWidgets('bundled restore reaches review after its list rebuilds', (
    tester,
  ) async {
    late AppDatabase database;
    late CollectionStore store;
    late ModuleHost host;
    late Directory directory;
    late ScriptPackage package;
    late ModuleCatalogClient client;
    const id = 'test.bundled.restore';
    const asset = 'assets/modules/restore-regression.xmodule';
    await tester.runAsync(() async {
      database = AppDatabase(NativeDatabase.memory());
      store = CollectionStore(database);
      directory = await Directory.systemTemp.createTemp('restore-ui-');
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      package = await fixtures.package(id, name: '恢复测试模块');
      client = ModuleCatalogClient(
        cacheDirectory: Directory('${directory.path}/catalog'),
        networkRetries: 0,
        preinstalledDigests: {id: package.packageDigest},
        transport: (url, {cancellation, onProgress, required maximumBytes}) =>
            throw StateError('Bundled restore should not require network'),
      );
    });
    final catalog = Uint8List.fromList(
      utf8.encode(
        jsonEncode([
          {'id': id, 'asset': asset, 'sha256': package.packageDigest},
        ]),
      ),
    );
    final load = Completer<ByteData>();
    rootBundle.clear();
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async {
        final path = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        if (path == 'assets/modules/catalog.json') {
          return ByteData.sublistView(catalog);
        }
        if (path == asset) return load.future;
        return null;
      },
    );
    addTearDown(() async {
      if (!load.isCompleted) load.complete(ByteData.sublistView(package.bytes));
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      );
      rootBundle.clear();
      client.dispose();
      await host.close();
      await store.close();
      await database.close();
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => database),
          moduleHostProvider.overrideWith((_) async => host),
          moduleCatalogClientProvider.overrideWith((_) async => client),
        ],
        child: const MaterialApp(home: Scaffold(body: HostManagerPage())),
      ),
    );
    await fixtures.settleNative(tester);
    final button = find.text('安装 / 恢复');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    load.complete(ByteData.sublistView(package.bytes));
    await fixtures.settleNative(tester);
    expect(find.text('确认模块安装计划'), findsOneWidget);
    // The review groups the module name and install action into separate rows.
    final review = find.byType(AlertDialog);
    expect(
      find.descendant(of: review, matching: find.text('恢复测试模块')),
      findsWidgets,
    );
    expect(
      find.descendant(of: review, matching: find.text('安装并启用 · 1.0.0')),
      findsOneWidget,
    );
    expect(find.text('确认安装'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await fixtures.settleNative(tester);
    expect(find.text('确认模块安装计划'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
