import 'ui_icon.dart';
import 'ui_icons.dart';
import 'content_colors.dart';
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
      compact: props['compact'] == true,
      onChanged: disabled || events['change'] == null
          ? null
          : (date) => events['change']!(date),
      days: [
        for (final day
            in (props['showDays'] == false
                ? const []
                : props['days'] as List? ?? []))
          Map<String, Object?>.from(day as Map),
      ],
    ),
    'ui.sectionHeader@1' => DailySectionHeader(
      title: '${props['title'] ?? ''}',
      subtitle: props['subtitle'] as String?,
      count: props['count'],
      presentation: props['presentation'] as String?,
      countAtEnd: props['countPosition'] == 'end',
      actionLabel: props['actionLabel'] as String?,
      actionIcon: props['actionIcon'] as String?,
      onAction: disabled || events['press'] == null
          ? null
          : () => events['press']!(null),
      compact: props['compact'] == true,
    ),
    'ui.agendaItem@1' => AgendaItem(
      title: '${props['title'] ?? ''}',
      subtitle: props['subtitle'] as String?,
      timeline: props['presentation'] == 'timeline',
      first: props['first'] == true,
      last: props['last'] == true,
      startTime: '${props['startTime'] ?? ''}',
      endTime: '${props['endTime'] ?? ''}',
      color: props['color'] as String?,
      badge: props['badge'] as String?,
      highlighted: props['highlighted'] == true,
      compact: props['compact'] == true,
      hideTime: props['hideTime'] == true,
      eyebrow: props['eyebrow'] as String?,
      icon: props['icon'] as String?,
      onPressed: disabled || events['press'] == null
          ? null
          : () => events['press']!(null),
    ),
    'ui.taskItem@1' => DailyTaskItem(
      title: '${props['title'] ?? ''}',
      subtitle: props['subtitle'] as String?,
      completed: props['completed'] == true,
      compact: props['compact'] == true,
      timeline: props['presentation'] == 'timeline',
      record: props['presentation'] == 'record',
      first: props['first'] == true,
      last: props['last'] == true,
      startTime: props['startTime'] as String?,
      endTime: props['endTime'] as String?,
      color: props['color'] as String?,
      colorKey: props['colorKey'],
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
    this.compact = false,
  });
  final String date;
  final String? summary, selectedDate, todayDate;
  final ValueChanged<String>? onChanged;
  final bool dateHeading, dateControls;
  final bool returnToToday;
  final bool compact;
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
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 8 : 12,
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
                    if (compact) ...[
                      const SizedBox(height: 7),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? theme.colorScheme.onPrimary.withValues(
                                  alpha: .8,
                                )
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ] else if (indicators.isNotEmpty) ...[
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
                      final selected = await showAppDateSheet(
                        context: context,
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
        if (!compact && summary != null && summary!.isNotEmpty) ...[
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
          SizedBox(height: compact ? 0 : 22),
          IgnorePointer(
            ignoring: reveal?.isTransitioning == true,
            child: ExcludeFocus(
              excluding: reveal?.isTransitioning == true,
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
                    final cellWidth =
                        52 * textScale.clamp(1.0, double.infinity);
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
          ),
        ],
        SizedBox(height: compact ? 0 : 12),
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
    this.presentation,
    this.count,
    this.countAtEnd = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.compact = false,
  });
  final String title;
  final String? subtitle, actionLabel, actionIcon, presentation;
  final Object? count;
  final bool countAtEnd;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (presentation == 'summary' || presentation == 'group') {
      final summary = presentation == 'summary';
      return Padding(
        padding: EdgeInsets.only(top: summary ? 0 : 8, bottom: summary ? 0 : 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: summary ? 52 : 35),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: summary
                      ? theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (actionLabel != null)
                Tooltip(
                  message: actionLabel!,
                  child: TextButton.icon(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(48, 48),
                    ),
                    icon: UiIcon(
                      actionIcon == 'add'
                          ? Icons.add_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 17,
                    ),
                    label: Text(actionLabel!),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final heading = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: title,
            style:
                (compact
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (count != null && !countAtEnd)
            TextSpan(
              text: '  $count',
              style:
                  (compact
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
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
                    UiIcon(
                      Icons.add_rounded,
                      size: 22,
                      semanticLabel: actionLabel,
                    )
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
            children: [
              heading,
              if (countAtEnd && count != null)
                Text(
                  '$count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ?action,
            ],
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
    this.compact = false,
    this.timeline = false,
    this.highlighted = false,
    this.first = false,
    this.last = false,
    this.hideTime = false,
    this.eyebrow,
    this.icon,
  });
  final String title, startTime, endTime;
  final String? subtitle, color, badge;
  final VoidCallback? onPressed;
  final bool compact, hideTime, timeline, highlighted, first, last;
  final String? eyebrow, icon;

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
    if (timeline) {
      final scheme = theme.colorScheme;
      final marker = highlighted ? scheme.primary : const Color(0xFF7F9D80);
      final badgeStyle = theme.textTheme.labelSmall?.copyWith(
        color: scheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      );
      final badgeLabel = badge == null ? null : Text(badge!, style: badgeStyle);
      return AgendaTimeLayout(
        startTime: startTime,
        endTime: endTime,
        marker: marker,
        first: first,
        last: last,
        emphasized: highlighted,
        child: Material(
          color: highlighted ? scheme.primaryContainer : scheme.surface,
          shape: AppDesign.smoothShape(
            radius: 15,
            side: BorderSide(color: scheme.outlineVariant, width: .8),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 61),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final wrapBadge =
                        box.maxWidth <
                        235 * MediaQuery.textScalerOf(context).scale(14) / 14;
                    return Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: ShapeDecoration(
                            shape: AppDesign.smoothShape(radius: 9),
                            color: highlighted
                                ? scheme.surface
                                : Color.alphaBlend(
                                    marker.withValues(alpha: .18),
                                    scheme.surface,
                                  ),
                          ),
                          child: UiIcon(
                            appIconData(icon ?? 'school'),
                            size: 18,
                            color: highlighted ? scheme.primary : marker,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (subtitle?.isNotEmpty == true)
                                Text(
                                  subtitle!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              if (wrapBadge && badgeLabel != null) badgeLabel,
                            ],
                          ),
                        ),
                        if (!wrapBadge && badgeLabel != null) ...[
                          const SizedBox(width: 4),
                          badgeLabel,
                        ],
                        if (onPressed != null && !wrapBadge)
                          const UiIcon(Icons.chevron_right_rounded, size: 14),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (compact) {
      final surface = Material(
        color: Color.alphaBlend(
          tint.withValues(alpha: dark ? .18 : .09),
          theme.colorScheme.surface,
        ),
        shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 3, color: tint),
                const SizedBox(width: 12),
                UiIcon(
                  appIconData(icon ?? 'school'),
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow?.isNotEmpty == true)
                          Text(
                            eyebrow!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (badge?.isNotEmpty == true) ...[
                          const SizedBox(height: 5),
                          Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onPressed != null)
                  UiIcon(
                    appIconData('right'),
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      );
      return hideTime
          ? surface
          : AgendaTimeLayout(
              startTime: startTime,
              endTime: endTime,
              child: surface,
            );
    }
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
    this.compact = false,
    this.timeline = false,
    this.record = false,
    this.first = false,
    this.last = false,
    this.startTime,
    this.endTime,
    this.color,
    this.colorKey,
  });
  final String title;
  final bool completed;
  final String? subtitle;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onOpen;
  final Widget? details;
  final bool compact, timeline, record, first, last;
  final String? startTime, endTime, color;
  final Object? colorKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (record) {
      final scheme = theme.colorScheme;
      return ListTile(
        leading: IconButton(
          tooltip: completed ? '重新打开$title' : '完成$title',
          onPressed: onChanged == null ? null : () => onChanged!(!completed),
          icon: Icon(
            completed ? Icons.check_circle_outline : Icons.circle_outlined,
            color: scheme.onSurfaceVariant,
            size: 20,
          ),
        ),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: onOpen == null
            ? null
            : const Icon(Icons.chevron_right, size: 18),
        minTileHeight: 60,
        horizontalTitleGap: 4,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        onTap: onOpen,
      );
    }
    if (compact) {
      final colored = color != null || colorKey != null;
      final tint = colored
          ? ContentColors.accent(colorKey, color: color)
          : theme.colorScheme.primary;
      final background = colored && !completed
          ? ContentColors.surface(tint, theme.colorScheme)
          : Color.alphaBlend(
              tint.withValues(alpha: completed ? .06 : 0),
              theme.colorScheme.surface,
            );
      final foreground = colored && !completed
          ? ContentColors.foreground(
              tint,
              background,
              theme.colorScheme.onSurface,
            )
          : theme.colorScheme.onSurface;
      final timed = startTime != null && endTime != null;
      final scheme = theme.colorScheme;
      final surface = Material(
        type: timeline && timed
            ? MaterialType.transparency
            : MaterialType.canvas,
        color: timeline ? (timed ? null : scheme.surface) : background,
        shape: AppDesign.smoothShape(
          radius: timeline ? 16 : AppDesign.controlRadius,
          side: timeline && !timed
              ? BorderSide(color: scheme.outlineVariant, width: .8)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Checkbox(
                    semanticLabel: completed ? '重新打开$title' : '完成$title',
                    value: completed,
                    fillColor: timeline
                        ? WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? scheme.primaryContainer
                                : scheme.surface,
                          )
                        : null,
                    checkColor: timeline ? scheme.primary : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(timeline ? 6 : 4),
                    ),
                    side: timeline
                        ? WidgetStateBorderSide.resolveWith(
                            (states) => BorderSide(
                              color: states.contains(WidgetState.selected)
                                  ? scheme.primary
                                  : scheme.outline,
                              width: 1,
                            ),
                          )
                        : BorderSide(color: scheme.outline, width: 1.5),
                    onChanged: onChanged == null
                        ? null
                        : (value) => onChanged!(value == true),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: timeline ? 62 : 48,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: completed
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                                color: completed
                                    ? theme.colorScheme.onSurfaceVariant
                                    : timeline
                                    ? scheme.onSurface
                                    : foreground,
                                decoration: completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (subtitle?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
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
                ),
              ],
            ),
            if (details != null)
              Padding(padding: const EdgeInsets.only(left: 48), child: details),
          ],
        ),
      );
      return startTime == null || endTime == null
          ? surface
          : AgendaTimeLayout(
              startTime: startTime!,
              endTime: endTime!,
              marker: timeline ? scheme.outline : null,
              first: first,
              last: last,
              child: surface,
            );
    }
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

/// Optional time gutter shared by different module-provided agenda records.
/// Narrow screens and large fonts place the time above the full-width content.
class AgendaTimeLayout extends StatelessWidget {
  const AgendaTimeLayout({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.child,
    this.marker,
    this.first = false,
    this.last = false,
    this.emphasized = false,
    this.hollow = false,
    this.topAligned = false,
  });
  final bool hollow, topAligned;
  final String startTime, endTime;
  final Widget child;
  final Color? marker;
  final bool first, last, emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (marker != null) {
      final scheme = theme.colorScheme;
      final narrow = MediaQuery.sizeOf(context).width <= 360;
      final timeWidth = narrow ? 51.0 : 48.0 * scale.clamp(1.0, 1.35);
      final timeGap = narrow ? 14.0 : 26.0;
      return Stack(
        children: [
          PositionedDirectional(
            start: timeWidth + (narrow ? 2 : 6),
            top: 0,
            bottom: 0,
            width: 9,
            child: Column(
              children: [
                if (topAligned)
                  SizedBox(
                    height: 18,
                    child: VerticalDivider(
                      width: 1,
                      color: first ? Colors.transparent : scheme.outlineVariant,
                    ),
                  )
                else
                  Expanded(
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: first ? Colors.transparent : scheme.outlineVariant,
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hollow ? scheme.surface : marker,
                    border: hollow ? Border.all(color: marker!) : null,
                  ),
                  child: const SizedBox.square(dimension: 9),
                ),
                Expanded(
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: last ? Colors.transparent : scheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: topAligned ? 10 : 4),
              child: Row(
                crossAxisAlignment: topAligned
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: timeWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            startTime,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: emphasized
                                  ? scheme.primary
                                  : scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            endTime,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: timeGap),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$startTime – $endTime', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              child,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46 * scale,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(startTime, style: theme.textTheme.labelMedium),
                    Text(
                      endTime,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
