import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/modules/module_registry.dart';
import '../core/ui/app_destination.dart';
import '../features/ai/ai_module.dart';
import '../features/declarative_runtime/declarative_runtime_controller.dart';
import '../features/module_manager/builtin_module_controller.dart';
import '../features/module_manager/module_manager_page.dart';
import '../features/tasks/application/providers.dart';
import '../features/tasks/quick_task_input.dart';
import '../features/settings/app_preferences.dart';
import '../features/settings/settings_page.dart';
import 'design_system.dart';
import 'mobile_bottom_dock.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.registry});
  final ModuleRegistry registry;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int index = 0;
  bool aiOpen = false;
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
      final destinations = widget.registry.ui.primaryDestinations;
      final retained = destinations.indexWhere(
        (item) => item.id == selectedDestinationId,
      );
      index = retained >= 0 ? retained : 0;
      if (!widget.registry.isEnabled('app.ai')) aiOpen = false;
    });
  }

  @override
  void dispose() {
    widget.registry.removeListener(_onRegistryChanged);
    quickController.dispose();
    super.dispose();
  }

  void _openAi(bool sidePanel) {
    if (!widget.registry.isEnabled('app.ai')) return;
    if (sidePanel) {
      setState(() => aiOpen = !aiOpen);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: AiWorkspacePanel(registry: widget.registry),
      ),
    );
  }

  void _openSettings() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(registry: widget.registry),
      ),
    );
  }

  void _navigationFeedback() {
    final preferences = ref.read(appPreferencesProvider).asData?.value;
    if (preferences?.haptics ?? true) HapticFeedback.selectionClick();
  }

  void _showMore(List<AppDestination> destinations) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('切换模块', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (var i = 4; i < destinations.length; i++)
              ListTile(
                shape: AppDesign.smoothShape(),
                leading: Icon(destinations[i].icon),
                title: Text(destinations[i].label),
                selected: i == index,
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => index = i);
                },
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
    final destinations = widget.registry.ui.primaryDestinations;
    if (destinations.isEmpty) {
      return const Scaffold(body: Center(child: Text('没有可用模块')));
    }
    if (index >= destinations.length) index = 0;

    final current = destinations[index];
    selectedDestinationId = current.id;
    final aiEnabled = widget.registry.isEnabled('app.ai');
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 820;
    final showPanel = desktop && aiOpen && width >= 1100;
    final showNavigation = MediaQuery.viewInsetsOf(context).bottom == 0;
    final showDock = showNavigation || current.quickAdd;
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
            if (desktop) _sidebar(destinations),
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
                        if (aiEnabled)
                          IconButton(
                            tooltip: '打开 AI 助手',
                            onPressed: () => _openAi(desktop && width >= 1100),
                            icon: const Icon(Icons.auto_awesome_outlined),
                          ),
                        if (!desktop)
                          IconButton(
                            tooltip: '打开设置',
                            onPressed: _openSettings,
                            icon: const Icon(Icons.settings_outlined),
                          ),
                      ],
                    ),
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
                              WorkspaceContentInsets(
                                bottom: dockInset,
                                child: current.builder(context),
                              ),
                              if (showDock)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: MobileBottomDock(
                                    destinations: destinations,
                                    selectedIndex: index,
                                    showNavigation: showNavigation,
                                    onSelected: (value) {
                                      if (value >= 4) {
                                        _navigationFeedback();
                                        _showMore(destinations);
                                      } else if (value != index) {
                                        _navigationFeedback();
                                        setState(() => index = value);
                                      }
                                    },
                                    input: current.quickAdd
                                        ? _quickInputContent(current.label)
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
                        child: _quickInputContent(current.label),
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
                    child: AiWorkspacePanel(registry: widget.registry),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(List<AppDestination> destinations) {
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
                itemCount: destinations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, i) => _sidebarDestination(destinations[i], i),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ListTile(
                shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
                leading: const Icon(Icons.settings_outlined, size: 21),
                title: const Text('设置'),
                onTap: _openSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarDestination(AppDestination destination, int i) {
    final selected = i == index;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: AppDesign.smoothShape(radius: AppDesign.controlRadius),
        hoverColor: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
        onTap: () => setState(() => index = i),
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
              Text(
                destination.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickInputContent(String pageLabel) {
    final destination = widget.registry.ui.primaryDestinations[index];
    return QuickTaskInput(
      controller: quickController,
      hintText: '添加到$pageLabel…',
      defaults: destination.quickAddDefaults,
    );
  }
}
