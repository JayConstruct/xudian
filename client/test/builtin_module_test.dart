import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/legacy_app.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/declarative_runtime/declarative_runtime_controller.dart';
import 'package:task_app/features/module_manager/builtin_module_controller.dart';
import 'package:task_app/features/module_manager/module_manager_page.dart';
import 'package:task_app/features/tasks/application/providers.dart';

Widget scope(AppDatabase db, XudianApp app) => ProviderScope(
  overrides: [
    databaseProvider.overrideWith((ref) async => db),
    aiSecretStoreProvider.overrideWithValue(_Secrets()),
  ],
  child: app,
);

void main() {
  test('built-in preferences restore while data and navigation order survive re-enable', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final registry = XudianApp().registry;
    addTearDown(registry.dispose);
    final controller = BuiltinModuleController(db: db, registry: registry);
    final now = DateTime.now();
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'project',
            name: '保留项目',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'task',
            title: '保留任务',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: 'ai.model', value: 'kept-model'),
        );
    for (final id in ['app.views.today', 'app.views.projects', 'app.ai']) {
      await controller.setEnabled(id, false);
    }
    final restored = XudianApp().registry;
    addTearDown(restored.dispose);
    final restoredController = BuiltinModuleController(
      db: db,
      registry: restored,
    );
    await restoredController.restore();
    expect(restored.ui.primaryDestinations.map((item) => item.id), [
      'app.views.inbox.home',
      'modules',
    ]);
    expect(restored.isEnabled('app.ai'), isFalse);
    for (final id in ['app.views.projects', 'app.views.today', 'app.ai']) {
      await restoredController.setEnabled(id, true);
    }
    expect(restored.ui.primaryDestinations.map((item) => item.id), [
      'app.views.today.home',
      'app.views.inbox.home',
      'projects',
      'modules',
    ]);
    expect((await db.select(db.projects).get()).single.name, '保留项目');
    expect((await db.select(db.tasks).get()).single.title, '保留任务');
    expect(
      (await db.select(db.appSettings).get())
          .singleWhere((row) => row.key == 'ai.model')
          .value,
      'kept-model',
    );
  });

  test(
    'dependencies and protected entry reject changes before persistence',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final registry = XudianApp().registry;
      addTearDown(registry.dispose);
      registry.addOrReplace(_DependentModule());
      final controller = BuiltinModuleController(db: db, registry: registry);
      await expectLater(
        controller.setEnabled('app.views.projects', false),
        throwsStateError,
      );
      await expectLater(
        controller.setEnabled('app.module.manager', false),
        throwsStateError,
      );
      expect(() => registry.remove('app.module.manager'), throwsStateError);
      expect(registry.isEnabled('app.views.projects'), isTrue);
      expect(await db.select(db.appSettings).get(), isEmpty);
      registry.remove('app.dependent.test');
      await controller.setEnabled('app.views.projects', false);
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: '${BuiltinModuleController.keyPrefix}app.module.manager',
              value: 'false',
            ),
          );
      await controller.restore();
      expect(registry.isEnabled('app.module.manager'), isTrue);
    },
  );

  test('failed storage write leaves the active module and UI intact', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final registry = XudianApp().registry;
    addTearDown(registry.dispose);
    await db.customStatement(
      "CREATE TRIGGER reject_module_setting BEFORE INSERT ON app_settings BEGIN SELECT RAISE(ABORT, 'write failed'); END",
    );
    await expectLater(
      BuiltinModuleController(
        db: db,
        registry: registry,
      ).setEnabled('app.views.projects', false),
      throwsA(anything),
    );
    expect(registry.isEnabled('app.views.projects'), isTrue);
    expect(
      registry.ui.primaryDestinations.any((item) => item.id == 'projects'),
      isTrue,
    );
    expect(await db.select(db.appSettings).get(), isEmpty);
  });

  test(
    'disabled shipped IDs cannot be replaced by installed modules',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final registry = XudianApp().registry;
      addTearDown(registry.dispose);
      await BuiltinModuleController(
        db: db,
        registry: registry,
      ).setEnabled('app.views.projects', false);
      final store = DeclarativeModuleStore(db);
      final runtime = DeclarativeRuntimeController(
        store: store,
        registry: registry,
      );
      await expectLater(
        runtime.install({
          'formatVersion': 1,
          'manifest': {
            'id': 'app.views.projects',
            'version': '2.0.0',
            'coreApi': '1',
          },
        }),
        throwsStateError,
      );
      expect(await store.getInstalled('app.views.projects'), isNull);
      expect(registry.isEnabled('app.views.projects'), isFalse);
    },
  );

  testWidgets(
    'closing the current native view falls back and hides AI across restart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final app = XudianApp();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
      await tester.pumpWidget(scope(db, app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('项目').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('打开设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('模块管理'));
      await tester.tap(find.text('模块管理'));
      await tester.pumpAndSettle();
      for (final id in ['app.views.projects', 'app.ai']) {
        final toggle = find.byKey(ValueKey('builtin-switch-$id'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('builtin-switch-app.module.manager')),
        findsNothing,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('AI 连接'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('项目'), findsNothing);
      expect(find.byTooltip('打开 AI 助手'), findsNothing);
      expect(find.text('暂无今天待办或逾期任务'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final restarted = XudianApp();
      await tester.pumpWidget(scope(db, restarted));
      await tester.pumpAndSettle();
      expect(restarted.registry.isEnabled('app.views.projects'), isFalse);
      expect(find.byTooltip('打开 AI 助手'), findsNothing);
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'all work views may hide while module management and selected identity remain stable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final app = XudianApp();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
      await tester.pumpWidget(scope(db, app));
      await tester.pumpAndSettle();
      if (find.text('模块').evaluate().isEmpty) {
        await tester.tap(find.text('更多'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('模块').last);
      await tester.pumpAndSettle();
      for (final id in [
        'app.views.today',
        'app.views.inbox',
        'app.views.projects',
      ]) {
        final toggle = find.byKey(ValueKey('builtin-switch-$id'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.byType(ModuleManagerPage), findsOneWidget);
      }
      expect(app.registry.ui.primaryDestinations.single.id, 'modules');
      final toggle = find.byKey(
        const ValueKey('builtin-switch-app.views.today'),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, 1500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(ModuleManagerPage), findsOneWidget);
      expect(
        app.registry.ui.primaryDestinations.first.id,
        'app.views.today.home',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _DependentModule implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.dependent.test',
    version: '1.0.0',
    coreApi: '1',
    dependencies: ['app.views.projects'],
  );
  @override
  List<UiRegistration> get ui => const [];
}

class _Secrets implements AiSecretStore {
  @override
  Future<String?> readApiKey() async => null;
  @override
  Future<void> writeApiKey(String value) async {}
  @override
  Future<void> deleteApiKey() async {}
}
