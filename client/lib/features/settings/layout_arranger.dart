import '../../app/workspace_sidebar_item.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../app/mobile_bottom_dock.dart';
import '../../app/more_workspace_page.dart';
import '../../core/module_host/time_grid.dart';
import '../../core/ui/app_destination.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_layout_resolver.dart';
import '../../core/ui/ui_registry.dart';
import '../../core/ui/ui_registration.dart';
import '../../core/ui/ui_slot.dart';
import '../../core/ui/ui_icon.dart';
import '../../core/ui/workspace_popup_menu.dart';
import 'settings_widgets.dart';
import 'ui_layout.dart';
import 'ui_layout_picker.dart';

class LayoutArranger extends StatefulWidget {
  const LayoutArranger({
    super.key,
    required this.registry,
    required this.profile,
    required this.desktop,
    required this.initialZone,
    required this.onSelect,
    required this.canMove,
    required this.onDrop,
    required this.onSave,
    required this.onDirectory,
    required this.onOptions,
    required this.dirty,
    this.error,
    this.saving = false,
  });
  final UiRegistry registry;
  final UiLayoutProfile profile;
  final bool desktop, dirty, saving;
  final String? error;
  final UiPlacement initialZone;
  final ValueChanged<String> onSelect;
  final bool Function(UiEntryRegistration) canMove;
  final void Function(UiEntryRegistration, UiPlacement, int) onDrop;
  final VoidCallback onSave, onDirectory, onOptions;

  @override
  State<LayoutArranger> createState() => _LayoutArrangerState();
}

class _LayoutArrangerState extends State<LayoutArranger> {
  late UiPlacement zone = widget.initialZone;
  String? dragging;
  final previewScroll = ScrollController();
  @override
  void dispose() {
    previewScroll.dispose();
    super.dispose();
  }

  List<UiEntryRegistration> at(UiPlacement place) => orderedEntries(
    widget.registry,
    widget.profile.mountFor,
    (e) => widget.profile.mountFor(e).placement == place,
  );
  List<UiEntryRegistration> get main => at(UiPlacement.main);
  int get count {
    final media = MediaQuery.of(context);
    final w = widget.desktop
        ? math.max(820.0, media.size.width)
        : math.min(
            media.size.width,
            media.size.width >= 820 ? 412.0 : media.size.width,
          );
    return navigationVisibleCount(
      total: main.length,
      limit: widget.profile.mainLimit,
      width:
          w - 24 - (widget.profile.morePageEnabled && !widget.desktop ? 72 : 0),
      textScale: media.textScaler.scale(12) / 12,
      desktop: widget.desktop,
    );
  }

  String name(UiPlacement p) => switch (p) {
    UiPlacement.main => widget.desktop ? '侧栏导航' : '底部导航',
    UiPlacement.header => '右上角菜单',
    _ => widget.profile.morePageEnabled ? '更多' : '全部入口',
  };
  void switchTo(UiPlacement next) {
    if (zone == next) return;
    setState(() => zone = next);
    if (dragging != null && next == UiPlacement.header) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && previewScroll.hasClients) {
          previewScroll.jumpTo(previewScroll.position.maxScrollExtent);
        }
      });
    }
  }

  String entryName(UiEntryRegistration entry) {
    if (widget.registry.entries.any(
      (other) => other.pageId != entry.pageId && other.label == entry.label,
    )) {
      return widget.registry.page(entry.pageId)?.title ?? entry.label;
    }
    return entry.label;
  }

  Widget palette({required bool prioritizeMain}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    bool available(UiEntryRegistration entry) =>
        !entry.content && widget.canMove(entry);
    final entries = widget.registry.entries.where(available);
    final choices = [
      if (prioritizeMain) ...main.where(available),
      for (final entry in entries)
        if (!prioritizeMain ||
            widget.profile.mountFor(entry).placement != UiPlacement.main)
          entry,
    ];
    final choiceIndexes = {
      for (final (index, entry) in choices.indexed)
        ValueKey('palette-${entry.id}'): index,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SettingsHeading('可选入口')),
            TextButton.icon(
              onPressed: widget.saving
                  ? null
                  : () async {
                      final selected = await showSettingsModal<String>(
                        context: context,
                        builder: (_) => UiLayoutPicker<String>(
                          title: '搜索可选入口',
                          entrySearch: true,
                          choices: [
                            for (final e in choices)
                              UiLayoutChoice(
                                value: e.id,
                                label: entryName(e),
                                icon: e.icon,
                                detail:
                                    '当前在${switch (widget.profile.mountFor(e).placement) {
                                      UiPlacement.main => widget.desktop ? '侧栏' : '底部导航',
                                      UiPlacement.settings => '设置',
                                      final place => placementLabel(place),
                                    }}',
                                keywords:
                                    '${widget.registry.page(e.pageId)?.title ?? ''} ${e.moduleId} ${e.id}',
                              ),
                          ],
                        ),
                      );
                      if (mounted && selected != null) {
                        widget.onSelect(selected);
                      }
                    },
              style: TextButton.styleFrom(
                foregroundColor: colors.onPrimaryContainer,
                padding: const EdgeInsetsDirectional.only(start: 8),
              ),
              icon: const UiIcon(Icons.search, size: 17),
              label: const Text('搜索入口'),
            ),
          ],
        ),
        Expanded(
          child: Material(
            color: colors.surface,
            shape: AppDesign.smoothShape(
              radius: 17,
              side: BorderSide(color: colors.outlineVariant, width: .8),
            ),
            clipBehavior: Clip.antiAlias,
            child: choices.isEmpty
                ? const Center(child: Text('没有匹配的入口'))
                : LayoutBuilder(
                    builder: (c, box) {
                      final scale = MediaQuery.textScalerOf(c).scale(13) / 13;
                      final cols = (box.maxWidth / (84 * scale)).floor().clamp(
                        2,
                        8,
                      );
                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisExtent: 39 + 30 * scale,
                        ),
                        itemCount: choices.length,
                        findChildIndexCallback: (key) => choiceIndexes[key],
                        itemBuilder: (_, i) {
                          final e = choices[i];
                          final tile = InkWell(
                            onTap: widget.saving
                                ? null
                                : () => widget.onSelect(e.id),
                            borderRadius: BorderRadius.circular(14),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SettingsGlyph(e.icon),
                                const SizedBox(height: 7),
                                Text(
                                  entryName(e),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                          return LongPressDraggable<UiEntryRegistration>(
                            key: ValueKey('palette-${e.id}'),
                            data: e,
                            maxSimultaneousDrags:
                                widget.saving ||
                                    dragging != null && dragging != e.id
                                ? 0
                                : 1,
                            onDragUpdate: (d) {
                              if (!previewScroll.hasClients) return;
                              final pos = previewScroll.position;
                              final box = pos.context.storageContext
                                  .findRenderObject();
                              if (box is! RenderBox || !box.hasSize) return;
                              final local = box.globalToLocal(d.globalPosition);
                              if (!box.size.contains(local)) return;
                              final step = local.dy < 32
                                  ? -12.0
                                  : local.dy > box.size.height - 32
                                  ? 12.0
                                  : 0.0;
                              if (step != 0) {
                                previewScroll.jumpTo(
                                  (pos.pixels + step).clamp(
                                    pos.minScrollExtent,
                                    pos.maxScrollExtent,
                                  ),
                                );
                              }
                            },
                            onDragStarted: () =>
                                setState(() => dragging = e.id),
                            onDragEnd: (_) {
                              if (mounted) setState(() => dragging = null);
                            },
                            feedback: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    UiIcon(e.icon, size: 18),
                                    const SizedBox(width: 6),
                                    Text(entryName(e)),
                                  ],
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: .4,
                              child: tile,
                            ),
                            child: tile,
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget rail() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainer,
      shape: AppDesign.smoothShape(
        radius: 14,
        side: BorderSide(color: colors.outlineVariant, width: .8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in [
                UiPlacement.main,
                UiPlacement.header,
                UiPlacement.more,
              ])
                Expanded(
                  child: DragTarget<UiEntryRegistration>(
                    key: ValueKey('zone-${p.name}'),
                    onMove: (_) => switchTo(p),
                    // Hover changes the preview. Only a target inside that preview commits a move.
                    onWillAcceptWithDetails: (_) {
                      switchTo(p);
                      return false;
                    },
                    builder: (context, _, _) => Semantics(
                      selected: p == zone,
                      button: true,
                      child: Material(
                        color: p == zone ? colors.surface : Colors.transparent,
                        shape: AppDesign.smoothShape(
                          radius: 11,
                          side: p == zone
                              ? BorderSide(
                                  color: colors.outlineVariant,
                                  width: .8,
                                )
                              : BorderSide.none,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => switchTo(p),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 37),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 4,
                              ),
                              child: Center(
                                child: Text(
                                  name(p),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: p == zone
                                        ? colors.onPrimaryContainer
                                        : colors.onSurfaceVariant,
                                    fontWeight: p == zone
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
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
    );
  }

  Widget target(int index, Widget child, {bool vertical = true}) {
    final current = zone;
    return DragTarget<UiEntryRegistration>(
      key: ValueKey('drop-${current.name}-$index'),
      onWillAcceptWithDetails: (v) =>
          !widget.saving &&
          widget.canMove(v.data) &&
          mountDiagnostic(
                widget.registry,
                v.data,
                UiMount(
                  placement: current,
                  context: widget.profile.mountFor(v.data).context,
                ),
              ) ==
              null,
      onAcceptWithDetails: (v) => widget.onDrop(v.data, current, index),
      builder: (c, candidates, _) => Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          if (candidates.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(c).colorScheme.primary
                        .withValues(alpha: .12),
                    border: vertical
                        ? Border(
                            top: BorderSide(
                              color: Theme.of(c).colorScheme.primary,
                              width: 3,
                            ),
                          )
                        : Border(
                            left: BorderSide(
                              color: Theme.of(c).colorScheme.primary,
                              width: 3,
                            ),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget tail(int i) => target(
    i,
    Container(
      alignment: Alignment.center,
      height: 40,
      color: Colors.transparent,
      child: const Text('放在这里'),
    ),
  );
  Widget scene() {
    final visible = main.take(count).toList(), explicit = at(UiPlacement.more);
    final extras = [...explicit, ...main.skip(count)];
    final head = at(UiPlacement.header);
    final previewPage = widget.registry.pages
        .where((p) => p.navigationPreview != null)
        .firstOrNull;
    final preview = previewPage?.navigationPreview;
    final assistant =
        preview?['assistant'] == true &&
        previewPage != null &&
        widget.registry
            .forSlot(UiSlot.workspaceAssistant)
            .whereType<WorkspaceAssistantRegistration>()
            .any((a) => a.supports({previewPage.moduleId}));
    final title =
        preview?['title'] as String? ?? (visible.firstOrNull?.label ?? '页面');
    Widget fixed(String label, IconData icon, {VoidCallback? onTap}) =>
        ListTile(
          onTap: onTap,
          key: label == '设置'
              ? const ValueKey('layout-preview-fixed-settings')
              : null,
          dense: true,
          leading: UiIcon(icon, size: 18),
          title: Text(label),
        );
    final hasMore = widget.profile.morePageEnabled;
    if (zone == UiPlacement.more) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Text(
              name(zone),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: MoreWorkspacePage(
              entries: extras,
              scrollController: previewScroll,
              onOpen: (e) => widget.onSelect(e.id),
              onSettings: () {},
              wrapEntry: (e, row) {
                final index = explicit.indexWhere((item) => item.id == e.id);
                return index < 0 ? row : target(index, row);
              },
              afterEntries: dragging == null ? null : tail(explicit.length),
            ),
          ),
        ],
      );
    }
    final previewHeader = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Icon(Icons.more_horiz),
        ],
      ),
    );
    final sample = preview == null
        ? const SizedBox.expand()
        : IgnorePointer(
            child: TimeGrid(
              columns: [
                for (final i in preview['columns'] as List? ?? [])
                  Map<String, Object?>.from(i as Map),
              ],
              rows: [
                for (final i in preview['rows'] as List? ?? [])
                  Map<String, Object?>.from(i as Map),
              ],
              blocks: [
                for (final i in preview['blocks'] as List? ?? [])
                  Map<String, Object?>.from(i as Map),
              ],
              options: const {
                'labelWidth': 36,
                'rowHeight': 48,
                'headerHeight': 44,
                'fitColumns': true,
                'fillWidth': true,
              },
              onEvent: (_) {},
            ),
          );
    final background = Column(
      children: [
        previewHeader,
        Expanded(child: sample),
      ],
    );
    if (zone == UiPlacement.header) {
      return Stack(
        children: [
          Positioned.fill(child: background),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: .12)),
          ),
          Positioned(
            top: 36,
            right: 8,
            bottom: 4,
            child: Align(
              alignment: Alignment.topRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 202),
                child: WorkspaceMenuSurface(
                  child: SingleChildScrollView(
                    controller: previewScroll,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final action
                            in (preview?['menu'] as List? ?? [])
                                .whereType<String>())
                          ListTile(
                            dense: true,
                            title: Text(action),
                            minTileHeight: 44,
                          ),
                        for (final (i, e) in head.indexed)
                          target(
                            i,
                            ListTile(
                              key: ValueKey('layout-row-${e.id}'),
                              minTileHeight: 44,
                              dense: true,
                              leading: UiIcon(e.icon, size: 18),
                              title: Text(e.label),
                              onTap: () => widget.onSelect(e.id),
                            ),
                          ),
                        if (dragging != null) tail(head.length),
                        if (head.isNotEmpty || preview != null)
                          const Divider(height: 8),
                        if (!hasMore)
                          fixed(
                            '全部入口',
                            Icons.grid_view_outlined,
                            onTap: () => switchTo(UiPlacement.more),
                          ),
                        fixed('设置', Icons.settings_outlined),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (widget.desktop) {
      return Row(
        children: [
          Flexible(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                fixed('序点', Icons.grid_view_outlined),
                const Text('工作台'),
                if (hasMore)
                  WorkspaceSidebarItem(
                    icon: Icons.grid_view_rounded,
                    label: '更多',
                    selected: false,
                    onTap: () => switchTo(UiPlacement.more),
                  ),
                for (final (i, e) in visible.indexed)
                  target(
                    i,
                    WorkspaceSidebarItem(
                      icon: e.icon,
                      label: e.label,
                      selected: i == visible.length - 1,
                      onTap: () => widget.onSelect(e.id),
                    ),
                  ),
                if (dragging != null) tail(visible.length),
                fixed('设置', Icons.settings_outlined),
              ],
            ),
          ),
          Expanded(flex: 2, child: background),
        ],
      );
    }
    final destinations = [
      if (hasMore)
        AppDestination(
          id: 'app.shell.more',
          label: '更多',
          icon: Icons.apps_rounded,
          selectedIcon: Icons.apps_rounded,
          builder: (_) => const SizedBox.shrink(),
        ),
      for (final e in visible)
        AppDestination(
          id: e.id,
          label: e.label,
          icon: e.icon,
          selectedIcon: e.selectedIcon ?? e.icon,
          builder: (_) => const SizedBox.shrink(),
        ),
    ];
    final dock = MobileBottomDock(
      destinations: destinations,
      selectedIndex: destinations.length - 1,
      visibleCount: destinations.length,
      hasMore: false,
      showNavigation: destinations.isNotEmpty,
      onAssistant: assistant ? () {} : null,
      onSelected: (i) {
        final id = destinations[i].id;
        if (id == 'app.shell.more') {
          switchTo(UiPlacement.more);
        } else {
          widget.onSelect(id);
        }
      },
    );
    return Stack(
      children: [
        Positioned.fill(child: background),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              dock,
              if (dragging != null)
                Positioned.fill(
                  child: Row(
                    children: [
                      if (hasMore) const Spacer(),
                      for (var i = 0; i <= visible.length; i++)
                        Expanded(
                          child: target(
                            i,
                            const SizedBox.expand(),
                            vertical: false,
                          ),
                        ),
                      if (assistant) const Spacer(),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (dragging != null && destinations.isEmpty)
          Align(alignment: Alignment.bottomCenter, child: tail(0)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final headingStyle = theme.textTheme.labelLarge?.copyWith(
      color: colors.onSurfaceVariant,
      fontSize: 13.3,
      fontWeight: FontWeight.w600,
    );
    return DetailPage(
      title: '编排入口',
      settingsStyle: true,
      actions: [
        Center(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 20),
            child: Text(widget.desktop ? '电脑配置' : '手机配置', style: headingStyle),
          ),
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesign.pageGutter,
              ),
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  final compact =
                      bounds.maxHeight < 440 + (textScale - 1) * 100;
                  final narrow = bounds.maxWidth < 680;
                  final phone = narrow && !widget.desktop;
                  // The drag and unsaved placement views keep their drop rail
                  // between the palette and the preview.
                  final railAbovePalette =
                      phone && !compact && dragging == null && !widget.dirty;
                  final zoneRail = KeyedSubtree(
                    key: const ValueKey('layout-arranger-rail'),
                    child: rail(),
                  );
                  final pane = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (railAbovePalette) ...[
                        zoneRail,
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        key: const ValueKey('layout-arranger-palette'),
                        height:
                            (compact ? 140 : (narrow ? 194 : 122)) +
                            (textScale - 1) * 60,
                        child: palette(prioritizeMain: phone),
                      ),
                      if (!railAbovePalette) ...[
                        const SettingsNote('拖动图标经过下方分区切页，再放入预览。'),
                        zoneRail,
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(child: SettingsHeading('${name(zone)}预览')),
                          if (zone == UiPlacement.main)
                            TextButton(
                              onPressed: widget.onOptions,
                              style: TextButton.styleFrom(
                                foregroundColor: colors.onPrimaryContainer,
                                padding: const EdgeInsetsDirectional.only(
                                  start: 8,
                                ),
                              ),
                              child: const Text('显示选项'),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(widget.dirty ? '有未保存更改' : ''),
                            ),
                        ],
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: phone
                                  ? bounds.maxWidth * 1.03
                                  : double.infinity,
                            ),
                            child: SizedBox.expand(
                              child: Material(
                                clipBehavior: Clip.antiAlias,
                                color: colors.surface,
                                shape: AppDesign.smoothShape(
                                  radius: 17,
                                  side: BorderSide(
                                    color: colors.outlineVariant,
                                    width: .8,
                                  ),
                                ),
                                child: scene(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.error != null)
                        Text(
                          widget.error!,
                          style: TextStyle(color: colors.error),
                        ),
                    ],
                  );
                  return compact
                      ? SingleChildScrollView(
                          child: SizedBox(
                            height: 470 + (textScale - 1) * 180,
                            child: pane,
                          ),
                        )
                      : pane;
                },
              ),
            ),
          ),
          SettingsFooter(
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onDirectory,
                    child: const Text('入口目录'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.saving || !widget.dirty
                        ? null
                        : widget.onSave,
                    child: Text(widget.saving ? '保存中…' : '保存布局'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
