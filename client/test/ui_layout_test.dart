import 'support/legacy_context.dart';

import 'package:task_app/core/ui/page_context_validation.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_layout_resolver.dart';
import 'package:task_app/core/ui/ui_page_host.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/settings/ui_layout.dart';
import 'package:task_app/features/settings/ui_layout_page.dart';
import 'package:task_app/features/settings/ui_layout_preview.dart';
import 'package:task_app/features/tasks/application/providers.dart';

Future<void> _openAdvancedEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('高级编辑'));
  await tester.pumpAndSettle();
}

class _Module implements AppModule {
  _Module(this.id, this.ui);
  final String id;
  @override
  final List<UiRegistration> ui;
  @override
  ModuleManifest get manifest => ModuleManifest(
    id: id,
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );
}

ModuleRegistry _registry({
  bool public = true,
  bool retain = true,
  bool editable = true,
  int? capacity,
  List<String> requiredContext = const [],
  VoidCallback? onPageBuild,
}) => ModuleRegistry([
  _Module('test.host', [
    UiPageRegistration(
      id: 'test.host.page',
      moduleId: 'test.host',
      title: '宿主',
      container: true,
      retainPosition: retain,
      builder: (_, _) => const SizedBox.shrink(),
      slots: [
        PageSlotDefinition(
          id: 'tabs',
          label: '公开页签',
          kind: PageSlotKind.tabs,
          isPublic: public,
          editable: editable,
          capacity: capacity,
        ),
      ],
    ),
    const UiEntryRegistration(
      id: 'test.host.entry',
      moduleId: 'test.host',
      pageId: 'test.host.page',
      label: '宿主',
      icon: Icons.home,
    ),
  ]),
  _Module('test.child', [
    UiPageRegistration(
      id: 'test.child.first',
      moduleId: 'test.child',
      title: '第一个',
      requiredContext: requiredContext,
      builder: (_, _) {
        onPageBuild?.call();
        return const Center(child: Text('第一个内容'));
      },
    ),
    UiPageRegistration(
      id: 'test.child.second',
      moduleId: 'test.child',
      title: '第二个',
      builder: (_, _) {
        onPageBuild?.call();
        return const Center(child: Text('第二个内容'));
      },
    ),
    for (final name in ['first', 'second'])
      UiEntryRegistration(
        id: 'test.child.$name.entry',
        moduleId: 'test.child',
        pageId: 'test.child.$name',
        label: name == 'first' ? '第一页' : '第二页',
        icon: Icons.pages,
        content: true,
        defaultMount: UiMount(
          placement: UiPlacement.page,
          pageId: 'test.host.page',
          slotId: 'tabs',
          order: name == 'first' ? 0 : 1,
        ),
      ),
  ]),
], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));

void main() {
  testWidgets(
    'mobile failure positioning and context editing retain unsaved bindings',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry(requiredContext: ['projectId']);
      final now = DateTime.now();
      await database
          .into(database.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'selected-project',
              name: '编辑器项目',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final container = ProviderContainer(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
      );
      await container.read(uiLayoutProvider.future);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: UiLayoutPage(
              registry: registry,
              initialDesktop: true,
              initialPageId: 'test.host.page',
              initialEntryId: 'test.child.first.entry',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('编辑 · 第一页'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('补充上下文'),
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('layout-inspector')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('补充上下文'));
      await tester.pumpAndSettle();
      final projectField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == '项目',
        ),
      );
      await tester.ensureVisible(projectField);
      await tester.tap(projectField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑器项目').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用此上下文'));
      await tester.pumpAndSettle();
      expect(find.textContaining('指定项目'), findsWidgets);
      expect(
        container.read(uiLayoutProvider).asData!.value.wide.mounts,
        isEmpty,
      );
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('layout-inspector'))),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(uiLayoutProvider)
            .asData!
            .value
            .wide
            .mounts['test.child.first.entry']!
            .context
            .projectId,
        'selected-project',
      );
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mounts,
        isEmpty,
      );
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isFalse,
      );
    },
  );

  testWidgets(
    'groups collapse and compatible target search preserves context without saving',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry();
      registry.ui.register(
        UiPageRegistration(
          id: 'test.host.alternate',
          moduleId: 'test.host',
          title: '另一个宿主',
          container: true,
          builder: (_, _) => const SizedBox.shrink(),
          slots: const [
            PageSlotDefinition(
              id: 'sections',
              label: '公开内容',
              kind: PageSlotKind.sections,
              isPublic: true,
            ),
            PageSlotDefinition(
              id: 'locked',
              label: '固定内容',
              kind: PageSlotKind.sections,
              isPublic: true,
              editable: false,
            ),
            PageSlotDefinition(
              id: 'private',
              label: '私有内容',
              kind: PageSlotKind.sections,
            ),
            PageSlotDefinition(id: 'buttons', label: '入口按钮', isPublic: true),
          ],
        ),
      );
      final proposal = UiLayout(
        narrow: UiLayoutProfile(
          mounts: {
            'test.child.first.entry': const UiMount(
              placement: UiPlacement.page,
              pageId: 'test.host.page',
              slotId: 'tabs',
              context: PageContext(projectId: 'bound-project'),
            ),
            'unavailable.entry': const UiMount(
              placement: UiPlacement.page,
              pageId: 'test.host.page',
              slotId: 'gone',
            ),
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
      );
      await container.read(uiLayoutProvider.future);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: UiLayoutPage(
              registry: registry,
              initialDraft: proposal,
              initialPageId: 'test.host.page',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('公开页签 · 2 / 2'), findsOneWidget);
      await tester.tap(find.text('公开页签 · 2 / 2'));
      await tester.pumpAndSettle();
      expect(find.text('第一页'), findsNothing);
      expect(find.text('第二页'), findsNothing);
      await tester.tap(find.text('公开页签 · 2 / 2'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('layout-row-test.child.first.entry')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('调整位置'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuButton<int>), findsNothing);
      expect(find.text('另一个宿主 / 公开内容'), findsOneWidget);
      expect(find.text('另一个宿主 / 固定内容'), findsNothing);
      expect(find.text('另一个宿主 / 私有内容'), findsNothing);
      expect(find.text('另一个宿主 / 入口按钮'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('layout-picker-search')),
        'test.host.alternate',
      );
      await tester.pumpAndSettle();
      expect(find.text('宿主 / 公开页签'), findsNothing);
      await tester.tap(find.text('另一个宿主 / 公开内容'));
      await tester.pumpAndSettle();
      expect(find.textContaining('另一个宿主 / 公开内容 · 第 1 项 · 指定项目'), findsWidgets);
      expect(
        proposal.narrow.mounts['test.child.first.entry']!.pageId,
        'test.host.page',
      );
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mounts,
        isEmpty,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = container
          .read(uiLayoutProvider)
          .asData!
          .value
          .narrow
          .mounts;
      expect(
        saved['test.child.first.entry']!.context.projectId,
        'bound-project',
      );
      expect(saved['test.child.first.entry']!.pageId, 'test.host.alternate');
      expect(saved['unavailable.entry']!.slotId, 'gone');
    },
  );

  testWidgets(
    'editor sessions compare canonical drafts, include invalid input and close on disposal',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry();
      final container = ProviderContainer(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
      );
      await container.read(uiLayoutProvider.future);
      final persisted = UiLayout(
        narrow: UiLayoutProfile(
          mainLimit: 4,
          mounts: {
            'test.host.entry': const UiMount(placement: UiPlacement.header),
            'missing.entry': const UiMount(placement: UiPlacement.hidden),
          },
        ),
      );
      await container.read(uiLayoutProvider.notifier).save(persisted);
      final equivalent = UiLayout(
        narrow: UiLayoutProfile(
          mainLimit: 4,
          mounts: {
            'missing.entry': const UiMount(placement: UiPlacement.hidden),
            'test.host.entry': const UiMount(placement: UiPlacement.header),
          },
        ),
      );
      final sessions = container.read(uiLayoutEditorSessionsProvider);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: UiLayoutPage(registry: registry, initialDraft: equivalent),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openAdvancedEditor(tester);
      expect(sessions.hasDirtyEditors, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('navigation-limit-false')),
        '0',
      );
      expect(sessions.hasDirtyEditors, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('navigation-limit-false')),
        '4',
      );
      expect(sessions.hasDirtyEditors, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('navigation-limit-false')),
        '2',
      );
      expect(sessions.hasDirtyEditors, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(sessions.hasDirtyEditors, isFalse);
    },
  );

  testWidgets(
    'editor refuses concurrent persisted changes without dropping its draft',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry();
      final container = ProviderContainer(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
      );
      await container.read(uiLayoutProvider.future);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: UiLayoutPage(
              registry: registry,
              initialDraft: UiLayout(narrow: UiLayoutProfile(mainLimit: 2)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openAdvancedEditor(tester);
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isTrue,
      );
      await container
          .read(uiLayoutProvider.notifier)
          .save(UiLayout(narrow: UiLayoutProfile(mainLimit: 9)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('布局已被其他操作修改'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('navigation-limit-false')),
            )
            .controller!
            .text,
        '2',
      );
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mainLimit,
        9,
      );
      expect(
        container.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
        isTrue,
      );
      expect(find.text('查看变更（1）'), findsOneWidget);
    },
  );

  testWidgets(
    'initial draft uses persisted baseline and initializes both controllers without publishing',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry();
      final container = ProviderContainer(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
      );
      await container.read(uiLayoutProvider.future);
      final proposal = UiLayout(
        narrow: UiLayoutProfile(
          mainLimit: 2,
          mounts: {
            'test.host.entry': const UiMount(placement: UiPlacement.header),
            'missing.entry': const UiMount(placement: UiPlacement.hidden),
            'stale.entry': const UiMount(
              placement: UiPlacement.page,
              pageId: 'missing.page',
              slotId: 'gone',
            ),
          },
        ),
        wide: UiLayoutProfile(mainLimit: 7),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: UiLayoutPage(registry: registry, initialDraft: proposal),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openAdvancedEditor(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('navigation-limit-false')),
            )
            .controller!
            .text,
        '2',
      );
      expect(find.text('查看变更（5）'), findsOneWidget);
      expect(find.text('missing.entry'), findsOneWidget);
      await tester.tap(find.text('电脑 / 宽屏'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('navigation-limit-true')),
            )
            .controller!
            .text,
        '7',
      );
      await tester.enterText(
        find.byKey(const ValueKey('navigation-limit-true')),
        '8',
      );
      expect(proposal.wide.mainLimit, 7);
      expect(
        container.read(uiLayoutProvider).asData!.value.wide.mainLimit,
        isNull,
      );
      expect(await database.select(database.appSettings).get(), isEmpty);
      await tester.tap(find.text('查看变更（5）'));
      await tester.pumpAndSettle();
      expect(find.text('窄屏 · 主导航直显上限'), findsOneWidget);
      expect(find.text('宽屏 · 主导航直显上限'), findsOneWidget);
      expect(find.textContaining('原：4'), findsOneWidget);
    },
  );

  testWidgets(
    'filtered anchors use the full group and preserve immutable contexts',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry();
      registry.ui.register(
        const UiEntryRegistration(
          id: 'test.child.third.entry',
          moduleId: 'test.child',
          pageId: 'test.child.second',
          label: '第三页',
          icon: Icons.pages,
          content: true,
          defaultMount: UiMount(
            placement: UiPlacement.page,
            pageId: 'test.host.page',
            slotId: 'tabs',
            order: 2,
          ),
        ),
      );
      final proposal = UiLayout(
        narrow: UiLayoutProfile(
          mounts: {
            'test.child.first.entry': const UiMount(
              placement: UiPlacement.page,
              pageId: 'test.host.page',
              slotId: 'tabs',
              context: PageContext(taskId: 'bound-task'),
            ),
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
      );
      await container.read(uiLayoutProvider.future);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: UiLayoutPage(
              registry: registry,
              initialDraft: proposal,
              initialPageId: 'test.host.page',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('layout-search')),
        'first',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('layout-row-test.child.first.entry')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '下移',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('移到指定项之后'));
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsOneWidget);
      expect(find.text('第三页'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('layout-picker-search')),
        'third',
      );
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsNothing);
      await tester.tap(find.text('第三页'));
      await tester.pumpAndSettle();
      expect(find.text('分组顺序 · 3 / 3'), findsOneWidget);
      await tester.tap(find.text('置顶'));
      await tester.pumpAndSettle();
      expect(find.text('分组顺序 · 1 / 3'), findsOneWidget);
      await tester.tap(find.text('置底'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移到指定项之前'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第三页'));
      await tester.pumpAndSettle();
      expect(find.text('分组顺序 · 2 / 3'), findsOneWidget);
      expect(proposal.narrow.mounts['test.child.first.entry']!.order, 0);
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mounts,
        isEmpty,
      );
      Navigator.of(
        tester.element(find.byKey(const ValueKey('layout-inspector'))),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final mounts = container
          .read(uiLayoutProvider)
          .asData!
          .value
          .narrow
          .mounts;
      expect(mounts['test.child.second.entry']!.order, 0);
      expect(mounts['test.child.first.entry']!.order, 1);
      expect(mounts['test.child.third.entry']!.order, 2);
      expect(mounts['test.child.first.entry']!.context.taskId, 'bound-task');
    },
  );

  testWidgets(
    'fixed slots remain inspectable but cannot be edited or added to',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry(editable: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pageContextValidityProvider.overrideWith(legacyPageContextValidity),
            databaseProvider.overrideWith((ref) async => database),
          ],
          child: MaterialApp(
            home: UiLayoutPage(
              registry: registry,
              initialPageId: 'test.host.page',
              initialEntryId: 'test.child.first.entry',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('模块固定槽位'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '调整位置'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '置底'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '补充上下文'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('添加入口或内容'));
      await tester.tap(find.text('添加入口或内容'));
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的兼容选项'), findsOneWidget);
    },
  );

  testWidgets(
    'failed editor save retains proposal and publishes only after retry succeeds',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry();
      final container = ProviderContainer(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
      );
      await container.read(uiLayoutProvider.future);
      await database.customStatement(
        "CREATE TRIGGER reject_layout BEFORE INSERT ON app_settings BEGIN SELECT RAISE(FAIL, 'test failure'); END",
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: UiLayoutPage(
              registry: registry,
              initialDraft: UiLayout(narrow: UiLayoutProfile(mainLimit: 2)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openAdvancedEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('navigation-limit-false')),
        '0',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('直显上限须为正整数，留空表示不限制'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('navigation-limit-false')),
        '2',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('布局保存失败，草稿保留，请重试'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('navigation-limit-false')),
            )
            .controller!
            .text,
        '2',
      );
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mainLimit,
        4,
      );
      await database.customStatement('DROP TRIGGER reject_layout');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mainLimit,
        2,
      );
    },
  );

  test(
    'diagnostics distinguish structure, context, capacity and hidden mounts',
    () {
      final registry = _registry(capacity: 1, requiredContext: ['projectId']);
      final privateRegistry = _registry(public: false);
      addTearDown(registry.dispose);
      addTearDown(privateRegistry.dispose);
      final first = registry.ui.entries[1];
      final second = registry.ui.entries[2];
      final profile = UiLayoutProfile();
      expect(
        layoutEntryDiagnostic(registry.ui, first, profile.mountFor)?.issue,
        UiMountIssue.missingContext,
      );
      expect(
        layoutEntryDiagnostic(registry.ui, second, profile.mountFor)?.issue,
        UiMountIssue.capacityExceeded,
      );
      expect(
        mountDiagnostic(privateRegistry.ui, first, first.defaultMount)?.issue,
        UiMountIssue.privateSlot,
      );
      expect(
        mountDiagnostic(
          registry.ui,
          first,
          const UiMount(
            placement: UiPlacement.page,
            pageId: 'missing.host',
            slotId: 'tabs',
          ),
        )?.issue,
        UiMountIssue.hostUnavailable,
      );
      final hidden = profile.withMount(
        first.id,
        const UiMount(placement: UiPlacement.hidden),
      );
      expect(
        layoutEntryDiagnostic(registry.ui, first, hidden.mountFor),
        isNull,
      );
      expect(hidden.withoutMount(first.id).mountFor(first), first.defaultMount);
      expect(
        mountDiagnostic(
          registry.ui,
          first,
          first.defaultMount,
          context: const PageContext(projectId: 'inherited'),
        ),
        isNull,
      );
      expect(
        const UiMount(context: PageContext(projectId: 'project')),
        UiMount.fromJson(
          const UiMount(context: PageContext(projectId: 'project')).toJson(),
        ),
      );
    },
  );

  testWidgets(
    'structural preview shows overflow without building business pages',
    (tester) async {
      var pageBuilds = 0;
      final registry = _registry(onPageBuild: () => pageBuilds++);
      addTearDown(registry.dispose);
      for (var index = 0; index < 5; index++) {
        registry.ui.register(
          UiEntryRegistration(
            id: 'test.host.extra$index',
            moduleId: 'test.host',
            pageId: 'test.child.first',
            label: '额外入口$index',
            icon: Icons.pages,
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: UiLayoutPreview(
            registry: registry.ui,
            profile: UiLayoutProfile(mainLimit: 2),
            desktop: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('主导航直显 · 2'), findsOneWidget);
      expect(find.text('更多（含溢出入口） · 4'), findsOneWidget);
      expect(pageBuilds, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor preview and change review retain both profile drafts without saving',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      var pageBuilds = 0;
      final registry = _registry(onPageBuild: () => pageBuilds++);
      late ProviderContainer container;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pageContextValidityProvider.overrideWith(legacyPageContextValidity),
            databaseProvider.overrideWith((ref) async => database),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return UiLayoutPage(registry: registry);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openAdvancedEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('navigation-limit-false')),
        '2',
      );
      await tester.tap(find.text('电脑 / 宽屏'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('navigation-limit-true')),
        '3',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看变更（2）'));
      await tester.tap(find.text('查看变更（2）'));
      await tester.pumpAndSettle();
      expect(find.text('窄屏 · 主导航直显上限'), findsOneWidget);
      expect(find.text('宽屏 · 主导航直显上限'), findsOneWidget);
      await tester.tap(find.text('返回编辑'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('预览草稿'));
      await tester.tap(find.text('预览草稿'));
      await tester.pumpAndSettle();
      expect(find.text('草稿结构预览'), findsOneWidget);
      expect(pageBuilds, 0);
      expect(
        container.read(uiLayoutProvider).asData!.value.narrow.mainLimit,
        4,
      );
      expect(
        container.read(uiLayoutProvider).asData!.value.wide.mainLimit,
        isNull,
      );
      await tester.tap(find.text('返回编辑'));
      await tester.pumpAndSettle();
      expect(find.text('查看变更（2）'), findsOneWidget);
    },
  );

  testWidgets(
    'editor search keeps group ordering safe and hides technical IDs by default',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pageContextValidityProvider.overrideWith(legacyPageContextValidity),
            databaseProvider.overrideWith((ref) async => database),
          ],
          child: MaterialApp(
            home: UiLayoutPage(
              registry: registry,
              initialPageId: 'test.host.page',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('layout-search'));
      expect(find.textContaining('公开页签 · 第 1 项'), findsOneWidget);
      expect(find.textContaining('公开页签 · 第 2 项'), findsOneWidget);
      await tester.ensureVisible(search);
      await tester.enterText(search, 'test.child.second');
      await tester.pumpAndSettle();
      expect(find.text('第一页'), findsNothing);
      expect(find.text('第二页'), findsOneWidget);
      expect(find.textContaining('公开页签 · 第 2 项'), findsOneWidget);
      expect(find.textContaining('模块：test.child'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('layout-row-test.child.second.entry')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('layout-inspector')), findsOneWidget);
      for (final arrow in tester.widgetList<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              (widget.tooltip == '上移' || widget.tooltip == '下移'),
        ),
      )) {
        expect(arrow.onPressed, isNull);
      }
      Navigator.of(
        tester.element(find.byKey(const ValueKey('layout-inspector'))),
      ).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('显示技术标识'));
      await tester.tap(find.text('显示技术标识'));
      await tester.pumpAndSettle();
      expect(find.textContaining('模块：test.child'), findsOneWidget);
      await tester.ensureVisible(search);
      await tester.enterText(search, '不存在的入口');
      await tester.pumpAndSettle();
      expect(find.text('当前范围没有符合条件的入口或内容。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'runtime failure opens the matching wide profile, host and entry',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry(public: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pageContextValidityProvider.overrideWith(legacyPageContextValidity),
            databaseProvider.overrideWith((ref) async => database),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: UiPageHost(registry: registry, pageId: 'test.host.page'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('处理挂载'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        'test.host.page',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('layout-search')))
            .controller!
            .text,
        'test.child.first.entry',
      );
      expect(find.text('第一页'), findsOneWidget);
      expect(find.text('第二页'), findsNothing);
    },
  );

  testWidgets('preview supports narrow screens and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final registry = _registry(capacity: 1);
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UiLayoutPreview(
          registry: registry.ui,
          profile: UiLayoutProfile(),
          desktop: false,
          pageId: 'test.host.page',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('槽位容量不足'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('返回编辑'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring one entry only changes the draft until saved', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final registry = _registry();
    final container = ProviderContainer(
      overrides: [
        pageContextValidityProvider.overrideWith(legacyPageContextValidity),
        databaseProvider.overrideWith((ref) async => database),
      ],
    );
    await container.read(uiLayoutProvider.future);
    await container
        .read(uiLayoutProvider.notifier)
        .save(
          UiLayout(
            narrow: UiLayoutProfile(
              mounts: {
                'test.host.entry': const UiMount(placement: UiPlacement.header),
              },
            ),
          ),
        );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      container.dispose();
      registry.dispose();
      await database.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: UiLayoutPage(registry: registry)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('右上角菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('layout-row-test.host.entry')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('恢复此项默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复此项默认'));
    await tester.pumpAndSettle();
    expect(find.text('查看变更（1）'), findsOneWidget);
    expect(find.text('恢复此项默认'), findsNothing);
    expect(
      container
          .read(uiLayoutProvider)
          .asData!
          .value
          .narrow
          .mounts['test.host.entry']!
          .placement,
      UiPlacement.header,
    );
    Navigator.of(tester.element(find.byKey(const ValueKey('layout-inspector'))))
        .pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看变更（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看变更（1）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('模块默认'), findsOneWidget);
    expect(find.textContaining('上下文配置有变化'), findsNothing);
  });
  test('layout round trips independent profiles and dormant mounts', () {
    final value = UiLayout(
      narrow: UiLayoutProfile(
        mainLimit: 2,
        mounts: {'missing.entry': const UiMount(placement: UiPlacement.hidden)},
      ),
      wide: UiLayoutProfile(mainLimit: 7),
    );
    final restored = UiLayout.fromJson(value.toJson());
    expect(restored.narrow.mainLimit, 2);
    expect(restored.wide.mainLimit, 7);
    expect(
      restored.narrow.mounts['missing.entry']!.placement,
      UiPlacement.hidden,
    );
    expect(
      () => UiLayoutProfile.fromJson({'mainLimit': 0, 'mounts': {}}),
      throwsFormatException,
    );
  });

  test('navigation cap excludes More and respects physical capacity', () {
    expect(
      navigationVisibleCount(
        total: 8,
        limit: 2,
        width: 390,
        textScale: 1,
        desktop: false,
      ),
      2,
    );
    expect(
      navigationVisibleCount(
        total: 8,
        limit: 8,
        width: 296,
        textScale: 1.5,
        desktop: false,
      ),
      2,
    );
    expect(
      navigationVisibleCount(
        total: 8,
        limit: 3,
        width: 1000,
        textScale: 1,
        desktop: true,
      ),
      3,
    );
    expect(
      navigationVisibleCount(
        total: 8,
        limit: null,
        width: 1000,
        textScale: 1,
        desktop: true,
      ),
      8,
    );
    expect(
      navigationVisibleCount(
        total: 0,
        limit: 4,
        width: 320,
        textScale: 1,
        desktop: false,
      ),
      0,
    );
  });

  test('public slots accept compatible contributions, private ones do not', () {
    final publicRegistry = _registry();
    final privateRegistry = _registry(public: false);
    addTearDown(publicRegistry.dispose);
    addTearDown(privateRegistry.dispose);
    final entry = publicRegistry.ui.entries.last;
    expect(mountProblem(publicRegistry.ui, entry, entry.defaultMount), isNull);
    expect(
      mountProblem(privateRegistry.ui, entry, entry.defaultMount),
      contains('未公开'),
    );
    expect(
      mountProblem(publicRegistry.ui, entry, const UiMount()),
      contains('只能'),
    );
    expect(
      mountProblem(
        publicRegistry.ui,
        entry,
        const UiMount(
          placement: UiPlacement.page,
          pageId: 'missing.page',
          slotId: 'tabs',
        ),
      ),
      contains('宿主'),
    );
  });

  test(
    'checks deep finite graphs without a fixed depth limit and detects cycles',
    () {
      final registrations = <UiRegistration>[];
      for (var index = 0; index < 150; index++) {
        registrations.add(
          UiPageRegistration(
            id: 'test.deep.page$index',
            moduleId: 'test.deep',
            title: '$index',
            container: true,
            builder: (_, _) => const SizedBox.shrink(),
            slots: const [
              PageSlotDefinition(
                id: 'body',
                label: '内容',
                kind: PageSlotKind.sections,
              ),
            ],
          ),
        );
        if (index > 0) {
          registrations.add(
            UiEntryRegistration(
              id: 'test.deep.entry$index',
              moduleId: 'test.deep',
              pageId: 'test.deep.page$index',
              label: '$index',
              icon: Icons.pages,
              content: true,
              defaultMount: UiMount(
                placement: UiPlacement.page,
                pageId: 'test.deep.page${index - 1}',
                slotId: 'body',
              ),
            ),
          );
        }
      }
      final registry = ModuleRegistry([
        _Module('test.deep', registrations),
      ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
      addTearDown(registry.dispose);
      expect(
        compositionWarnings(registry.ui, (entry) => entry.defaultMount).join(),
        contains('没有深度硬上限'),
      );
      expect(registry.ui.pages, hasLength(150));
      final overrides = UiLayoutProfile(
        mounts: {
          'test.deep.entry1': const UiMount(
            placement: UiPlacement.page,
            pageId: 'test.deep.page1',
            slotId: 'body',
          ),
        },
      );
      expect(
        compositionWarnings(registry.ui, overrides.mountFor).join(),
        contains('循环'),
      );
    },
  );

  test('storage persists profiles, recovers damaged data and publishes only successful saves', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        pageContextValidityProvider.overrideWith(legacyPageContextValidity),
        databaseProvider.overrideWith((ref) async => database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    await container.read(uiLayoutProvider.future);
    await container
        .read(uiLayoutProvider.notifier)
        .save(
          UiLayout(
            narrow: UiLayoutProfile(mainLimit: 1),
            wide: UiLayoutProfile(mainLimit: 3),
          ),
        );
    container.invalidate(uiLayoutProvider);
    expect((await container.read(uiLayoutProvider.future)).wide.mainLimit, 3);
    await database.customStatement(
      "UPDATE app_settings SET value = 'not-json' WHERE key = 'ui.layout'",
    );
    container.invalidate(uiLayoutProvider);
    final recovered = await container.read(uiLayoutProvider.future);
    expect(recovered.warning, isNotNull);
    expect(recovered.narrow.mainLimit, 4);
    await database.customStatement(
      'CREATE TRIGGER reject_layout BEFORE INSERT ON app_settings BEGIN SELECT RAISE(FAIL, \'test failure\'); END',
    );
    await expectLater(
      container
          .read(uiLayoutProvider.notifier)
          .save(UiLayout(narrow: UiLayoutProfile(mainLimit: 9))),
      throwsA(isA<Exception>()),
    );
    expect(container.read(uiLayoutProvider).asData!.value.narrow.mainLimit, 4);
  });

  for (final retain in [false, true]) {
    testWidgets('local tabs restore only when declared: $retain', (
      tester,
    ) async {
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry(retain: retain);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        registry.dispose();
        await database.close();
      });
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pageContextValidityProvider.overrideWith(legacyPageContextValidity),
            databaseProvider.overrideWith((ref) async => database),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, show, _) => show
                    ? UiPageHost(registry: registry, pageId: 'test.host.page')
                    : const Text('离开页面'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '第二页'));
      await tester.pumpAndSettle();
      expect(find.text('第二个内容'), findsOneWidget);
      visible.value = false;
      await tester.pumpAndSettle();
      visible.value = true;
      await tester.pumpAndSettle();
      expect(find.text(retain ? '第二个内容' : '第一个内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'private and missing-context contributions keep invalid configuration',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final registry = _registry(public: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pageContextValidityProvider.overrideWith(legacyPageContextValidity),
            databaseProvider.overrideWith((ref) async => database),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: UiPageHost(registry: registry, pageId: 'test.host.page'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('未公开'), findsOneWidget);
      await tester.tap(find.text('暂时保留'));
      await tester.pumpAndSettle();
      expect(registry.ui.entries.last.defaultMount.placement, UiPlacement.page);
      expect(find.text('第一个内容'), findsNothing);
    },
  );

  testWidgets('editor switches profiles without applying drafts until saved', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final registry = _registry();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      registry.dispose();
      await database.close();
    });
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return UiLayoutPage(registry: registry);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openAdvancedEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('navigation-limit-false')),
      '2',
    );
    await tester.tap(find.text('电脑 / 宽屏'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('navigation-limit-true')),
      '3',
    );
    expect(container.read(uiLayoutProvider).asData!.value.narrow.mainLimit, 4);
    await tester.tap(find.text('手机 / 窄屏'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('navigation-limit-false')),
          )
          .controller!
          .text,
      '2',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(container.read(uiLayoutProvider).asData!.value.narrow.mainLimit, 2);
    expect(container.read(uiLayoutProvider).asData!.value.wide.mainLimit, 3);
  });

  testWidgets(
    'deleted context blocks rendering and restores after object recovery',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final now = DateTime.now();
      Future<void> restoreProject() => database
          .into(database.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'context-project',
              name: '用户项目',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await restoreProject();
      final registry = ModuleRegistry([
        _Module('test.context', [
          UiPageRegistration(
            id: 'test.context.page',
            moduleId: 'test.context',
            title: '上下文页',
            requiredContext: const ['projectId'],
            builder: (_, _) => const Center(child: Text('有效上下文内容')),
          ),
        ]),
      ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        registry.dispose();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pageContextValidityProvider.overrideWith(legacyPageContextValidity),
            databaseProvider.overrideWith((ref) async => database),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: UiPageHost(
                registry: registry,
                pageId: 'test.context.page',
                pageContext: const PageContext(projectId: 'context-project'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('有效上下文内容'), findsOneWidget);
      await database.delete(database.projects).go();
      await tester.pumpAndSettle();
      expect(find.text('有效上下文内容'), findsNothing);
      expect(find.textContaining('对象不存在'), findsOneWidget);
      await restoreProject();
      await tester.pumpAndSettle();
      expect(find.text('有效上下文内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('cycle isolation stops only the recursive content branch', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final registry = ModuleRegistry([
      _Module('test.cycle', [
        UiPageRegistration(
          id: 'test.cycle.page',
          moduleId: 'test.cycle',
          title: '循环宿主',
          container: true,
          builder: (_, _) => const SizedBox.shrink(),
          slots: const [
            PageSlotDefinition(
              id: 'body',
              label: '内容',
              kind: PageSlotKind.tabs,
            ),
          ],
        ),
        const UiEntryRegistration(
          id: 'test.cycle.loop',
          moduleId: 'test.cycle',
          pageId: 'test.cycle.page',
          label: '循环分支',
          icon: Icons.loop,
          content: true,
          defaultMount: UiMount(
            placement: UiPlacement.page,
            pageId: 'test.cycle.page',
            slotId: 'body',
          ),
        ),
        UiPageRegistration(
          id: 'test.cycle.safe',
          moduleId: 'test.cycle',
          title: '有效分支',
          builder: (_, _) => const Center(child: Text('有效内容未受影响')),
        ),
        const UiEntryRegistration(
          id: 'test.cycle.valid',
          moduleId: 'test.cycle',
          pageId: 'test.cycle.safe',
          label: '有效分支',
          icon: Icons.check,
          content: true,
          defaultMount: UiMount(
            placement: UiPlacement.page,
            pageId: 'test.cycle.page',
            slotId: 'body',
            order: 1,
          ),
        ),
      ]),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      registry.dispose();
      await database.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: UiPageHost(registry: registry, pageId: 'test.cycle.page'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('循环内容嵌套'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '有效分支'));
    await tester.pumpAndSettle();
    expect(find.text('有效内容未受影响'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout editor supports narrow large text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final database = AppDatabase(NativeDatabase.memory());
    final registry = _registry();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      registry.dispose();
      await database.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
        child: MaterialApp(home: UiLayoutPage(registry: registry)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('电脑 / 宽屏'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('single-entry groups disable impossible reorder actions', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final registry = _registry();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      registry.dispose();
      await database.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pageContextValidityProvider.overrideWith(legacyPageContextValidity),
          databaseProvider.overrideWith((ref) async => database),
        ],
        child: MaterialApp(home: UiLayoutPage(registry: registry)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('底部导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test.host.entry')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '上移',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '下移',
            ),
          )
          .onPressed,
      isNull,
    );
  });
}
