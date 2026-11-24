import 'ui_icon.dart';
import '../../features/settings/settings_widgets.dart'
    show SettingsSheet, showSettingsModal;
import 'script_form_controls.dart';

import 'package:clock/clock.dart' show clock;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'ui_design.dart';

part 'date_selection_sheet.dart';

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
  String? helpText,
  String? rangeHint,
}) async {
  bool current() => context.mounted && (isCurrent?.call() ?? true);
  final now = clock.now();
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
    final start = initial(range['start']);
    final selectedStart = await showAppDateSheet(
      context: context,
      helpText: '选择开始日期',
      initialDate: start,
      firstDate: first,
      lastDate: last,
      confirmLabel: '下一步',
    );
    if (!context.mounted || !current() || selectedStart == null) return null;
    final end = range['end'] == null ? selectedStart : initial(range['end']);
    final selectedEnd = await showAppDateSheet(
      context: context,
      helpText: '选择结束日期',
      initialDate: end.isBefore(selectedStart) ? selectedStart : end,
      firstDate: selectedStart,
      lastDate: last,
      rangeHint: '开始日期为 ${selectedStart.month} 月 ${selectedStart.day} 日',
    );
    return !current() || selectedEnd == null
        ? null
        : {
            'start': formatInputDate(selectedStart),
            'end': formatInputDate(selectedEnd),
          };
  }
  DateTime? date;
  if (kind != TemporalInputKind.time) {
    date = await showAppDateSheet(
      context: context,
      helpText: helpText ?? '选择日期',
      initialDate: initial(value),
      firstDate: first,
      lastDate: last,
      rangeHint: rangeHint,
    );
    if (!current() || date == null) return null;
    if (kind == TemporalInputKind.date) return formatInputDate(date);
  }
  if (!context.mounted || !current()) return null;
  final match = RegExp(r'^(\d{2}):(\d{2})')
      .firstMatch('$value'.split('T').last);
  final selected = await showSettingsModal<TimeOfDay>(
    compactFrame: true,
    context: context,
    builder: (_) => _TimeWheelPicker(
      initial: TimeOfDay(
        hour: (int.tryParse(match?[1] ?? '') ?? now.hour).clamp(0, 23),
        minute: (int.tryParse(match?[2] ?? '') ?? now.minute).clamp(0, 59),
      ),
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
    this.helperText,
    this.minDate,
    this.maxDate,
    this.isCurrent,
    this.legacyDateTime = false,
    this.externalLabel = false,
    this.buttonLabel,
    this.buttonCaption,
  });
  final TemporalInputKind kind;
  final String label;
  final Object? value;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<Object?> onChanged;
  final bool enabled, clearable, editable, legacyDateTime, externalLabel;
  final String? errorText,
      helperText,
      minDate,
      maxDate,
      buttonLabel,
      buttonCaption;
  final bool Function()? isCurrent;

  @override
  Widget build(BuildContext context) {
    if (kind == TemporalInputKind.dateRange) {
      return _DateRangeInput(input: this);
    }
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
        value: controller?.text ?? value,
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

    if (buttonLabel != null && kind == TemporalInputKind.date) {
      if (buttonCaption != null) {
        final theme = Theme.of(context);
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: AlignmentDirectional.centerStart,
            ),
            onPressed: enabled ? choose : null,
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  buttonLabel!,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                UiIcon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Text(
                  buttonCaption!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: enabled ? choose : null,
          iconAlignment: IconAlignment.end,
          icon: const UiIcon(Icons.keyboard_arrow_down_rounded, size: 16),
          label: Text(
            buttonLabel!,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
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
            icon: const UiIcon(Icons.close_rounded),
          ),
        IconButton(
          tooltip: '选择$label',
          onPressed: enabled ? choose : null,
          icon: UiIcon(icon),
        ),
      ],
    );
    final decoration =
        (externalLabel
                ? AppDesign.outlinedField(context)
                : const InputDecoration())
            .copyWith(
              labelText: externalLabel ? null : label,
              enabled: enabled,
              errorText: validation,
              helperText: helperText,
              helperMaxLines: 3,
              suffixIcon: actions,
            );
    if (externalLabel &&
        !editable &&
        (kind == TemporalInputKind.date || kind == TemporalInputKind.time)) {
      final date = parseInputDate(currentValue);
      final display = date == null
          ? currentValue?.toString() ?? ''
          : MaterialLocalizations.of(context).formatFullDate(date);
      return ScriptFieldLabel(
        label: label,
        child: InkWell(
          onTap: enabled ? choose : null,
          borderRadius: BorderRadius.circular(AppDesign.compactRadius),
          child: InputDecorator(
            decoration: decoration,
            isEmpty: !hasValue,
            child: Text(display.isEmpty ? '点击选择' : display),
          ),
        ),
      );
    }
    if (controller != null) {
      final field = TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        readOnly: !editable,
        onTap: editable ? null : choose,
        decoration: decoration,
        onChanged: (text) => onChanged(text.isEmpty ? null : text),
      );
      return externalLabel
          ? ScriptFieldLabel(label: label, child: field)
          : field;
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

class _TimeWheelPicker extends StatefulWidget {
  const _TimeWheelPicker({required this.initial});
  final TimeOfDay initial;

  @override
  State<_TimeWheelPicker> createState() => _TimeWheelPickerState();
}

class _TimeWheelPickerState extends State<_TimeWheelPicker> {
  late final FixedExtentScrollController hours;
  late final FixedExtentScrollController minutes;
  late int hour, minute;

  @override
  void initState() {
    super.initState();
    hour = widget.initial.hour;
    minute = widget.initial.minute;
    hours = FixedExtentScrollController(initialItem: hour);
    minutes = FixedExtentScrollController(initialItem: minute);
  }

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemExtent = (MediaQuery.textScalerOf(context).scale(22) + 14).clamp(
      48.0,
      80.0,
    );
    Widget wheel(
      String label,
      int count,
      FixedExtentScrollController controller,
      ValueChanged<int> changed,
    ) => Expanded(
      child: Semantics(
        label: label,
        child: CupertinoPicker(
          key: ValueKey('time-wheel-$label'),
          scrollController: controller,
          itemExtent: itemExtent,
          selectionOverlay: null,
          onSelectedItemChanged: changed,
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text(
                  i.toString().padLeft(2, '0'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 22,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return SettingsSheet(
      title: const Text('选择时间'),
      showClose: true,
      expandedActions: true,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, TimeOfDay(hour: hour, minute: minute)),
          child: const Text('确定'),
        ),
      ],
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Expanded(child: Text('小时', textAlign: TextAlign.center)),
                Expanded(child: Text('分钟', textAlign: TextAlign.center)),
              ],
            ),
            SizedBox(
              height: itemExtent * 5,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: itemExtent,
                    decoration: ShapeDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: AppDesign.smoothShape(
                        radius: AppDesign.controlRadius,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      wheel('小时', 24, hours, (value) => hour = value),
                      wheel('分钟', 60, minutes, (value) => minute = value),
                    ],
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

class _DateRangeInput extends StatefulWidget {
  const _DateRangeInput({required this.input});
  final TemporalInput input;
  @override
  State<_DateRangeInput> createState() => _DateRangeInputState();
}

class _DateRangeInputState extends State<_DateRangeInput> {
  TemporalInput get input => widget.input;
  String? endpoint(String key) {
    final value = input.value;
    final raw = value is Map ? value[key] : null;
    return raw is String ? raw : null;
  }

  Future<void> choose(bool beginning) async {
    final previous = input.value;
    final start = parseInputDate(endpoint('start'));
    final minimum = parseInputDate(input.minDate);
    final lower =
        !beginning &&
            start != null &&
            (minimum == null || start.isAfter(minimum))
        ? start
        : minimum;
    final selected = await pickTemporalValue(
      context,
      kind: beginning ? TemporalInputKind.dateRange : TemporalInputKind.date,
      rangeHint: !beginning && start != null
          ? '开始日期为 ${start.month} 月 ${start.day} 日'
          : null,
      helpText: beginning ? '选择开始日期' : '选择结束日期',
      value: beginning ? previous : endpoint('end'),
      minDate: lower == null ? null : formatInputDate(lower),
      maxDate: input.maxDate,
      isCurrent: () =>
          identical(previous, input.value) && (input.isCurrent?.call() ?? true),
    );
    if (!mounted ||
        selected == null ||
        !identical(previous, input.value) ||
        !(input.isCurrent?.call() ?? true)) {
      return;
    }
    input.onChanged(
      beginning
          ? selected
          : {'start': endpoint('start') ?? selected, 'end': selected},
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = endpoint('start'), end = endpoint('end');
    final value = input.value;
    final error =
        input.errorText ??
        validateTemporalInput(
          TemporalInputKind.dateRange,
          value,
          minDate: input.minDate,
          maxDate: input.maxDate,
        );
    Widget dateField(String label, String? value, bool beginning) =>
        ScriptFieldLabel(
          label: label,
          child: InkWell(
            onTap: input.enabled ? () => choose(beginning) : null,
            child: InputDecorator(
              decoration: AppDesign.outlinedField(context).copyWith(
                enabled: input.enabled,
                contentPadding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
                suffixIconConstraints: const BoxConstraints(minWidth: 36),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (input.clearable && value != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '清除$label',
                        onPressed: input.enabled
                            ? () => input.onChanged(null)
                            : null,
                        icon: const UiIcon(Icons.close_rounded, size: 16),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '选择$label',
                      onPressed: input.enabled ? () => choose(beginning) : null,
                      icon: const UiIcon(
                        Icons.calendar_today_outlined,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              isEmpty: value == null,
              child: Text(value ?? '点击选择'),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(input.label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              dateField('开始日期', start, true),
              dateField('结束日期', end, false),
            ];
            final minimum =
                (input.clearable ? 380 : 310) *
                MediaQuery.textScalerOf(context).scale(1);
            if (constraints.maxWidth < minimum) {
              return Column(spacing: 12, children: fields);
            }
            return Row(
              spacing: 10,
              children: [for (final field in fields) Expanded(child: field)],
            );
          },
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
