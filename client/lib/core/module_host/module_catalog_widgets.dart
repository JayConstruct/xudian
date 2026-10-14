import 'package:flutter/material.dart';

import '../ui/native_ui.dart';
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
  });

  final String status, category;
  final List<String> categories;
  final ValueChanged<String> onStatusChanged, onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final labels = ['状态：$status', '分类：$category'];
    double labelWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width + 46;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = [
          _selector(context, 'status', labels[0], status, const [
            '全部',
            '推荐',
            '已安装',
            '未安装',
            '可更新',
          ], onStatusChanged),
          _selector(context, 'category', labels[1], category, [
            '全部分类',
            ...categories,
          ], onCategoryChanged),
        ];
        final halfWidth = (constraints.maxWidth - 8) / 2;
        if (labels.every((label) => labelWidth(label) <= halfWidth)) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: controls[0]),
              const SizedBox(width: 8),
              Expanded(child: controls[1]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [controls[0], const SizedBox(height: 8), controls[1]],
        );
      },
    );
  }

  Widget _selector(
    BuildContext context,
    String id,
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onSelected,
  ) => PopupMenuButton<String>(
    key: ValueKey('catalog-filter-$id'),
    tooltip: id == 'status' ? '筛选安装状态' : '筛选模块分类',
    initialValue: value,
    position: PopupMenuPosition.under,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final option in options)
        PopupMenuItem<String>(value: option, child: Text(option)),
    ],
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: AppDesign.smoothShape(
            radius: AppDesign.compactRadius,
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 6),
              const UiIcon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      ),
    ),
  );
}

class ModuleCatalogCard extends StatelessWidget {
  const ModuleCatalogCard({
    super.key,
    required this.name,
    required this.description,
    required this.status,
    required this.version,
    required this.action,
    this.featured = false,
    this.onDetails,
    this.onAction,
    this.secondaryActions = const [],
    this.unavailableHint,
  });

  final String name, description, status, version, action;
  final bool featured;
  final VoidCallback? onDetails, onAction;
  final List<Widget> secondaryActions;
  final String? unavailableHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: onDetails != null,
        label: '查看 $name 详情',
        child: InkWell(
          onTap: onDetails,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(name, style: theme.textTheme.titleMedium),
                    ),
                    const SizedBox(width: 8),
                    const ExcludeSemantics(
                      child: UiIcon(Icons.chevron_right, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: largeText ? null : 2,
                  overflow: largeText ? null : TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (featured)
                      Text(
                        '推荐',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    Text(
                      '$status · $version',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (unavailableHint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    unavailableHint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    NativeUi(
                      child: FilledButton.tonal(
                        onPressed: onAction,
                        child: Text(action),
                      ),
                    ),
                    ...secondaryActions,
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

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
