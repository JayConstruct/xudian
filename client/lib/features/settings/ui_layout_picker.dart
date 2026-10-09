import 'package:flutter/material.dart';

import '../../app/design_system.dart';

class UiLayoutChoice<Value> {
  const UiLayoutChoice({
    required this.value,
    required this.label,
    this.detail = '',
    this.keywords = '',
  });

  final Value value;
  final String label;
  final String detail;
  final String keywords;
}

class UiLayoutPicker<Value> extends StatefulWidget {
  const UiLayoutPicker({super.key, required this.title, required this.choices});

  final String title;
  final List<UiLayoutChoice<Value>> choices;

  @override
  State<UiLayoutPicker<Value>> createState() => _UiLayoutPickerState<Value>();
}

class _UiLayoutPickerState<Value> extends State<UiLayoutPicker<Value>> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final choices = widget.choices.where((choice) {
      return '${choice.label} ${choice.detail} ${choice.keywords}'
          .toLowerCase()
          .contains(query.trim().toLowerCase());
    }).toList();
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('layout-picker-search'),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '搜索名称、模块或标识',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: choices.isEmpty
                  ? const Center(child: Text('没有符合条件的兼容选项'))
                  : ListView.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        return ListTile(
                          shape: AppDesign.smoothShape(
                            radius: AppDesign.controlRadius,
                          ),
                          title: Text(choice.label),
                          subtitle: choice.detail.isEmpty
                              ? null
                              : Text(choice.detail),
                          onTap: () => Navigator.pop(context, choice.value),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
