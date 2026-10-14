import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/core/performance/startup_readiness.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/builtin_module_registration.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/features/settings/ui_layout.dart';
import 'package:task_app/features/settings/app_preferences.dart';

class _DelayedLayout extends UiLayoutController {
  final ready = Completer<UiLayout>();
  int reads = 0;

  @override
  Future<UiLayout> build() {
    reads++;
    return ready.future;
  }
}

class _Preferences extends AppPreferencesController {
  @override
  Future<AppPreferences> build() async => const AppPreferences();
}

class _StartupPages implements AppModule {
  final builds = <String, int>{};

  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'test.startup',
    version: '1.0.0',
    coreApi: '^1.0.0',
    permissions: ['ui.register'],
  );

  @override
  List<UiRegistration> get ui => [
    for (final id in ['default', 'saved']) ...[
      UiPageRegistration(
        id: 'test.startup.$id',
        moduleId: manifest.id,
        title: id,
        builder: (_, _) {
          builds.update(id, (count) => count + 1, ifAbsent: () => 1);
          return Text('workspace $id');
        },
      ),
      UiEntryRegistration(
        id: 'test.startup.$id',
        moduleId: manifest.id,
        pageId: 'test.startup.$id',
        label: id,
        icon: Icons.home,
        defaultMount: UiMount(order: id == 'default' ? 0 : 1),
      ),
    ],
  ];
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late Directory directory;
  late ModuleHost host;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('shell-startup-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  for (final restoreFails in [false, true]) {
    testWidgets(
      restoreFails
          ? 'restore failure reports recovery outcome without fully drawn'
          : 'no workspace reports recovery outcome without fully drawn',
      (tester) async {
        var reports = 0;
        final failures = <String>[];
        final startup = AppStartupReadiness(
          reportFullyDrawn: () async => reports++,
          reportUnavailable: (outcome) async => failures.add(outcome),
        )..start();
        final app = XudianApp();
        final layout = _DelayedLayout()..ready.complete(UiLayout());
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          app.registry.dispose();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              startupReadinessProvider.overrideWithValue(startup),
              databaseProvider.overrideWith((_) async => db),
              appPreferencesProvider.overrideWith(_Preferences.new),
              moduleHostProvider.overrideWith((_) async {
                if (restoreFails) throw StateError('Host unavailable');
                return host;
              }),
              uiLayoutProvider.overrideWith(() => layout),
            ],
            child: app,
          ),
        );
        await tester.pumpAndSettle();
        expect(reports, 0);
        expect(failures, [restoreFails ? 'restoreError' : 'noWorkspace']);
        expect(find.text('界面风格与恢复'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final layoutFails in [false, true]) {
    testWidgets(
      layoutFails
          ? 'layout read failure still opens the default workspace with recovery'
          : 'layout starts with the host and the first workspace uses saved mounts',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var startupReports = 0;
        final startup = AppStartupReadiness(
          reportFullyDrawn: () async {
            startupReports++;
          },
        )..start();
        final hostReady = Completer<ModuleHost>();
        final layout = _DelayedLayout();
        final pages = _StartupPages();
        final app = XudianApp();
        app.registry.registerBuiltin(
          BuiltinModuleRegistration(
            module: pages,
            title: 'startup',
            description: 'startup test',
          ),
        );
        var hostReads = 0;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          app.registry.dispose();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              startupReadinessProvider.overrideWithValue(startup),
              databaseProvider.overrideWith((_) async => db),
              appPreferencesProvider.overrideWith(_Preferences.new),
              moduleHostProvider.overrideWith((_) {
                hostReads++;
                return hostReady.future;
              }),
              uiLayoutProvider.overrideWith(() => layout),
            ],
            child: app,
          ),
        );
        await tester.pump();
        expect(hostReads, 1);
        expect(
          layout.reads,
          1,
          reason: 'Layout reading must start while the host is still pending',
        );
        expect(pages.builds, isEmpty);
        expect(startupReports, 0);
        hostReady.complete(host);
        await tester.pump();
        await tester.pump();
        expect(
          pages.builds,
          isEmpty,
          reason: 'No workspace may load against temporary default mounts',
        );
        if (layoutFails) {
          layout.ready.completeError(StateError('Layout storage unavailable'));
        } else {
          layout.ready.complete(
            UiLayout(
              narrow: UiLayoutProfile(
                mounts: {'test.startup.saved': const UiMount(order: -1)},
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(layout.reads, 1);
        expect(startupReports, 1);
        final dock = tester.widget<MobileBottomDock>(
          find.byType(MobileBottomDock),
        );
        expect(
          dock.destinations[dock.selectedIndex].id,
          'test.startup.${layoutFails ? 'default' : 'saved'}',
        );
        if (layoutFails) {
          expect(find.text('布局读取失败，暂用默认布局，点击重试'), findsOneWidget);
          expect(pages.builds['default'], greaterThan(0));
        } else {
          expect(pages.builds['default'], isNull);
          expect(pages.builds['saved'], greaterThan(0));
          expect(find.text('workspace saved'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
