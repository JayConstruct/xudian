import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/features/settings/ui_layout.dart';
import 'package:task_app/features/settings/ui_layout_navigation_preview.dart';
import 'package:task_app/features/settings/ui_layout_page.dart';

class _DelayedLayoutController extends UiLayoutController {
  final started = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();

  @override
  Future<void> saveIfUnchanged(
    UiLayout layout, {
    required UiLayout expected,
  }) async {
    started.complete();
    await release.future;
    await super.saveIfUnchanged(layout, expected: expected);
    finished.complete();
  }
}

void main() {
  late ModuleRegistry registry;
  late AppDatabase database;
  late ProviderContainer container;
  var pageBuilds = 0;
  var initialized = false;

  setUp(() => initialized = false);

  Future<void> initialize() async {
    if (initialized) return;
    initialized = true;
    pageBuilds = 0;
    registry = ModuleRegistry(
      const [],
      capabilities: CapabilityRegistry(const []),
    );
    database = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((_) async => database)],
    );
    await container.read(uiLayoutProvider.future);
    registry.ui.register(
      UiPageRegistration(
        id: 'test.page',
        moduleId: 'test',
        title: '业务页面',
        builder: (_, _) {
          pageBuilds++;
          return const Text('业务页面已打开');
        },
      ),
    );
    for (final entry in [
      ('today', '今天', UiPlacement.main),
      ('schedule', '课表', UiPlacement.main),
      ('import', '教务导入', UiPlacement.header),
      ('modules', '模块', UiPlacement.more),
      ('hidden', '隐藏工具', UiPlacement.hidden),
    ]) {
      registry.ui.register(
        UiEntryRegistration(
          id: entry.$1,
          moduleId: 'test',
          pageId: 'test.page',
          label: entry.$2,
          icon: Icons.apps,
          defaultMount: UiMount(placement: entry.$3),
        ),
      );
    }
  }

  tearDown(() async {
    if (!initialized) return;
    container.dispose();
    registry.dispose();
    await database.close();
  });

  Future<void> show(WidgetTester tester) async {
    await initialize();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: UiLayoutPage(registry: registry)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeInspector(WidgetTester tester) async {
    Navigator.of(tester.element(find.byKey(const ValueKey('layout-inspector'))))
        .pop();
    await tester.pumpAndSettle();
  }

  testWidgets('visual entries edit drafts without opening business pages', (
    tester,
  ) async {
    await show(tester);
    expect(find.byType(MobileBottomDock), findsNothing);
    expect(
      find.byKey(const ValueKey('layout-preview-header-menu')),
      findsNothing,
    );
    await tester.tap(find.text('底部导航'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileBottomDock), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-search')), findsNothing);
    expect(find.text('显示技术标识'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('today')));
    await tester.pumpAndSettle();
    expect(find.text('编辑 · 今天'), findsOneWidget);
    await tester.tap(find.text('调整位置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('顶部菜单'));
    await tester.pumpAndSettle();
    await closeInspector(tester);
    expect(
      tester
          .widget<MobileBottomDock>(find.byType(MobileBottomDock))
          .destinations
          .map((e) => e.id),
      ['schedule'],
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('查看变更（1）'), findsOneWidget);
    await tester.tap(find.text('右上角菜单'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileBottomDock), findsNothing);
    final menuItem = find.byKey(const ValueKey('layout-row-today'));
    await tester.ensureVisible(menuItem);
    await tester.tap(menuItem);
    await tester.pumpAndSettle();
    expect(find.text('编辑 · 今天'), findsOneWidget);
    expect(
      container.read(uiLayoutProvider).asData!.value.narrow.mounts,
      isEmpty,
    );
    expect(await database.select(database.appSettings).get(), isEmpty);
    expect(
      container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
      isTrue,
    );
    expect(pageBuilds, 0);
    expect(find.text('业务页面已打开'), findsNothing);
    await closeInspector(tester);
    final saved = Completer<void>();
    final subscription = container.listen(uiLayoutProvider, (_, next) {
      if (next.asData?.value.narrow.mounts['today'] != null &&
          !saved.isCompleted) {
        saved.complete();
      }
    });
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => saved.future.timeout(const Duration(seconds: 10)),
    );
    await tester.pumpAndSettle();
    subscription.close();
    expect(
      container
          .read(uiLayoutProvider)
          .asData!
          .value
          .narrow
          .mounts['today']!
          .placement,
      UiPlacement.header,
    );
    expect(container.read(uiLayoutProvider).asData!.value.wide.mounts, isEmpty);
    expect(pageBuilds, 0);
  });

  testWidgets('overflow opens the same more list and selects its editor', (
    tester,
  ) async {
    await initialize();
    await container
        .read(uiLayoutProvider.notifier)
        .save(UiLayout(narrow: UiLayoutProfile(mainLimit: 1)));
    await show(tester);
    await tester.tap(find.text('底部导航'));
    await tester.pumpAndSettle();
    final dock = tester.widget<MobileBottomDock>(find.byType(MobileBottomDock));
    expect(dock.destinations.map((e) => e.id), ['today']);
    expect(dock.hasMore, isTrue);
    await tester.tap(find.byKey(const ValueKey('more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('layout-more-modules')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-more-schedule')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('layout-more-schedule')));
    await tester.pumpAndSettle();
    expect(find.text('编辑 · 课表'), findsOneWidget);
    expect(find.text('更多入口'), findsNothing);
    await closeInspector(tester);
    expect(
      container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
      isFalse,
    );
    expect(pageBuilds, 0);
  });

  testWidgets(
    'fixed settings stays visible and hidden entries can be restored',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('右上角菜单'));
      await tester.pumpAndSettle();
      final settings = find.byKey(
        const ValueKey('layout-preview-fixed-settings'),
      );
      await tester.ensureVisible(settings);
      expect(tester.widget<ListTile>(settings).onTap, isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('常用与隐藏入口'));
      await tester.pumpAndSettle();
      final hidden = find.text('隐藏入口 · 1');
      await tester.ensureVisible(hidden);
      await tester.pumpAndSettle();
      await tester.tap(hidden);
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('layout-row-hidden'));
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('编辑 · 隐藏工具'), findsOneWidget);
      expect(pageBuilds, 0);
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isFalse,
      );
    },
  );

  testWidgets(
    'finishing a child save after returning keeps the parent editor open',
    (tester) async {
      await initialize();
      container.dispose();
      final controller = _DelayedLayoutController();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((_) async => database),
          uiLayoutProvider.overrideWith(() => controller),
        ],
      );
      await container.read(uiLayoutProvider.future);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => UiLayoutPage(registry: registry),
                    ),
                  ),
                  child: const Text('编辑布局'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑布局'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('底部导航'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('调整位置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('顶部菜单'));
      await tester.pumpAndSettle();
      await closeInspector(tester);

      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(controller.started.isCompleted, isTrue);
      expect(controller.finished.isCompleted, isFalse);
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mounts,
        isEmpty,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('入口与页面布局'), findsOneWidget);
      expect(find.text('右上角菜单'), findsOneWidget);
      expect(find.text('编辑布局'), findsNothing);

      await tester.runAsync(() async {
        controller.release.complete();
        await controller.finished.future.timeout(const Duration(seconds: 10));
      });
      await tester.pumpAndSettle();
      expect(find.byType(UiLayoutPage), findsOneWidget);
      expect(find.text('入口与页面布局'), findsOneWidget);
      expect(find.text('右上角菜单'), findsOneWidget);
      expect(find.text('编辑布局'), findsNothing);
      expect(find.text('保存中…'), findsNothing);
      expect(find.text('查看变更（1）'), findsNothing);
      expect(
        container
            .read(uiLayoutProvider)
            .asData!
            .value
            .narrow
            .mounts['today']!
            .placement,
        UiPlacement.header,
      );
      expect(
        container.read(uiLayoutProvider).asData!.value.wide.mounts,
        isEmpty,
      );
      expect(await database.select(database.appSettings).get(), hasLength(1));
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isFalse,
      );
      expect(pageBuilds, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final desktop in [false, true]) {
    testWidgets('preview is reachable with large text: desktop=$desktop', (
      tester,
    ) async {
      await initialize();
      tester.view.physicalSize = desktop
          ? const Size(1200, 900)
          : const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: desktop ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                UiLayoutNavigationPreview(
                  registry: registry.ui,
                  profile: UiLayoutProfile(mainLimit: 1),
                  desktop: desktop,
                  onSelected: (id) => selected = id,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('layout-row-import'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      expect(selected, 'import');
      final more = find.byKey(
        ValueKey(desktop ? 'layout-preview-more' : 'more'),
      );
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layout-more-schedule')));
      await tester.pumpAndSettle();
      expect(selected, 'schedule');
      expect(pageBuilds, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
