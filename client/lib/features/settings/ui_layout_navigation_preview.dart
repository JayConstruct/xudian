import '../../core/ui/ui_icon.dart';
import '../../core/ui/native_ui.dart';

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
    this.onMorePageChanged,
    this.area = UiLayoutPreviewArea.all,
  });

  final UiRegistry registry;
  final UiLayoutProfile profile;
  final bool desktop;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final VoidCallback? onEditLimit;
  final ValueChanged<bool>? onMorePageChanged;
  final UiLayoutPreviewArea area;

  List<UiEntryRegistration> _at(UiPlacement placement) => orderedEntries(
    registry,
    profile.mountFor,
    (entry) => profile.mountFor(entry).placement == placement,
  );

  Widget _entry(UiEntryRegistration entry) => NativeUi(
    child: ListTile(
      key: ValueKey('layout-row-${entry.id}'),
      shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
      leading: UiIcon(entry.icon, size: 22),
      title: Text(entry.label),
      selected: entry.id == selectedId,
      onTap: onSelected == null ? null : () => onSelected!(entry.id),
    ),
  );

  void _more(BuildContext context, List<UiEntryRegistration> entries) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          appBar: AppBar(title: const Text('更多入口')),
          body: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: entries.length,
            itemBuilder: (_, index) {
              final entry = entries[index];
              return NativeUi(
                child: ListTile(
                  key: ValueKey('layout-more-${entry.id}'),
                  shape: AppDesign.smoothShape(),
                  leading: UiIcon(entry.icon),
                  title: Text(entry.label),
                  onTap: onSelected == null
                      ? null
                      : () {
                          Navigator.pop(pageContext);
                          onSelected!(entry.id);
                        },
                ),
              );
            },
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
        width: width - 24 - (profile.morePageEnabled && !desktop ? 72 : 0),
        textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
        desktop: desktop,
      );
      final visible = main.take(count).toList();
      final more = [..._at(UiPlacement.more), ...main.skip(count)];
      final destinations = [
        if (profile.morePageEnabled)
          AppDestination(
            id: 'app.shell.more',
            label: '更多',
            icon: Icons.apps_rounded,
            selectedIcon: Icons.apps_rounded,
            builder: (_) => const SizedBox.shrink(),
          ),
        for (final entry in visible)
          AppDestination(
            id: entry.id,
            label: entry.label,
            icon: entry.icon,
            selectedIcon: entry.icon,
            builder: (_) => const SizedBox.shrink(),
          ),
      ];
      final header = _at(UiPlacement.header);
      final scheme = Theme.of(context).colorScheme;
      final nav = desktop
          ? Material(
              color: scheme.surfaceContainerLow,
              shape: AppDesign.smoothShape(),
              child: Column(
                children: [
                  if (profile.morePageEnabled)
                    NativeUi(
                      child: ListTile(
                        key: const ValueKey('layout-preview-more'),
                        leading: const UiIcon(Icons.more_horiz_rounded),
                        title: const Text('更多'),
                        onTap: () => _more(context, more),
                      ),
                    ),
                  for (final entry in visible) _entry(entry),
                ],
              ),
            )
          : MobileBottomDock(
              key: const ValueKey('layout-preview-bottom-bar'),
              destinations: destinations,
              selectedIndex: destinations.indexWhere((e) => e.id == selectedId),
              visibleCount: destinations.length,
              hasMore: false,
              onAssistant: () {},
              showNavigation: true,
              onSelected: (index) {
                if (destinations[index].id == 'app.shell.more') {
                  _more(context, more);
                } else {
                  onSelected?.call(destinations[index].id);
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
                  if (onMorePageChanged != null)
                    NativeUi(
                      child: SwitchListTile.adaptive(
                        key: const ValueKey('layout-more-page-enabled'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用“更多”页面'),
                        subtitle: const Text('在导航左侧集中显示常用工具和设置'),
                        value: profile.morePageEnabled,
                        onChanged: onMorePageChanged,
                      ),
                    ),
                  if (visible.isEmpty && !profile.morePageEnabled)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无导航入口，可从隐藏入口中添加。'),
                    )
                  else
                    nav,
                  if (onEditLimit != null)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: NativeUi(
                        child: TextButton.icon(
                          onPressed: onEditLimit,
                          icon: const UiIcon(Icons.tune, size: 18),
                          label: Text(
                            profile.mainLimit == null
                                ? '显示数量：自动'
                                : '最多显示 ${profile.mainLimit} 项',
                          ),
                        ),
                      ),
                    ),
                  if (more.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        profile.morePageEnabled
                            ? '“更多”页面中有 ${more.length} 个入口，超出显示数量的导航也会放在这里。'
                            : '“更多”页面已关闭，${more.length} 个入口可从右上角的“全部入口”访问。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (!profile.morePageEnabled && more.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: NativeUi(
                        child: TextButton.icon(
                          key: const ValueKey(
                            'layout-preview-all-entries-open',
                          ),
                          onPressed: () => _more(context, more),
                          icon: const UiIcon(Icons.apps_rounded, size: 18),
                          label: const Text('预览全部入口'),
                        ),
                      ),
                    ),
                  if (!desktop)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '右侧 AI 按钮仅在当前页面支持 AI 功能时显示。',
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
                        child: UiIcon(Icons.more_vert),
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
                            if (!profile.morePageEnabled && more.isNotEmpty)
                              NativeUi(
                                child: ListTile(
                                  key: const ValueKey(
                                    'layout-preview-all-entries',
                                  ),
                                  leading: const UiIcon(
                                    Icons.apps_rounded,
                                    size: 22,
                                  ),
                                  title: const Text('全部入口'),
                                  onTap: () => _more(context, more),
                                ),
                              ),
                            const NativeUi(
                              child: ListTile(
                                key: ValueKey('layout-preview-fixed-settings'),
                                leading: UiIcon(
                                  Icons.settings_outlined,
                                  size: 22,
                                ),
                                title: Text('设置'),
                                trailing: Tooltip(
                                  message: '固定入口，始终保留',
                                  child: UiIcon(Icons.lock_outline, size: 16),
                                ),
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
