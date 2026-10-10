import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/declarative/declarative_module.dart';

Future<Map<String, Object?>?> showDeclarativeFieldEditor({
  required BuildContext context,
  required DeclarativeModule module,
  required Map<String, Object?> current,
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => _DeclarativeFieldEditor(module: module, current: current),
  );
}

class _DeclarativeFieldEditor extends StatefulWidget {
  const _DeclarativeFieldEditor({required this.module, required this.current});

  final DeclarativeModule module;
  final Map<String, Object?> current;

  @override
  State<_DeclarativeFieldEditor> createState() =>
      _DeclarativeFieldEditorState();
}

class _DeclarativeFieldEditorState extends State<_DeclarativeFieldEditor> {
  String? error;
  final controllers = <String, TextEditingController>{};
  final booleans = <String, bool>{};
  final selections = <String, String?>{};
  final multiSelections = <String, Set<String>>{};
  final dateValues = <String, String?>{};

  @override
  void initState() {
    super.initState();
    for (final field in widget.module.fields) {
      final id = field['id'] as String;
      final type = field['type'] as String;
      final key = '${widget.module.manifest.id}:$id';
      final value = widget.current[key];
      switch (type) {
        case 'boolean':
          booleans[id] = value == true;
        case 'select':
          selections[id] = value as String?;
        case 'multiSelect':
          multiSelections[id] = value is List
              ? value.whereType<String>().toSet()
              : <String>{};
        case 'date':
        case 'datetime':
          dateValues[id] = value as String?;
        default:
          controllers[id] = TextEditingController(
            text: value?.toString() ?? '',
          );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑扩展字段'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in widget.module.fields) _field(field),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  void _save() {
    for (final field in widget.module.fields) {
      if (field['type'] != 'number') continue;
      final raw = controllers[field['id']]!.text.trim();
      if (raw.isNotEmpty && !(num.tryParse(raw)?.isFinite ?? false)) {
        setState(() => error = '${field['label']}请输入有效数字');
        return;
      }
    }
    Navigator.pop(context, _collect());
  }

  Widget _field(Map<String, Object?> field) {
    final id = field['id'] as String;
    final type = field['type'] as String;
    final label = field['label'] as String;
    final config =
        (field['config'] as Map?)?.cast<String, Object?>() ?? const {};
    final options =
        (config['options'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    switch (type) {
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: booleans[id] ?? false,
          onChanged: (value) => setState(() => booleans[id] = value),
        );
      case 'select':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            borderRadius: AppDesign.selectionBorderRadius,
            initialValue: options.contains(selections[id])
                ? selections[id]
                : null,
            decoration: InputDecoration(labelText: label),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (value) => setState(() => selections[id] = value),
          ),
        );
      case 'multiSelect':
        final selected = multiSelections[id] ?? <String>{};
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InputDecorator(
            decoration: InputDecoration(labelText: label),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  FilterChip(
                    label: Text(option),
                    selected: selected.contains(option),
                    onSelected: (enabled) {
                      setState(() {
                        if (enabled) {
                          selected.add(option);
                        } else {
                          selected.remove(option);
                        }
                        multiSelections[id] = selected;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      case 'date':
        return _dateTile(id, label, includeTime: false);
      case 'datetime':
        return _dateTile(id, label, includeTime: true);
      case 'number':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: controllers[id],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: controllers[id],
            decoration: InputDecoration(labelText: label),
          ),
        );
    }
  }

  Widget _dateTile(String id, String label, {required bool includeTime}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(dateValues[id] ?? '未设置'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dateValues[id] != null)
            IconButton(
              tooltip: '清除',
              onPressed: () => setState(() => dateValues[id] = null),
              icon: const Icon(Icons.clear),
            ),
          IconButton(
            tooltip: '选择日期',
            onPressed: () => _pickDate(id, includeTime),
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(String id, bool includeTime) async {
    final now = DateTime.now();
    final existing = DateTime.tryParse(dateValues[id] ?? '');
    final date = await showDatePicker(
      context: context,
      initialDate: existing ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    if (!includeTime) {
      setState(() => dateValues[id] = _date(date));
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: existing == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(existing),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => dateValues[id] = value.toIso8601String());
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  Map<String, Object?> _collect() {
    final result = <String, Object?>{};
    for (final field in widget.module.fields) {
      final id = field['id'] as String;
      final type = field['type'] as String;
      result[id] = switch (type) {
        'boolean' => booleans[id] ?? false,
        'select' => selections[id],
        'multiSelect' => (multiSelections[id] ?? const <String>{}).toList(),
        'date' || 'datetime' => dateValues[id],
        'number' => _number(controllers[id]?.text ?? ''),
        _ => _text(controllers[id]?.text ?? ''),
      };
    }
    return result;
  }

  Object? _number(String raw) {
    final value = raw.trim();
    return value.isEmpty ? null : num.tryParse(value);
  }

  Object? _text(String raw) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }
}
