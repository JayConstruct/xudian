import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/legacy_app.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/core/ui/ui_slot.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/tasks/application/providers.dart';
import 'package:task_app/features/ui_examples/ui_examples_module.dart';
import 'package:task_app/features/ui_examples/ui_examples_page.dart';
import 'package:task_app/core/ui/ui_page_host.dart';

void main() {
  test('UI examples register a standalone page without data permissions', () {
    final module = UiExamplesModule();
    expect(module.manifest.permissions, ['ui.register']);
    expect(module.manifest.requiresCapabilities, [
      'ui.registry',
      'ui.composition',
    ]);
    final page = module.ui.whereType<WidgetRegistration>().single;
    expect(page.slot, UiSlot.workspacePage);
    expect(page.id, module.manifest.id);
    final app = XudianApp();
    addTearDown(app.registry.dispose);
    expect(app.registry.isEnabled(module.manifest.id), isTrue);
    expect(app.registry.ui.primaryDestinations, hasLength(4));
  });

  testWidgets('module entry is switchable and examples never write tasks', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'real-task',
            title: '保留真实任务',
            createdAt: now,
            updatedAt: now,
          ),
        );
    Widget scope(XudianApp app) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        aiSecretStoreProvider.overrideWithValue(_Secrets()),
      ],
      child: app,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(scope(XudianApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模块').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('打开UI 示例'), 200);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开UI 示例'));
    await tester.pumpAndSettle();
    expect(find.byType(UiExamplesPage), findsOneWidget);
    final task = find.byKey(const ValueKey('example-task-plan'));
    await tester.scrollUntilVisible(task, 200);
    await tester.tap(
      find.descendant(of: task, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 项待办 · 2 项完成'), findsOneWidget);
    expect((await db.select(db.tasks).get()).single.title, '保留真实任务');
    expect(await db.select(db.changeOperations).get(), isEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('builtin-switch-app.ui.examples'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byTooltip('打开UI 示例'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final restarted = XudianApp();
    await tester.pumpWidget(scope(restarted));
    await tester.pumpAndSettle();
    expect(restarted.registry.isEnabled('app.ui.examples'), isFalse);
    expect(restarted.registry.ui.primaryDestinations, hasLength(4));
    expect((await db.select(db.tasks).get()).single.title, '保留真实任务');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final configuration in [
    (size: const Size(320, 640), scale: 1.5, brightness: Brightness.light),
    (size: const Size(390, 844), scale: 1.0, brightness: Brightness.light),
    (size: const Size(1280, 820), scale: 1.5, brightness: Brightness.dark),
  ]) {
    testWidgets(
      'examples remain interactive at ${configuration.size.width}px',
      (tester) async {
        tester.view.physicalSize = configuration.size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue =
            configuration.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData(brightness: configuration.brightness),
              home: const Scaffold(body: UiExamplesPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> reveal(Finder finder, {double delta = 200}) async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            finder,
            delta,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('ui-examples-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
        }

        Future<void> section(String label) async {
          final chip = find.widgetWithText(ChoiceChip, label);
          await reveal(chip, delta: -200);
          await tester.tap(chip);
          await tester.pumpAndSettle();
        }

        await section('输入控件');
        final title = find.byKey(const ValueKey('example-title'));
        await reveal(title);
        await tester.enterText(title, '');
        final submit = find.byKey(const ValueKey('example-submit'));
        await reveal(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('请输入示例标题'), findsOneWidget);
        await reveal(title, delta: -200);
        await tester.enterText(title, '仅供演示');
        await reveal(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('示例表单已验证，未写入真实任务。'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await section('状态反馈');
        await reveal(find.widgetWithText(ChoiceChip, '错误'));
        await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
        await tester.pumpAndSettle();
        await reveal(find.text('重试示例'));
        await tester.tap(find.text('重试示例'));
        await tester.pumpAndSettle();
        expect(find.text('示例操作成功'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await section('弹窗操作');
        await reveal(find.text('确认对话框'));
        await tester.tap(find.text('确认对话框'));
        await tester.pumpAndSettle();
        expect(find.text('这是确认流程演示，不会删除或修改真实数据。'), findsOneWidget);
        await tester.tap(find.text('确认演示'));
        await tester.pumpAndSettle();
        expect(find.text('操作结果：已确认演示'), findsOneWidget);
        await reveal(find.text('底部操作面板'));
        await tester.tap(find.text('底部操作面板'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('安排明天'));
        await tester.pumpAndSettle();
        expect(find.text('操作结果：已选择“安排明天”示例'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await reveal(find.text('重置示例'), delta: -200);
        await tester.tap(find.text('重置示例'));
        await tester.pumpAndSettle();
        expect(find.text('2 项待办 · 1 项完成'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'composition example uses public slots and isolates missing context',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final app = XudianApp();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        app.registry.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: MaterialApp(
            home: Scaffold(
              body: UiPageHost(
                registry: app.registry,
                pageId: 'app.ui.examples.composition',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '跨模块页签'));
      await tester.pumpAndSettle();
      expect(find.textContaining('此内容来自另一个模块'), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, '缺少上下文示例'));
      await tester.pumpAndSettle();
      expect(find.textContaining('页面缺少上下文'), findsOneWidget);
      await tester.tap(find.text('暂时保留'));
      await tester.pumpAndSettle();
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.changeOperations).get(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Secrets implements AiSecretStore {
  @override
  Future<String?> readApiKey() async => null;
  @override
  Future<void> writeApiKey(String value) async {}
  @override
  Future<void> deleteApiKey() async {}
}
