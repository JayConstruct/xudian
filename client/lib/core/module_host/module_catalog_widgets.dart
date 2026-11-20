import 'package:flutter/material.dart';

import '../../features/settings/settings_widgets.dart';
import '../ui/ui_icon.dart';
import '../ui/ui_design.dart';

class ModuleCatalogFilters extends StatelessWidget {
  const ModuleCatalogFilters({
    super.key,
    required this.status,
    required this.category,
    required this.categories,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    this.resultLabel = '模块目录',
    this.count = 0,
  });

  static const statuses = ['全部', '推荐', '可更新', '已安装', '未安装'];
  final String status, category, resultLabel;
  final int count;
  final List<String> categories;
  final ValueChanged<String> onStatusChanged, onCategoryChanged;

  Widget _statusLabel(String option) => Text(
    option,
    key: ValueKey('catalog-status-$option'),
    semanticsLabel: '筛选安装状态：$option',
  );

  Future<void> _pickCategory(BuildContext context) async {
    final next = await showSettingsModal<String>(
      context: context,
      useGlobalStyle: true,
      builder: (context) => SettingsSheet(
        title: const Text('模块分类'),
        expandedActions: true,
        content: SingleChildScrollView(
          child: SettingsGroupSurface(
            dividerIndent: SettingsListTileTheme.horizontalPadding,
            children: [
              for (final option in ['全部分类', ...categories])
                ListTile(
                  title: Text(option),
                  selected: option == category,
                  selectedColor: Theme.of(context).colorScheme.onSurface,
                  trailing: option == category
                      ? UiIcon(
                          Icons.check_rounded,
                          size: 19,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, option),
                ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (context.mounted && next != null) onCategoryChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(13);
            if (constraints.maxWidth < 5 * (3 * scale + 8)) {
              return Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final option in statuses)
                    ChoiceChip(
                      label: _statusLabel(option),
                      selected: option == status,
                      onSelected: (_) => onStatusChanged(option),
                    ),
                ],
              );
            }
            return SettingsSegments<String>(
              key: const ValueKey('catalog-filter-status'),
              segments: [
                for (final option in statuses)
                  ButtonSegment(value: option, label: _statusLabel(option)),
              ],
              selected: status,
              onChanged: onStatusChanged,
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: SettingsHeading('$resultLabel · $count')),
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const ValueKey('catalog-filter-category'),
                  onPressed: () => _pickCategory(context),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 40),
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UiIcon(Icons.tune, size: 17, color: colors.primary),
                      const SizedBox(width: 4),
                      Flexible(child: Text(category, textAlign: TextAlign.end)),
                      UiIcon(
                        Icons.expand_more,
                        size: 17,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ModuleCatalogCard extends StatelessWidget {
  const ModuleCatalogCard({
    super.key,
    required this.name,
    required this.description,
    required this.status,
    required this.version,
    required this.action,
    this.icon = Icons.extension_outlined,
    this.featured = false,
    this.onDetails,
    this.onAction,
    this.secondaryActions = const [],
    this.unavailableHint,
    this.grouped = false,
  });

  final String name, description, status, version, action;
  final IconData icon;
  final bool featured, grouped;
  final VoidCallback? onDetails, onAction;
  final List<Widget> secondaryActions;
  final String? unavailableHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final stackActions = largeText || secondaryActions.isNotEmpty;
    final actionButton = FilledButton.tonal(
      onPressed: onAction,
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        shape: AppDesign.smoothShape(radius: 11),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(action),
    );
    final statusLabel = '$status · $version';
    final showStatus = unavailableHint != null || secondaryActions.isNotEmpty;
    final tile = Semantics(
      button: onDetails != null,
      label: '查看 $name 详情\n$statusLabel',
      child: InkWell(
        onTap: onDetails,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SettingsGlyph(icon, size: 40, radius: 13),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Tooltip(
                        message: featured ? '推荐 · $statusLabel' : statusLabel,
                        excludeFromSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              description,
                              maxLines: largeText ? null : 1,
                              overflow: largeText
                                  ? null
                                  : TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!stackActions) ...[
                      const SizedBox(width: 8),
                      actionButton,
                    ],
                  ],
                ),
                if (showStatus)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 52,
                      top: 4,
                    ),
                    child: Text(statusLabel, style: theme.textTheme.bodySmall),
                  ),
                if (unavailableHint != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 52,
                      top: 4,
                    ),
                    child: Text(
                      unavailableHint!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
                if (stackActions)
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [actionButton, ...secondaryActions],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Material(
      color: grouped ? Colors.transparent : colors.surface,
      shape: grouped
          ? null
          : AppDesign.smoothShape(
              radius: 19,
              side: BorderSide(color: colors.outlineVariant),
            ),
      clipBehavior: grouped ? Clip.none : Clip.antiAlias,
      child: tile,
    );
  }
}

/// Content-sized cards avoid clipping long names or enlarged text to a grid's
/// fixed aspect ratio. Columns use the available width and current text scale.
class ModuleCatalogGrid extends StatelessWidget {
  const ModuleCatalogGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1320),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final scale = (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(
            1.0,
            1.6,
          );
          final minimumWidth = 320 * scale;
          final columns =
              ((constraints.maxWidth + spacing) / (minimumWidth + spacing))
                  .floor()
                  .clamp(1, 3);
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      ),
    ),
  );
}

/// Content-sized rows are built only near the viewport; each row keeps the
/// accessible card layout without a fixed height or aspect ratio.
class ModuleCatalogSliverGrid extends StatelessWidget {
  const ModuleCatalogSliverGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.groupedItemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? groupedItemBuilder;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      final availableWidth = constraints.crossAxisExtent.clamp(0.0, 1320.0);
      final scale = (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(
        1.0,
        1.6,
      );
      final columns = ((availableWidth + spacing) / (320 * scale + spacing))
          .floor()
          .clamp(1, 3);
      if (columns == 1 && groupedItemBuilder != null && itemCount > 0) {
        final colors = Theme.of(context).colorScheme;
        return DecoratedSliver(
          decoration: ShapeDecoration(
            color: colors.surface,
            shape: AppDesign.smoothShape(
              radius: 19,
              side: BorderSide(color: colors.outlineVariant),
            ),
          ),
          sliver: SliverList.separated(
            itemCount: itemCount,
            itemBuilder: groupedItemBuilder!,
            separatorBuilder: (_, _) => const SettingsDivider(indent: 66),
          ),
        );
      }
      final rowCount = (itemCount / columns).ceil();
      return SliverList.builder(
        itemCount: rowCount,
        itemBuilder: (context, row) => Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: availableWidth,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: row + 1 < rowCount ? spacing : 0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: spacing),
                    Expanded(
                      child: row * columns + column < itemCount
                          ? itemBuilder(context, row * columns + column)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
