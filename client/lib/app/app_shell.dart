import '../core/ui/native_ui.dart';
import '../core/ui/ui_icon.dart';
import '../core/ui/workspace_typography.dart';
import '../core/contracts/json_values.dart';
import '../core/performance/ui_load_trace.dart';

import 'dart:async';

import '../core/module_host/module_host.dart';
import '../core/module_host/module_package.dart';
import '../core/module_host/host_providers.dart';
import '../core/module_host/script_app_module.dart';
import '../core/module_host/host_dialogs.dart';
import '../core/module_host/host_manager_page.dart';
import '../core/module_host/host_settings_page.dart';
import '../core/module_host/host_control_services.dart';
import '../core/module_host/collection_store.dart';
import '../core/ui/ui_slot.dart';
import '../core/ui/ui_registration.dart';
import '../core/ui/code_preview_dialog.dart';

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
import 'host_platform_bridge.dart';
import 'design_system.dart';
import 'app_toast.dart';
import 'mobile_bottom_dock.dart';
import 'frosted_toolbar_surface.dart';
import 'workspace_popup_menu.dart';
import 'workspace_page_transition.dart';
import '../core/performance/startup_readiness.dart';
import 'more_workspace_page.dart';
import 'workspace_date_title.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.registry});
  final ModuleRegistry registry;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _moreEntry = UiEntryRegistration(
    id: 'app.shell.more',
    moduleId: 'app.core.system',
    pageId: 'app.shell.more',
    label: '更多',
    icon: Icons.grid_view_rounded,
  );
  final workspaceContexts = <String, PageContext>{};
  List<UiEntryRegistration> visibleWorkspaceEntries = const [];
  List<UiEntryRegistration> extraEntries = const [];
  int index = 0;
  UiEntryRegistration? panelEntry;
  PageContext? panelContext;
  bool restoring = true;
  String? restoreError;
  Map<String, String> restoreFailures = {};
  ModuleHost? host;
  HostPlatformBridge? platformBridge;
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

  Future<void> _restoreInstalledModules() =>
      UiLoadTrace.run('shell.restore', _restoreModulesAndLayout);

  Future<void> _restoreModulesAndLayout() async {
    try {
      // Resolve the persisted entry mounts alongside module restoration, before
      // the first workspace can choose or load its page.
      await Future.wait<void>([
        ref.read(moduleHostProvider.future).then<void>((value) {
          host = value;
        }),
        ref
            .read(uiLayoutProvider.future)
            .then<void>(
              (_) {},
              // Keep the existing layout recovery action available on read failure.
              onError: (Object error, StackTrace stack) {},
            ),
      ], eagerError: true);
      if (!mounted) return;
      platformBridge ??= HostPlatformBridge(host!.store);
      platformBridge!.attach(host!);
      host!.interaction = _hostInteraction;
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
        ref.read(startupReadinessProvider).unavailable('restoreError');
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
    platformBridge?.revokeInactive();
  }

  Future<Object?> _hostInteraction(
    ModuleActor caller,
    String method,
    Map<String, Object?> args,
  ) async {
    if (!mounted) throw StateError('Host interaction unavailable');
    switch (method) {
      case 'ui.showCode':
        await showCodePreviewDialog(context, args);
        return null;
      case 'ui.notify':
        AppToast.show(
          context,
          message: args['message'] as String,
          kind: args['kind'] as String,
          duration: Duration(milliseconds: args['duration'] as int),
        );
        return null;
      case 'ui.review':
        return reviewDialog(context, '确认实际数据变更', args);
      case 'packages.review':
        return reviewDialog(context, '审核模块文件、数据、界面和权限', args);
      case 'grants.request':
        return reviewDialog(context, '授权模块调用（30分钟，最多20次写入）', args);
      case 'browser.capture':
        return platformBridge!.invoke(
          caller,
          method,
          args,
          browserTheme: Theme.of(context),
        );
      case 'ui.dialog':
        return showDialog<Map<String, Object?>>(
          context: context,
          builder: (_) => UiPackScope(
            moduleId: caller.moduleId,
            child: HostFormDialog(
              title: args['title'] as String? ?? '模块输入',
              description: args['description'] as String?,
              submitLabel: args['submitLabel'] as String? ?? '继续',
              presentation: args['presentation'] as String?,
              fields: [
                for (final f in args['fields'] as List? ?? []) object(f),
              ],
            ),
          ),
        );
      case 'secrets.configure':
        return platformBridge!.configureSecret(caller, args['endpoint'], (
          endpoint,
        ) async {
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
          if (values == null) return null;
          return values['key'] as String;
        });
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
        if (method == 'ui.navigate') {
          final workspaceEntries = visibleWorkspaceEntries.where(
            (entry) =>
                entry.pageId == pageId &&
                entry.opening == UiOpening.workspace &&
                !entry.content,
          );
          if (workspaceEntries.isNotEmpty) {
            final entry = workspaceEntries.first;
            final pageContext = _profile
                .mountFor(entry)
                .context
                .merge(PageContext(values: values));
            if (mountProblem(
                  widget.registry.ui,
                  entry,
                  _profile.mountFor(entry),
                  context: pageContext,
                ) ==
                null) {
              // A module can navigate from a detail route or modal panel.
              // Reveal the shell before rendering the destination; background
              // pages defer work while a route covers them (including handoff
              // to another module's preview page).
              final workspaceRoute = ModalRoute.of(context);
              if (workspaceRoute != null) {
                Navigator.of(context)
                    .popUntil((route) => identical(route, workspaceRoute));
              }
              _openEntry(entry, pageContext: pageContext);
              return true;
            }
          }
        }
        final child = UiPackScope(
          moduleId: page.moduleId,
          child: UiPageHost(
            registry: widget.registry,
            pageId: pageId,
            pageContext: PageContext(values: values),
          ),
        );
        if (method == 'ui.panel') {
          final presentation = object(args['presentation'] ?? {});
          final adaptive = presentation['adaptive'] == true;
          final centered = presentation['wide'] == 'center';
          if (adaptive && centered && MediaQuery.sizeOf(context).width >= 820) {
            unawaited(
              showDialog<void>(
                context: context,
                builder: (panelContext) => Dialog(
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 560,
                    height: MediaQuery.sizeOf(panelContext).height * .85,
                    child: Column(
                      children: [
                        AppBar(
                          automaticallyImplyLeading: false,
                          title: Text(page.title),
                          actions: [
                            IconButton(
                              tooltip: '关闭面板',
                              onPressed: () => Navigator.pop(panelContext),
                              icon: const UiIcon(Icons.close),
                            ),
                          ],
                        ),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            );
          } else if (adaptive && MediaQuery.sizeOf(context).width >= 820) {
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
                                NativeUi(
                                  child: IconButton(
                                    tooltip: '关闭面板',
                                    onPressed: () =>
                                        Navigator.pop(panelContext),
                                    icon: const UiIcon(Icons.close),
                                  ),
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
        return platformBridge!.invoke(caller, method, args);
    }
  }

  void _showRestoreFailures() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => NativeUi(
        child: AlertDialog(
          title: const Text('模块恢复详情'),
          content: SingleChildScrollView(
            child: Text(
              restoreFailures.entries
                  .map((failure) => '${failure.key}\n${failure.value}')
                  .join('\n\n'),
            ),
          ),
          actions: [
            NativeUi(
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ),
            NativeUi(
              child: TextButton(
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
            ),
          ],
        ),
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
    platformBridge?.close();
    super.dispose();
  }

  UiLayoutProfile get _profile =>
      (ref.read(uiLayoutProvider).asData?.value ?? UiLayout()).profile(
        MediaQuery.sizeOf(context).width >= 820,
      );

  void _openEntry(UiEntryRegistration entry, {PageContext? pageContext}) {
    if (entry.id == _moreEntry.id) {
      if (_profile.morePageEnabled) {
        _navigationFeedback();
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => selectedDestinationId = entry.id);
      }
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
        builder: (dialogContext) => NativeUi(
          child: AlertDialog(
            title: const Text('入口失效'),
            content: Text(problem),
            actions: [
              NativeUi(
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('暂时保留'),
                ),
              ),
              NativeUi(
                child: TextButton(
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
              ),
            ],
          ),
        ),
      );
      return;
    }
    _navigationFeedback();
    if (entry.opening == UiOpening.workspace) {
      setState(() {
        if (pageContext != null) workspaceContexts[entry.id] = pageContext;
        selectedDestinationId = entry.id;
      });
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
            pageContext:
                pageContext ??
                workspaceContexts[entry.id] ??
                _profile.mountFor(entry).context,
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
      Listener(
        onPointerSignal: workspaceChrome.handlePointerSignal,
        child: NotificationListener<ScrollNotification>(
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
                            child: NativeUi(
                              child: IconButton(
                                tooltip: '展开工具栏',
                                onPressed: workspaceChrome.reveal,
                                icon: const UiIcon(Icons.unfold_more),
                              ),
                            ),
                          ),
                        UiPackScope(
                          defaultOnly: true,
                          child: NativeUi(
                            child: IconButton(
                              tooltip: '界面风格与恢复',
                              onPressed: _openUiRecovery,
                              icon: const UiIcon(Icons.palette_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _chromeRevealButton() => Tooltip(
    message: '展开顶栏和导航',
    child: FrostedToolbarSurface(
      radius: 28,
      child: NativeUi(
        child: TextButton.icon(
          key: const ValueKey('workspace-chrome-reveal'),
          onPressed: workspaceChrome.reveal,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          icon: const UiIcon(Icons.unfold_more, size: 20),
          label: const Text('展开工具栏'),
        ),
      ),
    ),
  );

  Widget _workspaceHeader(
    String fallbackTitle,
    List<UiEntryRegistration> entries, {
    VoidCallback? onAssistant,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final dateTitle = workspaceHeader.lease?.mode == 'date';
    final titleStyle = WorkspaceTypography.titleStyle(textTheme);
    var controlHeight = kMinInteractiveDimension;
    for (final (style, padding) in [
      (titleStyle, 16.0),
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
        ? NativeUi(
            child: TextButton(
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
                  const UiIcon(Icons.expand_more, size: 18),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();
    final titleContent = spec?['titleEvent'] == null
        ? Text(
            title,
            maxLines: WorkspaceTypography.titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          )
        : NativeUi(
            child: TextButton(
              onPressed: () => contribution!.dispatch(spec!['titleEvent']),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: WorkspaceTypography.titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  const UiIcon(Icons.expand_more, size: 18),
                ],
              ),
            ),
          );
    Widget titleAtHeight(double minimumHeight) => LayoutBuilder(
      builder: (context, constraints) {
        final available =
            constraints.maxWidth - (spec?['titleEvent'] == null ? 0 : 52);
        final painter = TextPainter(
          text: TextSpan(text: title, style: titleStyle),
          maxLines: WorkspaceTypography.titleMaxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: available.clamp(1, double.infinity).toDouble());
        final measured = painter.height + 16;
        painter.dispose();
        return SizedBox(
          height: measured > minimumHeight ? measured : minimumHeight,
          child: Align(
            alignment: leading['label'] is String
                ? Alignment.center
                : Alignment.centerLeft,
            child: titleContent,
          ),
        );
      },
    );
    final titleWidget = dateTitle
        ? WorkspaceDateTitle(
            title: title,
            date: spec?['selectedDate'] as String?,
            style: titleStyle,
            onEvent: spec?['dateNavigation'] == true && contribution != null
                ? (type) => unawaited(contribution.dispatch({'type': type}))
                : null,
            onEventWithOrigin:
                spec?['dateNavigation'] == true && contribution != null
                ? (type, bounds) => unawaited(
                    contribution.dispatch({
                      'type': type,
                      'originBounds': bounds,
                    }),
                  )
                : null,
          )
        : titleAtHeight(controlHeight);
    Widget menuLabel(String label, IconData icon) => Row(
      children: [
        UiIcon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
    final menuPreferences = ref.watch(appPreferencesProvider).asData?.value;
    final returnToToday =
        dateTitle &&
        spec?['dateNavigation'] == true &&
        spec?['todayDate'] is String &&
        spec?['selectedDate'] != spec?['todayDate'];
    final menu = Builder(
      builder: (menuContext) => UiAnnotation(
        id: 'app.shell.menu',
        name: '页面菜单',
        purpose: '打开页面操作、模块入口及设置',
        child: WorkspacePopupMenu(
          key: const ValueKey('workspace-menu'),
          haptics: menuPreferences?.haptics ?? true,
          reduceMotion: menuPreferences?.reduceMotion ?? false,
          onSelected: (index) {
            if (index == -1) {
              _openSettings();
            } else if (index == -2) {
              _showAllEntries(extraEntries);
            } else if (index == -3) {
              final box = menuContext.findRenderObject();
              unawaited(
                contribution!.dispatch({
                  'type': 'date.today',
                  if (box is RenderBox && box.hasSize)
                    'originBounds': box.localToGlobal(Offset.zero) & box.size,
                }),
              );
            } else if (index < actions.length) {
              contribution?.dispatch(actions[index]['event']);
            } else {
              _openEntry(entries[index - actions.length]);
            }
          },
          items: [
            if (returnToToday)
              PopupMenuItem(
                value: -3,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: menuLabel('回到今天', Icons.today_outlined),
              ),
            if (returnToToday && (actions.isNotEmpty || entries.isNotEmpty))
              const PopupMenuDivider(height: 8),
            for (var i = 0; i < actions.length; i++)
              PopupMenuItem(
                value: i,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('${actions[i]['label'] ?? ''}'),
              ),
            if (actions.isNotEmpty && entries.isNotEmpty)
              const PopupMenuDivider(height: 8),
            for (var i = 0; i < entries.length; i++)
              PopupMenuItem(
                value: actions.length + i,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: UiAnnotation(
                  id: entries[i].id,
                  name: entries[i].label,
                  moduleId: entries[i].moduleId,
                  slot: 'header',
                  purpose: '打开功能入口',
                  child: menuLabel(entries[i].label, entries[i].icon),
                ),
              ),
            if (returnToToday || actions.isNotEmpty || entries.isNotEmpty)
              const PopupMenuDivider(height: 8),
            if (!_profile.morePageEnabled)
              PopupMenuItem(
                value: -2,
                height: 44,
                child: menuLabel('全部入口', Icons.grid_view_outlined),
              ),
            PopupMenuItem(
              value: -1,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: UiAnnotation(
                id: 'app.shell.settings',
                name: '设置',
                purpose: '受保护的设置与恢复入口',
                child: menuLabel('设置', Icons.settings_outlined),
              ),
            ),
          ],
        ),
      ),
    );
    final fallback = Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Row(
        children: [
          if (contribution != null && leading['label'] is String)
            Expanded(child: leadingWidget),
          Expanded(flex: contribution == null ? 1 : 2, child: titleWidget),
        ],
      ),
    );
    // The unified menu is owned by the host and cannot be removed by a recipe.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
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
          if (onAssistant != null)
            NativeUi(
              child: IconButton(
                key: const ValueKey('desktop-workspace-assistant'),
                tooltip: 'AI 助手',
                onPressed: onAssistant,
                icon: const UiIcon(Icons.auto_awesome_outlined),
              ),
            ),
          UiPackScope(defaultOnly: true, child: menu),
        ],
      ),
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

  void _showAllEntries(List<UiEntryRegistration> entries) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (routeContext) => DetailPage(
          title: '全部入口',
          child: MoreWorkspacePage(
            entries: entries,
            onOpen: (entry) {
              Navigator.pop(routeContext);
              _openEntry(entry);
            },
            onSettings: () {
              Navigator.pop(routeContext);
              _openSettings();
            },
          ),
        ),
      ),
    );
  }

  Set<String> _assistantModules(UiEntryRegistration root) {
    final modules = <String>{root.moduleId};
    final rootContext =
        workspaceContexts[root.id] ?? _profile.mountFor(root).context;
    final pages = <String, PageContext>{
      root.pageId: rootContext.merge(
        PageContext(
          values: {
            if (workspaceHeader.content?.spec['selectedDate'] != null)
              'selectedDate': workspaceHeader.content!.spec['selectedDate'],
          },
        ),
      ),
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in widget.registry.ui.entries) {
        final mount = _profile.mountFor(entry);
        final parentContext = pages[mount.pageId];
        if (!entry.content ||
            mount.placement != UiPlacement.page ||
            parentContext == null) {
          continue;
        }
        final parent = widget.registry.ui.page(mount.pageId!);
        final slots = parent?.slots.where((slot) => slot.id == mount.slotId);
        if (slots == null || slots.isEmpty) continue;
        final slot = slots.first;
        if (!slot.inline ||
            slot.kind != PageSlotKind.sections ||
            mountDiagnostic(
                  widget.registry.ui,
                  entry,
                  mount,
                  context: parentContext,
                ) !=
                null) {
          continue;
        }
        if (slot.capacity != null) {
          final siblings = orderedEntries(
            widget.registry.ui,
            _profile.mountFor,
            (candidate) {
              final target = _profile.mountFor(candidate);
              return target.placement == UiPlacement.page &&
                  target.pageId == mount.pageId &&
                  target.slotId == mount.slotId;
            },
          );
          if (siblings.indexOf(entry) >= slot.capacity!) continue;
        }
        if (!pages.containsKey(entry.pageId)) {
          pages[entry.pageId] = parentContext.merge(mount.context);
          changed = true;
        }
        modules.add(entry.moduleId);
      }
      for (final moduleId in modules.toList()) {
        for (final dependency
            in host?.instances[moduleId]?.package.dependencies ??
                const <String>[]) {
          changed = modules.add(dependency) || changed;
        }
      }
    }
    return modules;
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return const Scaffold(
        body: Center(child: NativeUi(child: CircularProgressIndicator())),
      );
    }
    if (restoreError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(restoreError!),
              NativeUi(
                child: TextButton(
                  onPressed: () {
                    setState(() => restoring = true);
                    _restoreInstalledModules();
                  },
                  child: const Text('重试'),
                ),
              ),
              NativeUi(
                child: TextButton(
                  onPressed: _openSettings,
                  child: const Text('打开设置'),
                ),
              ),
              UiPackScope(
                defaultOnly: true,
                child: NativeUi(
                  child: TextButton(
                    onPressed: _openUiRecovery,
                    child: const Text('界面风格与恢复'),
                  ),
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
    final workspace = orderedEntries(
      widget.registry.ui,
      profile.mountFor,
      (entry) => entry.opening == UiOpening.workspace && !entry.content,
    );
    if (workspace.isEmpty) {
      ref.read(startupReadinessProvider).unavailable('noWorkspace');
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('没有可用工作区'),
              NativeUi(
                child: TextButton(
                  onPressed: _openSettings,
                  child: const Text('打开设置并恢复模块'),
                ),
              ),
              UiPackScope(
                defaultOnly: true,
                child: NativeUi(
                  child: TextButton(
                    onPressed: _openUiRecovery,
                    child: const Text('界面风格与恢复'),
                  ),
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
    final showingMore =
        profile.morePageEnabled && selectedDestinationId == _moreEntry.id;
    final activeEntry = showingMore
        ? _moreEntry
        : selected.isEmpty
        ? workspace.first
        : selected.first;
    final activeOrder = showingMore ? -1 : workspace.indexOf(activeEntry);
    selectedDestinationId = activeEntry.id;
    final current = showingMore
        ? AppDestination(
            id: _moreEntry.id,
            label: '更多',
            icon: _moreEntry.icon,
            selectedIcon: _moreEntry.icon,
            builder: (_) => MoreWorkspacePage(
              entries: extraEntries,
              onOpen: _openEntry,
              onSettings: _openSettings,
            ),
          )
        : _destination(activeEntry);
    final activePage = widget.registry.ui.page(activeEntry.pageId);
    final instance = host?.instances[activeEntry.moduleId];
    final lease = workspaceHeader.activate(
      identity:
          '${activeEntry.id}:${activeEntry.pageId}:${(workspaceContexts[activeEntry.id] ?? profile.mountFor(activeEntry).context).identity}:${instance?.actor.generation}',
      moduleId: activeEntry.moduleId,
      pageId: activeEntry.pageId,
      enabled:
          {'contributed', 'date'}.contains(activePage?.headerMode) &&
          (instance != null || activePage?.headerMode == 'date'),
      mode: activePage?.headerMode ?? 'standard',
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
    final chromeProgress = workspaceChrome.progress;
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
    final contextModules = showingMore
        ? <String>{}
        : _assistantModules(activeEntry);
    final assistant = showingMore
        ? null
        : widget.registry.ui
              .forSlot(UiSlot.workspaceAssistant)
              .whereType<WorkspaceAssistantRegistration>()
              .where((registration) => registration.supports(contextModules))
              .firstOrNull;
    void openAssistant() {
      if (assistant == null) return;
      final pageContext =
          workspaceContexts[activeEntry.id] ??
          profile.mountFor(activeEntry).context;
      final values = <String, Object?>{
        ...pageContext.values,
        if (workspaceHeader.content?.spec['selectedDate'] != null)
          'selectedDate': workspaceHeader.content!.spec['selectedDate'],
      };
      unawaited(
        assistant.onOpen(
          context,
          pageContext.merge(PageContext(values: values)),
        ),
      );
    }

    final mainCount = navigationVisibleCount(
      total: main.length,
      limit: profile.mainLimit,
      width: width - 24 - (profile.morePageEnabled && !desktop ? 72 : 0),
      textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
      desktop: desktop,
    );
    final more = [...at(UiPlacement.more), ...main.skip(mainCount)];
    final visibleMain = main.take(mainCount).toList();
    visibleWorkspaceEntries = visibleMain;
    extraEntries = more;
    final navigationEntries = [
      if (profile.morePageEnabled) _moreEntry,
      ...visibleMain,
    ];
    final destinations = navigationEntries.map(_destination).toList();
    index = navigationEntries.indexWhere((entry) => entry.id == activeEntry.id);
    if (index < 0 &&
        profile.morePageEnabled &&
        more.any((entry) => entry.id == activeEntry.id)) {
      index = 0;
    }
    final showPanel = desktop && panelEntry != null && width >= 1100;
    final showNavigation = MediaQuery.viewInsetsOf(context).bottom == 0;
    final showDock =
        (showNavigation &&
            (navigationEntries.isNotEmpty || assistant != null)) ||
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
    final collapsedInset = !desktop && showDock
        ? 60.0 + (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 100)
        : dockInset;
    final contentInset =
        dockInset + (collapsedInset - dockInset) * chromeProgress;
    final workspaceRevision = canonicalJson({
      'modules': [
        for (final module in widget.registry.modules)
          [module.manifest.id, module.manifest.version],
      ],
      'instances': {
        for (final entry
            in host?.instances.entries ??
                const <MapEntry<String, ScriptInstance>>[])
          entry.key: [
            entry.value.actor.generation,
            entry.value.package.packageDigest,
          ],
      },
      'layout': profile.toJson(),
      'desktop': desktop,
    });
    final retentionKeys = <String, Object?>{
      for (final entry in workspace)
        entry.id: canonicalJson([
          workspaceRevision,
          entry.pageId,
          (workspaceContexts[entry.id] ?? profile.mountFor(entry).context)
              .navigationIdentity,
        ]),
      if (profile.morePageEnabled) _moreEntry.id: workspaceRevision,
    };
    return Scaffold(
      backgroundColor: AppDesign.canvas(context),
      body: SafeArea(
        child: Row(
          children: [
            if (desktop)
              _sidebar(destinations, navigationEntries, const [], false),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WorkspacePageTransition(
                    key: const ValueKey('workspace-page-transition'),
                    destinationId: activeEntry.id,
                    order: activeOrder,
                    backgroundColor: AppDesign.canvas(context),
                    maxRetainedPages: 4,
                    retentionKeys: retentionKeys,
                    deferUntilReady: true,
                    onDestinationReady: () =>
                        ref.read(startupReadinessProvider).workspaceReady(),
                    child: Column(
                      children: [
                        WorkspaceChromeHeader(
                          key: const ValueKey('workspace-header-region'),
                          controller: workspaceChrome,
                          child: _workspaceHeader(
                            current.label,
                            header,
                            onAssistant: desktop && assistant != null
                                ? openAssistant
                                : null,
                          ),
                        ),
                        if (layout?.warning != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(layout!.warning!),
                          ),
                        if (ref.watch(uiLayoutProvider).hasError)
                          NativeUi(
                            child: TextButton(
                              onPressed: () => ref.invalidate(uiLayoutProvider),
                              child: const Text('布局读取失败，暂用默认布局，点击重试'),
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                                NativeUi(
                                  child: TextButton(
                                    onPressed: _showRestoreFailures,
                                    child: const Text('查看详情'),
                                  ),
                                ),
                                NativeUi(
                                  child: IconButton(
                                    tooltip: '关闭恢复提示',
                                    onPressed: () => setState(
                                      () => restoreFailures = const {},
                                    ),
                                    icon: const UiIcon(Icons.close, size: 18),
                                  ),
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
                                : RepaintBoundary(
                                    child: WorkspaceContentInsets(
                                      bottom: contentInset,
                                      child: workspaceContent(),
                                    ),
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
                  if (!desktop && showDock)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: IgnorePointer(
                        ignoring: chromeCollapsed,
                        child: ExcludeSemantics(
                          excluding: chromeCollapsed,
                          child: FractionalTranslation(
                            translation: Offset(0, chromeProgress * 1.5),
                            child: Opacity(
                              opacity: 1 - chromeProgress,
                              child: MobileBottomDock(
                                onSizeChanged: _dockSizeChanged,
                                destinations: destinations,
                                selectedIndex: index,
                                visibleCount: destinations.length,
                                hasMore: false,
                                moreSelected: false,
                                onAssistant: assistant == null
                                    ? null
                                    : openAssistant,
                                annotate: true,
                                entryModuleIds: {
                                  for (final entry in navigationEntries)
                                    entry.id: entry.moduleId,
                                },
                                showNavigation: showNavigation,
                                onSelected: (value) {
                                  if (value >= 0 &&
                                      value < navigationEntries.length) {
                                    _openEntry(navigationEntries[value]);
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
          UiIcon(Icons.grid_view_outlined, color: theme.colorScheme.primary),
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
          : NativeUi(
              child: ListTile(
                leading: const UiIcon(Icons.more_horiz),
                title: const Text('更多'),
                selected: moreSelected,
                onTap: () => _showAllEntries(more),
              ),
            ),
    );
    final settings = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: UiAnnotation(
        id: 'app.shell.settings',
        name: '设置',
        purpose: '受保护的设置与恢复入口',
        child: NativeUi(
          child: ListTile(
            shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
            leading: const UiIcon(Icons.settings_outlined, size: 21),
            title: const Text('设置'),
            onTap: _openSettings,
          ),
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
        'more': (_) => _showAllEntries(more),
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
                UiIcon(
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
