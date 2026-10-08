import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/legacy_app.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/ai/settings/ai_settings_store.dart';
import 'package:task_app/features/settings/app_preferences.dart';
import 'package:task_app/features/tasks/application/providers.dart';

Widget app(AppDatabase db, AiSecretStore secrets) => ProviderScope(
  overrides: [
    databaseProvider.overrideWith((ref) async => db),
    aiSecretStoreProvider.overrideWithValue(secrets),
  ],
  child: XudianApp(),
);

void main() {
  testWidgets(
    'settings persist and apply after a fresh app scope with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secrets = MemorySecrets();
      await tester.pumpWidget(app(db, secrets));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('打开设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观主题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.tap(find.widgetWithText(SwitchListTile, '减少动画'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(SwitchListTile, '触感反馈'));
      await tester.tap(find.widgetWithText(SwitchListTile, '触感反馈'));
      await tester.pumpAndSettle();
      final row = (await db.select(db.appSettings).get()).singleWhere(
        (row) => row.key == AppPreferencesController.storageKey,
      );
      expect(jsonDecode(row.value), {
        'theme': 'dark',
        'reduceMotion': true,
        'haptics': false,
      });
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(db, secrets));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      final context = tester.element(find.byTooltip('打开设置'));
      expect(MediaQuery.disableAnimationsOf(context), isTrue);
      final prefs = await ProviderScope.containerOf(context)
          .read(appPreferencesProvider.future);
      expect(prefs.haptics, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'AI connection validates and is shared with workspace without losing quick draft',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secrets = MemorySecrets();
      await tester.pumpWidget(app(db, secrets));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '尚未提交的任务');
      await tester.tap(find.byTooltip('打开设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('AI 连接'));
      await tester.tap(find.text('AI 连接'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'http://remote.example/v1/chat/completions',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test-model');
      await tester.enterText(find.byType(TextFormField).at(2), 'test-secret');
      await tester.ensureVisible(find.text('保存连接配置'));
      await tester.tap(find.text('保存连接配置'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 HTTPS 接口地址；本机地址可使用 HTTP'), findsOneWidget);
      expect(secrets.key, isNull);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'https://example.com/v1/chat/completions',
      );
      await tester.ensureVisible(find.text('保存连接配置'));
      await tester.tap(find.text('保存连接配置'));
      await tester.pumpAndSettle();
      expect((await DriftAiSettingsStore(db).load()).model, 'test-model');
      expect(secrets.key, 'test-secret');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('尚未提交的任务'), findsOneWidget);
      await tester.tap(find.byTooltip('打开 AI 助手'));
      await tester.pumpAndSettle();
      expect(find.text('对话'), findsOneWidget);
      expect(find.text('test-model'), findsNothing);
      await tester.tap(find.text('高级开发'));
      await tester.pumpAndSettle();
      expect(find.text('test-model'), findsOneWidget);
      expect(find.text('模型连接设置'), findsNothing);
      await tester.ensureVisible(find.text('模型连接'));
      await tester.tap(find.text('模型连接'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(2), '');
      await tester.ensureVisible(find.text('保存连接配置'));
      await tester.tap(find.text('保存连接配置'));
      await tester.pumpAndSettle();
      expect(secrets.key, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test(
    'unreadable appearance preferences fall back without affecting AI settings',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: AppPreferencesController.storageKey,
              value: 'invalid json',
            ),
          );
      await DriftAiSettingsStore(db)
          .save(endpoint: 'https://example.com', model: 'saved-model');
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(container.dispose);
      final prefs = await container.read(appPreferencesProvider.future);
      expect(prefs.themeMode, ThemeMode.system);
      expect(prefs.reduceMotion, isFalse);
      await container
          .read(appPreferencesProvider.notifier)
          .save(prefs.copyWith(themeMode: ThemeMode.light));
      expect((await DriftAiSettingsStore(db).load()).model, 'saved-model');
    },
  );
}

class MemorySecrets implements AiSecretStore {
  String? key;

  @override
  Future<String?> readApiKey() async => key;
  @override
  Future<void> writeApiKey(String value) async {
    key = value;
  }

  @override
  Future<void> deleteApiKey() async {
    key = null;
  }
}
