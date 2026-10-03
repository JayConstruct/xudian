import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/tasks/application/providers.dart';
import 'package:task_app/features/module_manager/builtin_module_controller.dart';

void main() {
  testWidgets('quick add writes a task and inbox displays it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => database),
          aiSecretStoreProvider.overrideWithValue(_TestAiSecretStore()),
        ],
        child: XudianApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '购买牛奶');
    await tester.pump();
    await tester.tap(find.byTooltip('添加任务'));
    await tester.pumpAndSettle();
    expect((await database.select(database.tasks).get()).single.title, '购买牛奶');
    expect(find.text('购买牛奶'), findsOneWidget);

    await tester.tap(find.text('收件箱').last);
    await tester.pumpAndSettle();
    expect(find.text('购买牛奶'), findsOneWidget);

    await tester.tap(find.byTooltip('打开 AI 助手'));
    await tester.pumpAndSettle();
    expect(find.text('AI 工作区'), findsOneWidget);
    expect(find.text('作用范围 · 私有模块功能'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('desktop workspace opens AI beside the current page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => database),
          aiSecretStoreProvider.overrideWithValue(_TestAiSecretStore()),
        ],
        child: XudianApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('工作台'), findsOneWidget);

    await tester.tap(find.byTooltip('打开 AI 助手'));
    await tester.pumpAndSettle();
    expect(find.text('AI 工作区'), findsOneWidget);
    expect(find.text('今天已经安排妥当'), findsOneWidget);

    final app = tester.widget<XudianApp>(find.byType(XudianApp));
    final container = ProviderScope.containerOf(
      tester.element(find.text('工作台')),
    );
    final modules = await container.read(
      builtinModuleControllerProvider(app.registry).future,
    );
    await modules.setEnabled('app.ai', false);
    await tester.pumpAndSettle();
    expect(find.text('AI 工作区'), findsNothing);
    expect(find.byTooltip('打开 AI 助手'), findsNothing);
    await modules.setEnabled('app.ai', true);
    await tester.pumpAndSettle();
    expect(find.text('AI 工作区'), findsNothing);
    expect(find.byTooltip('打开 AI 助手'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('floating dock keeps the last task reachable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.now();
    await database.batch((batch) {
      for (var i = 0; i < 18; i++) {
        batch.insert(
          database.tasks,
          TasksCompanion.insert(
            id: 'task-$i',
            title: '任务 $i',
            createdAt: now.add(Duration(seconds: i)),
            updatedAt: now,
          ),
        );
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => database),
          aiSecretStoreProvider.overrideWithValue(_TestAiSecretStore()),
        ],
        child: XudianApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('收件箱').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();

    final lastTile = find.ancestor(
      of: find.text('任务 0'),
      matching: find.byType(TaskObjectTile),
    );
    final dock = find.byKey(const ValueKey('mobile-bottom-dock'));
    expect(tester.getRect(lastTile).bottom, lessThan(tester.getRect(dock).top));
    await tester.tap(
      find.descendant(of: lastTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    final tasks = await database.select(database.tasks).get();
    expect(
      tasks.singleWhere((task) => task.id == 'task-0').completedAt,
      isNotNull,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-navigation')), findsNothing);
    await tester.enterText(find.byType(TextField).first, '键盘上方添加');
    await tester.pump();
    await tester.tap(find.byTooltip('添加任务'));
    await tester.pumpAndSettle();
    expect(
      (await database.select(database.tasks).get()).any(
        (task) => task.title == '键盘上方添加',
      ),
      isTrue,
    );
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-navigation')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('project dialog controller survives its closing animation', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => database),
          aiSecretStoreProvider.overrideWithValue(_TestAiSecretStore()),
        ],
        child: XudianApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '临时草稿');
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(await database.select(database.projects).get(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _TestAiSecretStore implements AiSecretStore {
  @override
  Future<String?> readApiKey() async => null;

  @override
  Future<void> writeApiKey(String value) async {}

  @override
  Future<void> deleteApiKey() async {}
}
