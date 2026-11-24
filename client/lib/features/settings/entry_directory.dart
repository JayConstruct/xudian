import '../../core/ui/tab_content_transition.dart';
import '../../core/module_host/host_providers.dart';
import '../../core/module_host/module_installation_snapshot.dart';
import '../../data/providers.dart';
import '../../app/app_toast.dart';
import 'entry_context_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/modules/module_registry.dart';
import '../../core/ui/module_detail_page.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_layout_resolver.dart';
import '../../core/ui/ui_icon.dart';
import '../../core/module_host/host_settings_page.dart';
import '../../core/contracts/json_values.dart';
import 'settings_focus.dart';
import 'settings_widgets.dart';
import 'ui_layout.dart';
import 'ui_layout_page.dart';

typedef OpenShellEntry = void Function(
  UiEntryRegistration entry,
  PageContext context,
);
typedef LocateShellEntry = void Function(
  String id,
  UiPlacement placement, {
  String? sourcePage,
});

/// The shell supplies the same assistant availability calculation used by its dock.
class EntryWorkspaceScope extends InheritedWidget {
  const EntryWorkspaceScope({
    super.key,
    required this.assistantSources,
    required super.child,
  });
  final Iterable<UiEntryRegistration> Function(String pageId) assistantSources;
  @override
  bool updateShouldNotify(EntryWorkspaceScope old) =>
      old.assistantSources != assistantSources;
}

typedef _UnavailableEntry = ({String title, String module, String id});
final _unavailableEntries = StreamProvider.autoDispose<List<_UnavailableEntry>>(
  (ref) async* {
    final host = await ref.watch(moduleHostProvider.future);
    Future<List<_UnavailableEntry>> read() async {
      final installed = await readModuleInstallations(
        host,
        reuseVerified: true,
      );
      final items = <_UnavailableEntry>[];
      for (final value in installed.values.where(
        (i) => !i.enabled || !host.instances.containsKey(i.package.id),
      )) {
        for (final page
            in (value.package.definition['pages'] as List? ?? [])
                .whereType<Map>()) {
          if (page['entry'] == null &&
              (page['entries'] as List? ?? []).isEmpty) {
            continue;
          }
          items.add((
            title: (page['title'] ?? page['id']).toString(),
            module: value.package.title,
            id: value.package.id,
          ));
        }
      }
      return items;
    }

    yield await read();
    yield* host.registryChanges.stream.asyncMap((_) => read());
  },
);

class EntryDirectoryPage extends ConsumerStatefulWidget {
  const EntryDirectoryPage({
    super.key,
    required this.registry,
    this.openShellEntry,
    this.locateShellEntry,
  });
  final ModuleRegistry registry;
  final OpenShellEntry? openShellEntry;
  final LocateShellEntry? locateShellEntry;
  @override
  ConsumerState<EntryDirectoryPage> createState() => _EntryDirectoryPageState();
}

typedef _Origin = ({
  String path,
  String? pageId,
  UiPlacement placement,
  UiEntryRegistration entry,
});

class _EntryDirectoryPageState extends ConsumerState<EntryDirectoryPage> {
  final search = TextEditingController();
  final scroll = ScrollController();
  bool locate = false;
  ModuleRegistry get registry => widget.registry;
  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void push(Widget page) =>
      Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
  String title(UiEntryRegistration entry) {
    final page = registry.ui.page(entry.pageId);
    return page != null &&
            registry.ui.entries.any(
              (e) => e.pageId != entry.pageId && e.label == entry.label,
            )
        ? page.title
        : entry.label;
  }

  Future<void> open(UiEntryRegistration entry, UiLayoutProfile profile) async {
    final mount = profile.mountFor(entry);
    if (entry.content &&
        mount.placement == UiPlacement.page &&
        mount.pageId != null) {
      showOriginPage(mount.pageId!, entry.id, mount.context);
      return;
    }
    var supplied = mount.context;
    final required =
        registry.ui.page(entry.pageId)?.requiredContext ?? const <String>[];
    if (!supplied.satisfies(required) &&
        required.every(
          (key) =>
              key == 'taskId' ||
              key == 'projectId' ||
              supplied.value(key) != null,
        )) {
      try {
        final db = await ref.read(databaseProvider.future);
        if (!mounted) return;
        final chosen = await chooseEntryContext(
          context,
          db,
          supplied,
          requiredKeys: required,
        );
        if (!mounted || chosen == null) return;
        supplied = chosen;
      } catch (_) {
        if (mounted) {
          AppToast.show(context, message: '无法读取可选对象，请重试', kind: 'error');
        }
        return;
      }
    }
    final problem = mountDiagnostic(
      registry.ui,
      entry,
      UiMount(placement: UiPlacement.hidden, context: supplied),
    );
    if (problem != null) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('入口需要配置'),
          content: Text(problem.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                edit(entry);
              },
              child: const Text('配置入口'),
            ),
          ],
        ),
      );
      return;
    }
    if (widget.openShellEntry != null &&
        (entry.opening == UiOpening.workspace ||
            entry.opening == UiOpening.adaptivePanel &&
                MediaQuery.sizeOf(context).width >= 1100)) {
      widget.openShellEntry!(entry, supplied);
      return;
    }
    final page = ModuleDetailPage(
      registry: registry,
      pageId: entry.pageId,
      title: title(entry),
      pageContext: supplied,
      panel: entry.opening == UiOpening.adaptivePanel,
    );
    if (entry.opening == UiOpening.adaptivePanel) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => FractionallySizedBox(heightFactor: .88, child: page),
      );
    } else {
      push(page);
    }
  }

  void edit(UiEntryRegistration entry) => push(
    UiLayoutPage(
      registry: registry,
      initialDesktop: MediaQuery.sizeOf(context).width >= 820,
      initialEntryId: entry.id,
    ),
  );
  void showOriginPage(String page, String anchor, PageContext ctx) => push(
    SettingsFocus(
      label: anchor,
      child: ModuleDetailPage(
        registry: registry,
        pageId: page,
        pageContext: ctx,
      ),
    ),
  );
  void showSettings([String? anchor]) => push(
    SettingsFocus(
      label: anchor ?? '',
      child: HostSettingsPage(
        registry: registry,
        onOpenEntry: widget.openShellEntry,
        onLocate: widget.locateShellEntry,
        returnToSearch: anchor != null,
      ),
    ),
  );
  Future<void> details(
    List<UiEntryRegistration> entries,
    UiLayoutProfile profile,
    List<_Origin> origins,
  ) async {
    final entry = entries.first;
    void go(BuildContext sheet, VoidCallback run) {
      Navigator.pop(sheet);
      run();
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(c).height * .8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDesign.pageGutter,
            0,
            AppDesign.pageGutter,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title(entry), style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (origins.isEmpty)
                const SettingsNote('没有已显示的位置。可以从目录直接打开，或在编排页把它放回导航或菜单。')
              else
                SettingsGroup(
                  title: '选择一条路径，在 App 中定位',
                  children: [
                    for (final origin in origins)
                      ListTile(
                        leading: const UiIcon(Icons.place_outlined),
                        title: Text(origin.path),
                        trailing: const UiIcon(Icons.chevron_right),
                        onTap: () => go(c, () {
                          final target = origin.entry;
                          final mount = profile.mountFor(target);
                          if (origin.pageId != null &&
                              origin.placement == UiPlacement.page) {
                            showOriginPage(
                              origin.pageId!,
                              target.id,
                              mount.context,
                            );
                            return;
                          }
                          if (origin.placement == UiPlacement.settings) {
                            if (target.id == 'modules' &&
                                origin.path.contains('模块管理与恢复')) {
                              push(
                                SettingsFocus(
                                  label: '模块管理与恢复',
                                  child: ModuleSettingsPage(registry: registry),
                                ),
                              );
                            } else {
                              showSettings(target.label);
                            }
                            return;
                          }
                          if (widget.locateShellEntry != null) {
                            final label =
                                registry.ui.page(target.pageId)?.title ??
                                target.label;
                            widget.locateShellEntry!(
                              origin.pageId == null
                                  ? target.id
                                  : origin.placement == UiPlacement.main
                                  ? 'app.shell.assistant'
                                  : 'menu-action:$label',
                              origin.placement,
                              sourcePage: origin.pageId,
                            );
                          } else {
                            edit(target);
                          }
                        }),
                      ),
                  ],
                ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => go(c, () => edit(entry)),
                    child: const Text('前往编排'),
                  ),
                  FilledButton(
                    onPressed: () => go(c, () => open(entry, profile)),
                    child: const Text('打开入口'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unavailable =
        ref.watch(_unavailableEntries).asData?.value ??
        const <_UnavailableEntry>[];
    final stored = ref.watch(uiLayoutProvider);
    final media = MediaQuery.of(context), wide = media.size.width >= 820;
    return DetailPage(
      settingsStyle: true,
      title: '入口目录',
      child: stored.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(uiLayoutProvider),
            child: const Text('重试读取布局'),
          ),
        ),
        data: (layout) => ListenableBuilder(
          listenable: registry,
          builder: (context, _) {
            final profile = layout.profile(wide);
            final all = orderedEntries(
              registry.ui,
              profile.mountFor,
              (_) => true,
            );
            final main = all
                .where((e) => profile.mountFor(e).placement == UiPlacement.main)
                .toList();
            final count = navigationVisibleCount(
              total: main.length,
              fixedMore: profile.morePageEnabled,
              limit: profile.mainLimit,
              width:
                  media.size.width -
                  24 -
                  (profile.morePageEnabled && !wide ? 72 : 0),
              textScale: media.textScaler.scale(12) / 12,
              desktop: wide,
            );
            final more = profile.morePageEnabled ? '更多' : '右上角菜单 › 全部入口';
            String position(UiEntryRegistration e) {
              final m = profile.mountFor(e);
              return switch (m.placement) {
                UiPlacement.main =>
                  main.indexOf(e) >= count
                      ? '$more · 导航溢出'
                      : wide
                      ? '侧栏导航'
                      : '底部导航',
                UiPlacement.header => '右上角菜单',
                UiPlacement.more => more,
                UiPlacement.settings => '设置 › 常用入口',
                UiPlacement.hidden => '已隐藏',
                UiPlacement.page => [
                  registry.ui.page(m.pageId ?? '')?.title ?? '不可用页面',
                  registry.ui
                          .page(m.pageId ?? '')
                          ?.slots
                          .where((s) => s.id == m.slotId)
                          .firstOrNull
                          ?.label ??
                      '页面槽位',
                ].join(' › '),
              };
            }

            int priority(UiEntryRegistration entry) {
              if (entry.content) return 6;
              return switch (profile.mountFor(entry).placement) {
                UiPlacement.main => 0,
                UiPlacement.more => 1,
                UiPlacement.header => 2,
                UiPlacement.settings => 3,
                UiPlacement.page => 4,
                UiPlacement.hidden => 5,
              };
            }

            final sorted = [
              for (var level = 0; level <= 6; level++)
                ...all.where((e) => priority(e) == level),
            ];
            final grouped = <(String, String), List<UiEntryRegistration>>{};
            for (final e in sorted) {
              grouped
                  .putIfAbsent((
                    e.pageId,
                    canonicalJson(profile.mountFor(e).context.values),
                  ), () => [])
                  .add(e);
            }
            List<_Origin> origins(List<UiEntryRegistration> group) {
              final result = <_Origin>[];
              for (final e in group) {
                final m = profile.mountFor(e);
                if (m.placement != UiPlacement.hidden &&
                    layoutEntryDiagnostic(registry.ui, e, profile.mountFor) ==
                        null) {
                  final overflow =
                      m.placement == UiPlacement.main &&
                      main.indexOf(e) >= count;
                  final source = m.placement == UiPlacement.page
                      ? registry.ui.page(m.pageId ?? '')
                      : null;
                  final prefix = source?.settingsPath;
                  final path = prefix != null && prefix.isNotEmpty
                      ? '$prefix › ${position(e)}'
                      : position(e);
                  result.add((
                    path: '$path › ${e.label}',
                    pageId: m.pageId,
                    placement: overflow ? UiPlacement.more : m.placement,
                    entry: e,
                  ));
                }
                final page = registry.ui.page(e.pageId);
                if (page?.menuSourcePage case final String source) {
                  final host = registry.ui.page(source);
                  if (host != null) {
                    result.add((
                      path: '${host.title} › 右上角菜单 › ${e.label}',
                      pageId: source,
                      placement: UiPlacement.header,
                      entry: e,
                    ));
                  }
                }
                if (e.id == 'modules') {
                  result.add((
                    path: '设置 › 模块与连接 › 模块管理与恢复',
                    pageId: null,
                    placement: UiPlacement.settings,
                    entry: e,
                  ));
                }
              }
              final scope = context
                  .dependOnInheritedWidgetOfExactType<EntryWorkspaceScope>();
              for (final source
                  in scope?.assistantSources(group.first.pageId) ??
                      const <UiEntryRegistration>[]) {
                result.add((
                  path: '${source.label} › 助手按钮',
                  pageId: source.pageId,
                  placement: UiPlacement.main,
                  entry: group.first,
                ));
              }
              return result;
            }

            final query = search.text.trim().toLowerCase();
            final matches = grouped.values
                .where(
                  (group) => group.any(
                    (e) =>
                        '${title(e)} ${e.label} ${e.moduleId} ${registry.ui.page(e.pageId)?.title}'
                            .toLowerCase()
                            .contains(query),
                  ),
                )
                .toList();
            final inactive = unavailable.where(
              (e) => '${e.title} ${e.module} ${e.id}'.toLowerCase().contains(
                query,
              ),
            );
            final settingsMatch = '设置'.contains(query);
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.pageGutter,
                8,
                AppDesign.pageGutter,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SlidingSegments<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('打开入口')),
                      ButtonSegment(value: true, label: Text('查找位置')),
                    ],
                    selected: locate,
                    onChanged: (v) => setState(() => locate = v),
                  ),
                  const SizedBox(height: 16),
                  SettingsSearchField(
                    controller: search,
                    hint: '搜索入口名称或模块',
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: TabContentTransition(
                      index: locate ? 1 : 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SettingsHeading(locate ? '当前设备 · 已生效布局' : '所有入口'),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView(
                              controller: scroll,
                              children: [
                                if (matches.isEmpty &&
                                    !settingsMatch &&
                                    inactive.isEmpty)
                                  const SettingsNote('没有匹配的入口'),
                                SettingsGroup(
                                  children: [
                                    for (final group in matches)
                                      Builder(
                                        builder: (c) {
                                          final e = group.first;
                                          final paths = locate
                                              ? origins(group)
                                              : const <_Origin>[];
                                          return ListTile(
                                            leading: SettingsGlyph(
                                              e.icon,
                                              surface: false,
                                            ),
                                            title: Text(title(e)),
                                            trailing: locate
                                                ? Text(
                                                    paths.length > 1
                                                        ? '${paths.length} 个位置'
                                                        : paths.isEmpty
                                                        ? '已隐藏'
                                                        : paths.first.pageId !=
                                                                  null &&
                                                              paths
                                                                      .first
                                                                      .placement ==
                                                                  UiPlacement
                                                                      .main
                                                        ? '助手按钮'
                                                        : position(e),
                                                    style: Theme.of(c)
                                                        .textTheme
                                                        .bodySmall,
                                                  )
                                                : const Icon(
                                                    Icons.north_east,
                                                    size: 18,
                                                  ),
                                            onTap: () => locate
                                                ? details(group, profile, paths)
                                                : open(e, profile),
                                          );
                                        },
                                      ),
                                    for (final item in inactive)
                                      ListTile(
                                        enabled: false,
                                        leading: const SettingsGlyph(
                                          Icons.extension_off_outlined,
                                        ),
                                        title: Text(item.title),
                                        subtitle: Text(
                                          '${item.module}未启用，可在模块管理中查看状态。',
                                        ),
                                      ),
                                    if (settingsMatch)
                                      ListTile(
                                        leading: const SettingsGlyph(
                                          Icons.settings_outlined,
                                          surface: false,
                                        ),
                                        title: const Text('设置'),
                                        trailing: locate
                                            ? const Text('固定入口')
                                            : const Icon(
                                                Icons.north_east,
                                                size: 18,
                                              ),
                                        onTap: () => locate
                                            ? showModalBottomSheet<void>(
                                                context: context,
                                                showDragHandle: true,
                                                builder: (c) => SafeArea(
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      for (final place in [
                                                        if (wide)
                                                          (
                                                            UiPlacement.main,
                                                            '侧栏导航',
                                                          ),
                                                        (
                                                          UiPlacement.header,
                                                          '右上角菜单',
                                                        ),
                                                        (
                                                          UiPlacement.more,
                                                          more,
                                                        ),
                                                      ])
                                                        ListTile(
                                                          title: Text(
                                                            '${place.$2} › 设置',
                                                          ),
                                                          onTap: () {
                                                            Navigator.pop(c);
                                                            if (widget
                                                                    .locateShellEntry !=
                                                                null) {
                                                              widget
                                                                  .locateShellEntry!(
                                                                'app.shell.settings',
                                                                place.$1,
                                                              );
                                                            } else {
                                                              showSettings();
                                                            }
                                                          },
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            : showSettings(),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
