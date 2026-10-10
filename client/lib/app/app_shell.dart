import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../core/module_host/module_host.dart';
import '../core/module_host/module_package.dart';
import '../core/module_host/host_providers.dart';
import '../core/module_host/script_app_module.dart';
import '../core/module_host/host_network.dart';
import '../core/module_host/host_browser.dart';
import '../core/module_host/host_dialogs.dart';
import '../core/module_host/host_manager_page.dart';
import '../core/module_host/host_settings_page.dart';
import '../core/module_host/host_control_services.dart';
import '../core/module_host/collection_store.dart';
import '../core/ui/ui_slot.dart';
import '../core/ui/ui_registration.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/modules/module_registry.dart';
import '../core/ui/app_destination.dart';
import '../core/ui/ui_composition.dart';
import '../core/ui/ui_layout_resolver.dart';
import '../core/ui/ui_page_host.dart';
import '../core/ui/ui_annotation.dart';
import '../core/ui/ui_component.dart';
import '../core/ui/ui_pack_settings_page.dart';
import '../core/ui/workspace_header.dart';
import '../core/ui/module_detail_page.dart';
import '../core/ui/workspace_chrome.dart';
import '../features/settings/ui_layout.dart';
import '../features/settings/ui_layout_page.dart';
import '../features/settings/app_preferences.dart';
import 'design_system.dart';
import 'mobile_bottom_dock.dart';
import 'frosted_toolbar_surface.dart';

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
  Map<String, String> restoreFailures = {};
  ModuleHost? host;
  HostNetwork? network;
  final browser = HostBrowser();
  StreamSubscription<void>? hostSubscription;
  StreamSubscription<Set<String>>? dataSubscription;
  String? selectedDestinationId;
  final workspaceHeader = WorkspaceHeaderController();
  final workspaceChrome = WorkspaceChromeController();
  double? _measuredDockHeight;

  void _dockSizeChanged(Size size) {
    if (!mounted || _measuredDockHeight == size.height) return;
    setState(() => _measuredDockHeight = size.height);
  }

  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_onRegistryChanged);
    workspaceHeader.addListener(_headerChanged);
    workspaceChrome.addListener(_headerChanged);
    _restoreInstalledModules();
  }

  Future<void> _restoreInstalledModules() async {
    try {
      host = await ref.read(moduleHostProvider.future);
      if (!mounted) return;
      network ??= HostNetwork(host!.store);
      host!.interaction = _hostInteraction;
      host!.onDeactivate = (actor) {
        network!.revoke(actor);
        unawaited(browser.revoke(actor));
      };
      host!.onDeleteData = network!.deleteModuleCredentials;
      registerHostControlServices(
        host!,
        widget.registry,
        hasDirtyLayout: () =>
            ref.read(uiLayoutEditorSessionsProvider).hasDirtyEditors,
      );
      dataSubscription ??= host!.store.changes.stream.listen((ids) {
        if (mounted && ids.contains('app.host')) {
          ref.invalidate(appPreferencesProvider);
          ref.invalidate(uiLayoutProvider);
        }
      });
      hostSubscription ??= host!.registryChanges.stream.listen(
        (_) => _syncHost(),
      );
      _syncHost();
      setState(() {
        restoring = false;
        restoreError = null;
        restoreFailures = Map.of(host!.failures);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          restoring = false;
          restoreError = '恢复模块状态失败：$error';
        });
      }
    }
  }

  void _syncHost() {
    if (!mounted || host == null) return;
    widget.registry.replaceExtensions([
      for (final instance in host!.instances.values)
        ScriptAppModule(host!, instance.package),
    ]);
    network?.revokeInactive();
  }

  Future<Object?> _hostInteraction(
    ModuleActor caller,
    String method,
    Map<String, Object?> args,
  ) async {
    if (!mounted) throw StateError('Host interaction unavailable');
    switch (method) {
      case 'ui.review':
        return reviewDialog(context, '确认实际数据变更', args);
      case 'packages.review':
        return reviewDialog(context, '审核模块文件、数据、界面和权限', args);
      case 'grants.request':
        return reviewDialog(context, '授权模块调用（30分钟，最多20次写入）', args);
      case 'ui.dialog':
        return showDialog<Map<String, Object?>>(
          context: context,
          builder: (_) => UiPackScope(
            moduleId: caller.moduleId,
            child: HostFormDialog(
              title: args['title'] as String? ?? '模块输入',
              fields: [
                for (final f in args['fields'] as List? ?? []) object(f),
              ],
            ),
          ),
        );
      case 'secrets.configure':
        final endpoint = network!.validateEndpoint(args['endpoint']);
        final values = await showDialog<Map<String, Object?>>(
          context: context,
          builder: (_) => UiPackScope(
            defaultOnly: true,
            child: HostFormDialog(
              title: '安全凭据 · ${caller.moduleId}',
              fields: [
                {
                  'key': 'key',
                  'label': '${args['label'] ?? '密钥'}（绑定 $endpoint）',
                  'type': 'secret',
                },
              ],
            ),
          ),
        );
        host!.store.requireActive(caller);
        if (values == null) return null;
        return network!.configure(
          caller,
          endpoint.toString(),
          values['key'] as String,
        );
      case 'secrets.delete':
        await network!.delete(caller, args['handle'] as String);
        return null;
      case 'http.request':
        return network!.request(caller, args);
      case 'http.cancel':
        network!.cancel(caller, args['id'] as String);
        return null;
      case 'files.readText':
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(label: 'JSON 文件', extensions: ['json']),
          ],
        );
        if (file == null) return null;
        final bytes = await file.readAsBytes();
        if (bytes.length > 2 * 1024 * 1024) throw StateError('文件超过2 MiB');
        return utf8.decode(bytes);
      case 'browser.capture':
        return browser.capture(caller, args);
      case 'files.saveText':
        if (utf8.encode(args['text'] as String).length > 2 * 1024 * 1024) {
          throw StateError('文件超过2 MiB');
        }
        if (Platform.isAndroid) {
          return await const MethodChannel('xudian.host/files')
                  .invokeMethod<bool>('saveText', {
                    'name': args['name'],
                    'text': args['text'],
                  }) ??
              false;
        }
        final location = await getSaveLocation(
          suggestedName: args['name'] as String,
        );
        if (location == null) return false;
        await XFile.fromData(
          Uint8List.fromList(utf8.encode(args['text'] as String)),
          mimeType: 'application/json',
        ).saveTo(location.path);
        return true;
      case 'ui.navigate':
      case 'ui.panel':
        final pageId = args['page'] as String;
        if (pageId == 'app.host.settings') {
          _openSettings();
          return true;
        }
        if (pageId == 'app.host.layout') {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => UiLayoutPage(registry: widget.registry),
              ),
            ),
          );
          return true;
        }
        final page = widget.registry.ui.page(pageId);
        if (page == null) throw StateError('Page unavailable');
        final values = object(args['context'] ?? {});
        final child = UiPackScope(
          moduleId: page.moduleId,
          child: UiPageHost(
            registry: widget.registry,
            pageId: pageId,
            pageContext: PageContext(values: values),
          ),
        );
        if (method == 'ui.panel') {
          final adaptive =
              object(args['presentation'] ?? {})['adaptive'] == true;
          if (adaptive && MediaQuery.sizeOf(context).width >= 820) {
            unawaited(
              showGeneralDialog<void>(
                context: context,
                barrierDismissible: true,
                barrierLabel: '关闭面板',
                pageBuilder: (panelContext, _, _) => SafeArea(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 480,
                      child: Material(
                        elevation: 16,
                        color: Theme.of(context).colorScheme.surface,
                        child: Column(
                          children: [
                            AppBar(
                              automaticallyImplyLeading: false,
                              title: Text(page.title),
                              actions: [
                                IconButton(
                                  tooltip: '关闭面板',
                                  onPressed: () => Navigator.pop(panelContext),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            Expanded(child: child),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          } else {
            unawaited(
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: adaptive,
                builder: (_) =>
                    FractionallySizedBox(heightFactor: .9, child: child),
              ),
            );
          }
        } else {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => UiPackScope(
                  moduleId: page.moduleId,
                  child: ModuleDetailPage(
                    registry: widget.registry,
                    pageId: pageId,
                    pageContext: PageContext(values: values),
                    title: page.title,
                    child: child,
                  ),
                ),
              ),
            ),
          );
        }
        return true;
      default:
        throw StateError('Unsupported host capability: $method');
    }
  }

  void _showRestoreFailures() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('模块恢复详情'),
        content: SingleChildScrollView(
          child: Text(
            restoreFailures.entries
                .map((failure) => '${failure.key}\n${failure.value}')
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
                    body: const HostManagerPage(),
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

  void _headerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.registry.removeListener(_onRegistryChanged);
    workspaceHeader.removeListener(_headerChanged);
    workspaceHeader.dispose();
    workspaceChrome.removeListener(_headerChanged);
    workspaceChrome.dispose();
    hostSubscription?.cancel();
    dataSubscription?.cancel();
    if (host?.interaction == _hostInteraction) host?.interaction = null;
    network?.close();
    unawaited(browser.close());
    super.dispose();
  }

  UiLayoutProfile get _profile =>
      (ref.read(uiLayoutProvider).asData?.value ?? UiLayout()).profile(
        MediaQuery.sizeOf(context).width >= 820,
      );

  void _openEntry(UiEntryRegistration entry, {PageContext? pageContext}) {
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
          builder: (_) => UiPackScope(
            moduleId: entry.moduleId,
            child: ModuleDetailPage(
              registry: widget.registry,
              pageId: entry.pageId,
              pageContext: pageContext ?? _profile.mountFor(entry).context,
              title: entry.label,
              child: _page(entry, pageContext: pageContext),
            ),
          ),
        ),
      );
    }
  }

  Widget _page(UiEntryRegistration entry, {PageContext? pageContext}) =>
      UiPackScope(
        moduleId: entry.moduleId,
        child: UiEntryActivationScope(
          open: (entry, context) => _openEntry(entry, pageContext: context),
          child: UiPageHost(
            key: ValueKey(entry.id),
            registry: widget.registry,
            pageId: entry.pageId,
            pageContext: pageContext ?? _profile.mountFor(entry).context,
            mountPath: [entry.id],
          ),
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

  Widget _chromeWorkspace({required Widget child, required bool collapsed}) =>
      NotificationListener<ScrollNotification>(
        onNotification: workspaceChrome.handleScroll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (collapsed)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (MediaQuery.sizeOf(context).width < 820)
                        _chromeRevealButton()
                      else
                        UiPackScope(
                          defaultOnly: true,
                          child: IconButton(
                            tooltip: '展开工具栏',
                            onPressed: workspaceChrome.reveal,
                            icon: const Icon(Icons.unfold_more),
                          ),
                        ),
                      UiPackScope(
                        defaultOnly: true,
                        child: IconButton(
                          tooltip: '界面风格与恢复',
                          onPressed: _openUiRecovery,
                          icon: const Icon(Icons.palette_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _chromeRevealButton() => Tooltip(
    message: '展开顶栏和导航',
    child: FrostedToolbarSurface(
      radius: 28,
      child: TextButton.icon(
        key: const ValueKey('workspace-chrome-reveal'),
        onPressed: workspaceChrome.reveal,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        icon: const Icon(Icons.unfold_more, size: 20),
        label: const Text('展开工具栏'),
      ),
    ),
  );

  Widget _workspaceHeader(
    String fallbackTitle,
    List<UiEntryRegistration> entries,
  ) {
    final textTheme = Theme.of(context).textTheme;
    var controlHeight = kMinInteractiveDimension;
    for (final (style, padding) in [
      (textTheme.headlineSmall!, 0.0),
      (textTheme.titleMedium!, 16.0),
      (textTheme.labelLarge!, 16.0),
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: '课表 Ag', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final height = (painter.height + padding).ceilToDouble();
      if (height > controlHeight) controlHeight = height;
      painter.dispose();
    }
    final moduleOwnsHeader = workspaceHeader.lease?.isActive() == true;
    final contribution = moduleOwnsHeader ? workspaceHeader.content : null;
    final spec = contribution?.spec;
    final title = spec?['title'] is String
        ? spec!['title'] as String
        : moduleOwnsHeader
        ? ''
        : fallbackTitle;
    final leading = object(spec?['leading'] ?? {});
    final actions = (spec?['actions'] as List? ?? const [])
        .take(12)
        .map(object)
        .toList();
    final leadingWidget = contribution != null && leading['label'] is String
        ? TextButton(
            onPressed: leading['event'] == null
                ? null
                : () => contribution.dispatch(leading['event']),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    leading['label'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          )
        : const SizedBox.shrink();
    final titleContent = spec?['titleEvent'] == null
        ? Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          )
        : TextButton(
            onPressed: () => contribution!.dispatch(spec!['titleEvent']),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          );
    // Every workspace reserves the same title height, including first renders.
    // Large text expands all headers together rather than only button titles.
    final titleWidget = SizedBox(
      height: controlHeight,
      child: Align(
        alignment: moduleOwnsHeader ? Alignment.center : Alignment.centerLeft,
        child: titleContent,
      ),
    );
    Widget menuLabel(String label, IconData icon) => Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
    final menu = UiAnnotation(
      id: 'app.shell.menu',
      name: '页面菜单',
      purpose: '打开页面操作、模块入口及设置',
      child: PopupMenuButton<int>(
        key: const ValueKey('workspace-menu'),
        tooltip: '页面菜单',
        icon: const Icon(Icons.more_vert),
        position: PopupMenuPosition.under,
        shape: AppDesign.smoothShape(radius: 20),
        constraints: const BoxConstraints(minWidth: 224, maxWidth: 320),
        onSelected: (index) {
          if (index == -1) {
            _openSettings();
          } else if (index < actions.length) {
            contribution?.dispatch(actions[index]['event']);
          } else {
            _openEntry(entries[index - actions.length]);
          }
        },
        itemBuilder: (_) => [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem(
              value: i,
              child: Text('${actions[i]['label'] ?? ''}'),
            ),
          if (actions.isNotEmpty && entries.isNotEmpty)
            const PopupMenuDivider(),
          for (var i = 0; i < entries.length; i++)
            PopupMenuItem(
              value: actions.length + i,
              child: UiAnnotation(
                id: entries[i].id,
                name: entries[i].label,
                moduleId: entries[i].moduleId,
                slot: 'header',
                purpose: '打开功能入口',
                child: menuLabel(entries[i].label, entries[i].icon),
              ),
            ),
          if (actions.isNotEmpty || entries.isNotEmpty)
            const PopupMenuDivider(),
          PopupMenuItem(
            value: -1,
            child: UiAnnotation(
              id: 'app.shell.settings',
              name: '设置',
              purpose: '受保护的设置与恢复入口',
              child: menuLabel('设置', Icons.settings_outlined),
            ),
          ),
        ],
      ),
    );
    final fallback = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Row(
        children: [
          if (contribution != null && leading['label'] is String)
            Expanded(child: leadingWidget),
          Expanded(flex: contribution == null ? 1 : 2, child: titleWidget),
        ],
      ),
    );
    // The unified menu is owned by the host and cannot be removed by a recipe.
    return Row(
      children: [
        if (spec?['backEvent'] != null)
          BackButton(
            onPressed: () => contribution!.dispatch(spec!['backEvent']),
          ),
        Expanded(
          child: UiComponent(
            ref: 'ui.chrome.header@1',
            props: {'title': title},
            slots: {
              'title': titleWidget,
              'leading': leadingWidget,
              'actions': const SizedBox.shrink(),
            },
            fallback: fallback,
          ),
        ),
        UiPackScope(defaultOnly: true, child: menu),
      ],
    );
  }

  void _openUiRecovery() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => UiPackScope(
          defaultOnly: true,
          child: UiPackSettingsPage(registry: widget.registry),
        ),
      ),
    );
  }

  void _openSettings() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => HostSettingsPage(registry: widget.registry),
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
              UiPackScope(
                defaultOnly: true,
                child: TextButton(
                  onPressed: _openUiRecovery,
                  child: const Text('界面风格与恢复'),
                ),
              ),
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
    final workspace =
        entries
            .where(
              (entry) => entry.opening == UiOpening.workspace && !entry.content,
            )
            .toList()
          ..sort(
            (a, b) =>
                profile.mountFor(a).order.compareTo(profile.mountFor(b).order),
          );
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
              UiPackScope(
                defaultOnly: true,
                child: TextButton(
                  onPressed: _openUiRecovery,
                  child: const Text('界面风格与恢复'),
                ),
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
    final activePage = widget.registry.ui.page(activeEntry.pageId);
    final instance = host?.instances[activeEntry.moduleId];
    final lease = workspaceHeader.activate(
      identity:
          '${activeEntry.id}:${activeEntry.pageId}:${profile.mountFor(activeEntry).context.identity}:${instance?.actor.generation}',
      moduleId: activeEntry.moduleId,
      pageId: activeEntry.pageId,
      enabled: activePage?.headerMode == 'contributed' && instance != null,
      isActive: () =>
          mounted &&
          selectedDestinationId == activeEntry.id &&
          identical(host?.instances[activeEntry.moduleId], instance),
    );
    workspaceChrome.configure(
      lease?.identity ?? activeEntry.id,
      enabled:
          lease?.isActive() == true &&
          workspaceHeader.content?.spec['autoHideChrome'] == true &&
          MediaQuery.viewInsetsOf(context).bottom == 0,
    );
    final chromeCollapsed = workspaceChrome.collapsed;
    final chromeDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    Widget workspaceContent() => WorkspaceHeaderScope(
      controller: workspaceHeader,
      lease: lease,
      child: current.builder(context),
    );
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
    final more = [...at(UiPlacement.more), ...main.skip(mainCount)];
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
        ? (_measuredDockHeight ??
                  MobileBottomDock.height(
                    context,
                    hasInput: current.quickAdd,
                    showNavigation: showNavigation,
                  )) +
              24
        : 0.0;
    final contentInset = chromeCollapsed && !desktop && showDock
        ? 60.0 + (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 100)
        : dockInset;
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
                  KeyedSubtree(
                    key: const ValueKey('workspace-header-region'),
                    child: chromeDuration == Duration.zero
                        ? (chromeCollapsed
                              ? const SizedBox(
                                  width: double.infinity,
                                  height: 0,
                                )
                              : _workspaceHeader(current.label, header))
                        : AnimatedSize(
                            duration: chromeDuration,
                            alignment: Alignment.topCenter,
                            child: chromeCollapsed
                                ? const SizedBox(
                                    width: double.infinity,
                                    height: 0,
                                  )
                                : _workspaceHeader(current.label, header),
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
                                setState(() => restoreFailures = const {}),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _chromeWorkspace(
                      collapsed: chromeCollapsed,
                      child: desktop
                          ? Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1040,
                                ),
                                child: workspaceContent(),
                              ),
                            )
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                RepaintBoundary(
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(end: contentInset),
                                    duration: chromeDuration,
                                    child: workspaceContent(),
                                    builder: (_, inset, child) =>
                                        WorkspaceContentInsets(
                                          bottom: inset,
                                          child: child!,
                                        ),
                                  ),
                                ),
                                if (showDock)
                                  Positioned(
                                    left: 12,
                                    right: 12,
                                    bottom: 12,
                                    child: IgnorePointer(
                                      ignoring: chromeCollapsed,
                                      child: ExcludeSemantics(
                                        excluding: chromeCollapsed,
                                        child: AnimatedSlide(
                                          offset: chromeCollapsed
                                              ? const Offset(0, 1.5)
                                              : Offset.zero,
                                          duration: chromeDuration,
                                          child: AnimatedOpacity(
                                            opacity: chromeCollapsed ? 0 : 1,
                                            duration: chromeDuration,
                                            child: MobileBottomDock(
                                              onSizeChanged: _dockSizeChanged,
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
                                                if (value >=
                                                    visibleMain.length) {
                                                  _navigationFeedback();
                                                  _showMore(more);
                                                } else {
                                                  _openEntry(
                                                    visibleMain[value],
                                                  );
                                                }
                                              },
                                              input: current.quickAdd
                                                  ? _quickInputContent(current)
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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
    final brand = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 28),
      child: Row(
        children: [
          Icon(Icons.grid_view_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            '序点',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    final navigation = ListView.separated(
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
    );
    final settings = Padding(
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
    );
    final fallback = SizedBox(
      width: 216,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            brand,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 0, 8),
              child: Text(
                '工作台',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppDesign.muted(context),
                ),
              ),
            ),
            Expanded(child: navigation),
            if (workspaceChrome.collapsed) _chromeRevealButton(),
            settings,
          ],
        ),
      ),
    );
    return UiComponent(
      ref: 'ui.chrome.sidebar@1',
      props: {
        'selectedIndex': index,
        'moreSelected': moreSelected,
        'destinations': [
          for (var i = 0; i < destinations.length; i++)
            {
              'id': destinations[i].id,
              'label': destinations[i].label,
              'index': i,
              'selected': i == index,
            },
        ],
      },
      slots: {'navigation': navigation, 'brand': brand, 'settings': settings},
      events: {
        'select': (value) {
          if (value is int && value >= 0 && value < entries.length) {
            _openEntry(entries[value]);
          }
        },
        'more': (_) => _showMore(more),
      },
      fallback: fallback,
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
      purpose: '使用当前工作区的输入贡献',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final contribution
              in widget.registry.ui
                  .forSlot(UiSlot.inputActions)
                  .whereType<WidgetRegistration>())
            contribution.builder(context),
        ],
      ),
    );
  }
}
