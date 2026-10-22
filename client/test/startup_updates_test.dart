import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/app_updates/github_app_updates.dart';
import 'package:task_app/core/app_updates/startup_update_preference.dart';
import 'package:task_app/core/app_updates/startup_updates.dart';
import 'package:task_app/core/module_catalog/catalog_providers.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/features/settings/update_settings_page.dart';

import 'module_catalog_test.dart' show Fixture, makePackage;

class FailingPreference extends StartupUpdatePreference {
  @override
  Future<bool> build() async => false;

  @override
  Future<void> save(bool enabled) async => throw StateError('disk full');
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('opt-in persists across cold scopes; disabling persists too', () async {
    ProviderContainer scope() => ProviderContainer(
      overrides: [databaseProvider.overrideWith((_) async => db)],
    );
    var container = scope();
    expect(await container.read(startupUpdateEnabledProvider.future), isFalse);
    await container.read(startupUpdateEnabledProvider.notifier).save(true);
    container.dispose();
    container = scope();
    expect(await container.read(startupUpdateEnabledProvider.future), isTrue);
    await container.read(startupUpdateEnabledProvider.notifier).save(false);
    container.dispose();
    container = scope();
    expect(await container.read(startupUpdateEnabledProvider.future), isFalse);
    container.dispose();
  });

  test(
    'disabled startup sends no requests, enabling waits for next cold launch',
    () async {
      var calls = 0;
      ProviderContainer scope() => ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          startupAppCheckProvider.overrideWithValue(() async {
            calls++;
            return const AppUpdateResult(
              InstalledAppVersion('1.0.0', '1'),
              null,
            );
          }),
          startupModuleCheckProvider.overrideWithValue(() async {
            calls++;
            return const ModuleUpdateSummary({});
          }),
        ],
      );
      var container = scope();
      await container.read(startupUpdatesProvider.notifier).start();
      await container.read(startupUpdateEnabledProvider.notifier).save(true);
      await container.read(startupUpdatesProvider.notifier).start();
      expect(calls, 0);
      container.dispose();
      container = scope();
      await container.read(startupUpdatesProvider.notifier).start();
      expect(calls, 2);
      container.dispose();
    },
  );

  test(
    'checks run concurrently once; app failure preserves module updates',
    () async {
      final app = Completer<AppUpdateResult>();
      final modules = Completer<ModuleUpdateSummary>();
      var appCalls = 0, moduleCalls = 0;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          startupAppCheckProvider.overrideWithValue(() {
            appCalls++;
            return app.future;
          }),
          startupModuleCheckProvider.overrideWithValue(() {
            moduleCalls++;
            return modules.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(startupUpdateEnabledProvider.notifier).save(true);
      final running = container.read(startupUpdatesProvider.notifier).start();
      await Future<void>.delayed(Duration.zero);
      expect(appCalls, 1);
      expect(moduleCalls, 1);
      expect(container.read(startupUpdatesProvider).checking, isTrue);
      expect(
        await container.read(startupUpdatesProvider.notifier).start(),
        isFalse,
      );
      app.completeError(const SocketException('offline'));
      modules.complete(const ModuleUpdateSummary({'test.one': '模块 2.0.0'}));
      expect(await running, isTrue);
      final state = container.read(startupUpdatesProvider);
      expect(state.checking, isFalse);
      expect(state.appFailed, isTrue);
      expect(state.modulesFailed, isFalse);
      expect(state.hasUpdates, isTrue);
      expect(
        await container.read(startupUpdatesProvider.notifier).start(),
        isFalse,
      );
      expect(appCalls, 1);
    },
  );

  test('late completion after scope disposal is harmless', () async {
    final pending = Completer<AppUpdateResult>();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((_) async => db),
        startupAppCheckProvider.overrideWithValue(() => pending.future),
        startupModuleCheckProvider.overrideWithValue(
          () async => const ModuleUpdateSummary({}),
        ),
      ],
    );
    await container.read(startupUpdateEnabledProvider.notifier).save(true);
    final running = container.read(startupUpdatesProvider.notifier).start();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    pending.complete(
      const AppUpdateResult(InstalledAppVersion('1.0.0', '1'), null),
    );
    expect(await running, isFalse);
  });

  testWidgets(
    'switch saves without starting requests and survives a fresh page',
    (tester) async {
      Future<void> show() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWith((_) async => db)],
            child: const MaterialApp(home: UpdateSettingsPage()),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('启动时检查更新'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await show();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(find.text('正在后台检查 App 和模块更新…'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed save leaves switch off and retry available', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          startupUpdateEnabledProvider.overrideWith(FailingPreference.new),
        ],
        child: const MaterialApp(home: UpdateSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('启动时检查更新'));
    await tester.pumpAndSettle();
    final control = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(control.value, isFalse);
    expect(control.onChanged, isNotNull);
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('module check includes disabled installs, filters host, prerelease and repository, isolates bad indexes', () async {
    final directory = await Directory.systemTemp.createTemp('startup-updates-');
    final store = CollectionStore(db);
    final host = ModuleHost(
      store: store,
      directory: Directory('${directory.path}/host'),
    );
    final fixture = Fixture(Directory('${directory.path}/cache'));
    await host.initialize();
    addTearDown(() async {
      fixture.client.dispose();
      await host.close();
      await store.close();
      await directory.delete(recursive: true);
    });
    for (final id in [
      'test.one',
      'test.disabled',
      'test.foreign',
      'test.broken',
    ]) {
      await host.install(await makePackage(id));
      await fixture.add(await makePackage(id, version: '2.0.0'));
    }
    await host.disable('test.disabled');
    await db.customStatement('INSERT INTO host_meta(key,value) VALUES(?,?)', [
      'module-repository:test.foreign',
      'Someone/else',
    ]);
    await fixture.add(await makePackage('test.one', version: '3.0.0-beta.1'));
    await fixture.add(await makePackage('test.one', version: '4.0.0'));
    final newest =
        (fixture.indexes['test.one']!['versions'] as List).last as Map;
    newest['manifest'] = {...(newest['manifest'] as Map), 'hostApi': '^99.0.0'};
    await fixture.add(await makePackage('test.uninstalled', version: '2.0.0'));
    fixture.sync();
    fixture.documents[fixture.modules['test.broken']!['indexUrl'] as String] =
        utf8.encode('{}');
    final container = ProviderContainer(
      overrides: [
        moduleHostProvider.overrideWith((_) async => host),
        moduleCatalogClientProvider.overrideWith((_) async => fixture.client),
      ],
    );
    addTearDown(container.dispose);
    final result = await container.read(startupModuleCheckProvider)();
    expect(result.updates, {
      'test.one': 'test.one 2.0.0',
      'test.disabled': 'test.disabled 2.0.0',
    });
    expect(result.incomplete, isTrue);
    expect(
      fixture.requests,
      4,
    ); // Catalog plus only three installed module indexes.
  });
}
