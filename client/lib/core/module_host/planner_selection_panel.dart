import 'package:flutter/material.dart';

import '../../app/frosted_toolbar_surface.dart';
import 'planner_board_types.dart';
import 'planner_card_appearance.dart';

class PlannerSelectionPanel extends StatelessWidget {
  const PlannerSelectionPanel({
    super.key,
    required this.item,
    required this.timeLabel,
    required this.deadlineLabel,
    required this.gapLabels,
    required this.enabled,
    required this.onEvent,
    required this.onCommandAction,
    required this.onClose,
    required this.onEditTime,
    required this.onZoom,
  });

  final BoardItem item;
  final String timeLabel;
  final String? deadlineLabel;
  final List<String> gapLabels;
  final bool enabled;
  final ValueChanged<Object?> onEvent;
  final void Function(Object?, Object?)? onCommandAction;
  final VoidCallback onClose, onZoom;
  final VoidCallback? onEditTime;

  @override
  Widget build(BuildContext context) {
    final actions =
        (item['actions'] is List ? item['actions'] as List : const [])
            .whereType<Map>()
            .where(
              (action) => action['label'] is String && action['event'] is Map,
            )
            .take(3)
            .toList();
    final scheme = Theme.of(context).colorScheme;
    final sourceLabel = item['sourceLabel']?.toString();
    final showSource =
        item['showSelectionSource'] != false &&
        sourceLabel != null &&
        sourceLabel.isNotEmpty &&
        (item['readOnly'] == true || sourceLabel != '任务');
    final appearance = PlannerCardAppearance.of(item);
    final inlineActions =
        item['selectionLayout'] == 'inlineActions' && actions.length == 1;
    Widget actionButton(Map action, {bool inline = false}) {
      final VoidCallback? onPressed = !enabled || action['disabled'] == true
          ? null
          : () {
              if (onCommandAction != null && action['command'] is Map) {
                onCommandAction!(action['event'], action['command']);
              } else {
                onEvent(action['event']);
              }
            };
      if (inline) {
        return FilledButton(
          onPressed: onPressed,
          child: Text(action['label'] as String),
        );
      }
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(switch (action['icon']) {
          'check' => Icons.check_circle_outline,
          'undo' => Icons.undo,
          'history' => Icons.history,
          _ => Icons.play_arrow_outlined,
        }, size: 18),
        label: Text(action['label'] as String),
      );
    }

    return FrostedToolbarSurface(
      key: const ValueKey('planner-selection-panel'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['title'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (appearance.badgeText.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(
                      appearance.badgeText,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  tooltip: '关闭选中任务',
                ),
              ],
            ),
            Text(timeLabel, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (deadlineLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  deadlineLabel!,
                  style: TextStyle(
                    color: item['overdue'] == true
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final detail
                in (item['selectionDetails'] is List
                        ? item['selectionDetails'] as List
                        : const [])
                    .whereType<Map>())
              if ('${detail['value'] ?? ''}'.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${detail['label'] ?? ''} ${detail['value']}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
            if (showSource && sourceLabel != appearance.badgeText)
              Text(sourceLabel),
            if ('${item['selectionNote'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${item['selectionNote']}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            if (gapLabels.isNotEmpty)
              Wrap(
                spacing: 12,
                children: [
                  for (final gap in gapLabels)
                    Text(
                      '空闲$gap',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            const SizedBox(height: 8),
            if (actions.isNotEmpty && !inlineActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in actions) actionButton(action),
                  ],
                ),
              ),
            Row(
              children: [
                if (inlineActions && actions.isNotEmpty) ...[
                  Expanded(child: actionButton(actions.first, inline: true)),
                  const SizedBox(width: 8),
                ],
                if (onEditTime != null) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onEditTime,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('编辑时间'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: item['event'] == null
                        ? null
                        : () => onEvent(item['event']),
                    child: const Text('查看详情'),
                  ),
                ),
                IconButton(
                  onPressed: onZoom,
                  icon: const Icon(Icons.zoom_in),
                  tooltip: '放大该时段',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
