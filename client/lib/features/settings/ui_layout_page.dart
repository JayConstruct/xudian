import '../../core/ui/tab_content_transition.dart';
import 'entry_context_picker.dart';
import '../../core/ui/ui_icon.dart';
import '../../core/ui/native_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../app/app_toast.dart';
import '../../core/contracts/json_values.dart';
import '../../core/modules/module_registry.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_layout_resolver.dart';
import '../../data/providers.dart';
import 'ui_layout.dart';
import 'ui_layout_navigation_preview.dart';
import 'ui_layout_picker.dart';
import 'ui_layout_preview.dart';
import 'settings_widgets.dart';
import 'entry_directory.dart';
import 'layout_arranger.dart';

part 'ui_layout_changes.dart';

part 'ui_layout_inspector.dart';

class UiLayoutPage extends ConsumerStatefulWidget {
  const UiLayoutPage({
    super.key,
    required this.registry,
    this.initialDraft,
    this.initialPageId,
    this.initialEntryId,
    this.initialDesktop = false,
    this.onOpenEntry,
    this.onLocate,
  });

  final ModuleRegistry registry;
  final UiLayout? initialDraft;
  final String? initialPageId;
  final String? initialEntryId;
  final bool initialDesktop;
  final OpenShellEntry? onOpenEntry;
  final LocateShellEntry? onLocate;

  @override
  ConsumerState<UiLayoutPage> createState() => _UiLayoutPageState();
}

class _UiLayoutPageState extends ConsumerState<UiLayoutPage> {
  UiLayout? draft;
  UiLayout? baseline;
  bool desktop = false;
  bool saving = false;
  String? pageId;
  String? error;
  final limitControllers = <bool, TextEditingController>{};
  UiLayoutProfile? checkedProfile;
  List<String> warnings = const [];
  Map<String, UiMountDiagnostic?> entryDiagnostics = const {};
  String search = '';
  bool onlyProblems = false;
  bool showIdentifiers = false;
  bool advanced = false;
  final searchController = TextEditingController();
  String? selectedId;
  final collapsedGroups = <(UiPlacement, String?, String?)>{};
  final inspectorRevision = ValueNotifier(0);
  final layoutRevision = ValueNotifier(0);
  UiLayoutPreviewArea activeArea = UiLayoutPreviewArea.all;
  bool inspectorOpen = false;
  bool positioned = false;
  bool scopeRouteOpen = false;
  final sessionToken = Object();
  late final UiLayoutEditorSessions editorSessions;

  @override
  void initState() {
    super.initState();
    editorSessions = ref.read(uiLayoutEditorSessionsProvider);
    editorSessions.open(sessionToken);
    pageId = widget.initialPageId;
    desktop = widget.initialDesktop;
    search = widget.initialEntryId ?? '';
    searchController.text = search;
    selectedId = widget.initialEntryId;
    advanced = widget.initialEntryId != null;
    widget.registry.addListener(_changed);
  }

  void _changed() {
    if (mounted) _update(() => checkedProfile = null);
    inspectorRevision.value++;
  }

  void _update(VoidCallback change) {
    setState(change);
    layoutRevision.value++;
  }

  String _areaTitle(UiLayoutPreviewArea area) => switch (area) {
    UiLayoutPreviewArea.navigation => desktop ? '侧栏导航' : '底部导航',
    UiLayoutPreviewArea.header => '右上角菜单',
    UiLayoutPreviewArea.other => '常用与隐藏入口',
    UiLayoutPreviewArea.all => '入口与页面布局',
  };

  Future<void> _openArea(UiLayoutPreviewArea area) async {
    activeArea = area;
    selectedId = null;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (childContext) => ValueListenableBuilder<int>(
          valueListenable: layoutRevision,
          builder: (_, revision, _) => _buildEditor(childContext, area),
        ),
      ),
    );
    if (!mounted) return;
    _update(() {
      activeArea = UiLayoutPreviewArea.all;
      selectedId = null;
      pageId = null;
    });
  }

  Future<void> _openScope(String? id) async {
    scopeRouteOpen = true;
    advanced = id == null;
    pageId = id;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (c) => ValueListenableBuilder(
          valueListenable: layoutRevision,
          builder: (_, _, _) =>
              _buildEditor(c, UiLayoutPreviewArea.all, inScope: true),
        ),
      ),
    );
    if (mounted) {
      _update(() {
        scopeRouteOpen = false;
        pageId = null;
        advanced = false;
        selectedId = null;
      });
    }
  }

  void _directory() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => EntryDirectoryPage(
        registry: widget.registry,
        openShellEntry: widget.onOpenEntry,
        locateShellEntry: widget.onLocate,
      ),
    ),
  );

  void _drop(UiEntryRegistration entry, UiPlacement placement, int index) {
    if (saving ||
        widget.registry.ui.entries.where((e) => identical(e, entry)).isEmpty ||
        entry.content ||
        !_editable(entry)) {
      return;
    }
    final siblings = orderedEntries(
      widget.registry.ui,
      profile.mountFor,
      (e) => profile.mountFor(e).placement == placement,
    );
    final previous = siblings.indexWhere((e) => e.id == entry.id);
    if (previous >= 0 && (index == previous || index == previous + 1)) return;
    siblings.removeWhere((e) => e.id == entry.id);
    siblings.insert(
      (previous >= 0 && previous < index ? index - 1 : index).clamp(
        0,
        siblings.length,
      ),
      entry,
    );
    var value = profile;
    for (final (i, e) in siblings.indexed) {
      final old = profile.mountFor(e);
      if (old.placement == placement && old.order == i) continue;
      value = value.withMount(
        e.id,
        UiMount(placement: placement, order: i, context: old.context),
      );
    }
    _setProfile(value);
  }

  void _displayOptions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (c) => ValueListenableBuilder(
        valueListenable: layoutRevision,
        builder: (_, _, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDesign.pageGutter,
            0,
            AppDesign.pageGutter,
            20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('导航显示选项', style: Theme.of(c).textTheme.titleLarge),
              SettingsGroup(
                children: [
                  SwitchListTile(
                    key: const ValueKey('layout-more-page-enabled'),
                    title: const Text('启用“更多”页面'),
                    value: profile.morePageEnabled,
                    onChanged: saving
                        ? null
                        : (v) => _setProfile(profile.withMorePageEnabled(v)),
                  ),
                  SettingsEntry(
                    title: '主导航直显上限',
                    subtitle: profile.mainLimit?.toString() ?? '自动',
                    icon: Icons.tune,
                    onTap: _editLimit,
                  ),
                ],
              ),
              const SettingsNote('关闭“更多”后，可从右上角菜单的“全部入口”访问这些工具。'),
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('返回编排'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overview() {
    return DetailPage(
      title: '布局与导航',
      settingsStyle: true,
      child: SettingsList(
        footer: FilledButton(
          onPressed: saving || _changes().isEmpty ? null : () => _save(context),
          child: const Text('保存布局'),
        ),
        children: [
          const SettingsHeading('设备配置'),
          const SizedBox(height: 10),
          SlidingSegments<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('手机 / 窄屏')),
              ButtonSegment(value: true, label: Text('电脑 / 宽屏')),
            ],
            selected: desktop,
            onChanged: (value) => _update(() {
              desktop = value;
              selectedId = null;
              collapsedGroups.clear();
            }),
          ),
          const SizedBox(height: 16),
          TabContentTransition(
            index: desktop ? 1 : 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroup(
                  title: '入口与位置',
                  children: [
                    SettingsEntry(
                      title: '编排入口',
                      subtitle: '把图标拖到导航、菜单或更多',
                      icon: Icons.dashboard_outlined,
                      onTap: () => _openArea(UiLayoutPreviewArea.navigation),
                    ),
                    SettingsEntry(
                      title: '入口目录',
                      subtitle: '打开入口，或查看它在 App 中的位置',
                      icon: Icons.list,
                      onTap: _directory,
                    ),
                    SettingsEntry(
                      title: '常用与隐藏入口',
                      subtitle: '调整设置首页的快捷方式',
                      icon: Icons.push_pin_outlined,
                      onTap: () => _openArea(UiLayoutPreviewArea.other),
                    ),
                  ],
                ),
                SettingsGroup(
                  title: '页面编排',
                  children: [
                    SettingsEntry(
                      title: '页面内容布局',
                      icon: Icons.view_quilt_outlined,
                      onTap: () async {
                        final choices = widget.registry.ui.pages
                            .where((p) => p.slots.isNotEmpty)
                            .toList();
                        final result = await showModalBottomSheet<String>(
                          showDragHandle: true,
                          useSafeArea: true,
                          isScrollControlled: true,
                          context: context,
                          builder: (_) => UiLayoutPicker(
                            title: '选择编辑页面',
                            choices: [
                              for (final p in choices)
                                UiLayoutChoice(
                                  value: p.id,
                                  label: p.title,
                                  detail: p.slots.map((s) => s.label).join('、'),
                                  keywords: p.id,
                                ),
                            ],
                          ),
                        );
                        if (mounted && result != null) await _openScope(result);
                      },
                    ),
                    SettingsEntry(
                      title: '高级编辑',
                      subtitle: warnings.isEmpty
                          ? null
                          : '${warnings.length} 项配置需要检查',
                      icon: Icons.tune,
                      onTap: () => _openScope(null),
                    ),
                  ],
                ),
                SettingsGroup(
                  title: '本次草稿',
                  children: [
                    SettingsEntry(
                      title: '预览结构',
                      icon: Icons.visibility_outlined,
                      onTap: _preview,
                    ),
                    SettingsEntry(
                      title: _changes().isEmpty
                          ? '查看变更'
                          : '查看变更（${_changes().length}）',
                      icon: Icons.compare_arrows,
                      onTap: _reviewChanges,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    editorSessions.close(sessionToken);
    widget.registry.removeListener(_changed);
    searchController.dispose();
    inspectorRevision.dispose();
    layoutRevision.dispose();
    for (final controller in limitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  UiLayoutProfile get profile => draft!.profile(desktop);

  void _markDirty() {
    if (draft == null || baseline == null) return;
    final invalidInput = limitControllers.values.any(
      (controller) =>
          controller.text.isNotEmpty &&
          (int.tryParse(controller.text) ?? 0) < 1,
    );
    editorSessions.markDirty(
      sessionToken,
      invalidInput ||
          canonicalJson(draft!.toJson()) != canonicalJson(baseline!.toJson()),
    );
  }

  void _toggleAdvanced() {
    _update(() {
      advanced = !advanced;
      if (!advanced) {
        searchController.clear();
        search = '';
        onlyProblems = false;
      }
    });
  }

  void _setProfile(UiLayoutProfile value) {
    _update(() {
      draft = UiLayout(
        narrow: desktop ? draft!.narrow : value,
        wide: desktop ? value : draft!.wide,
      );
      error = null;
      checkedProfile = null;
    });
    _markDirty();
    inspectorRevision.value++;
  }

  void _move(UiEntryRegistration entry, UiMount mount) {
    _setProfile(profile.withMount(entry.id, mount));
    if (activeArea == UiLayoutPreviewArea.all) {
      _update(
        () =>
            pageId = mount.placement == UiPlacement.page ? mount.pageId : null,
      );
    }
  }

  bool _validLimits() {
    for (final controller in limitControllers.values) {
      if (controller.text.isNotEmpty &&
          (int.tryParse(controller.text) ?? 0) < 1) {
        _update(() => error = '直显上限须为正整数，留空表示不限制');
        return false;
      }
    }
    return true;
  }

  Future<void> _save(BuildContext editorContext) async {
    if (!_validLimits()) return;
    final savingRoute = ModalRoute.of(editorContext);
    _update(() => saving = true);
    try {
      await ref
          .read(uiLayoutProvider.notifier)
          .saveIfUnchanged(draft!, expected: baseline!);
      if (mounted) {
        baseline = draft;
        _markDirty();
        if (editorContext.mounted && savingRoute?.isCurrent == true) {
          Navigator.of(editorContext).pop();
        }
      }
    } on StateError catch (failure) {
      if (mounted) _update(() => error = '${failure.message}；草稿保留，未覆盖已保存配置');
    } catch (_) {
      if (mounted) _update(() => error = '布局保存失败，草稿保留，请重试');
    } finally {
      if (mounted) _update(() => saving = false);
    }
  }

  void _preview() {
    if (!_validLimits()) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => UiLayoutPreview(
        registry: widget.registry.ui,
        profile: profile,
        desktop: desktop,
        pageId: pageId,
        area: activeArea,
      ),
    );
  }

  void _reset() {
    final mounts = Map<String, UiMount>.of(profile.mounts)
      ..removeWhere((id, mount) {
        final entries = widget.registry.ui.entries.where(
          (entry) => entry.id == id,
        );
        final original = entries.isEmpty ? null : entries.first.defaultMount;
        return pageId == null
            ? mount.placement != UiPlacement.page ||
                  original?.placement != UiPlacement.page
            : (mount.placement == UiPlacement.page && mount.pageId == pageId) ||
                  (original?.placement == UiPlacement.page &&
                      original?.pageId == pageId);
      });
    final value = UiLayoutProfile(
      mainLimit: pageId == null ? (desktop ? null : 4) : profile.mainLimit,
      morePageEnabled: pageId == null ? true : profile.morePageEnabled,
      mounts: mounts,
    );
    _setProfile(value);
    limitControllers[desktop]?.text = value.mainLimit?.toString() ?? '';
    _markDirty();
  }

  bool _editable(UiEntryRegistration entry) {
    final mount = profile.mountFor(entry);
    if (mount.placement != UiPlacement.page) return true;
    final host = widget.registry.ui.page(mount.pageId ?? '');
    final slots = host?.slots.where((slot) => slot.id == mount.slotId);
    return slots == null || slots.isEmpty || slots.first.editable;
  }

  List<(String, UiMount)> _targets(UiEntryRegistration entry) => [
    if (!entry.content)
      for (final placement in UiPlacement.values.where(
        (value) => value != UiPlacement.page,
      ))
        (
          placementLabel(placement),
          UiMount(
            placement: placement,
            context: profile.mountFor(entry).context,
          ),
        ),
    if (entry.content)
      (
        '隐藏',
        UiMount(
          placement: UiPlacement.hidden,
          context: profile.mountFor(entry).context,
        ),
      ),
    for (final host in widget.registry.ui.pages)
      for (final slot in host.slots)
        if (slot.editable &&
            mountProblem(
                  widget.registry.ui,
                  entry,
                  UiMount(
                    placement: UiPlacement.page,
                    pageId: host.id,
                    slotId: slot.id,
                  ),
                  checkContext: false,
                ) ==
                null)
          (
            '${host.title} / ${slot.label}',
            UiMount(
              placement: UiPlacement.page,
              pageId: host.id,
              slotId: slot.id,
              context: profile.mountFor(entry).context,
            ),
          ),
  ];

  Future<void> _context(UiEntryRegistration entry) async {
    try {
      final database = await ref.read(databaseProvider.future);
      if (!mounted) return;
      final mount = profile.mountFor(entry);
      final result = await chooseEntryContext(context, database, mount.context);
      if (result != null && mounted) {
        _move(
          entry,
          UiMount(
            placement: mount.placement,
            pageId: mount.pageId,
            slotId: mount.slotId,
            order: mount.order,
            context: result,
          ),
        );
      }
    } catch (_) {
      if (mounted) _update(() => error = '读取可选上下文失败，请重试');
    }
  }

  (UiPlacement, String?, String?) _groupKey(UiEntryRegistration entry) {
    final mount = profile.mountFor(entry);
    return (mount.placement, mount.pageId, mount.slotId);
  }

  List<UiEntryRegistration> _orderedEntries() {
    final entries = widget.registry.ui.entries.toList();
    final catalogOrder = {
      for (var index = 0; index < entries.length; index++)
        entries[index].id: index,
    };
    entries.sort((first, second) {
      final firstMount = profile.mountFor(first);
      final secondMount = profile.mountFor(second);
      final group = firstMount.placement.index.compareTo(
        secondMount.placement.index,
      );
      if (group != 0) return group;
      final host = (firstMount.pageId ?? '').compareTo(
        secondMount.pageId ?? '',
      );
      if (host != 0) return host;
      final slot = (firstMount.slotId ?? '').compareTo(
        secondMount.slotId ?? '',
      );
      if (slot != 0) return slot;
      final order = firstMount.order.compareTo(secondMount.order);
      return order == 0
          ? catalogOrder[first.id]!.compareTo(catalogOrder[second.id]!)
          : order;
    });
    return entries;
  }

  List<UiEntryRegistration> _siblings(UiEntryRegistration entry) =>
      _orderedEntries()
          .where((other) => _groupKey(other) == _groupKey(entry))
          .toList();

  void _placeAt(UiEntryRegistration entry, int destination) {
    if (saving || !_editable(entry)) return;
    final entries = _siblings(entry)
      ..removeWhere((other) => other.id == entry.id);
    entries.insert(destination.clamp(0, entries.length), entry);
    var value = profile;
    for (var order = 0; order < entries.length; order++) {
      final other = entries[order];
      final mount = profile.mountFor(other);
      value = value.withMount(
        other.id,
        UiMount(
          placement: mount.placement,
          pageId: mount.pageId,
          slotId: mount.slotId,
          order: order,
          context: mount.context,
        ),
      );
    }
    _setProfile(value);
  }

  Future<void> _anchor(UiEntryRegistration entry, bool after) async {
    final selected = await showModalBottomSheet<String>(
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      context: context,
      builder: (_) => UiLayoutPicker<String>(
        title: after ? '移到指定项之后' : '移到指定项之前',
        choices: [
          for (final other in _siblings(entry))
            if (other.id != entry.id)
              UiLayoutChoice(
                value: other.id,
                label: other.label,
                detail: _location(profile.mountFor(other)),
                keywords: '${other.id} ${other.moduleId} ${other.pageId}',
              ),
        ],
      ),
    );
    if (!mounted || selected == null || saving || !_editable(entry)) return;
    final siblings = _siblings(entry)
      ..removeWhere((other) => other.id == entry.id);
    final index = siblings.indexWhere((other) => other.id == selected);
    if (index >= 0) _placeAt(entry, index + (after ? 1 : 0));
  }

  Future<void> _target(UiEntryRegistration entry) async {
    final targets = _targets(entry);
    final selected = await showModalBottomSheet<UiMount>(
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      context: context,
      builder: (_) => UiLayoutPicker<UiMount>(
        title: '选择兼容位置',
        choices: [
          for (final target in targets)
            UiLayoutChoice(
              value: target.$2,
              label: target.$1,
              detail: target.$2.placement == UiPlacement.page
                  ? '页面槽位 · 保留上下文'
                  : '全局入口 · 保留上下文',
              keywords:
                  '${target.$2.pageId ?? ''} ${target.$2.slotId ?? ''} '
                  '${widget.registry.ui.page(target.$2.pageId ?? '')?.moduleId ?? ''}',
            ),
        ],
      ),
    );
    if (selected != null && mounted && !saving && _editable(entry)) {
      _move(entry, selected);
    }
  }

  Future<void> _select(String id, bool split) async {
    _update(() => selectedId = id);
    if (split || inspectorOpen) return;
    inspectorOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .75,
        child: ValueListenableBuilder<int>(
          valueListenable: inspectorRevision,
          builder: (_, revision, _) => _inspector(),
        ),
      ),
    );
    inspectorOpen = false;
  }

  void _status() {
    showModalBottomSheet<void>(
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      context: context,
      builder: (dialogContext) => NativeUi(
        child: SettingsSheet(
          title: const Text('草稿状态'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('变更仅在保存后生效；失效项可以暂时保留，条件恢复后重新使用。'),
                  if (baseline?.warning != null) Text(baseline!.warning!),
                  if (error != null) Text(error!),
                  for (final warning in warnings) Text(warning),
                  for (final entry in widget.registry.ui.entries)
                    if (entryDiagnostics[entry.id] != null)
                      NativeUi(
                        child: ListTile(
                          title: Text(entry.label),
                          subtitle: Text(
                            '${entryDiagnostics[entry.id]!.message}\n${entryDiagnostics[entry.id]!.suggestion}',
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            NativeUi(
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('返回编辑'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitField() => NativeUi(
    child: TextField(
      key: ValueKey('navigation-limit-$desktop'),
      controller: limitControllers[desktop],
      enabled: !saving,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '主导航直显上限',
        hintText: '留空不限制',
        isDense: true,
      ),
      onChanged: (text) {
        final limit = text.isEmpty ? null : int.tryParse(text);
        if (text.isEmpty || (limit != null && limit > 0)) {
          _setProfile(
            UiLayoutProfile(
              mainLimit: limit,
              morePageEnabled: profile.morePageEnabled,
              mounts: profile.mounts,
            ),
          );
        }
        _markDirty();
      },
    ),
  );

  void _editLimit() {
    showModalBottomSheet<void>(
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      context: context,
      builder: (dialogContext) => NativeUi(
        child: SettingsSheet(
          title: const Text('主导航直显上限'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _limitField(),
                const SizedBox(height: 8),
                const Text('不包含“更多”；留空不限制，空间不足时自动减少。'),
              ],
            ),
          ),
          actions: [
            NativeUi(
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('返回编辑'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _buildEditor(context, UiLayoutPreviewArea.all);

  Widget _buildEditor(
    BuildContext context,
    UiLayoutPreviewArea area, {
    bool inScope = false,
  }) {
    final childPage = area != UiLayoutPreviewArea.all;
    final state = childPage
        ? ref.read(uiLayoutProvider)
        : ref.watch(uiLayoutProvider);
    final loaded = state.asData?.value;
    if (draft == null && loaded != null) {
      draft = widget.initialDraft ?? loaded;
      baseline = loaded;
      for (final wide in [false, true]) {
        limitControllers[wide] = TextEditingController(
          text: draft!.profile(wide).mainLimit?.toString() ?? '',
        );
      }
      _markDirty();
    }
    if (draft == null) {
      return NativeUi(
        child: Scaffold(
          appBar: AppBar(title: const Text('布局与导航')),
          body: Center(
            child: state.hasError
                ? NativeUi(
                    child: TextButton(
                      onPressed: () => ref.invalidate(uiLayoutProvider),
                      child: const Text('读取失败，重试'),
                    ),
                  )
                : const NativeUi(child: CircularProgressIndicator()),
          ),
        ),
      );
    }
    if (!identical(checkedProfile, profile)) {
      checkedProfile = profile;
      warnings = compositionWarnings(widget.registry.ui, profile.mountFor);
      entryDiagnostics = {
        for (final entry in widget.registry.ui.entries)
          entry.id: layoutEntryDiagnostic(
            widget.registry.ui,
            entry,
            profile.mountFor,
          ),
      };
    }
    if (area == UiLayoutPreviewArea.navigation ||
        area == UiLayoutPreviewArea.header) {
      return LayoutArranger(
        registry: widget.registry.ui,
        profile: profile,
        desktop: desktop,
        initialZone: area == UiLayoutPreviewArea.header
            ? UiPlacement.header
            : UiPlacement.main,
        onSelect: (id) => _select(id, false),
        canMove: _editable,
        onDrop: _drop,
        dirty: _changes().isNotEmpty,
        saving: saving,
        error: error,
        onSave: () => _save(context),
        onDirectory: _directory,
        onOptions: _displayOptions,
      );
    }
    if (!childPage &&
        ((!inScope && scopeRouteOpen) || (!advanced && pageId == null))) {
      return _overview();
    }
    final pages = widget.registry.ui.pages
        .where((page) => page.slots.isNotEmpty)
        .toList();
    final dormantPageIds = {
      for (final entry in widget.registry.ui.entries)
        if (profile.mountFor(entry).placement == UiPlacement.page &&
            profile.mountFor(entry).pageId != null)
          profile.mountFor(entry).pageId!,
      for (final mount in profile.mounts.values)
        if (mount.placement == UiPlacement.page && mount.pageId != null)
          mount.pageId!,
      ?pageId,
    }..removeAll(pages.map((page) => page.id));
    final entries = _orderedEntries().where((entry) {
      final mount = profile.mountFor(entry);
      return pageId == null
          ? mount.placement != UiPlacement.page
          : mount.placement == UiPlacement.page && mount.pageId == pageId;
    }).toList();
    final query = search.trim().toLowerCase();
    bool matches(UiEntryRegistration entry) {
      final diagnostic = entryDiagnostics[entry.id];
      if (onlyProblems && diagnostic == null) return false;
      return query.isEmpty ||
          '${entry.label} ${entry.id} ${entry.moduleId} ${entry.pageId} '
                  '${_location(profile.mountFor(entry))} ${diagnostic?.message ?? ''}'
              .toLowerCase()
              .contains(query);
    }

    final visibleEntries = entries.where(matches).toList();
    final orphans = profile.mounts.entries
        .where(
          (item) =>
              !widget.registry.ui.entries.any(
                (entry) => entry.id == item.key,
              ) &&
              (query.isEmpty ||
                  '${item.key} ${_location(item.value)}'.toLowerCase().contains(
                    query,
                  )) &&
              (pageId == null
                  ? item.value.placement != UiPlacement.page
                  : item.value.pageId == pageId),
        )
        .toList();
    final groups =
        <(UiPlacement, String?, String?), List<UiEntryRegistration>>{};
    for (final entry in visibleEntries) {
      groups.putIfAbsent(_groupKey(entry), () => []).add(entry);
    }
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final compactToolbar = MediaQuery.sizeOf(context).width < 720 * textScale;
    final split = MediaQuery.sizeOf(context).width >= 1000 * textScale;
    final showTools = !childPage && (pageId != null || advanced);
    if (!positioned) {
      positioned = true;
      if (widget.initialEntryId != null && !split) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _select(widget.initialEntryId!, false);
        });
      }
    }
    final groupTotals = <(UiPlacement, String?, String?), int>{};
    final entryPositions = <String, int>{};
    for (final entry in entries) {
      final key = _groupKey(entry);
      groupTotals[key] = (groupTotals[key] ?? 0) + 1;
      entryPositions[entry.id] = groupTotals[key]!;
    }
    final rows = <Widget Function()>[];
    for (final group in groups.entries) {
      final mount = profile.mountFor(group.value.first);
      final slots = widget.registry.ui
          .page(mount.pageId ?? '')
          ?.slots
          .where((slot) => slot.id == mount.slotId);
      final label = mount.placement != UiPlacement.page
          ? placementLabel(mount.placement)
          : slots == null || slots.isEmpty
          ? '失效槽位 · ${mount.slotId}'
          : slots.first.label;
      final total = groupTotals[group.key]!;
      final collapsed = collapsedGroups.contains(group.key);
      rows.add(
        () => NativeUi(
          child: ListTile(
            key: ValueKey('layout-group-${group.key}'),
            dense: true,
            title: Text('$label · ${group.value.length} / $total'),
            leading: UiIcon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
            ),
            onTap: () => _update(() {
              if (collapsed) {
                collapsedGroups.remove(group.key);
              } else {
                collapsedGroups.add(group.key);
              }
            }),
          ),
        ),
      );
      if (!collapsed) {
        for (final entry in group.value) {
          final diagnostic = entryDiagnostics[entry.id];
          rows.add(
            () => NativeUi(
              child: ListTile(
                key: ValueKey('layout-row-${entry.id}'),
                dense: true,
                selected: selectedId == entry.id,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                leading: UiIcon(
                  diagnostic == null
                      ? entry.icon
                      : diagnostic.issue == UiMountIssue.missingContext
                      ? Icons.info_outline
                      : Icons.warning_amber_outlined,
                ),
                title: Text(entry.label),
                subtitle: Text(
                  '${showIdentifiers ? '模块：${entry.moduleId} · ${entry.id}\n' : ''}'
                  '${_location(profile.mountFor(entry), position: entryPositions[entry.id])}'
                  '${diagnostic == null ? '' : ' · ${diagnostic.issue == UiMountIssue.missingContext ? '上下文待检查' : '失效'}'}',
                  maxLines: showIdentifiers ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: UiIcon(
                  _editable(entry) ? Icons.chevron_right : Icons.lock_outline,
                ),
                onTap: saving ? null : () => _select(entry.id, split),
              ),
            ),
          );
        }
      }
    }
    if (orphans.isNotEmpty) {
      const orphanKey = (UiPlacement.hidden, null, '__orphans');
      final collapsed = collapsedGroups.contains(orphanKey);
      rows.add(
        () => NativeUi(
          child: ListTile(
            dense: true,
            title: Text('不可用贡献 · ${orphans.length}'),
            leading: UiIcon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
            ),
            onTap: () => _update(() {
              if (collapsed) {
                collapsedGroups.remove(orphanKey);
              } else {
                collapsedGroups.add(orphanKey);
              }
            }),
          ),
        ),
      );
      if (!collapsed) {
        for (final orphan in orphans) {
          rows.add(
            () => NativeUi(
              child: ListTile(
                key: ValueKey('layout-row-${orphan.key}'),
                dense: true,
                selected: selectedId == orphan.key,
                leading: const UiIcon(Icons.warning_amber_outlined),
                title: Text(orphan.key),
                subtitle: const Text('模块或入口不可用，配置已保留'),
                onTap: saving ? null : () => _select(orphan.key, split),
              ),
            ),
          );
        }
      }
    }
    final entryList = rows.isEmpty
        ? const Center(child: Text('当前范围没有符合条件的入口或内容。'))
        : ListView.builder(
            key: ValueKey('layout-list-$desktop-$pageId'),
            itemCount: rows.length,
            itemBuilder: (_, index) => rows[index](),
          );
    final problemCount =
        entryDiagnostics.values.where((value) => value != null).length +
        profile.mounts.keys
            .where(
              (id) =>
                  !widget.registry.ui.entries.any((entry) => entry.id == id),
            )
            .length;
    final profileSelector = NativeUi(
      child: SlidingSegments<bool>(
        minSegmentWidth: compactToolbar ? 48 : 100,
        segments: [
          ButtonSegment(
            value: false,
            tooltip: '手机 / 窄屏',
            label: compactToolbar ? null : const Text('手机 / 窄屏'),
            icon: compactToolbar ? const UiIcon(Icons.phone_android) : null,
          ),
          ButtonSegment(
            value: true,
            tooltip: '电脑 / 宽屏',
            label: compactToolbar ? null : const Text('电脑 / 宽屏'),
            icon: compactToolbar ? const UiIcon(Icons.laptop) : null,
          ),
        ],
        selected: desktop,
        onChanged: saving
            ? null
            : (value) => _update(() {
                desktop = value;
                selectedId = null;
                collapsedGroups.clear();
              }),
      ),
    );
    final scopeSelector = NativeUi(
      child: DropdownButtonFormField<String>(
        borderRadius: AppDesign.selectionBorderRadius,
        key: ValueKey('layout-scope-$pageId'),
        initialValue: pageId ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: '编辑区域', isDense: true),
        items: [
          const DropdownMenuItem(
            value: '',
            child: Text('导航与菜单', overflow: TextOverflow.ellipsis),
          ),
          for (final page in pages)
            DropdownMenuItem(
              value: page.id,
              child: Text(
                '${page.title}${showIdentifiers ? ' · ${page.id}' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          for (final id in dormantPageIds)
            DropdownMenuItem(
              value: id,
              child: Text('失效页面配置 · $id', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: saving
            ? null
            : (value) => _update(() {
                pageId = value == '' ? null : value;
                selectedId = null;
              }),
      ),
    );
    final searchField = NativeUi(
      child: TextField(
        key: const ValueKey('layout-search'),
        controller: searchController,
        enabled: !saving,
        decoration: InputDecoration(
          labelText: '搜索入口、模块、页面或位置',
          isDense: true,
          prefixIcon: const UiIcon(Icons.search),
          suffixIcon: search.isEmpty
              ? null
              : NativeUi(
                  child: IconButton(
                    tooltip: '清空搜索',
                    onPressed: () {
                      searchController.clear();
                      _update(() => search = '');
                    },
                    icon: const UiIcon(Icons.clear),
                  ),
                ),
        ),
        onChanged: (value) => _update(() => search = value),
      ),
    );
    final list = area == UiLayoutPreviewArea.other
        ? SettingsList(
            children: [
              if (_changes().isNotEmpty)
                SettingsEntry(
                  title: '查看变更（${_changes().length}）',
                  icon: Icons.compare_arrows,
                  onTap: _reviewChanges,
                ),
              UiLayoutNavigationPreview(
                registry: widget.registry.ui,
                profile: profile,
                desktop: desktop,
                selectedId: selectedId,
                onSelected: saving ? null : (id) => _select(id, split),
                area: area,
              ),
            ],
          )
        : entryList;
    if (compactToolbar && showTools) {
      return Scaffold(
        appBar: AppBar(title: Text(pageId == null ? '高级编辑' : '页面内容布局')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  key: ValueKey('layout-list-$pageId'),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppDesign.pageGutter,
                        8,
                        AppDesign.pageGutter,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            profileSelector,
                            const SizedBox(height: 12),
                            if (advanced) searchField,
                            const SizedBox(height: 8),
                            SettingsGroup(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: scopeSelector,
                                ),
                                if (advanced) ...[
                                  SwitchListTile(
                                    title: const Text('仅失效 / 待检查'),
                                    value: onlyProblems,
                                    onChanged: saving
                                        ? null
                                        : (v) =>
                                              _update(() => onlyProblems = v),
                                  ),
                                  SwitchListTile(
                                    title: const Text('显示技术标识'),
                                    value: showIdentifiers,
                                    onChanged: (v) =>
                                        _update(() => showIdentifiers = v),
                                  ),
                                ],
                                if (pageId == null)
                                  SettingsEntry(
                                    title: '主导航直显上限',
                                    subtitle:
                                        profile.mainLimit?.toString() ?? '自动',
                                    icon: Icons.tune,
                                    onTap: _editLimit,
                                  ),
                              ],
                            ),
                            Text(
                              pageId == null ? '按位置浏览' : '页面槽位',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: TabContentTransition.sliver(
                        index: desktop ? 1 : 0,
                        child: SliverList.builder(
                          itemCount: rows.length,
                          itemBuilder: (_, i) => rows[i](),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppDesign.pageGutter,
                        8,
                        AppDesign.pageGutter,
                        18,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: SettingsGroup(
                          children: [
                            if (rows.isEmpty)
                              const SettingsNote('当前范围没有符合条件的入口或内容。'),
                            if (pageId != null)
                              SettingsEntry(
                                title: '添加入口或内容',
                                icon: Icons.add,
                                onTap: _add,
                                enabled: !saving,
                              ),
                            SettingsEntry(
                              title: '草稿状态',
                              subtitle: problemCount == 0
                                  ? '所有入口均可用'
                                  : '$problemCount 项配置需要检查',
                              icon: Icons.info_outline,
                              onTap: _status,
                            ),
                            SettingsEntry(
                              title: '查看变更（${_changes().length}）',
                              icon: Icons.compare_arrows,
                              onTap: _reviewChanges,
                            ),
                            SettingsEntry(
                              title: '恢复当前范围默认',
                              icon: Icons.restore,
                              onTap: _reset,
                              enabled: !saving,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : _preview,
                        child: const Text('预览草稿'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving || _changes().isEmpty
                            ? null
                            : () => _save(context),
                        child: const Text('保存布局'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return NativeUi(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            area == UiLayoutPreviewArea.all
                ? (pageId != null ? '页面内容布局' : '高级编辑')
                : _areaTitle(area),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!showTools)
              NativeUi(
                child: IconButton(
                  tooltip: '预览草稿',
                  onPressed: saving ? null : _preview,
                  icon: const UiIcon(Icons.visibility_outlined),
                ),
              ),
            if (!inScope && pageId == null && !childPage)
              NativeUi(
                child: IconButton(
                  tooltip: advanced ? '返回可视编辑' : '高级编辑',
                  onPressed: saving ? null : _toggleAdvanced,
                  icon: UiIcon(
                    advanced ? Icons.dashboard_outlined : Icons.tune,
                  ),
                ),
              ),
            NativeUi(
              child: TextButton(
                onPressed: saving ? null : () => _save(context),
                child: Text(saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (!childPage)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    profileSelector,
                    const SizedBox(width: 8),
                    Expanded(child: scopeSelector),
                    if (pageId == null && showTools) ...[
                      const SizedBox(width: 8),
                      if (compactToolbar)
                        NativeUi(
                          child: IconButton(
                            tooltip: '主导航直显上限',
                            onPressed: saving ? null : _editLimit,
                            icon: const UiIcon(Icons.tune),
                          ),
                        )
                      else
                        SizedBox(width: 160 * textScale, child: _limitField()),
                    ],
                  ],
                ),
              ),
            if (showTools)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: searchField,
              ),
            if (showTools)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    NativeUi(
                      child: TextButton(
                        onPressed: _reviewChanges,
                        child: Text('查看变更（${_changes().length}）'),
                      ),
                    ),
                    NativeUi(
                      child: TextButton(
                        onPressed: _status,
                        child: Text('状态（$problemCount）'),
                      ),
                    ),
                    NativeUi(
                      child: FilterChip(
                        label: const Text('仅失效 / 待检查'),
                        selected: onlyProblems,
                        onSelected: saving
                            ? null
                            : (value) => _update(() => onlyProblems = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    NativeUi(
                      child: FilterChip(
                        label: const Text('显示技术标识'),
                        selected: showIdentifiers,
                        onSelected: (value) =>
                            _update(() => showIdentifiers = value),
                      ),
                    ),
                    NativeUi(
                      child: TextButton.icon(
                        onPressed: saving ? null : _preview,
                        icon: const UiIcon(Icons.visibility_outlined),
                        label: const Text('预览草稿'),
                      ),
                    ),
                    if (pageId != null)
                      NativeUi(
                        child: TextButton(
                          onPressed: saving ? null : _add,
                          child: const Text('添加入口或内容'),
                        ),
                      ),
                    NativeUi(
                      child: TextButton(
                        onPressed: saving ? null : _reset,
                        child: const Text('恢复当前范围默认'),
                      ),
                    ),
                    NativeUi(
                      child: TextButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                  ],
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: TabContentTransition(
                index: desktop ? 1 : 0,
                child: split && (showTools || (childPage && selectedId != null))
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: list),
                          const VerticalDivider(width: 1),
                          SizedBox(width: 360 * textScale, child: _inspector()),
                        ],
                      )
                    : list,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final host = widget.registry.ui.page(pageId ?? '');
    if (host == null) return;
    final choices = <UiLayoutChoice<(UiEntryRegistration, UiMount)>>[
      for (final entry in widget.registry.ui.entries)
        if (_editable(entry))
          for (final target in _targets(entry))
            if (target.$2.pageId == host.id)
              UiLayoutChoice(
                value: (entry, target.$2),
                label: entry.label,
                detail: target.$1,
                keywords: '${entry.id} ${entry.moduleId} ${entry.pageId}',
              ),
    ];
    final selected = await showModalBottomSheet<(UiEntryRegistration, UiMount)>(
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      context: context,
      builder: (_) => UiLayoutPicker(title: '选择贡献与槽位', choices: choices),
    );
    if (selected != null && mounted && !saving && _editable(selected.$1)) {
      _move(selected.$1, selected.$2);
      _update(() => selectedId = selected.$1.id);
    }
  }
}
