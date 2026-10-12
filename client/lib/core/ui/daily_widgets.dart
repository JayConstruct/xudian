import 'ui_icon.dart';
import 'temporal_input.dart';
import 'daily_date_strip.dart';
import 'date_reveal.dart';

import 'package:flutter/material.dart';

import 'ui_design.dart';
import 'ui_motion.dart';

DateTime? _dailyDate(Object? value) {
  final date = parseInputDate(value);
  return date != null && date.year >= 1 ? date : null;
}

/// Shared daily-feed components. Module code owns data and actions; UI packs
/// may replace their presentation using the public contracts.
Widget? dailyUiComponent(
  String ref,
  Map<String, Object?> props,
  Map<String, Widget> slots,
  Map<String, void Function(Object?)> events,
) {
  final disabled = props['disabled'] == true;
  return switch (ref) {
    'ui.dayOverview@1' => DayOverview(
      date: '${props['date'] ?? ''}',
      summary: props['summary'] as String?,
      selectedDate: props['selectedDate'] as String?,
      todayDate: props['todayDate'] as String?,
      dateHeading: props['dateHeading'] != false,
      dateControls: props['dateControls'] != false,
      returnToToday: props['returnToToday'] != false,
      onChanged: disabled || events['change'] == null
          ? null
          : (date) => events['change']!(date),
      days: [
        for (final day in props['days'] as List? ?? [])
          Map<String, Object?>.from(day as Map),
      ],
    ),
    'ui.sectionHeader@1' => DailySectionHeader(
      title: '${props['title'] ?? ''}',
      subtitle: props['subtitle'] as String?,
      count: props['count'],
      actionLabel: props['actionLabel'] as String?,
      actionIcon: props['actionIcon'] as String?,
      onAction: disabled || events['press'] == null
          ? null
          : () => events['press']!(null),
    ),
    'ui.agendaItem@1' => AgendaItem(
      title: '${props['title'] ?? ''}',
      subtitle: props['subtitle'] as String?,
      startTime: '${props['startTime'] ?? ''}',
      endTime: '${props['endTime'] ?? ''}',
      color: props['color'] as String?,
      badge: props['badge'] as String?,
      onPressed: disabled || events['press'] == null
          ? null
          : () => events['press']!(null),
    ),
    'ui.taskItem@1' => DailyTaskItem(
      title: '${props['title'] ?? ''}',
      subtitle: props['subtitle'] as String?,
      completed: props['completed'] == true,
      onChanged: disabled || events['change'] == null
          ? null
          : (value) => events['change']!(value),
      onOpen: disabled || events['open'] == null
          ? null
          : () => events['open']!(null),
      details: slots['details'],
    ),
    _ => null,
  };
}

class DayOverview extends StatelessWidget {
  const DayOverview({
    super.key,
    required this.date,
    this.summary,
    this.selectedDate,
    this.todayDate,
    this.onChanged,
    this.dateHeading = true,
    this.dateControls = true,
    this.returnToToday = true,
    this.days = const [],
  });
  final String date;
  final String? summary, selectedDate, todayDate;
  final ValueChanged<String>? onChanged;
  final bool dateHeading, dateControls;
  final bool returnToToday;
  final List<Map<String, Object?>> days;

  Widget day(BuildContext context, Map<String, Object?> entry) {
    final theme = Theme.of(context);
    final selected = entry['date'] == (selectedDate ?? date);
    final today = entry['isToday'] == true || entry['date'] == todayDate;
    final pending = entry['pending'] as int?;
    final completed = entry['completed'] as int?;
    final truncated = entry['truncated'] == true ? '+' : '';
    final indicators = [
      if (pending != null) '$pending$truncated 待办',
      if (completed != null && completed > 0) '$completed$truncated 已完成',
    ];
    return Semantics(
      label: '${entry['date']}',
      value: [if (today) '今天', ...indicators].join('，'),
      selected: selected,
      button: onChanged != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDesign.controlRadius),
        onTap: onChanged == null || _dailyDate(entry['date']) == null
            ? null
            : () => onChanged!('${entry['date']}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: TweenAnimationBuilder<double>(
            duration: AppMotion.duration(
              context,
              DateRevealScope.of(context) == null
                  ? AppMotion.dateChange
                  : Duration.zero,
              respectHighContrast: true,
            ),
            curve: AppMotion.enter,
            tween: Tween(
              begin: selected ? 1.0 : 0.0,
              end: selected ? 1.0 : 0.0,
            ),
            builder: (context, amount, _) {
              final background = Color.lerp(
                theme.scaffoldBackgroundColor,
                theme.colorScheme.primary,
                amount,
              )!;
              // Interpolating light and dark foregrounds can make a date label
              // unreadable mid-transition. Choose the stronger contrast instead.
              Color foreground({bool muted = false}) {
                if (amount == 0) {
                  return muted
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface;
                }
                if (amount == 1) return theme.colorScheme.onPrimary;
                final first = theme.colorScheme.onSurface,
                    second = theme.colorScheme.onPrimary;
                double contrast(Color color) {
                  final a = color.computeLuminance(),
                      b = background.computeLuminance();
                  return (a > b
                      ? (a + .05) / (b + .05)
                      : (b + .05) / (a + .05));
                }

                return contrast(first) >= contrast(second) ? first : second;
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 2,
                ),
                decoration: BoxDecoration(
                  color: background,
                  border: today && !selected
                      ? Border.all(color: theme.colorScheme.primary)
                      : null,
                  borderRadius: BorderRadius.circular(AppDesign.controlRadius),
                ),
                child: Column(
                  children: [
                    Text(
                      today ? '今天' : '${entry['label'] ?? ''}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: foreground(muted: true),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DateTime.tryParse('${entry['date']}')?.day ?? ''}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: foreground(),
                      ),
                    ),
                    if (indicators.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final indicator in indicators)
                        Text(
                          indicator,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground(muted: true),
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reveal = DateRevealScope.of(context);
    final value = _dailyDate(selectedDate ?? date);
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final label = value == null
        ? date
        : '${value.month}月${value.day}日 ${weekdays[value.weekday - 1]}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dateHeading && (onChanged == null || value == null))
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        if (dateControls && onChanged != null && value != null) ...[
          DateRevealNavigation(
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        locale: const Locale('zh', 'CN'),
                        helpText: '选择日期',
                        initialDate: value,
                        firstDate: DateTime(1),
                        lastDate: DateTime(9999, 12, 31),
                      );
                      if (context.mounted && selected != null) {
                        onChanged!(formatInputDate(selected));
                      }
                    },
                    child: Text(
                      dateHeading ? '${value.year}年$label' : '选择日期',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '前一天',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: value.isAfter(DateTime(1))
                      ? () => onChanged!(
                          formatInputDate(
                            DateTime(value.year, value.month, value.day - 1),
                          ),
                        )
                      : null,
                  icon: const UiIcon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: '后一天',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: value.isBefore(DateTime(9999, 12, 31))
                      ? () => onChanged!(
                          formatInputDate(
                            DateTime(value.year, value.month, value.day + 1),
                          ),
                        )
                      : null,
                  icon: const UiIcon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ],
        if (returnToToday &&
            onChanged != null &&
            value != null &&
            _dailyDate(todayDate) != null &&
            (selectedDate ?? date) != todayDate)
          DateRevealNavigation(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onChanged!(todayDate!),
                child: const Text('回到今天'),
              ),
            ),
          ),
        if (summary != null && summary!.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              UiIcon(
                Icons.circle_outlined,
                size: 21,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (days.isNotEmpty) ...[
          const SizedBox(height: 22),
          IgnorePointer(
            ignoring: reveal?.isTransitioning == true,
            child: ExcludeSemantics(
              excluding: reveal?.isTransitioning == true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final shown = days.take(7).toList();
                  final occurrences = <Object?, int>{};
                  for (final entry in shown) {
                    final date = entry['date'];
                    occurrences[date] = (occurrences[date] ?? 0) + 1;
                  }
                  Key? dateKey(Map<String, Object?> entry) =>
                      occurrences[entry['date']] == 1
                      ? ValueKey('daily-date:${entry['date']}')
                      : null;
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  final cellWidth = 52 * textScale.clamp(1.0, double.infinity);
                  if (constraints.maxWidth < shown.length * cellWidth) {
                    return _ScrollableDateStrip(
                      selectedDate: selectedDate ?? date,
                      selectedIndex: shown.indexWhere(
                        (day) => day['date'] == (selectedDate ?? date),
                      ),
                      cellWidth: cellWidth,
                      viewportWidth: constraints.maxWidth,
                      children: [
                        for (final entry in shown)
                          SizedBox(
                            key: dateKey(entry),
                            width: cellWidth,
                            child: day(context, entry),
                          ),
                      ],
                    );
                  }
                  if (DailyDateStrip.supports(shown, selectedDate ?? date)) {
                    return DailyDateStrip(
                      days: shown,
                      selectedDate: selectedDate ?? date,
                      width: constraints.maxWidth,
                      animate: reveal == null,
                      onChanged: onChanged,
                      cellBuilder: (entry) => day(context, entry),
                    );
                  }
                  return Row(
                    children: [
                      for (final entry in shown)
                        Expanded(
                          key: dateKey(entry),
                          child: day(context, entry),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

/// The date strip keeps ordinary font sizes in a row; larger cells scroll.
/// Only date/geometry changes recenter it, preserving user scroll on count refresh.
class _ScrollableDateStrip extends StatefulWidget {
  const _ScrollableDateStrip({
    required this.selectedDate,
    required this.selectedIndex,
    required this.cellWidth,
    required this.viewportWidth,
    required this.children,
  });
  final String selectedDate;
  final int selectedIndex;
  final double cellWidth, viewportWidth;
  final List<Widget> children;
  @override
  State<_ScrollableDateStrip> createState() => _ScrollableDateStripState();
}

class _ScrollableDateStripState extends State<_ScrollableDateStrip> {
  double get offset =>
      ((widget.selectedIndex.clamp(0, widget.children.length - 1) + .5) *
                  widget.cellWidth -
              widget.viewportWidth / 2)
          .clamp(
            0.0,
            (widget.children.length * widget.cellWidth - widget.viewportWidth)
                .clamp(0.0, double.infinity),
          );
  late final ScrollController controller = ScrollController(
    initialScrollOffset: offset,
  );
  @override
  void didUpdateWidget(_ScrollableDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.children.length != widget.children.length ||
        oldWidget.cellWidth != widget.cellWidth ||
        oldWidget.viewportWidth != widget.viewportWidth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) controller.jumpTo(offset);
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    scrollDirection: Axis.horizontal,
    child: Row(children: widget.children),
  );
}

class DailySectionHeader extends StatelessWidget {
  const DailySectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.count,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });
  final String title;
  final String? subtitle, actionLabel, actionIcon;
  final Object? count;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (count != null)
            TextSpan(
              text: '  $count',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
    );
    final action = actionLabel == null
        ? null
        : Tooltip(
            message: actionLabel!,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (actionIcon == 'add')
                    const UiIcon(Icons.add_rounded, size: 22)
                  else ...[
                    Text(actionLabel!),
                    const SizedBox(width: 3),
                    const UiIcon(Icons.chevron_right_rounded, size: 18),
                  ],
                ],
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [heading, ?action],
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AgendaItem extends StatelessWidget {
  const AgendaItem({
    super.key,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.subtitle,
    this.color,
    this.badge,
    this.onPressed,
  });
  final String title, startTime, endTime;
  final String? subtitle, color, badge;
  final VoidCallback? onPressed;

  Color accent(BuildContext context) {
    final digits = color?.replaceFirst('#', '');
    final number = digits == null ? null : int.tryParse(digits, radix: 16);
    return number == null || (digits!.length != 6 && digits.length != 8)
        ? Theme.of(context).colorScheme.primary
        : Color(digits.length == 6 ? number | 0xff000000 : number);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = accent(context);
    final dark = theme.brightness == Brightness.dark;
    final timeWidth = 54.0 * MediaQuery.textScalerOf(context).scale(16) / 16;
    final surface = Material(
      color: Color.alphaBlend(
        tint.withValues(alpha: dark ? .16 : .09),
        theme.colorScheme.surface,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 3, color: tint),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (badge != null && badge!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final times = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          startTime,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          endTime,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        if (constraints.maxWidth - timeWidth <
            170 * textScale.clamp(1.0, double.infinity)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$startTime – $endTime', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              surface,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: timeWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: times,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: surface),
          ],
        );
      },
    );
  }
}

class DailyTaskItem extends StatelessWidget {
  const DailyTaskItem({
    super.key,
    required this.title,
    required this.completed,
    this.subtitle,
    this.onChanged,
    this.onOpen,
    this.details,
  });
  final String title;
  final bool completed;
  final String? subtitle;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onOpen;
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              height: 52,
              child: Checkbox(
                semanticLabel: '完成$title',
                value: completed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1.5,
                ),
                onChanged: onChanged == null
                    ? null
                    : (value) => onChanged!(value == true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (details != null)
          Padding(padding: const EdgeInsets.only(left: 52), child: details),
        const SizedBox(height: 6),
        Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: .35),
        ),
      ],
    );
  }
}
