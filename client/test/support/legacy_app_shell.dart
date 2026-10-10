// Frozen v2 regression fixture. Never imported by production.
import 'package:task_app/features/ai/assistant_runtime.dart';
import 'package:task_app/features/declarative_runtime/declarative_runtime_controller.dart';
import 'package:task_app/features/module_manager/builtin_module_controller.dart';
import 'package:task_app/features/module_manager/module_manager_page.dart';
import 'package:task_app/features/tasks/application/providers.dart';
import 'package:task_app/features/tasks/quick_task_input.dart';
import 'package:task_app/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/ui/app_destination.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_layout_resolver.dart';
import 'package:task_app/core/ui/ui_page_host.dart';
import 'package:task_app/core/ui/ui_annotation.dart';
import 'package:task_app/features/settings/ui_layout.dart';
import 'package:task_app/features/settings/ui_layout_page.dart';
import 'package:task_app/features/settings/app_preferences.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.registry});
  final ModuleRegistry registry;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int index = 0;
  UiEntryRegistration? panelEntry;
  PageContext? panelContext;
  bool restoring = true;
  String? restoreError;
  List<ModuleRestoreFailure> restoreFailures = const [];
  String? selectedDestinationId;
  final quickController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_onRegistryChanged);
    _restoreInstalledModules();
  }

  Future<void> _restoreInstalledModules() async {
    try {
      await (await ref.read(
        builtinModuleControllerProvider(widget.registry).future,
      )).restore();
      if (!mounted) return;
      final store = await ref.read(declarativeModuleStoreProvider.future);
      final runtime = DeclarativeRuntimeController(
        store: store,
        registry: widget.registry,
        ruleEngine: await ref.read(ruleEngineProvider.future),
        templateEngine: await ref.read(templateEngineProvider.future),
      );
      final failures = await runtime.restoreEnabled();
      if (mounted) {
        setState(() {
          restoring = false;
          restoreError = null;
          restoreFailures = failures;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          restoring = false;
          restoreError = '恢复模块状态失败';
        });
      }
    }
  }

  void _showRestoreFailures() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('模块恢复详情'),
        content: SingleChildScrollView(
          child: Text(
            restoreFailures
                .map((failure) => '${failure.moduleId}\n${failure.reason}')
                .join('\n\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('模块管理')),
                    body: ModuleManagerPage(registry: widget.registry),
                  ),
                ),
              );
            },
            child: const Text('管理模块'),
          ),
        ],
      ),
    );
  }

  void _onRegistryChanged() {
    if (!mounted) return;
    setState(() {
      final destinations = widget.registry.ui.entries;
      final retained = destinations.indexWhere(
        (item) => item.id == selectedDestinationId,
      );
      index = retained >= 0 ? retained : 0;
      if (panelEntry != null &&
          !destinations.any((entry) => entry.id == panelEntry!.id)) {
        panelEntry = null;
      }
    });
  }

  @override
  void dispose() {
    widget.registry.removeListener(_onRegistryChanged);
    quickController.dispose();
    super.dispose();
  }

  UiLayoutProfile get _profile =>
      (ref.read(uiLayoutProvider).asData?.value ?? UiLayout()).profile(
        MediaQuery.sizeOf(context).width >= 820,
      );

  void _openEntry(UiEntryRegistration entry, {PageContext? pageContext}) {
    if (entry.id == 'app.ai.entry') {
      ref.read(assistantControllerProvider(widget.registry)).open();
      return;
    }
    final mount = _profile.mountFor(entry);
    final problem = mountProblem(
      widget.registry.ui,
      entry,
      mount,
      context: pageContext ?? const PageContext(),
    );
    if (problem != null) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('入口失效'),
          content: Text(problem),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('暂时保留'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UiLayoutPage(registry: widget.registry),
                  ),
                );
              },
              child: const Text('处理挂载'),
            ),
          ],
        ),
      );
      return;
    }
    _navigationFeedback();
    if (entry.opening == UiOpening.workspace) {
      setState(() => selectedDestinationId = entry.id);
    } else if (entry.opening == UiOpening.adaptivePanel &&
        MediaQuery.sizeOf(context).width >= 1100) {
      setState(() {
        panelEntry = panelEntry?.id == entry.id ? null : entry;
        panelContext = pageContext;
      });
    } else if (entry.opening == UiOpening.adaptivePanel) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.88,
          child: _page(entry, pageContext: pageContext),
        ),
      );
    } else {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DetailPage(
            title: entry.label,
            child: _page(entry, pageContext: pageContext),
          ),
        ),
      );
    }
  }

  Widget _page(UiEntryRegistration entry, {PageContext? pageContext}) =>
      UiEntryActivationScope(
        open: (entry, context) => _openEntry(entry, pageContext: context),
        child: UiPageHost(
          key: ValueKey(entry.id),
          registry: widget.registry,
          pageId: entry.pageId,
          pageContext: pageContext ?? _profile.mountFor(entry).context,
          mountPath: [entry.id],
        ),
      );

  AppDestination _destination(UiEntryRegistration entry) {
    final page = widget.registry.ui.page(entry.pageId);
    return AppDestination(
      id: entry.id,
      label: entry.label,
      icon: entry.icon,
      selectedIcon: entry.selectedIcon ?? entry.icon,
      builder: (_) => _page(entry),
      quickAdd: page?.quickAdd ?? false,
      quickAddDefaults: page?.quickAddDefaults ?? const {},
    );
  }

  void _openSettings() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          registry: widget.registry,
          onOpenEntry: (entry) {
            Navigator.pop(context);
            _openEntry(entry);
          },
        ),
      ),
    );
  }

  void _navigationFeedback() {
    final preferences = ref.read(appPreferencesProvider).asData?.value;
    if (preferences?.haptics ?? true) HapticFeedback.selectionClick();
  }

  void _showMore(List<UiEntryRegistration> entries) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('更多入口', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final entry in entries)
                      ListTile(
                        shape: AppDesign.smoothShape(),
                        leading: Icon(entry.icon),
                        title: Text(entry.label),
                        selected: entry.id == selectedDestinationId,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _openEntry(entry);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (restoreError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(restoreError!),
              TextButton(
                onPressed: () {
                  setState(() => restoring = true);
                  _restoreInstalledModules();
                },
                child: const Text('重试'),
              ),
              TextButton(onPressed: _openSettings, child: const Text('打开设置')),
            ],
          ),
        ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 820;
    final layout = ref.watch(uiLayoutProvider).asData?.value;
    final profile = (layout ?? UiLayout()).profile(desktop);
    final entries = widget.registry.ui.entries;
    final workspace = entries
        .where(
          (entry) => entry.opening == UiOpening.workspace && !entry.content,
        )
        .toList();
    if (workspace.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('没有可用工作区'),
              TextButton(
                onPressed: _openSettings,
                child: const Text('打开设置并恢复模块'),
              ),
            ],
          ),
        ),
      );
    }
    final selected = workspace.where(
      (entry) => entry.id == selectedDestinationId,
    );
    final activeEntry = selected.isEmpty ? workspace.first : selected.first;
    selectedDestinationId = activeEntry.id;
    final current = _destination(activeEntry);
    List<UiEntryRegistration> at(UiPlacement placement) => orderedEntries(
      widget.registry.ui,
      profile.mountFor,
      (entry) => profile.mountFor(entry).placement == placement,
    );
    final main = at(UiPlacement.main);
    final header = at(UiPlacement.header);
    final mainCount = navigationVisibleCount(
      total: main.length,
      limit: profile.mainLimit,
      width: width - 24,
      textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
      desktop: desktop,
    );
    final headerLimit = headerVisibleCount(width: width, desktop: desktop);
    final visibleHeader = header.take(headerLimit).toList();
    final more = [
      ...at(UiPlacement.more),
      ...main.skip(mainCount),
      ...header.skip(headerLimit),
    ];
    final visibleMain = main.take(mainCount).toList();
    final destinations = visibleMain.map(_destination).toList();
    index = visibleMain.indexWhere((entry) => entry.id == activeEntry.id);
    final moreSelected = more.any((entry) => entry.id == activeEntry.id);
    final showPanel = desktop && panelEntry != null && width >= 1100;
    final showNavigation = MediaQuery.viewInsetsOf(context).bottom == 0;
    final showDock =
        (showNavigation && (visibleMain.isNotEmpty || more.isNotEmpty)) ||
        current.quickAdd;
    final dockInset = !desktop && showDock
        ? MobileBottomDock.height(
                context,
                hasInput: current.quickAdd,
                showNavigation: showNavigation,
              ) +
              24
        : 0.0;
    return Scaffold(
      backgroundColor: AppDesign.canvas(context),
      body: SafeArea(
        child: Row(
          children: [
            if (desktop)
              _sidebar(destinations, visibleMain, more, moreSelected),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            current.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final entry in visibleHeader)
                          UiAnnotation(
                            id: entry.id,
                            name: entry.label,
                            moduleId: entry.moduleId,
                            slot: 'header',
                            purpose: '打开功能入口',
                            child: IconButton(
                              tooltip: entry.id == 'app.ai.entry'
                                  ? '打开 AI 助手'
                                  : '打开${entry.label}',
                              onPressed: () => _openEntry(entry),
                              icon: Icon(entry.icon),
                            ),
                          ),
                        if (!desktop)
                          UiAnnotation(
                            id: 'app.shell.settings',
                            name: '设置',
                            purpose: '受保护的设置与恢复入口',
                            child: IconButton(
                              tooltip: '打开设置',
                              onPressed: _openSettings,
                              icon: const Icon(Icons.settings_outlined),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (layout?.warning != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(layout!.warning!),
                    ),
                  if (ref.watch(uiLayoutProvider).hasError)
                    TextButton(
                      onPressed: () => ref.invalidate(uiLayoutProvider),
                      child: const Text('布局读取失败，暂用默认布局，点击重试'),
                    ),
                  if (restoreFailures.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${restoreFailures.length} 个扩展模块恢复失败，已停用，数据保留',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: _showRestoreFailures,
                            child: const Text('查看详情'),
                          ),
                          IconButton(
                            tooltip: '关闭恢复提示',
                            onPressed: () =>
                                setState(() => restoreFailures = const []),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: desktop
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1040),
                              child: current.builder(context),
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              RepaintBoundary(
                                child: WorkspaceContentInsets(
                                  bottom: dockInset,
                                  child: current.builder(context),
                                ),
                              ),
                              if (showDock)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: MobileBottomDock(
                                    destinations: destinations,
                                    selectedIndex: index,
                                    visibleCount: destinations.length,
                                    hasMore: more.isNotEmpty,
                                    moreSelected: moreSelected,
                                    annotate: true,
                                    entryModuleIds: {
                                      for (final entry in visibleMain)
                                        entry.id: entry.moduleId,
                                    },
                                    showNavigation: showNavigation,
                                    onSelected: (value) {
                                      if (value >= visibleMain.length) {
                                        _navigationFeedback();
                                        _showMore(more);
                                      } else {
                                        _openEntry(visibleMain[value]);
                                      }
                                    },
                                    input: current.quickAdd
                                        ? _quickInputContent(current)
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (desktop && current.quickAdd)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 20 : 12,
                        4,
                        desktop ? 20 : 12,
                        desktop ? 18 : 8,
                      ),
                      child: FloatingSurface(
                        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                        child: _quickInputContent(current),
                      ),
                    ),
                ],
              ),
            ),
            if (showPanel)
              SizedBox(
                width: 370,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 16, 16),
                  child: FloatingSurface(
                    padding: EdgeInsets.zero,
                    child: _page(panelEntry!, pageContext: panelContext),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(
    List<AppDestination> destinations,
    List<UiEntryRegistration> entries,
    List<UiEntryRegistration> more,
    bool moreSelected,
  ) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 216,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 28),
              child: Row(
                children: [
                  Icon(
                    Icons.grid_view_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '序点',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 0, 8),
              child: Text(
                '工作台',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppDesign.muted(context),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: destinations.length + (more.isEmpty ? 0 : 1),
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, i) => i < destinations.length
                    ? _sidebarDestination(destinations[i], i, entries[i])
                    : ListTile(
                        leading: const Icon(Icons.more_horiz),
                        title: const Text('更多'),
                        selected: moreSelected,
                        onTap: () => _showMore(more),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: UiAnnotation(
                id: 'app.shell.settings',
                name: '设置',
                purpose: '受保护的设置与恢复入口',
                child: ListTile(
                  shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
                  leading: const Icon(Icons.settings_outlined, size: 21),
                  title: const Text('设置'),
                  onTap: _openSettings,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarDestination(
    AppDestination destination,
    int i,
    UiEntryRegistration entry,
  ) {
    final selected = i == index;
    final scheme = Theme.of(context).colorScheme;
    return UiAnnotation(
      id: entry.id,
      name: entry.label,
      moduleId: entry.moduleId,
      slot: 'main',
      purpose: '主导航入口',
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : Colors.transparent,
        shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: AppDesign.smoothShape(radius: AppDesign.controlRadius),
          hoverColor: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
          onTap: () => _openEntry(entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  destination.icon,
                  size: 21,
                  color: selected ? scheme.primary : AppDesign.muted(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickInputContent(AppDestination destination) {
    return UiAnnotation(
      id: 'app.shell.quick_input',
      name: '快速输入',
      pagePath: destination.id,
      slot: 'input',
      purpose: '创建当前主工作区对应的任务',
      child: QuickTaskInput(
        controller: quickController,
        hintText: '添加到${destination.label}…',
        defaults: destination.quickAddDefaults,
      ),
    );
  }
}
