import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/legacy_app.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_annotation.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/module_manager/module_manager_page.dart';
import 'package:task_app/features/settings/ui_layout.dart';
import 'package:task_app/features/tasks/application/providers.dart';
import 'package:task_app/features/tasks/quick_task_input.dart';
import 'package:task_app/features/ui_examples/ui_examples_page.dart';

class _Secrets implements AiSecretStore {
  @override
  Future<String?> readApiKey() async => null;
  @override
  Future<void> writeApiKey(String value) async {}
  @override
  Future<void> deleteApiKey() async {}
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 820)]) {
    testWidgets('configured main limit and overflow work at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      final app = XudianApp();
      await database
          .into(database.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: UiLayoutController.storageKey,
              value: jsonEncode(
                UiLayout(
                  narrow: UiLayoutProfile(mainLimit: 2),
                  wide: UiLayoutProfile(mainLimit: 2),
                ).toJson(),
              ),
            ),
          );
      late ProviderContainer container;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        app.registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => database),
            aiSecretStoreProvider.overrideWithValue(_Secrets()),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return app;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('更多'), findsOneWidget);
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('模块').last);
      await tester.pumpAndSettle();
      expect(find.byType(ModuleManagerPage), findsOneWidget);
      if (size.width < 820) {
        expect(
          tester
              .widget<MobileBottomDock>(find.byType(MobileBottomDock))
              .moreSelected,
          isTrue,
        );
      }
      final loaded = container.read(uiLayoutProvider).asData!.value;
      final narrow = loaded.narrow.withMount(
        'modules',
        const UiMount(placement: UiPlacement.hidden),
      );
      final wide = loaded.wide.withMount(
        'modules',
        const UiMount(placement: UiPlacement.hidden),
      );
      await container
          .read(uiLayoutProvider.notifier)
          .save(UiLayout(narrow: narrow, wide: wide));
      await tester.pumpAndSettle();
      expect(find.byType(ModuleManagerPage), findsOneWidget);
      if (size.width < 820) {
        expect(
          tester
              .widget<MobileBottomDock>(find.byType(MobileBottomDock))
              .moreSelected,
          isFalse,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'relocated detail action preserves workspace selection and quick draft',
    (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      final app = XudianApp();
      final layout = UiLayout(
        narrow: UiLayoutProfile(
          mainLimit: null,
          mounts: {
            'app.ui.examples.entry': const UiMount(
              placement: UiPlacement.main,
              order: 1,
            ),
          },
        ),
      );
      await database
          .into(database.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: UiLayoutController.storageKey,
              value: jsonEncode(layout.toJson()),
            ),
          );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        app.registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => database),
            aiSecretStoreProvider.overrideWithValue(_Secrets()),
          ],
          child: app,
        ),
      );
      await tester.pumpAndSettle();
      final quick = tester.widget<QuickTaskInput>(find.byType(QuickTaskInput));
      quick.controller!.text = '未提交草稿';
      final dock = tester.widget<MobileBottomDock>(
        find.byType(MobileBottomDock),
      );
      final selectedBefore = dock.destinations[dock.selectedIndex].id;
      await tester.tap(find.text('UI 示例'));
      await tester.pumpAndSettle();
      expect(find.byType(UiExamplesPage), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final restored = tester.widget<MobileBottomDock>(
        find.byType(MobileBottomDock),
      );
      expect(restored.destinations[restored.selectedIndex].id, selectedBefore);
      expect(
        tester
            .widget<QuickTaskInput>(find.byType(QuickTaskInput))
            .controller!
            .text,
        '未提交草稿',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'annotation controls remain usable across settings and workspace',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      final app = XudianApp();
      late ProviderContainer container;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        app.registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => database),
            aiSecretStoreProvider.overrideWithValue(_Secrets()),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return app;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      container.read(uiAnnotationProvider.notifier).setEnabled(true);
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出界面标注'), findsOneWidget);
      expect(find.textContaining(RegExp(r'U\d+ ·')), findsWidgets);
      await tester.tap(find.byTooltip('暂时隐藏标注'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('打开设置'));
      await tester.pumpAndSettle();
      expect(find.text('入口与页面布局'), findsOneWidget);
      expect(find.byTooltip('退出界面标注'), findsOneWidget);
      await tester.tap(find.byTooltip('退出界面标注'));
      await tester.pumpAndSettle();
      expect(container.read(uiAnnotationProvider), isFalse);
      expect(find.textContaining(RegExp(r'U\d+ ·')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
