import 'dart:convert';

import 'package:flutter/material.dart';

import 'temporal_input.dart';

/// A local form for ordered time ranges. Edits never invoke a module renderer;
/// the owner receives the complete draft and submits it through its normal flow.
class TimeRangeTable extends StatefulWidget {
  const TimeRangeTable({
    super.key,
    required this.value,
    required this.baseline,
    required this.onChanged,
    this.enabled = true,
  });

  final Map<String, Object?> value;
  final Map<String, Object?> baseline;
  final ValueChanged<Map<String, Object?>> onChanged;
  final bool enabled;

  @override
  State<TimeRangeTable> createState() => _TimeRangeTableState();
}

class _TimeRangeTableState extends State<TimeRangeTable> {
  late Map<String, Object?> draft = _copy(widget.value);
  late final duration = TextEditingController(
    text: '${draft['durationMinutes'] ?? ''}',
  );
  int revision = 0;

  static Map<String, Object?> _copy(Map<String, Object?> value) =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

  List<Map<String, Object?>> get rows => (draft['rows'] as List? ?? [])
      .map((row) => Map<String, Object?>.from(row as Map))
      .toList();

  static int? _minutes(Object? raw) {
    if (raw is! String || !RegExp(r'^\d{2}:\d{2}$').hasMatch(raw)) {
      return null;
    }
    final parts = raw.split(':').map(int.parse).toList();
    return parts[0] < 24 && parts[1] < 60 ? parts[0] * 60 + parts[1] : null;
  }

  static String _time(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  int? get durationMinutes {
    final text = '${draft['durationMinutes'] ?? ''}';
    final value = RegExp(r'^\d+$').hasMatch(text) ? int.tryParse(text) : null;
    return value != null && value >= 1 && value <= 1440 ? value : null;
  }

  static Object _comparable(Map<String, Object?> value) => [
    '${value['durationMinutes'] ?? ''}',
    for (final row in value['rows'] as List? ?? [])
      [row['id'], row['start'], row['end'], row['manualEnd'] == true],
  ];

  String? get error {
    if (durationMinutes == null) return '每节时长需为 1–1440 分钟的整数';
    var previousEnd = -1;
    for (final row in rows) {
      final start = _minutes(row['start']), end = _minutes(row['end']);
      if (start == null || end == null) {
        return '${row['label']}：请设置当日有效的开始和结束时间';
      }
      if (start < previousEnd || end <= start) {
        return '${row['label']}：时间不能重叠，结束时间需晚于开始时间';
      }
      previousEnd = end;
    }
    return null;
  }

  Map<String, Object?> _result() {
    final dirty =
        jsonEncode(_comparable(draft)) !=
        jsonEncode(_comparable(widget.baseline));
    return {
      ..._copy(draft),
      'dirty': dirty,
      'resetDisabled': !dirty,
      'saveDisabled': !dirty || error != null,
      'error': error,
    };
  }

  void _change(VoidCallback edit) {
    setState(() {
      edit();
      revision++;
    });
    widget.onChanged(_result());
  }

  Future<void> _pick(String id, String part) async {
    if (!widget.enabled) return;
    final row = rows.singleWhere((row) => row['id'] == id);
    final currentRevision = revision;
    bool current() => mounted && widget.enabled && revision == currentRevision;
    final selected = await pickTemporalValue(
      context,
      kind: TemporalInputKind.time,
      value: row[part],
      helpText: '${row['label']} · ${part == 'start' ? '开始时间' : '结束时间'}',
      isCurrent: current,
    );
    if (!current() || selected is! String || selected == row[part]) return;
    _change(() {
      final next = rows;
      final index = next.indexWhere((row) => row['id'] == id);
      final updated = {...next[index], part: selected};
      if (part == 'end') {
        updated['manualEnd'] = true;
      } else if (updated['manualEnd'] != true && durationMinutes != null) {
        final end = _minutes(selected)! + durationMinutes!;
        // Keep the chosen start visible, but require an explicit correction
        // instead of wrapping an automatic end time into the following day.
        updated['end'] = end < 1440 ? _time(end) : '';
      }
      next[index] = updated;
      draft['rows'] = next;
    });
  }

  @override
  void didUpdateWidget(TimeRangeTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(widget.value) != jsonEncode(oldWidget.value)) {
      draft = _copy(widget.value);
      revision++;
      final text = '${draft['durationMinutes'] ?? ''}';
      if (duration.text != text) duration.text = text;
    }
  }

  @override
  void dispose() {
    duration.dispose();
    super.dispose();
  }

  Widget _cell(Map<String, Object?> row, String part) {
    final manual = part == 'end' && row['manualEnd'] == true;
    final label = '${row['label']} · ${part == 'start' ? '开始时间' : '结束时间'}';
    return Semantics(
      label: label,
      button: true,
      enabled: widget.enabled,
      child: Tooltip(
        message: manual ? '$label（手动设置，保留此时间）' : label,
        child: InkWell(
          key: ValueKey('time-range-${row['id']}-$part'),
          onTap: widget.enabled ? () => _pick('${row['id']}', part) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${row[part] ?? ''}'.isEmpty ? '请选择' : '${row[part]}',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (manual)
                    Text(
                      '手动',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headingStyle = Theme.of(context).textTheme.labelLarge;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Text(text, style: headingStyle, textAlign: TextAlign.center),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('time-range-duration'),
          controller: duration,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '每节时长',
            suffixText: '分钟',
            errorText: durationMinutes == null ? '请输入 1–1440 之间的整数' : null,
          ),
          onChanged: (value) => _change(() => draft['durationMinutes'] = value),
        ),
        const SizedBox(height: 12),
        Text(
          '修改开始时间时自动计算结束时间，手动设置的结束时间会保留。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FlexColumnWidth(.85),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            border: TableBorder(
              horizontalInside: BorderSide(color: scheme.outlineVariant),
            ),
            children: [
              TableRow(
                decoration: BoxDecoration(color: scheme.surfaceContainerLow),
                children: [
                  for (final label in ['节次', '开始', '结束'])
                    TableCell(child: heading(label)),
                ],
              ),
              for (final row in rows)
                TableRow(
                  key: ValueKey(row['id']),
                  children: [
                    TableCell(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${row['label']}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    // Explicit cells preserve the semantic coordinate space
                    // when the first column has a different width.
                    TableCell(child: _cell(row, 'start')),
                    TableCell(child: _cell(row, 'end')),
                  ],
                ),
            ],
          ),
        ),
        if (error != null && durationMinutes != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: scheme.error)),
        ],
      ],
    );
  }
}
