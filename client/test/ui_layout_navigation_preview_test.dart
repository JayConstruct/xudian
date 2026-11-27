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

  void phoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 916);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('候选列表按分区过滤，可搜索添加并撤销', (tester) async {
    phoneViewport(tester);
    await show(tester);
    await tester.tap(find.text('编排入口'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('palette-today')), findsNothing);
    final field = find.byKey(const ValueKey('arranger-search'));
    await tester.enterText(field, 'hidden');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('palette-import')), findsNothing);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hidden')), findsOneWidget);
    expect(
      container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
      isTrue,
    );
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('palette-hidden')), findsOneWidget);
    expect(
      container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
      isFalse,
    );
  });

  testWidgets(
    'drag hover switches zones and only a drop inside the preview edits the draft',
    (tester) async {
      phoneViewport(tester);
      await show(tester);
      await tester.tap(find.text('编排入口'));
      await tester.pumpAndSettle();
      final palette = find.byKey(const ValueKey('palette-hidden'));
      Future<TestGesture> hover(String zone) async {
        final gesture = await tester.startGesture(tester.getCenter(palette));
        await tester.pump(const Duration(milliseconds: 600));
        final target = find.byKey(ValueKey('zone-$zone'));
        expect(
          tester.getTopLeft(palette).dy,
          greaterThan(tester.getBottomLeft(target).dy),
        );
        await gesture.moveTo(tester.getCenter(target));
        await tester.pumpAndSettle();
        return gesture;
      }

      final cancelled = await hover('header');
      expect(
        find.byKey(const ValueKey('layout-preview-fixed-settings')),
        findsOneWidget,
      );
      await cancelled.up();
      await tester.pumpAndSettle();
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isFalse,
      );
      final move = await hover('more');
      expect(
        find.byKey(const ValueKey('more-workspace-settings')),
        findsOneWidget,
      );
      final target = find.byKey(const ValueKey('drop-more-0'));
      await move.moveTo(tester.getCenter(target));
      await tester.pump();
      await move.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('more-entry-hidden')), findsOneWidget);
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isTrue,
      );
      expect(
        container.read(uiLayoutProvider).requireValue.narrow.mounts,
        isEmpty,
      );
      expect(pageBuilds, 0);
    },
  );

  testWidgets(
    'long pressing a dock icon or a More row reorders the actual preview',
    (tester) async {
      phoneViewport(tester);
      await initialize();
      await container
          .read(uiLayoutProvider.notifier)
          .save(
            UiLayout(
              narrow: UiLayoutProfile(
                mounts: {
                  'hidden': const UiMount(
                    placement: UiPlacement.more,
                    order: 1,
                  ),
                },
              ),
            ),
          );
      await show(tester);
      await tester.tap(find.text('编排入口'));
      await tester.pumpAndSettle();
      Future<void> reorder(Finder source, Finder target) async {
        final gesture = await tester.startGesture(tester.getCenter(source));
        await tester.pump(const Duration(milliseconds: 650));
        final destination = tester.getCenter(target);
        await gesture.moveTo(destination);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      final dock = find.byType(MobileBottomDock);
      final firstId = tester.widget<MobileBottomDock>(dock).destinations[1].id;
      final secondId = tester.widget<MobileBottomDock>(dock).destinations[2].id;
      await reorder(
        find.byKey(ValueKey(secondId)),
        find.byKey(const ValueKey('drop-main-0')),
      );
      expect(
        tester.widget<MobileBottomDock>(dock).destinations.map((x) => x.id),
        ['app.shell.more', secondId, firstId],
      );
      await tester.tap(find.byKey(const ValueKey('zone-more')));
      await tester.pumpAndSettle();
      final modules = find.byKey(const ValueKey('more-entry-modules'));
      final hidden = find.byKey(const ValueKey('more-entry-hidden'));
      expect(
        tester.getCenter(hidden).dy,
        greaterThan(tester.getCenter(modules).dy),
      );
      await reorder(hidden, find.byKey(const ValueKey('drop-more-0')));
      expect(
        tester.getCenter(hidden).dy,
        lessThan(tester.getCenter(modules).dy),
      );
      expect(pageBuilds, 0);
    },
  );

  testWidgets('按落点插入、跨区移动、拖出取消与拖入移除，撤销保留先前草稿', (tester) async {
    phoneViewport(tester);
    await show(tester);
    await tester.tap(find.text('编排入口'));
    await tester.pumpAndSettle();
    Finder keyed(String key) => find.byKey(ValueKey(key));
    Future<TestGesture> pick(String key) async {
      final gesture = await tester.startGesture(tester.getCenter(keyed(key)));
      await tester.pump(const Duration(milliseconds: 650));
      return gesture;
    }

    Future<void> drop(TestGesture g, Offset target) async {
      await g.moveTo(target);
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
    }

    List<String> order() => tester
        .widget<MobileBottomDock>(find.byType(MobileBottomDock))
        .destinations
        .map((e) => e.id)
        .toList();
    final added = await pick('palette-hidden');
    await drop(
      added,
      tester.getCenter(keyed('drop-main-0')) + const Offset(8, 0),
    );
    expect(order(), ['app.shell.more', 'today', 'hidden', 'schedule']);
    final cancel = await pick('hidden');
    await drop(cancel, tester.getCenter(find.text('编排入口')));
    expect(order(), ['app.shell.more', 'today', 'hidden', 'schedule']);
    final move = await pick('hidden');
    await move.moveTo(tester.getCenter(keyed('zone-header')));
    await tester.pumpAndSettle();
    final menu = keyed('drop-header-0');
    await drop(move, tester.getCenter(menu) + const Offset(0, 8));
    expect(
      tester.getCenter(keyed('layout-row-hidden')).dy,
      greaterThan(tester.getCenter(keyed('layout-row-import')).dy),
    );
    final remove = await pick('layout-row-hidden');
    await drop(remove, tester.getCenter(keyed('drop-remove')));
    expect(keyed('layout-row-hidden'), findsNothing);
    expect(keyed('palette-hidden'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(keyed('layout-row-hidden'), findsOneWidget);
    expect(
      container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
      isTrue,
    );
    expect(
      container.read(uiLayoutProvider).requireValue.narrow.mounts,
      isEmpty,
    );
  });

  testWidgets('拖至长列表边缘，按松手时可见的行插入', (tester) async {
    phoneViewport(tester);
    await initialize();
    for (var i = 0; i < 18; i++) {
      registry.ui.register(
        UiEntryRegistration(
          id: 'extra-$i',
          moduleId: 'test',
          pageId: 'test.page',
          label: '入口 $i',
          icon: Icons.apps,
          defaultMount: UiMount(placement: UiPlacement.header, order: i + 1),
        ),
      );
    }
    await show(tester);
    await tester.tap(find.text('编排入口'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('zone-header')));
    await tester.pumpAndSettle();
    final candidate = find.byKey(const ValueKey('palette-hidden'));
    final drag = await tester.startGesture(tester.getCenter(candidate));
    await tester.pump(const Duration(milliseconds: 650));
    final viewport = find
        .ancestor(
          of: find.byKey(const ValueKey('drop-header-0')),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final point = Offset(
      tester.getCenter(find.byKey(const ValueKey('drop-header-0'))).dx,
      tester.getBottomLeft(viewport).dy - 16,
    );
    await drag.moveTo(point);
    for (var frame = 0; frame < 36; frame++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    final rows = ['import', for (var i = 0; i < 18; i++) 'extra-$i'];
    final row = rows.indexWhere(
      (id) => tester
          .getRect(find.byKey(ValueKey('layout-row-$id')))
          .contains(point),
    );
    expect(row, greaterThan(4));
    final anchor = tester.getRect(
      find.byKey(ValueKey('layout-row-${rows[row]}')),
    );
    final expected = row + (point.dy > anchor.center.dy ? 1 : 0);
    await drag.up();
    await tester.pumpAndSettle();
    final inserted = find.descendant(
      of: find.byKey(ValueKey('drop-header-$expected')),
      matching: find.byKey(const ValueKey('layout-row-hidden')),
    );
    expect(inserted, findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(
      container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
      isFalse,
    );
  });

  testWidgets('visual entries edit drafts without opening business pages', (
    tester,
  ) async {
    await show(tester);
    expect(find.byType(MobileBottomDock), findsNothing);
    expect(
      find.byKey(const ValueKey('layout-preview-header-menu')),
      findsNothing,
    );
    await tester.tap(find.text('编排入口'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileBottomDock), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-search')), findsNothing);
    expect(find.text('显示技术标识'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('today')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整位置与上下文'));
    await tester.pumpAndSettle();
    expect(find.text('编辑 · 今天'), findsOneWidget);
    await closeInspector(tester);
    await tester.tap(find.byKey(const ValueKey('today')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整位置与上下文'));
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
      ['app.shell.more', 'schedule'],
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('查看变更（1）'), findsOneWidget);
    await tester.tap(find.text('编排入口'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('zone-header')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileBottomDock), findsNothing);
    final menuItem = find.byKey(const ValueKey('layout-row-today'));
    await tester.ensureVisible(menuItem);
    await tester.tap(menuItem);
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整位置与上下文'));
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
    await tester.tap(find.text('保存布局'));
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
    await tester.tap(find.text('编排入口'));
    await tester.pumpAndSettle();
    final dock = tester.widget<MobileBottomDock>(find.byType(MobileBottomDock));
    expect(dock.destinations.map((e) => e.id), ['app.shell.more', 'today']);
    expect(dock.hasMore, isFalse);
    expect(dock.onAssistant, isNull);
    await tester.tap(find.byKey(const ValueKey('app.shell.more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-entry-modules')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-entry-schedule')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('more-entry-schedule')),
    );
    await tester.tap(find.byKey(const ValueKey('more-entry-schedule')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整位置与上下文'));
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
    'More switch edits the draft and disabling retains overflow access',
    (tester) async {
      await initialize();
      await container
          .read(uiLayoutProvider.notifier)
          .save(UiLayout(narrow: UiLayoutProfile(mainLimit: 1)));
      await show(tester);
      await tester.tap(find.text('编排入口'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示选项'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('layout-more-page-enabled'));
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final dock = tester.widget<MobileBottomDock>(
        find.byType(MobileBottomDock),
      );
      expect(dock.destinations.map((e) => e.id), ['today']);
      expect(find.textContaining('右上角菜单的“全部入口”访问'), findsOneWidget);
      await tester.tap(find.text('返回编排'));
      await tester.pumpAndSettle();
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.morePageEnabled,
        isTrue,
      );
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('zone-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('more-entry-modules')), findsOneWidget);
      expect(find.byKey(const ValueKey('more-entry-schedule')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('查看变更（1）'), findsOneWidget);
      await tester.tap(find.text('编排入口'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示选项'));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(pageBuilds, 0);
    },
  );

  testWidgets(
    'fixed settings stays visible and hidden entries can be restored',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('编排入口'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('zone-header')));
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
      await tester.tap(find.text('编排入口'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('调整位置与上下文'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('调整位置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('顶部菜单'));
      await tester.pumpAndSettle();
      await closeInspector(tester);

      await tester.tap(find.text('保存布局'));
      await tester.pump();
      expect(controller.started.isCompleted, isTrue);
      expect(controller.finished.isCompleted, isFalse);
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mounts,
        isEmpty,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('布局与导航'), findsOneWidget);
      expect(find.text('编排入口'), findsOneWidget);
      expect(find.text('编辑布局'), findsNothing);

      await tester.runAsync(() async {
        controller.release.complete();
        await controller.finished.future.timeout(const Duration(seconds: 10));
      });
      await tester.pumpAndSettle();
      expect(find.byType(UiLayoutPage), findsOneWidget);
      expect(find.text('布局与导航'), findsOneWidget);
      expect(find.text('编排入口'), findsOneWidget);
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
        ValueKey(desktop ? 'layout-preview-more' : 'app.shell.more'),
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
