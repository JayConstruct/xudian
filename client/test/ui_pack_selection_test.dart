import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/host_manager_page.dart';
import 'package:task_app/core/module_host/host_settings_page.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_pack.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_pack_providers.dart';
import 'package:task_app/core/ui/ui_pack_settings_page.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'selection persists across scopes, retaining missing module choices',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final first = ProviderContainer(
        overrides: [databaseProvider.overrideWith((ref) async => database)],
      );
      try {
        expect(
          (await first.read(uiSelectionProvider.future)).globalPackId,
          defaultUiPackId,
        );
        final selection = UiSelection(
          globalPackId: 'missing.global',
          modulePackIds: {'app.tasks': 'missing.local'},
        );
        await first.read(uiSelectionProvider.notifier).save(selection);
        final second = ProviderContainer(
          overrides: [databaseProvider.overrideWith((ref) async => database)],
        );
        try {
          expect(
            (await second.read(uiSelectionProvider.future)).toJson(),
            selection.toJson(),
          );
          await database.customStatement(
            "CREATE TABLE business_probe (value TEXT)",
          );
          await database.customStatement(
            "INSERT INTO business_probe VALUES ('keep')",
          );
          await second.read(uiSelectionProvider.notifier).restoreDefaults();
          expect(
            second.read(uiSelectionProvider).requireValue.toJson(),
            UiSelection().toJson(),
          );
          expect(
            (await database
                    .customSelect('SELECT value FROM business_probe')
                    .get())
                .single
                .read<String>('value'),
            'keep',
          );
        } finally {
          second.dispose();
        }
      } finally {
        first.dispose();
        await database.close();
      }
    },
  );

  test('failed persistence keeps the published selection and stale draft cannot overwrite', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => database)],
    );
    try {
      final baseline = await container.read(uiSelectionProvider.future);
      final saved = UiSelection(globalPackId: 'example.ui.compact');
      await container.read(uiSelectionProvider.notifier).save(saved);
      await expectLater(
        container
            .read(uiSelectionProvider.notifier)
            .saveIfUnchanged(
              UiSelection(globalPackId: 'other'),
              expected: baseline,
            ),
        throwsStateError,
      );
      expect(
        container.read(uiSelectionProvider).requireValue.globalPackId,
        saved.globalPackId,
      );
      await database.customStatement(
        "CREATE TRIGGER reject_ui_selection BEFORE INSERT ON app_settings WHEN NEW.key='ui.selection' BEGIN SELECT RAISE(ABORT, 'test persistence failure'); END",
      );
      await expectLater(
        container.read(uiSelectionProvider.notifier).restoreDefaults(),
        throwsA(anything),
      );
      expect(
        container.read(uiSelectionProvider).requireValue.globalPackId,
        saved.globalPackId,
      );
      final row =
          await (database.select(database.appSettings)..where(
                (row) => row.key.equals(UiSelectionController.storageKey),
              ))
              .getSingle();
      expect(jsonDecode(row.value), saved.toJson());
    } finally {
      container.dispose();
      await database.close();
    }
  });

  test(
    'sample is a verified UI-only package with all five templates',
    () async {
      final package = await ScriptPackage.verify(
        File('../dist/modules/example.ui.compact.xmodule').readAsBytesSync(),
        allowUnsignedLocal: true,
      );
      expect(package.isUiPack, isTrue);
      expect(package.definition.containsKey('entryPoint'), isFalse);
      expect(package.permissions, isEmpty);
      final components = package.uiPack!.components;
      for (final name in ['list', 'form', 'settings', 'detail', 'timeGrid']) {
        expect(components, contains('ui.page.$name@1'));
      }
    },
  );

  testWidgets(
    'preview works without host or database access and exercises every template',
    (tester) async {
      final package = await ScriptPackage.verify(
        File('../dist/modules/example.ui.compact.xmodule').readAsBytesSync(),
        allowUnsignedLocal: true,
      );
      var databaseReads = 0, hostReads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async {
              databaseReads++;
              throw StateError('Preview must not access persistence');
            }),
            moduleHostProvider.overrideWith((ref) async {
              hostReads++;
              throw StateError('Preview must not initialize the business host');
            }),
          ],
          child: MaterialApp(
            home: UiPackPreviewPage(
              packs: {package.id: package.uiPack!},
              selection: UiSelection(globalPackId: package.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['表单页', '设置页', '详情页', '时间网格页', '列表页']) {
        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        if (label == '表单页') {
          expect(find.widgetWithText(OutlinedButton, '保存示例'), findsOneWidget);
          await tester.enterText(find.byType(TextField), '保留模拟草稿');
          tester.testTextInput.hide();
          await tester.tap(find.widgetWithText(FilterChip, '深色'));
          await tester.pumpAndSettle();
          expect(find.text('保留模拟草稿'), findsOneWidget);
          await tester.tap(find.widgetWithText(FilterChip, '深色'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.widgetWithText(FilterChip, '深色'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<UiScopeData>(find.byType(UiScopeData))
            .last
            .theme
            .brightness,
        Brightness.dark,
      );
      await tester.tap(find.widgetWithText(FilterChip, '宽屏'));
      await tester.pumpAndSettle();
      expect(databaseReads, 0);
      expect(hostReads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor shows unavailable global and module choices and only saves explicit changes',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final selection = UiSelection(
        globalPackId: 'missing.global',
        modulePackIds: {'missing.module': 'missing.local'},
      );
      await database
          .into(database.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: UiSelectionController.storageKey,
              value: jsonEncode(selection.toJson()),
            ),
          );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => database),
            moduleHostProvider.overrideWith(
              (ref) async =>
                  throw StateError('No business host in this settings test'),
            ),
            uiPackRegistryProvider.overrideWith(
              (ref) => Stream.value(const {}),
            ),
          ],
          child: const MaterialApp(home: UiPackSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('missing.global（不可用，自动回退）'), findsOneWidget);
      expect(find.text('missing.local（不可用，自动回退）'), findsOneWidget);
      expect(find.text('missing.module'), findsOneWidget);
      final row =
          await (database.select(database.appSettings)..where(
                (row) => row.key.equals(UiSelectionController.storageKey),
              ))
              .getSingle();
      expect(jsonDecode(row.value), selection.toJson());
      await tester.tap(find.text('预览草稿'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        jsonDecode(
          (await (database.select(database.appSettings)..where(
                    (row) => row.key.equals(UiSelectionController.storageKey),
                  ))
                  .getSingle())
              .value,
        ),
        selection.toJson(),
      );
      await tester.tap(find.text('恢复默认界面'));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(
          (await (database.select(database.appSettings)..where(
                    (row) => row.key.equals(UiSelectionController.storageKey),
                  ))
                  .getSingle())
              .value,
        ),
        UiSelection().toJson(),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  testWidgets(
    'selected sample styles production settings and manager and UI categories remain usable',
    (tester) async {
      late AppDatabase database;
      late CollectionStore store;
      late ModuleHost host;
      late Directory directory;
      await tester.runAsync(() async {
        database = AppDatabase(NativeDatabase.memory());
        store = CollectionStore(database);
        directory = await Directory.systemTemp.createTemp(
          'ui-pack-production-',
        );
        host = ModuleHost(store: store, directory: directory);
        await host.initialize();
        await host.install(
          await ScriptPackage.verify(
            await File('../dist/modules/example.ui.compact.xmodule')
                .readAsBytes(),
            allowUnsignedLocal: true,
          ),
        );
      });
      final registry = ModuleRegistry([
        HostManagerModule(),
      ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
      final pack = host.instances['example.ui.compact']!.package.uiPack!;
      final selection = UiSelection(globalPackId: pack.moduleId);
      Widget page(Widget child) => ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => database),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: MaterialApp(
          home: UiPackScope(
            previewPacks: {pack.moduleId: pack},
            previewSelection: selection,
            child: child,
          ),
        ),
      );
      try {
        await tester.pumpWidget(page(HostSettingsPage(registry: registry)));
        await tester.pumpAndSettle();
        expect(find.text('界面风格'), findsOneWidget);
        expect(
          tester
              .widgetList<UiScopeData>(find.byType(UiScopeData))
              .last
              .registry
              .resolve('ui.page.settings@1')
              ?.pack
              .moduleId,
          pack.moduleId,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(page(const Scaffold(body: HostManagerPage())));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(OutlinedButton, '导入 .xmodule'),
          findsOneWidget,
        );
        expect(
          find.text(host.instances['example.ui.compact']!.package.title),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'UI 包'));
        await tester.pumpAndSettle();
        expect(
          find.text(host.instances['example.ui.compact']!.package.title),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(ChoiceChip, '业务模块'));
        await tester.pumpAndSettle();
        expect(
          find.text(host.instances['example.ui.compact']!.package.title),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        registry.dispose();
        await tester.runAsync(() async {
          await host.close();
          await store.close();
          await database.close();
          await directory.delete(recursive: true);
        });
      }
    },
  );
}
