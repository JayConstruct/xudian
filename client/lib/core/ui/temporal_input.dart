import 'package:flutter/material.dart';

enum TemporalInputKind { date, time, dateTime, dateRange }

String formatInputDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? parseInputDate(Object? raw) {
  if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return null;
  }
  final date = DateTime.tryParse(raw);
  return date != null && formatInputDate(date) == raw ? date : null;
}

String? validateTemporalInput(
  TemporalInputKind kind,
  Object? value, {
  String? minDate,
  String? maxDate,
  bool legacyDateTime = false,
}) {
  if (value == null || value == '') return null;
  final first = parseInputDate(minDate), last = parseInputDate(maxDate);
  if (first != null && last != null && first.isAfter(last)) {
    return '可选日期范围无效';
  }
  String? bounds(DateTime date) {
    final day = DateUtils.dateOnly(date);
    if (first != null && day.isBefore(first) ||
        last != null && day.isAfter(last)) {
      return '请选择允许范围内的日期';
    }
    return null;
  }

  bool validTime(String raw) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(raw);
    return match != null &&
        int.parse(match[1]!) < 24 &&
        int.parse(match[2]!) < 60;
  }

  switch (kind) {
    case TemporalInputKind.time:
      return value is String && validTime(value) ? null : '请输入有效 HH:mm 时间';
    case TemporalInputKind.date:
      final date = parseInputDate(value);
      return date == null ? '请输入有效 YYYY-MM-DD 日期' : bounds(date);
    case TemporalInputKind.dateTime:
      if (value is! String) return '请输入有效日期时间';
      final parts = value.split('T');
      final date = parts.length == 2 ? parseInputDate(parts.first) : null;
      if (date != null && validTime(parts.last)) return bounds(date);
      if (legacyDateTime && DateTime.tryParse(value) != null) {
        return bounds(DateTime.parse(value));
      }
      return '请输入有效 YYYY-MM-DDTHH:mm 日期时间';
    case TemporalInputKind.dateRange:
      if (value is! Map) return '请选择完整日期范围';
      final start = parseInputDate(value['start']),
          end = parseInputDate(value['end']);
      if (start == null || end == null) return '请选择完整日期范围';
      if (start.isAfter(end)) return '结束日期不能早于开始日期';
      return bounds(start) ?? bounds(end);
  }
}

Future<Object?> pickTemporalValue(
  BuildContext context, {
  required TemporalInputKind kind,
  Object? value,
  String? minDate,
  String? maxDate,
  bool Function()? isCurrent,
}) async {
  bool current() => context.mounted && (isCurrent?.call() ?? true);
  final now = DateTime.now();
  final first = parseInputDate(minDate) ?? DateTime(1900);
  final last = parseInputDate(maxDate) ?? DateTime(2100, 12, 31);
  if (last.isBefore(first) || !current()) return null;
  DateTime initial(Object? raw) {
    final parsed = raw is String ? DateTime.tryParse(raw) : null;
    final date = DateUtils.dateOnly(parsed ?? now);
    return date.isBefore(first)
        ? first
        : date.isAfter(last)
        ? last
        : date;
  }

  if (kind == TemporalInputKind.dateRange) {
    final range = value is Map ? value : const {};
    final start = initial(range['start']), end = initial(range['end']);
    final selected = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: range['start'] == null || range['end'] == null
          ? null
          : DateTimeRange(start: start, end: end.isBefore(start) ? start : end),
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        final theme = DatePickerTheme.of(context);
        final defaultStyle = DatePickerTheme.defaults(context)
            .rangePickerHeaderHeadlineStyle!;
        final style = defaultStyle
            .merge(theme.rangePickerHeaderHeadlineStyle)
            .copyWith(
              fontSize:
                  theme.rangePickerHeaderHeadlineStyle?.fontSize ??
                  defaultStyle.fontSize,
            );
        final scaler = MediaQuery.textScalerOf(context)
            .clamp(maxScaleFactor: 1.3);
        final localizations = MaterialLocalizations.of(context);
        // The native range header keeps the start date in a fixed-width row.
        // Measure every month so selecting a longer or cross-year date still
        // fits, including the animation from the smaller input-mode dialog.
        // Leave space for the end date and retain text scaling.
        var widest = 0.0;
        for (var month = 1; month <= 12; month++) {
          final painter = TextPainter(
            text: TextSpan(
              text:
                  '${localizations.formatShortDate(DateTime(last.year, month, 28))} – ',
              style: style,
            ),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          if (painter.width > widest) widest = painter.width;
          painter.dispose();
        }
        final headerWidth = (width - 32).clamp(
          0.0,
          MediaQuery.orientationOf(context) == Orientation.portrait
              ? 328.0
              : 496.0,
        );
        final available = (headerWidth - (width < 360 ? 42 : 72) - 64 - 48)
            .clamp(48.0, double.infinity);
        if (widest <= available) return child!;
        return DatePickerTheme(
          data: theme.copyWith(
            rangePickerHeaderHeadlineStyle: style.copyWith(
              fontSize: style.fontSize! * available / widest,
            ),
          ),
          child: child!,
        );
      },
    );
    return !current() || selected == null
        ? null
        : {
            'start': formatInputDate(selected.start),
            'end': formatInputDate(selected.end),
          };
  }
  DateTime? date;
  if (kind != TemporalInputKind.time) {
    date = await showDatePicker(
      context: context,
      initialDate: initial(value),
      firstDate: first,
      lastDate: last,
    );
    if (!current() || date == null) return null;
    if (kind == TemporalInputKind.date) return formatInputDate(date);
  }
  if (!context.mounted || !current()) return null;
  final match = RegExp(r'^(\d{2}):(\d{2})')
      .firstMatch('$value'.split('T').last);
  final selected = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: (int.tryParse(match?[1] ?? '') ?? now.hour).clamp(0, 23),
      minute: (int.tryParse(match?[2] ?? '') ?? now.minute).clamp(0, 59),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (!current() || selected == null) return null;
  final time =
      '${selected.hour.toString().padLeft(2, '0')}:'
      '${selected.minute.toString().padLeft(2, '0')}';
  return date == null ? time : '${formatInputDate(date)}T$time';
}

/// The host owns the controller and value, including invalid editing text.
class TemporalInput extends StatelessWidget {
  const TemporalInput({
    super.key,
    required this.kind,
    required this.label,
    required this.onChanged,
    this.controller,
    this.focusNode,
    this.value,
    this.enabled = true,
    this.clearable = true,
    this.editable = true,
    this.errorText,
    this.minDate,
    this.maxDate,
    this.isCurrent,
    this.legacyDateTime = false,
  });
  final TemporalInputKind kind;
  final String label;
  final Object? value;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<Object?> onChanged;
  final bool enabled, clearable, editable, legacyDateTime;
  final String? errorText, minDate, maxDate;
  final bool Function()? isCurrent;

  @override
  Widget build(BuildContext context) {
    final icon = kind == TemporalInputKind.time
        ? Icons.access_time_rounded
        : kind == TemporalInputKind.dateRange
        ? Icons.date_range_outlined
        : Icons.calendar_today_outlined;
    final currentValue = controller?.text ?? value;
    final validation =
        errorText ??
        validateTemporalInput(
          kind,
          currentValue,
          minDate: minDate,
          maxDate: maxDate,
          legacyDateTime: legacyDateTime,
        );
    Future<void> choose() async {
      final before = controller?.text;
      final selected = await pickTemporalValue(
        context,
        kind: kind,
        value: currentValue,
        minDate: minDate,
        maxDate: maxDate,
        isCurrent: () =>
            (isCurrent?.call() ?? true) && controller?.text == before,
      );
      if (context.mounted && selected != null && (isCurrent?.call() ?? true)) {
        if (controller != null) controller!.text = '$selected';
        onChanged(selected);
      }
    }

    final hasValue = currentValue != null && currentValue != '';
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (clearable && hasValue)
          IconButton(
            tooltip: '清除$label',
            onPressed: enabled
                ? () {
                    controller?.clear();
                    onChanged(null);
                  }
                : null,
            icon: const Icon(Icons.close_rounded),
          ),
        IconButton(
          tooltip: '选择$label',
          onPressed: enabled ? choose : null,
          icon: Icon(icon),
        ),
      ],
    );
    final decoration = InputDecoration(
      labelText: label,
      enabled: enabled,
      errorText: validation,
      suffixIcon: actions,
    );
    if (controller != null) {
      return TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        readOnly: !editable,
        onTap: editable ? null : choose,
        decoration: decoration,
        onChanged: (text) => onChanged(text.isEmpty ? null : text),
      );
    }
    final display = value is Map
        ? '${(value as Map)['start']} 至 ${(value as Map)['end']}'
        : '${value ?? ''}'.replaceFirst('T', ' ');
    return InputDecorator(
      decoration: decoration,
      isEmpty: !hasValue,
      child: InkWell(
        onTap: enabled ? choose : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(display.isEmpty ? '点击选择' : display),
        ),
      ),
    );
  }
}
