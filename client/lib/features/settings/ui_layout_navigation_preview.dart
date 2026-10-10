import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../app/mobile_bottom_dock.dart';
import '../../core/ui/app_destination.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_layout_resolver.dart';
import '../../core/ui/ui_registry.dart';
import 'ui_layout.dart';

enum UiLayoutPreviewArea { all, navigation, header, other }

/// Edits entry placement without opening or building any registered page.
class UiLayoutNavigationPreview extends StatelessWidget {
  const UiLayoutNavigationPreview({
    super.key,
    required this.registry,
    required this.profile,
    required this.desktop,
    this.selectedId,
    this.onSelected,
    this.onEditLimit,
    this.area = UiLayoutPreviewArea.all,
  });

  final UiRegistry registry;
  final UiLayoutProfile profile;
  final bool desktop;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final VoidCallback? onEditLimit;
  final UiLayoutPreviewArea area;

  List<UiEntryRegistration> _at(UiPlacement placement) => orderedEntries(
    registry,
    profile.mountFor,
    (entry) => profile.mountFor(entry).placement == placement,
  );

  Widget _entry(UiEntryRegistration entry) => ListTile(
    key: ValueKey('layout-row-${entry.id}'),
    shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
    leading: Icon(entry.icon, size: 22),
    title: Text(entry.label),
    selected: entry.id == selectedId,
    onTap: onSelected == null ? null : () => onSelected!(entry.id),
  );

  void _more(BuildContext context, List<UiEntryRegistration> entries) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('更多入口', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (_, index) {
                    final entry = entries[index];
                    return ListTile(
                      key: ValueKey('layout-more-${entry.id}'),
                      shape: AppDesign.smoothShape(),
                      leading: Icon(entry.icon),
                      title: Text(entry.label),
                      onTap: onSelected == null
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              onSelected!(entry.id);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final main = _at(UiPlacement.main);
      final width = desktop
          ? 1024.0
          : math.min(390.0, constraints.maxWidth + 24);
      final count = navigationVisibleCount(
        total: main.length,
        limit: profile.mainLimit,
        width: width - 24,
        textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
        desktop: desktop,
      );
      final visible = main.take(count).toList();
      final more = [..._at(UiPlacement.more), ...main.skip(count)];
      final header = _at(UiPlacement.header);
      final scheme = Theme.of(context).colorScheme;
      final nav = desktop
          ? Material(
              color: scheme.surfaceContainerLow,
              shape: AppDesign.smoothShape(),
              child: Column(
                children: [
                  for (final entry in visible) _entry(entry),
                  if (more.isNotEmpty)
                    ListTile(
                      key: const ValueKey('layout-preview-more'),
                      leading: const Icon(Icons.more_horiz_rounded),
                      title: const Text('更多'),
                      onTap: () => _more(context, more),
                    ),
                ],
              ),
            )
          : MobileBottomDock(
              key: const ValueKey('layout-preview-bottom-bar'),
              destinations: [
                for (final entry in visible)
                  AppDestination(
                    id: entry.id,
                    label: entry.label,
                    icon: entry.icon,
                    selectedIcon: entry.icon,
                    builder: (_) => const SizedBox.shrink(),
                  ),
              ],
              selectedIndex: visible.indexWhere((e) => e.id == selectedId),
              visibleCount: visible.length,
              hasMore: more.isNotEmpty,
              moreSelected: more.any((e) => e.id == selectedId),
              showNavigation: true,
              onSelected: (index) {
                if (index >= visible.length) {
                  _more(context, more);
                } else {
                  onSelected?.call(visible[index].id);
                }
              },
            );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (area == UiLayoutPreviewArea.all ||
              area == UiLayoutPreviewArea.navigation)
            _section(
              context,
              desktop ? '侧栏导航' : '底部导航',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (visible.isEmpty && more.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无导航入口，可从隐藏入口中添加。'),
                    )
                  else
                    nav,
                  if (onEditLimit != null)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: onEditLimit,
                        icon: const Icon(Icons.tune, size: 18),
                        label: Text(
                          profile.mainLimit == null
                              ? '显示数量：自动'
                              : '最多显示 ${profile.mainLimit} 项',
                        ),
                      ),
                    ),
                  if (more.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '“更多”中有 ${more.length} 个入口，超出显示数量的导航也会放在这里。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          if (area == UiLayoutPreviewArea.all ||
              area == UiLayoutPreviewArea.header)
            _section(
              context,
              '右上角菜单',
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '页面标题',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.more_vert),
                      ),
                    ],
                  ),
                  Material(
                    key: const ValueKey('layout-preview-header-menu'),
                    elevation: 4,
                    color: scheme.surface,
                    shape: AppDesign.smoothShape(radius: 20),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            for (final entry in header) _entry(entry),
                            if (header.isNotEmpty) const Divider(height: 16),
                            const ListTile(
                              key: ValueKey('layout-preview-fixed-settings'),
                              leading: Icon(Icons.settings_outlined, size: 22),
                              title: Text('设置'),
                              trailing: Tooltip(
                                message: '固定入口，始终保留',
                                child: Icon(Icons.lock_outline, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '页面专属操作随当前页面变化；设置为固定入口。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (area == UiLayoutPreviewArea.all ||
              area == UiLayoutPreviewArea.other)
            for (final group in [
              (UiPlacement.settings, '设置常用入口'),
              (UiPlacement.hidden, '隐藏入口'),
            ])
              if (_at(group.$1).isNotEmpty)
                ExpansionTile(
                  key: ValueKey('layout-preview-group-${group.$1.name}'),
                  tilePadding: EdgeInsets.zero,
                  title: Text('${group.$2} · ${_at(group.$1).length}'),
                  children: [for (final entry in _at(group.$1)) _entry(entry)],
                ),
        ],
      );
    },
  );
}
