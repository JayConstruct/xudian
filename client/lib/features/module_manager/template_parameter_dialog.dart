import 'package:flutter/material.dart';

import '../../app/design_system.dart';

Future<Map<String, Object?>?> showTemplateParameterDialog({
  required BuildContext context,
  required Map<String, Object?> template,
}) {
  final parameters =
      (template['parameters'] as List?)?.cast<Map>() ?? const <Map>[];
  if (parameters.isEmpty) {
    return Future.value(const <String, Object?>{});
  }
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => _TemplateParameterDialog(
      title: template['title'] as String,
      parameters: parameters,
    ),
  );
}

class _TemplateParameterDialog extends StatefulWidget {
  const _TemplateParameterDialog({
    required this.title,
    required this.parameters,
  });

  final String title;
  final List<Map> parameters;

  @override
  State<_TemplateParameterDialog> createState() =>
      _TemplateParameterDialogState();
}
class _TemplateParameterDialogState
    extends State<_TemplateParameterDialog> {
  final controllers = <String, TextEditingController>{};
  final values = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    for (final parameter in widget.parameters) {
      final id = parameter['id'] as String;
      final type = parameter['type'] as String;
      final initial = parameter['default'];
      if (type == 'text' || type == 'number') {
        controllers[id] = TextEditingController(
          text: initial?.toString() ?? '',
        );
      } else if (type == 'boolean') {
        values[id] = initial is bool ? initial : false;
      } else {
        values[id] = initial;
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
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final parameter in widget.parameters)
                _field(parameter),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('创建任务'),
        ),
      ],
    );
  }
  Widget _field(Map parameter) {
    final id = parameter['id'] as String;
    final label = parameter['label'] as String;
    final type = parameter['type'] as String;
    final required = parameter['required'] == true;

    switch (type) {
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: required ? const Text('必填') : null,
          value: values[id] as bool? ?? false,
          onChanged: (value) => setState(() => values[id] = value),
        );
      case 'select':
        final options = (parameter['options'] as List).cast<String>();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            borderRadius: AppDesign.selectionBorderRadius,
            initialValue: values[id] as String?,
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
            ),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (value) => setState(() => values[id] = value),
          ),
        );
      case 'multiSelect':
        final options = (parameter['options'] as List).cast<String>();
        final selected =
            (values[id] as List?)?.cast<String>().toSet() ?? <String>{};
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in options)
                  FilterChip(
                    label: Text(option),
                    selected: selected.contains(option),
                    onSelected: (enabled) {
                      final next = {...selected};
                      if (enabled) {
                        next.add(option);
                      } else {
                        next.remove(option);
                      }
                      setState(() => values[id] = next.toList());
                    },
                  ),
              ],
            ),
          ),
        );
      case 'date':
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(required ? '$label *' : label),
          subtitle: Text(values[id]?.toString() ?? '未设置'),
          trailing: IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => _pickDate(id),
          ),
        );
      case 'datetime':
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(required ? '$label *' : label),
          subtitle: Text(values[id]?.toString() ?? '未设置'),
          trailing: IconButton(
            icon: const Icon(Icons.schedule_outlined),
            onPressed: () => _pickDateTime(id),
          ),
        );
      case 'number':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: controllers[id],
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
            ),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: controllers[id],
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
            ),
          ),
        );
    }
  }
  Future<void> _pickDateTime(String id) async {
    final now = DateTime.now();
    final current = DateTime.tryParse(values[id]?.toString() ?? '') ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final result = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => values[id] = result.toIso8601String());
  }

  Future<void> _pickDate(String id) async {
    final now = DateTime.now();
    final current = DateTime.tryParse(values[id]?.toString() ?? '');
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      values[id] =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  void _submit() {
    final result = <String, Object?>{};
    for (final parameter in widget.parameters) {
      final id = parameter['id'] as String;
      final type = parameter['type'] as String;
      Object? value;
      if (type == 'text') {
        final raw = controllers[id]!.text.trim();
        value = raw.isEmpty ? null : raw;
      } else if (type == 'number') {
        final raw = controllers[id]!.text.trim();
        value = raw.isEmpty ? null : num.tryParse(raw);
        if (raw.isNotEmpty && value == null) {
          _error('${parameter['label']} 必须是数字');
          return;
        }
      } else {
        value = values[id];
      }

      if (value == null && parameter['required'] == true) {
        _error('请填写 ${parameter['label']}');
        return;
      }
      if (value != null) result[id] = value;
    }
    Navigator.pop(context, result);
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
