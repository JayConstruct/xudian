import 'dart:convert';

import 'package:flutter/material.dart';

import 'module_package.dart';
import '../ui/ui_component.dart';
import '../ui/temporal_input.dart';
import '../ui/input_validation.dart';

Future<bool> reviewDialog(
  BuildContext context,
  String title,
  Object? details,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => UiPackScope(
        defaultOnly: true,
        child: AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(details),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    ) ??
    false;

class HostFormDialog extends StatefulWidget {
  const HostFormDialog({super.key, required this.title, required this.fields});
  final String title;
  final List<Map<String, Object?>> fields;
  @override
  State<HostFormDialog> createState() => _HostFormDialogState();
}

class _HostFormDialogState extends State<HostFormDialog> {
  final controllers = <String, TextEditingController>{};
  final selections = <String, String?>{};
  final booleans = <String, bool>{};
  final multiples = <String, Set<String>>{};
  final errors = <String, String>{};
  final ranges = <String, Object?>{};
  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      final key = field['key'] as String;
      if (field['type'] == 'select') {
        final value = field['value'];
        selections[key] =
            (field['options'] as List? ?? []).any(
              (o) => object(o)['value'] == value,
            )
            ? value as String?
            : null;
      } else if (field['type'] == 'boolean') {
        booleans[key] = field['value'] == true;
      } else if (field['type'] == 'multiSelect') {
        multiples[key] = (field['value'] is List ? field['value'] as List : [])
            .cast<String>()
            .toSet();
      } else if (field['type'] == 'dateRange') {
        ranges[key] = field['value'];
      } else {
        controllers[key] = TextEditingController(
          text: '${field['value'] ?? ''}',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void submit() {
    final result = <String, Object?>{
      ...selections,
      ...booleans,
      ...ranges,
      for (final e in multiples.entries) e.key: e.value.toList(),
    };
    errors.clear();
    for (final field in widget.fields) {
      final key = field['key'] as String, type = field['type'];
      final text = controllers[key]?.text;
      if (text != null) result[key] = text;
      if (field['required'] == true &&
          (result[key] == null ||
              result[key] == '' ||
              result[key] is List && (result[key] as List).isEmpty)) {
        errors[key] = '请填写此项';
      }
      if (type == 'number') {
        final value = num.tryParse(text ?? '');
        final error = validateNumberInput(
          text ?? '',
          integer: field['integer'] == true,
          min: field['min'] as num?,
          max: field['max'] as num?,
        );
        if (value == null || error != null) {
          errors[key] = error ?? '请输入有效数字';
        } else {
          result[key] = value;
        }
      }
      if (_temporalKind(type) case final kind?) {
        final error = validateTemporalInput(
          kind,
          result[key],
          minDate: field['minDate'] as String?,
          maxDate: field['maxDate'] as String?,
          legacyDateTime: true,
        );
        if (error != null) errors[key] = error;
      }
      if (field['maxLength'] is int &&
          (text?.length ?? 0) > (field['maxLength'] as int)) {
        errors[key] = '内容超过长度限制';
      }
    }
    if (errors.isNotEmpty) {
      setState(() {});
      return;
    }
    Navigator.pop(context, result);
  }

  TemporalInputKind? _temporalKind(Object? type) => switch (type) {
    'date' => TemporalInputKind.date,
    'time' => TemporalInputKind.time,
    'datetime' => TemporalInputKind.dateTime,
    'dateRange' => TemporalInputKind.dateRange,
    _ => null,
  };

  Widget _field(Map<String, Object?> field) {
    final key = field['key'] as String;
    final label = '${field['label']}';
    if (_temporalKind(field['type']) case final kind?) {
      return TemporalInput(
        kind: kind,
        label: label,
        controller: controllers[key],
        value: ranges[key],
        errorText: errors[key],
        clearable: field['clearable'] != false,
        minDate: field['minDate'] as String?,
        maxDate: field['maxDate'] as String?,
        legacyDateTime: true,
        onChanged: (value) => setState(() {
          if (kind == TemporalInputKind.dateRange) ranges[key] = value;
          errors.remove(key);
        }),
      );
    }
    if (field['type'] == 'boolean') {
      return CheckboxListTile(
        title: Text(label),
        value: booleans[key] ?? false,
        onChanged: (value) => setState(() => booleans[key] = value == true),
      );
    }
    if (field['type'] == 'multiSelect') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in (field['options'] as List? ?? []).map(
                object,
              ))
                FilterChip(
                  label: Text('${option['label']}'),
                  selected: multiples[key]!.contains(option['value']),
                  onSelected: (selected) => setState(() {
                    final value = option['value'] as String;
                    if (selected) {
                      multiples[key]!.add(value);
                    } else {
                      multiples[key]!.remove(value);
                    }
                    errors.remove(key);
                  }),
                ),
            ],
          ),
          if (errors[key] != null)
            Text(
              errors[key]!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      );
    }
    if (field['type'] == 'select') {
      return DropdownButtonFormField<String>(
        initialValue: selections[key],
        isExpanded: true,
        decoration: InputDecoration(labelText: label, errorText: errors[key]),
        items: [
          for (final option in (field['options'] as List? ?? []).map(object))
            DropdownMenuItem(
              value: option['value'] as String,
              child: Text(
                '${option['label']}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) => setState(() {
          selections[key] = value;
          errors.remove(key);
        }),
      );
    }
    return TextField(
      controller: controllers[key],
      obscureText: field['type'] == 'secret',
      enableSuggestions: field['type'] != 'secret',
      autocorrect: field['type'] != 'secret',
      minLines: field['type'] == 'multiline' ? 3 : 1,
      maxLines: field['type'] == 'multiline' ? 10 : 1,
      keyboardType: field['type'] == 'number'
          ? TextInputType.numberWithOptions(
              decimal: field['integer'] != true,
              signed: true,
            )
          : null,
      decoration: InputDecoration(labelText: label, errorText: errors[key]),
      onChanged: (_) => setState(() => errors.remove(key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final native = AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _fieldWrap(field, _field(field)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: submit, child: const Text('继续')),
      ],
    );
    final form = UiComponent(
      ref: 'ui.page.form@1',
      props: {'title': widget.title},
      slots: {
        'fields': native.content!,
        'actions': Wrap(spacing: 8, children: native.actions!),
      },
      fallback: native,
    );
    return UiComponent(
      ref: 'ui.dialog@1',
      props: {'title': widget.title},
      slots: {'content': form},
      fallback: form,
    );
  }

  Widget _fieldWrap(Map<String, Object?> field, Widget native) {
    final ref = switch (field['type']) {
      'boolean' => 'ui.checkbox@1',
      'select' => 'ui.select@1',
      'multiSelect' => 'ui.multiSelect@1',
      'number' => 'ui.numberInput@1',
      'date' => 'ui.dateInput@1',
      'datetime' => 'ui.dateTimeInput@1',
      'time' => 'ui.timeInput@1',
      'dateRange' => 'ui.dateRangeInput@1',
      _ => 'ui.input@1',
    };
    return UiComponent(
      key: ValueKey(field['key']),
      ref: ref,
      props: {'label': field['label'], 'key': field['key']},
      slots: {'control': native},
      fallback: native,
      defaultOnly: field['type'] == 'secret',
    );
  }
}
