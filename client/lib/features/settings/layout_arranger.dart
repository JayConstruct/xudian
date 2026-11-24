import '../../core/ui/tab_content_transition.dart';
import '../../app/workspace_sidebar_item.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../app/mobile_bottom_dock.dart';
import '../../app/more_workspace_page.dart';
import '../../core/ui/app_destination.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_layout_resolver.dart';
import '../../core/ui/ui_registry.dart';
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
  int? insertion;
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
      fixedMore: widget.profile.morePageEnabled,
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
    setState(() {
      zone = next;
      insertion = null;
    });
  }

  void drag(String? id) {
    if (!mounted || dragging == id) return;
    setState(() {
      dragging = id;
      insertion = null;
    });
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
                                label: widget.registry.entryLabel(e),
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
                                  widget.registry.entryLabel(e),
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
                            onDragStarted: () => drag(e.id),
                            onDragEnd: (_) => drag(null),
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
                                    Text(widget.registry.entryLabel(e)),
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

  static const zones = [UiPlacement.main, UiPlacement.header, UiPlacement.more];

  Widget rail() => SlidingSegments<UiPlacement>(
    segments: [
      for (final place in zones)
        ButtonSegment(value: place, label: Text(name(place))),
    ],
    selected: zone,
    onChanged: switchTo,
    // Hover previews the zone. Only dropping inside the preview commits a move.
    wrapSegment: (place, child) => DragTarget<UiEntryRegistration>(
      key: ValueKey('zone-${place.name}'),
      onMove: (_) => switchTo(place),
      onWillAcceptWithDetails: (_) {
        switchTo(place);
        return false;
      },
      builder: (_, _, _) => child,
    ),
  );

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
      onMove: (_) {
        if (dragging != null && insertion != index) {
          setState(() => insertion = index);
        }
      },
      onLeave: (_) {
        if (mounted && zone == current && insertion == index) {
          setState(() => insertion = null);
        }
      },
      builder: (c, candidates, _) => Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          child,
          if (candidates.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
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

  Widget editable(
    UiEntryRegistration entry,
    int index,
    Widget child, {
    bool horizontal = false,
    bool last = false,
  }) {
    final control = LayoutBuilder(
      builder: (context, box) {
        final draggable = LongPressDraggable<UiEntryRegistration>(
          data: entry,
          maxSimultaneousDrags: widget.saving || !widget.canMove(entry) ? 0 : 1,
          onDragStarted: () => drag(entry.id),
          onDragCompleted: () => drag(null),
          onDraggableCanceled: (_, _) => drag(null),
          feedback: Material(
            elevation: 4,
            color: Theme.of(context).colorScheme.surface,
            shape: horizontal
                ? const StadiumBorder()
                : AppDesign.smoothShape(radius: 15),
            child: SizedBox(
              width: box.maxWidth,
              height: horizontal ? box.maxHeight : null,
              child: IgnorePointer(
                child: horizontal ? child : SettingsListTileTheme(child: child),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0, child: child),
          child: child,
        );
        final origin = dragging == null
            ? -1
            : at(zone).indexWhere((e) => e.id == dragging);
        final destination = insertion ?? origin;
        final shift = origin < 0
            ? 0.0
            : index >= destination && index < origin
            ? 1.0
            : index > origin && index < destination
            ? -1.0
            : 0.0;
        return target(
          index,
          FractionalTranslation(
            translation: horizontal ? Offset(shift, 0) : Offset(0, shift),
            transformHitTests: false,
            child: draggable,
          ),
          vertical: !horizontal,
        );
      },
    );
    if (!last) return control;
    return Stack(
      fit: horizontal ? StackFit.expand : StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        control,
        if (dragging != null)
          Positioned.fill(
            child: Align(
              alignment: horizontal
                  ? AlignmentDirectional.centerEnd
                  : Alignment.bottomCenter,
              child: FractionallySizedBox(
                widthFactor: horizontal ? .45 : 1,
                heightFactor: horizontal ? 1 : .45,
                child: target(
                  index + 1,
                  const SizedBox.expand(),
                  vertical: !horizontal,
                ),
              ),
            ),
          ),
      ],
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
      return MoreWorkspacePage(
        entries: extras,
        scrollController: previewScroll,
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        onOpen: (e) => widget.onSelect(e.id),
        onSettings: () {},
        wrapEntry: (e, row) {
          final index = explicit.indexWhere((item) => item.id == e.id);
          return index < 0
              ? row
              : editable(e, index, row, last: index == explicit.length - 1);
        },
        afterEntries: dragging != null && explicit.isEmpty ? tail(0) : null,
      );
    }
    if (zone == UiPlacement.header) {
      return Align(
        alignment: AlignmentDirectional.topEnd,
        child: SizedBox(
          width: 202,
          child: WorkspaceMenuSurface(
            child: SingleChildScrollView(
              controller: previewScroll,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, entry) in head.indexed)
                    editable(
                      entry,
                      index,
                      ListTile(
                        key: ValueKey('layout-row-${entry.id}'),
                        dense: true,
                        minTileHeight: 44,
                        leading: UiIcon(entry.icon, size: 18),
                        title: Text(widget.registry.entryLabel(entry)),
                        onTap: () => widget.onSelect(entry.id),
                      ),
                      last: index == head.length - 1,
                    ),
                  if (dragging != null && head.isEmpty) tail(0),
                  if (head.isNotEmpty) const Divider(height: 8),
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
                  editable(
                    e,
                    i,
                    WorkspaceSidebarItem(
                      icon: e.icon,
                      label: e.label,
                      selected: i == visible.length - 1,
                      onTap: () => widget.onSelect(e.id),
                    ),
                    last: i == visible.length - 1,
                  ),
                if (dragging != null && visible.isEmpty) tail(0),
                fixed('设置', Icons.settings_outlined),
              ],
            ),
          ),
          const Spacer(flex: 2),
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
      wrapDestination: (id, child) {
        final index = visible.indexWhere((entry) => entry.id == id);
        return index < 0
            ? child
            : editable(
                visible[index],
                index,
                child,
                horizontal: true,
                last: index == visible.length - 1,
              );
      },
      onSelected: (i) {
        final id = destinations[i].id;
        if (id == 'app.shell.more') {
          switchTo(UiPlacement.more);
        } else {
          widget.onSelect(id);
        }
      },
    );
    return Align(
      alignment: Alignment.topCenter,
      child: visible.isEmpty && dragging != null
          ? Column(mainAxisSize: MainAxisSize.min, children: [dock, tail(0)])
          : dock,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DetailPage(
      title: '编排入口',
      settingsStyle: true,
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
                  final pane = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        key: const ValueKey('layout-arranger-palette'),
                        height:
                            (compact ? 140 : (narrow ? 198 : 142)) +
                            (textScale - 1) * 60,
                        child: palette(prioritizeMain: phone),
                      ),
                      SettingsNote(
                        zone == UiPlacement.main && !widget.desktop
                            ? '拖动图标经过标签可切页，长按导航图标可左右排序。'
                            : '拖动图标经过标签可切页，长按条目可上下排序。',
                      ),
                      KeyedSubtree(
                        key: const ValueKey('layout-arranger-rail'),
                        child: rail(),
                      ),
                      const SizedBox(height: 18),
                      if (zone == UiPlacement.main)
                        Row(
                          children: [
                            Expanded(child: SettingsHeading(name(zone))),
                            TextButton(
                              onPressed: widget.onOptions,
                              child: const Text('显示选项'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: TabContentTransition(
                          index: zones.indexOf(zone),
                          child: scene(),
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
