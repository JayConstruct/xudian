import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/design_system.dart';
import '../../app/mobile_bottom_dock.dart';
import '../../core/ui/app_destination.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_layout_resolver.dart';
import '../../core/ui/ui_registry.dart';
import '../../core/ui/ui_icon.dart';
import '../../core/ui/workspace_popup_menu.dart';
import 'settings_widgets.dart';
import 'ui_layout.dart';

typedef _Landing = ({UiPlacement zone, int index, bool after});

class _Slot {
  const _Slot(this.zone, this.index, this.horizontal, this.empty);
  final UiPlacement zone;
  final int index;
  final bool horizontal, empty;
}

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
    required this.onUndo,
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
  final UiLayoutProfile? Function(UiEntryRegistration, UiPlacement, int) onDrop;
  final void Function(UiLayoutProfile, UiLayoutProfile) onUndo;
  final VoidCallback onSave, onDirectory, onOptions;

  @override
  State<LayoutArranger> createState() => _LayoutArrangerState();
}

class _LayoutArrangerState extends State<LayoutArranger> {
  static const zones = [UiPlacement.main, UiPlacement.header, UiPlacement.more];
  late UiPlacement zone = widget.initialZone;
  final search = TextEditingController();
  final previewScroll = ScrollController();
  final previewKey = GlobalKey();
  UiEntryRegistration? dragging;
  bool fromPreview = false;
  _Landing? landing;
  Timer? edgeTimer;
  Offset? pointer;
  ({
    String text,
    String entryId,
    UiLayoutProfile before,
    UiLayoutProfile after,
  })?
  change;

  @override
  void dispose() {
    edgeTimer?.cancel();
    previewScroll.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LayoutArranger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(change?.after, widget.profile)) change = null;
  }

  List<UiEntryRegistration> at(UiPlacement place) => orderedEntries(
    widget.registry,
    widget.profile.mountFor,
    (e) => widget.profile.mountFor(e).placement == place,
  );
  String name(UiPlacement place) => switch (place) {
    UiPlacement.main => widget.desktop ? '侧栏导航' : '底部导航',
    UiPlacement.more => widget.profile.morePageEnabled ? '更多' : '全部入口',
    UiPlacement.header => '右上角菜单',
    UiPlacement.hidden => '已隐藏',
    UiPlacement.settings => '设置',
    UiPlacement.page => '页面槽位',
  };
  String label(UiEntryRegistration e) => widget.registry.entryLabel(e);

  int visibleCount(int total) {
    final media = MediaQuery.of(context);
    final w = widget.desktop
        ? math.max(820.0, media.size.width)
        : media.size.width >= 820
        ? 412.0
        : media.size.width;
    return navigationVisibleCount(
      total: total,
      fixedMore: widget.profile.morePageEnabled,
      limit: widget.profile.mainLimit,
      desktop: widget.desktop,
      width:
          w - 24 - (widget.profile.morePageEnabled && !widget.desktop ? 72 : 0),
      textScale: media.textScaler.scale(12) / 12,
    );
  }

  bool accepts(UiEntryRegistration e, UiPlacement place) =>
      !widget.saving &&
      !e.content &&
      widget.canMove(e) &&
      (place == UiPlacement.hidden ||
          mountDiagnostic(
                widget.registry,
                e,
                UiMount(
                  placement: place,
                  context: widget.profile.mountFor(e).context,
                ),
              ) ==
              null);

  void move(UiEntryRegistration e, UiPlacement place, int index) {
    if (!accepts(e, place)) return;
    final before = widget.profile;
    final source = before.mountFor(e).placement;
    final after = widget.onDrop(e, place, index);
    if (after == null) return;
    final title = '「${label(e)}」';
    var message = place == UiPlacement.hidden
        ? '已从${name(source)}移除$title'
        : source == place
        ? '已调整$title的位置'
        : source == UiPlacement.hidden
        ? '已将$title添加到${name(place)}'
        : '已将$title从${name(source)}移入${name(place)}';
    if (place == UiPlacement.main) {
      final main = orderedEntries(
        widget.registry,
        after.mountFor,
        (x) => after.mountFor(x).placement == place,
      );
      if (main.indexOf(e) >= visibleCount(main.length)) {
        message += '，在「${name(UiPlacement.more)}」中显示';
      }
    }
    setState(
      () =>
          change = (text: message, entryId: e.id, before: before, after: after),
    );
  }

  void switchTo(UiPlacement next) {
    if (next == zone) return;
    if (previewScroll.hasClients) previewScroll.jumpTo(0);
    setState(() {
      zone = next;
      landing = null;
    });
  }

  Future<void> actions(UiEntryRegistration e) async {
    if (widget.saving) return;
    final place = widget.profile.mountFor(e).placement;
    final siblings = at(place);
    final index = siblings.indexOf(e);
    final horizontal = place == UiPlacement.main && !widget.desktop;
    final action = await showSettingsModal<_EntryAction>(
      context: context,
      builder: (sheet) => SettingsSheet(
        showClose: true,
        title: Row(
          children: [
            SettingsGlyph(e.icon),
            const SizedBox(width: 12),
            Flexible(child: Text(label(e))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${name(place)} · 第 ${index + 1} 个可编排入口'),
              const SizedBox(height: 12),
              Row(
                spacing: 8,
                children: [
                  for (final previous in [true, false])
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            (previous ? index > 0 : index + 1 < siblings.length)
                            ? () => Navigator.pop(
                                sheet,
                                previous
                                    ? _EntryAction.previous
                                    : _EntryAction.next,
                              )
                            : null,
                        child: Text(
                          horizontal
                              ? (previous ? '左移一位' : '右移一位')
                              : (previous ? '上移一位' : '下移一位'),
                        ),
                      ),
                    ),
                ],
              ),
              ListTile(
                leading: const UiIcon(Icons.tune),
                title: const Text('调整位置与上下文'),
                onTap: () => Navigator.pop(sheet, _EntryAction.inspect),
              ),
              ListTile(
                leading: const UiIcon(Icons.remove_circle_outline),
                textColor: Theme.of(sheet).colorScheme.error,
                title: Text('从${name(place)}移除'),
                subtitle: const Text('移除后可在「可添加入口」中找回。'),
                onTap: () => Navigator.pop(sheet, _EntryAction.remove),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted ||
        action == null ||
        widget.saving ||
        !widget.registry.entries.contains(e) ||
        widget.profile.mountFor(e).placement != place) {
      return;
    }
    final current = at(place).indexOf(e);
    switch (action) {
      case _EntryAction.inspect:
        widget.onSelect(e.id);
      case _EntryAction.remove:
        move(e, UiPlacement.hidden, 0);
      case _EntryAction.previous:
        if (current > 0) move(e, place, current - 1);
      case _EntryAction.next:
        if (current + 1 < at(place).length) move(e, place, current + 2);
    }
  }

  Widget dragSource(
    UiEntryRegistration e,
    Widget child, {
    Key? key,
    bool preview = false,
    bool immediate = false,
  }) {
    final enabled = !widget.saving && widget.canMove(e) && dragging == null;
    final dockIcon =
        preview &&
        widget.profile.mountFor(e).placement == UiPlacement.main &&
        !widget.desktop;
    final glyph = UiIcon(e.icon, size: dockIcon ? 22 : 19);
    final feedback = FractionalTranslation(
      translation: const Offset(-.5, -1.1),
      child: Material(
        elevation: 5,
        shape: const StadiumBorder(),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: dockIcon
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    glyph,
                    Text(
                      label(e),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [glyph, const SizedBox(width: 7), Text(label(e))],
                ),
        ),
      ),
    );
    void start() {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        dragging = e;
        fromPreview = preview;
        landing = null;
      });
    }

    // Completion/cancellation also run when hovering another tab has disposed the source.
    if (immediate) {
      return Draggable<UiEntryRegistration>(
        key: key,
        data: e,
        maxSimultaneousDrags: enabled ? 1 : 0,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        onDragStarted: start,
        onDragCompleted: endDrag,
        onDraggableCanceled: (_, _) => endDrag(),
        child: child,
      );
    }
    return LongPressDraggable<UiEntryRegistration>(
      key: key,
      data: e,
      maxSimultaneousDrags: enabled ? 1 : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      onDragStarted: start,
      onDragCompleted: endDrag,
      onDraggableCanceled: (_, _) => endDrag(),
      childWhenDragging: Opacity(opacity: .28, child: child),
      child: child,
    );
  }

  void endDrag() {
    stopScroll();
    if (!mounted || dragging == null) return;
    setState(() {
      dragging = null;
      landing = null;
      fromPreview = false;
    });
  }

  void stopScroll() {
    pointer = null;
    edgeTimer?.cancel();
    edgeTimer = null;
  }

  double scrollStep(Offset point) {
    final box = previewKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !previewScroll.hasClients || !box.hasSize) {
      return 0;
    }
    final local = box.globalToLocal(point);
    if (!box.size.contains(local)) return 0;
    final band = math.min(32.0, box.size.height / 3);
    final pos = previewScroll.position;
    if (local.dy < band && pos.extentBefore > 0) return -10;
    if (local.dy > box.size.height - band && pos.extentAfter > 0) return 10;
    return 0;
  }

  void updateScroll(Offset point) {
    if (scrollStep(point) == 0) {
      stopScroll();
      return;
    }
    pointer = point;
    edgeTimer ??= Timer.periodic(const Duration(milliseconds: 24), (_) {
      final p = pointer;
      if (!mounted || p == null || dragging == null || scrollStep(p) == 0) {
        stopScroll();
        return;
      }
      final pos = previewScroll.position;
      pos.jumpTo(
        (pos.pixels + scrollStep(p)).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pointer == p && dragging != null) highlight(hit(p));
      });
    });
  }

  // Hit-test the stationary slots again on release. Scrolling can put a different
  // row beneath the finger without producing another pointer-move event.
  _Landing? hit(Offset point, {bool hover = false}) {
    final result = BoxHitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      point,
      View.of(context).viewId,
    );
    for (final item in result.path) {
      final box = item.target;
      if (box is! RenderMetaData) continue;
      final data = box.metaData;
      if (data is UiPlacement) {
        if (data == UiPlacement.hidden) {
          return fromPreview ? (zone: data, index: 0, after: false) : null;
        }
        if (hover) switchTo(data);
        return null;
      }
      if (data is _Slot && data.zone == zone) {
        final p = box.globalToLocal(point);
        final after =
            !data.empty &&
            (data.horizontal
                ? p.dx > box.size.width / 2
                : p.dy > box.size.height / 2);
        return (zone: zone, index: data.index + (after ? 1 : 0), after: after);
      }
    }
    return null;
  }

  void highlight(_Landing? next) {
    if (next != null && !accepts(dragging!, next.zone)) next = null;
    if (landing != next) setState(() => landing = next);
  }

  Widget dragArea(Widget child) => DragTarget<UiEntryRegistration>(
    onWillAcceptWithDetails: (d) => !widget.saving && widget.canMove(d.data),
    onMove: (d) {
      if (dragging == null) return;
      highlight(hit(d.offset, hover: true));
      updateScroll(d.offset);
    },
    onLeave: (_) {
      stopScroll();
      if (mounted && landing != null) setState(() => landing = null);
    },
    onAcceptWithDetails: (d) {
      final dest = hit(d.offset);
      if (dest != null) move(d.data, dest.zone, dest.index);
    },
    builder: (_, _, _) => child,
  );

  Widget slot(
    List<UiEntryRegistration> list,
    int index,
    Widget child, {
    bool horizontal = false,
    bool empty = false,
  }) {
    final dest = landing?.zone == zone ? landing?.index : null;
    final origin = dragging == null ? -1 : list.indexOf(dragging!);
    final shift = origin < 0 || dest == null
        ? 0.0
        : index >= dest && index < origin
        ? 1.0
        : index > origin && index < dest
        ? -1.0
        : 0.0;
    // Dock icons and overflow rows have different axes and sizes.
    final sameAxis =
        zone != UiPlacement.main ||
        widget.desktop ||
        (origin < visibleCount(list.length)) == horizontal;
    final before = dest == index && landing?.after == false;
    final after = dest == index + 1 && landing?.after == true;
    final line = BorderSide(
      color: Theme.of(context).colorScheme.primary,
      width: 3,
    );
    return MetaData(
      key: ValueKey('drop-${zone.name}-$index'),
      behavior: HitTestBehavior.opaque,
      metaData: _Slot(zone, index, horizontal, empty),
      child: Stack(
        fit: horizontal ? StackFit.expand : StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          FractionalTranslation(
            translation: !sameAxis
                ? Offset.zero
                : horizontal
                ? Offset(shift, 0)
                : Offset(0, shift),
            transformHitTests: false,
            child: child,
          ),
          if (before || after)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: horizontal
                        ? Border(
                            left: before ? line : BorderSide.none,
                            right: after ? line : BorderSide.none,
                          )
                        : Border(
                            top: before ? line : BorderSide.none,
                            bottom: after ? line : BorderSide.none,
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String dragHint() {
    final dest = landing;
    if (dragging != null) {
      if (dest?.zone == UiPlacement.hidden) return '松手移除「${label(dragging!)}」';
      if (dest != null) {
        final list = at(zone);
        if (dest.index < list.length) {
          return '松手放在「${label(list[dest.index])}」前';
        }
        return '松手放到${name(zone)}末尾';
      }
      return '拖到指定位置，经过上方标签可切换分区。';
    }
    return zone == UiPlacement.main && !widget.desktop
        ? '长按左右排序，轻点入口可移除。'
        : '拖动手柄排序，轻点条目可移除。';
  }

  Widget removeTarget() {
    final colors = Theme.of(context).colorScheme;
    final over = landing?.zone == UiPlacement.hidden;
    return MetaData(
      key: const ValueKey('drop-remove'),
      metaData: UiPlacement.hidden,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: over ? colors.error : colors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UiIcon(
              Icons.remove_circle_outline,
              color: over ? colors.onError : colors.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Text(
              over ? '松手移除入口' : '拖到这里移除入口',
              style: TextStyle(
                color: over ? colors.onError : colors.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget palette() {
    final query = search.text.trim().toLowerCase();
    final matches = widget.registry.entries.where(
      (e) =>
          widget.profile.mountFor(e).placement != zone &&
          accepts(e, zone) &&
          '${label(e)} ${e.moduleId} ${e.id} ${widget.registry.page(e.pageId)?.title ?? ''}'
              .toLowerCase()
              .contains(query),
    );
    final choices = [
      for (final hidden in [true, false])
        ...matches.where(
          (e) =>
              (widget.profile.mountFor(e).placement == UiPlacement.hidden) ==
              hidden,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SettingsHeading('可添加入口')),
            Text(
              '${choices.length} 项',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        SettingsSearchField(
          fieldKey: const ValueKey('arranger-search'),
          controller: search,
          hint: '搜索名称或模块',
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: AppDesign.smoothShape(
              radius: 17,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: choices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(heightFactor: 1, child: Text('没有匹配的入口')),
                  )
                : ListView.separated(
                    key: PageStorageKey('arranger-palette-${zone.name}'),
                    primary: false,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: choices.length,
                    separatorBuilder: (_, _) => const SettingsDivider(),
                    itemBuilder: (_, i) {
                      final e = choices[i],
                          source = widget.profile.mountFor(e).placement;
                      final hidden = source == UiPlacement.hidden;
                      return dragSource(
                        e,
                        ListTile(
                          dense: true,
                          leading: SettingsGlyph(e.icon),
                          title: Text(label(e)),
                          subtitle: Text(hidden ? '已隐藏' : '当前在${name(source)}'),
                          onTap: () => widget.onSelect(e.id),
                          trailing: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: hidden
                                  ? Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer
                                  : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainer,
                              minimumSize: const Size(64, 32),
                              shape: AppDesign.smoothShape(radius: 10),
                            ),
                            onPressed: () => move(e, zone, at(zone).length),
                            icon: UiIcon(
                              hidden
                                  ? Icons.add
                                  : Icons.subdirectory_arrow_left,
                              size: 16,
                            ),
                            label: Text(hidden ? '添加' : '移入'),
                          ),
                        ),
                        key: ValueKey('palette-${e.id}'),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget entryRow(List<UiEntryRegistration> entries, int index) {
    final e = entries[index];
    final handle = dragSource(
      e,
      const SizedBox(
        width: 44,
        height: 44,
        child: Center(child: UiIcon(Icons.drag_handle, size: 18)),
      ),
      preview: true,
      immediate: true,
    );
    final row = ListTile(
      key: ValueKey(
        zone == UiPlacement.more ? 'more-entry-${e.id}' : 'layout-row-${e.id}',
      ),
      minTileHeight: 44,
      dense: true,
      contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 2),
      leading: UiIcon(e.icon, size: 18),
      title: Text(label(e)),
      trailing: handle,
      onTap: () => actions(e),
    );
    return slot(entries, index, dragSource(e, row, preview: true));
  }

  Widget fixed(String text, IconData icon, {Key? key, VoidCallback? tap}) =>
      ListTile(
        key: key,
        dense: true,
        minTileHeight: 44,
        leading: UiIcon(icon, size: 18),
        title: Text(text),
        trailing: const Text('固定'),
        onTap: tap,
      );

  Widget scene() {
    final entries = at(zone);
    final hasMore = widget.profile.morePageEnabled;
    final settings = fixed(
      '设置',
      Icons.settings_outlined,
      key: ValueKey(
        zone == UiPlacement.more
            ? 'more-workspace-settings'
            : 'layout-preview-fixed-settings',
      ),
    );
    Widget empty(String text) => slot(
      entries,
      0,
      Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 46),
        child: Text(dragging == null ? text : '放在这里'),
      ),
      empty: true,
    );
    final rows = [
      for (var i = 0; i < entries.length; i++) entryRow(entries, i),
    ];
    if (zone == UiPlacement.header) {
      return Align(
        alignment: AlignmentDirectional.topEnd,
        child: SizedBox(
          width: 215,
          child: WorkspaceMenuSurface(
            child: Column(
              children: [
                if (entries.isEmpty) empty('还没有菜单入口'),
                ...rows,
                const Divider(height: 1),
                if (!hasMore)
                  fixed(
                    '全部入口',
                    Icons.grid_view,
                    tap: () => switchTo(UiPlacement.more),
                  ),
                settings,
              ],
            ),
          ),
        ),
      );
    }
    final main = zone == UiPlacement.main ? entries : at(UiPlacement.main);
    final visible = visibleCount(main.length);
    final extras = main.skip(visible).toList();
    if (zone == UiPlacement.more) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroup(
            title: '常用工具',
            children: [if (entries.isEmpty) empty('暂无常用工具，可从下方添加。'), ...rows],
          ),
          if (extras.isNotEmpty)
            SettingsGroup(
              title: '导航溢出',
              children: [
                for (final e in extras)
                  ListTile(
                    key: ValueKey('more-entry-${e.id}'),
                    dense: true,
                    leading: UiIcon(e.icon),
                    title: Text(label(e)),
                    subtitle: Text('来自${name(UiPlacement.main)}'),
                    onTap: () => actions(e),
                  ),
              ],
            ),
          SettingsGroup(title: '应用', children: [settings]),
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
      for (final e in main.take(visible))
        AppDestination(
          id: e.id,
          label: label(e),
          icon: e.icon,
          selectedIcon: e.selectedIcon ?? e.icon,
          builder: (_) => const SizedBox.shrink(),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.desktop)
          Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: SettingsGroup(
                title: '工作台',
                children: [
                  if (hasMore)
                    fixed(
                      '更多',
                      Icons.grid_view,
                      tap: () => switchTo(UiPlacement.more),
                    ),
                  ...rows.take(visible),
                  settings,
                ],
              ),
            ),
          )
        else
          MobileBottomDock(
            destinations: destinations,
            selectedIndex: destinations.indexWhere(
              (d) => d.id == (dragging?.id ?? change?.entryId),
            ),
            visibleCount: destinations.length,
            hasMore: false,
            showNavigation: destinations.isNotEmpty,
            wrapDestination: (id, child) {
              final i = main.indexWhere((e) => e.id == id);
              return i < 0
                  ? child
                  : slot(
                      entries,
                      i,
                      dragSource(main[i], child, preview: true),
                      horizontal: true,
                    );
            },
            onSelected: (i) {
              if (destinations[i].id == 'app.shell.more') {
                switchTo(UiPlacement.more);
                return;
              }
              actions(main[i - (hasMore ? 1 : 0)]);
            },
          ),
        if (visible == 0) empty('暂无导航入口，可从下方添加。'),
        if (extras.isNotEmpty)
          SettingsGroup(
            title: '在「${name(UiPlacement.more)}」中显示',
            children: rows.skip(visible).toList(),
          ),
      ],
    );
  }

  Widget preview(double maxHeight) {
    final nav = zone == UiPlacement.main;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SettingsHeading(
                nav
                    ? (widget.desktop ? '侧栏预览' : '导航预览')
                    : zone == UiPlacement.header
                    ? '菜单预览'
                    : '${name(zone)}预览',
              ),
            ),
            if (nav)
              TextButton.icon(
                onPressed: widget.saving ? null : widget.onOptions,
                icon: const UiIcon(Icons.tune, size: 16),
                label: const Text('显示选项'),
              ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              key: previewKey,
              controller: previewScroll,
              child: scene(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(dragHint(), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget contents(BoxConstraints bounds) {
    final wide = bounds.maxWidth >= 780;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final compact = bounds.maxHeight < 345 + 65 * (scale - 1);
    final areaHeight = compact ? 380 + 90 * scale : bounds.maxHeight;
    final board = preview(wide ? areaHeight * .7 : areaHeight * .38);
    final panes = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: board),
              const SizedBox(width: 30),
              Expanded(child: palette()),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              board,
              const SizedBox(height: 18),
              Expanded(child: palette()),
            ],
          );
    return compact
        ? SingleChildScrollView(
            child: SizedBox(height: areaHeight, child: panes),
          )
        : panes;
  }

  @override
  Widget build(BuildContext context) {
    final note = change;
    return DetailPage(
      title: '编排入口',
      settingsStyle: true,
      maxBodyWidth: 1024,
      child: dragArea(
        Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesign.pageGutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: SlidingSegments<UiPlacement>(
                          segments: [
                            for (final z in zones)
                              ButtonSegment(value: z, label: Text(name(z))),
                          ],
                          selected: zone,
                          onChanged: switchTo,
                          wrapSegment: (z, c) => MetaData(
                            key: ValueKey('zone-${z.name}'),
                            metaData: z,
                            behavior: HitTestBehavior.opaque,
                            child: c,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, bounds) => contents(bounds),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.error != null)
              Text(
                widget.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (note != null && dragging == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesign.pageGutter,
                  vertical: 4,
                ),
                child: Material(
                  color: Theme.of(context).colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 12,
                      end: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.text,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onInverseSurface,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: widget.saving
                              ? null
                              : () {
                                  widget.onUndo(note.after, note.before);
                                  setState(() => change = null);
                                },
                          child: Text(
                            '撤销',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .inversePrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SettingsFooter(
              child: dragging != null && fromPreview
                  ? removeTarget()
                  : Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: widget.onDirectory,
                            child: const Text('入口目录'),
                          ),
                        ),
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
      ),
    );
  }
}

enum _EntryAction { previous, next, inspect, remove }
