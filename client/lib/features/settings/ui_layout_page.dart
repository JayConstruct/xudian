import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
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

class UiLayoutPage extends ConsumerStatefulWidget {
  const UiLayoutPage({
    super.key,
    required this.registry,
    this.initialDraft,
    this.initialPageId,
    this.initialEntryId,
    this.initialDesktop = false,
  });

  final ModuleRegistry registry;
  final UiLayout? initialDraft;
  final String? initialPageId;
  final String? initialEntryId;
  final bool initialDesktop;

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
    showDialog<void>(
      context: context,
      builder: (_) => UiLayoutPreview(
        registry: widget.registry.ui,
        profile: profile,
        desktop: desktop,
        pageId: pageId,
        area: activeArea,
      ),
    );
  }

  String _location(UiMount? mount, {int? position}) {
    if (mount == null) return '无配置';
    final host = widget.registry.ui.page(mount.pageId ?? '');
    final slots = host?.slots.where((slot) => slot.id == mount.slotId);
    final location = mount.placement == UiPlacement.page
        ? '${host?.title ?? '不可用页面'} / '
              '${slots == null || slots.isEmpty ? '不可用槽位' : slots.first.label}'
        : placementLabel(mount.placement);
    return '$location · ${position == null ? '排序值 ${mount.order}' : '第 $position 项'}'
        '${mount.context.taskId == null ? '' : ' · 指定任务'}'
        '${mount.context.projectId == null ? '' : ' · 指定项目'}';
  }

  List<(String, String, String)> _changes() {
    if (baseline == null || draft == null) return const [];
    final entries = {
      for (final entry in widget.registry.ui.entries) entry.id: entry,
    };
    return [
      for (final wide in [false, true]) ...[
        if (baseline!.profile(wide).mainLimit != draft!.profile(wide).mainLimit)
          (
            '${wide ? '宽屏' : '窄屏'} · 主导航直显上限',
            baseline!.profile(wide).mainLimit?.toString() ?? '不限制',
            draft!.profile(wide).mainLimit?.toString() ?? '不限制',
          ),
        for (final id in {
          ...baseline!.profile(wide).mounts.keys,
          ...draft!.profile(wide).mounts.keys,
        })
          if (baseline!.profile(wide).mounts[id] !=
              draft!.profile(wide).mounts[id])
            (
              '${wide ? '宽屏' : '窄屏'} · ${entries[id]?.label ?? id}',
              '${_location(baseline!.profile(wide).mounts[id] ?? entries[id]?.defaultMount)}'
                  '${baseline!.profile(wide).mounts.containsKey(id) ? '' : '（模块默认）'}',
              '${_location(draft!.profile(wide).mounts[id] ?? entries[id]?.defaultMount)}'
                  '${draft!.profile(wide).mounts.containsKey(id) ? '' : '（模块默认）'}'
                  '${(baseline!.profile(wide).mounts[id] ?? entries[id]?.defaultMount)?.context != (draft!.profile(wide).mounts[id] ?? entries[id]?.defaultMount)?.context ? ' · 上下文配置有变化' : ''}',
            ),
      ],
    ];
  }

  void _reviewChanges() {
    final changes = _changes();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('草稿变更 · ${changes.length} 项'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('包括两套屏幕配置和所有编排范围；尚未保存。'),
                if (changes.isEmpty) const Text('与进入编辑器时的配置一致。'),
                for (final change in changes)
                  ListTile(
                    title: Text(change.$1),
                    subtitle: Text('原：${change.$2}\n新：${change.$3}'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('返回编辑'),
          ),
        ],
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
      final tasks = await database.select(database.tasks).get();
      final projects = await database.select(database.projects).get();
      if (!mounted) return;
      final mount = profile.mountFor(entry);
      String? taskId = tasks.any((task) => task.id == mount.context.taskId)
          ? mount.context.taskId
          : null;
      String? projectId =
          projects.any((project) => project.id == mount.context.projectId)
          ? mount.context.projectId
          : null;
      final result = await showDialog<PageContext>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('补充上下文'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('未指定的上下文由宿主提供；选择具体对象不会增加模块权限。'),
                  DropdownButtonFormField<String>(
                    borderRadius: AppDesign.selectionBorderRadius,
                    initialValue: taskId ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '任务'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('由宿主提供')),
                      for (final task in tasks)
                        DropdownMenuItem(
                          value: task.id,
                          child: Text(
                            task.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        update(() => taskId = value == '' ? null : value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    borderRadius: AppDesign.selectionBorderRadius,
                    initialValue: projectId ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '项目'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('由宿主提供')),
                      for (final project in projects)
                        DropdownMenuItem(
                          value: project.id,
                          child: Text(
                            project.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        update(() => projectId = value == '' ? null : value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  PageContext(taskId: taskId, projectId: projectId),
                ),
                child: const Text('使用此上下文'),
              ),
            ],
          ),
        ),
      );
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
    final selected = await showDialog<String>(
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
    final selected = await showDialog<UiMount>(
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

  Widget _inspector() {
    final entries = widget.registry.ui.entries.where(
      (entry) => entry.id == selectedId,
    );
    if (entries.isEmpty) {
      final mount = profile.mounts[selectedId];
      if (mount == null) {
        return const Center(child: Text('选择一项以编辑位置、顺序和上下文'));
      }
      return ListView(
        key: const ValueKey('layout-inspector'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '编辑 · $selectedId',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(_location(mount)),
          const Text('模块或入口不可用，配置已保留；恢复模块后可重新使用。'),
          TextButton.icon(
            onPressed: saving
                ? null
                : () {
                    _setProfile(profile.withoutMount(selectedId!));
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('清理失效配置'),
          ),
        ],
      );
    }
    final entry = entries.single;
    final mount = profile.mountFor(entry);
    final diagnostic = layoutEntryDiagnostic(
      widget.registry.ui,
      entry,
      profile.mountFor,
    );
    final editable = !saving && _editable(entry);
    final siblings = _siblings(entry);
    final index = siblings.indexWhere((other) => other.id == entry.id);
    final filtered = search.trim().isNotEmpty || onlyProblems;
    return ListView(
      key: const ValueKey('layout-inspector'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '编辑 · ${entry.label}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '${_location(mount, position: index + 1)} · ${entry.content ? '嵌入内容' : openingLabel(entry.opening)}',
        ),
        if (showIdentifiers)
          Text('${entry.id}\n模块：${entry.moduleId}\n页面：${entry.pageId}'),
        if (!editable && !saving) const Text('模块固定槽位，不可调整位置、顺序或上下文。'),
        if (mount.placement == UiPlacement.page)
          for (final slot
              in widget.registry.ui.page(mount.pageId ?? '')?.slots ??
                  const <PageSlotDefinition>[])
            if (slot.id == mount.slotId)
              Text(
                '${slot.label} · ${slot.isPublic ? '公开' : '私有'} · '
                '${slotKindLabel(slot.kind)} · ${slot.editable ? '可编排' : '模块固定'}'
                '${slot.capacity == null ? '' : ' · 容量 ${slot.capacity}'}',
              ),
        if (diagnostic != null) ...[
          const SizedBox(height: 12),
          Text(
            '${diagnostic.issue == UiMountIssue.missingContext ? '上下文待检查' : '失效'}：${diagnostic.message}\n${diagnostic.suggestion}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('配置保持不变，条件恢复后可重新使用'))),
            child: const Text('暂时保留'),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: editable ? () => _target(entry) : null,
          icon: const Icon(Icons.place_outlined),
          label: const Text('调整位置'),
        ),
        const SizedBox(height: 16),
        Text('分组顺序 · ${index + 1} / ${siblings.length}'),
        Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: '上移',
              onPressed: editable && !filtered && index > 0
                  ? () => _placeAt(entry, index - 1)
                  : null,
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: '下移',
              onPressed: editable && !filtered && index < siblings.length - 1
                  ? () => _placeAt(entry, index + 1)
                  : null,
              icon: const Icon(Icons.arrow_downward),
            ),
            TextButton(
              onPressed: editable && index > 0
                  ? () => _placeAt(entry, 0)
                  : null,
              child: const Text('置顶'),
            ),
            TextButton(
              onPressed: editable && index < siblings.length - 1
                  ? () => _placeAt(entry, siblings.length - 1)
                  : null,
              child: const Text('置底'),
            ),
            TextButton(
              onPressed: editable && siblings.length > 1
                  ? () => _anchor(entry, false)
                  : null,
              child: const Text('移到指定项之前'),
            ),
            TextButton(
              onPressed: editable && siblings.length > 1
                  ? () => _anchor(entry, true)
                  : null,
              child: const Text('移到指定项之后'),
            ),
          ],
        ),
        if (filtered) const Text('筛选时暂停相邻上移 / 下移；置顶、置底及指定锚点始终基于完整分组。'),
        const SizedBox(height: 12),
        TextButton(
          onPressed: editable ? () => _context(entry) : null,
          child: const Text('补充上下文'),
        ),
        if (profile.mounts.containsKey(entry.id))
          TextButton(
            onPressed: editable
                ? () => _setProfile(profile.withoutMount(entry.id))
                : null,
            child: const Text('恢复此项默认'),
          ),
        if (mount.placement == UiPlacement.page)
          TextButton(
            onPressed: editable
                ? () => _move(
                    entry,
                    UiMount(
                      placement: UiPlacement.hidden,
                      context: mount.context,
                    ),
                  )
                : null,
            child: const Text('移除挂载'),
          ),
      ],
    );
  }

  void _status() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
                    ListTile(
                      title: Text(entry.label),
                      subtitle: Text(
                        '${entryDiagnostics[entry.id]!.message}\n${entryDiagnostics[entry.id]!.suggestion}',
                      ),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('返回编辑'),
          ),
        ],
      ),
    );
  }

  Widget _limitField() => TextField(
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
        _setProfile(UiLayoutProfile(mainLimit: limit, mounts: profile.mounts));
      }
      _markDirty();
    },
  );

  void _editLimit() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('返回编辑'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _buildEditor(context, UiLayoutPreviewArea.all);

  Widget _buildEditor(BuildContext context, UiLayoutPreviewArea area) {
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
      return Scaffold(
        appBar: AppBar(title: const Text('入口与页面布局')),
        body: Center(
          child: state.hasError
              ? TextButton(
                  onPressed: () => ref.invalidate(uiLayoutProvider),
                  child: const Text('读取失败，重试'),
                )
              : const CircularProgressIndicator(),
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
        () => ListTile(
          key: ValueKey('layout-group-${group.key}'),
          dense: true,
          title: Text('$label · ${group.value.length} / $total'),
          leading: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
          onTap: () => _update(() {
            if (collapsed) {
              collapsedGroups.remove(group.key);
            } else {
              collapsedGroups.add(group.key);
            }
          }),
        ),
      );
      if (!collapsed) {
        for (final entry in group.value) {
          final diagnostic = entryDiagnostics[entry.id];
          rows.add(
            () => ListTile(
              key: ValueKey('layout-row-${entry.id}'),
              dense: true,
              selected: selectedId == entry.id,
              selectedTileColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer,
              leading: Icon(
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
              trailing: Icon(
                _editable(entry) ? Icons.chevron_right : Icons.lock_outline,
              ),
              onTap: saving ? null : () => _select(entry.id, split),
            ),
          );
        }
      }
    }
    if (orphans.isNotEmpty) {
      const orphanKey = (UiPlacement.hidden, null, '__orphans');
      final collapsed = collapsedGroups.contains(orphanKey);
      rows.add(
        () => ListTile(
          dense: true,
          title: Text('不可用贡献 · ${orphans.length}'),
          leading: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
          onTap: () => _update(() {
            if (collapsed) {
              collapsedGroups.remove(orphanKey);
            } else {
              collapsedGroups.add(orphanKey);
            }
          }),
        ),
      );
      if (!collapsed) {
        for (final orphan in orphans) {
          rows.add(
            () => ListTile(
              key: ValueKey('layout-row-${orphan.key}'),
              dense: true,
              selected: selectedId == orphan.key,
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text(orphan.key),
              subtitle: const Text('模块或入口不可用，配置已保留'),
              onTap: saving ? null : () => _select(orphan.key, split),
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
    final list = pageId == null && !advanced
        ? ListView(
            key: const ValueKey('layout-visual-editor'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                childPage
                    ? '点选入口调整位置、顺序或隐藏。修改后，保存才会应用。'
                    : '选择需要调整的区域，返回此页会保留未保存的修改。',
              ),
              if (_changes().isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _reviewChanges,
                    child: Text('查看变更（${_changes().length}）'),
                  ),
                ),
              const SizedBox(height: 20),
              if (childPage)
                UiLayoutNavigationPreview(
                  registry: widget.registry.ui,
                  profile: profile,
                  desktop: desktop,
                  selectedId: selectedId,
                  onSelected: saving ? null : (id) => _select(id, split),
                  onEditLimit: saving || area != UiLayoutPreviewArea.navigation
                      ? null
                      : _editLimit,
                  area: area,
                ),
              if (!childPage)
                SettingsGroup(
                  children: [
                    SettingsEntry(
                      title: desktop ? '侧栏导航' : '底部导航',
                      subtitle: orderedEntries(
                        widget.registry.ui,
                        profile.mountFor,
                        (entry) =>
                            profile.mountFor(entry).placement ==
                            UiPlacement.main,
                      ).map((entry) => entry.label).join('、'),
                      icon: desktop
                          ? Icons.view_sidebar_outlined
                          : Icons.view_week_outlined,
                      enabled: !saving,
                      onTap: () => _openArea(UiLayoutPreviewArea.navigation),
                    ),
                    SettingsEntry(
                      title: '右上角菜单',
                      subtitle: [
                        ...orderedEntries(
                          widget.registry.ui,
                          profile.mountFor,
                          (entry) =>
                              profile.mountFor(entry).placement ==
                              UiPlacement.header,
                        ).map((entry) => entry.label),
                        '设置（固定）',
                      ].join('、'),
                      icon: Icons.more_vert,
                      enabled: !saving,
                      onTap: () => _openArea(UiLayoutPreviewArea.header),
                    ),
                    SettingsEntry(
                      title: '常用与隐藏入口',
                      subtitle: '调整设置常用入口，恢复或移动隐藏入口',
                      icon: Icons.visibility_outlined,
                      enabled: !saving,
                      onTap: () => _openArea(UiLayoutPreviewArea.other),
                    ),
                  ],
                ),
              if (!childPage && problemCount > 0)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text('$problemCount 项配置需要检查'),
                  subtitle: const Text('可在高级编辑中查看和修复'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _update(() => advanced = true),
                ),
              if (!childPage)
                TextButton.icon(
                  onPressed: () => _update(() => advanced = true),
                  icon: const Icon(Icons.tune),
                  label: const Text('高级编辑'),
                ),
            ],
          )
        : entryList;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _areaTitle(area),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!showTools)
            IconButton(
              tooltip: '预览草稿',
              onPressed: saving ? null : _preview,
              icon: const Icon(Icons.visibility_outlined),
            ),
          if (pageId == null && !childPage)
            IconButton(
              tooltip: advanced ? '返回可视编辑' : '高级编辑',
              onPressed: saving ? null : _toggleAdvanced,
              icon: Icon(advanced ? Icons.dashboard_outlined : Icons.tune),
            ),
          TextButton(
            onPressed: saving ? null : () => _save(context),
            child: Text(saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!childPage)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: !compactToolbar,
                    segments: [
                      ButtonSegment(
                        value: false,
                        tooltip: '手机 / 窄屏',
                        label: compactToolbar ? null : const Text('手机 / 窄屏'),
                        icon: compactToolbar
                            ? const Icon(Icons.phone_android)
                            : null,
                      ),
                      ButtonSegment(
                        value: true,
                        tooltip: '电脑 / 宽屏',
                        label: compactToolbar ? null : const Text('电脑 / 宽屏'),
                        icon: compactToolbar ? const Icon(Icons.laptop) : null,
                      ),
                    ],
                    selected: {desktop},
                    onSelectionChanged: saving
                        ? null
                        : (value) => _update(() {
                            desktop = value.single;
                            selectedId = null;
                            collapsedGroups.clear();
                          }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppDesign.selectionBorderRadius,
                      key: ValueKey('layout-scope-$pageId'),
                      initialValue: pageId ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '编辑区域',
                        isDense: true,
                      ),
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
                            child: Text(
                              '失效页面配置 · $id',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => _update(() {
                              pageId = value == '' ? null : value;
                              selectedId = null;
                            }),
                    ),
                  ),
                  if (pageId == null && showTools) ...[
                    const SizedBox(width: 8),
                    if (compactToolbar)
                      IconButton(
                        tooltip: '主导航直显上限',
                        onPressed: saving ? null : _editLimit,
                        icon: const Icon(Icons.tune),
                      )
                    else
                      SizedBox(width: 160 * textScale, child: _limitField()),
                  ],
                ],
              ),
            ),
          if (showTools)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: TextField(
                key: const ValueKey('layout-search'),
                controller: searchController,
                enabled: !saving,
                decoration: InputDecoration(
                  labelText: '搜索入口、模块、页面或位置',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () {
                            searchController.clear();
                            _update(() => search = '');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
                onChanged: (value) => _update(() => search = value),
              ),
            ),
          if (showTools)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _reviewChanges,
                    child: Text('查看变更（${_changes().length}）'),
                  ),
                  TextButton(
                    onPressed: _status,
                    child: Text('状态（$problemCount）'),
                  ),
                  FilterChip(
                    label: const Text('仅失效 / 待检查'),
                    selected: onlyProblems,
                    onSelected: saving
                        ? null
                        : (value) => _update(() => onlyProblems = value),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('显示技术标识'),
                    selected: showIdentifiers,
                    onSelected: (value) =>
                        _update(() => showIdentifiers = value),
                  ),
                  TextButton.icon(
                    onPressed: saving ? null : _preview,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('预览草稿'),
                  ),
                  if (pageId != null)
                    TextButton(
                      onPressed: saving ? null : _add,
                      child: const Text('添加入口或内容'),
                    ),
                  TextButton(
                    onPressed: saving ? null : _reset,
                    child: const Text('恢复当前范围默认'),
                  ),
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
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
        ],
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
    final selected = await showDialog<(UiEntryRegistration, UiMount)>(
      context: context,
      builder: (_) => UiLayoutPicker(title: '选择贡献与槽位', choices: choices),
    );
    if (selected != null && mounted && !saving && _editable(selected.$1)) {
      _move(selected.$1, selected.$2);
      _update(() => selectedId = selected.$1.id);
    }
  }
}
