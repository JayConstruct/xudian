import 'package:flutter/material.dart';

import '../../core/ui/native_ui.dart';
import 'settings_widgets.dart';

class UiLayoutChoice<Value> {
  const UiLayoutChoice({
    required this.value,
    required this.label,
    this.icon = Icons.layers_outlined,
    this.detail = '',
    this.keywords = '',
  });

  final Value value;
  final String label, detail, keywords;
  final IconData icon;
}

class UiLayoutPicker<Value> extends StatefulWidget {
  const UiLayoutPicker({
    super.key,
    required this.title,
    required this.choices,
    this.entrySearch = false,
  });

  final String title;
  final List<UiLayoutChoice<Value>> choices;
  final bool entrySearch;

  @override
  State<UiLayoutPicker<Value>> createState() => _UiLayoutPickerState<Value>();
}

class _UiLayoutPickerState<Value> extends State<UiLayoutPicker<Value>> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final choices = widget.choices.where((choice) {
      return '${choice.label} ${choice.detail} ${choice.keywords}'
          .toLowerCase()
          .contains(query);
    }).toList();
    return NativeUi(
      child: SettingsSheet(
        title: Text(widget.title),
        expandedActions: true,
        content: SizedBox(
          height: widget.entrySearch && query.isNotEmpty ? 317 : 354,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSearchField(
                fieldKey: const ValueKey('layout-picker-search'),
                controller: search,
                hint: '搜索名称、模块或标识',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              if (widget.entrySearch && choices.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: SettingsHeading(query.isEmpty ? '可选入口' : '搜索结果'),
                    ),
                    if (query.isNotEmpty)
                      Text(
                        '${choices.length} 个入口',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Flexible(
                child: choices.isEmpty
                    ? ListView(
                        shrinkWrap: true,
                        children: [
                          SettingsEmptyState(
                            title: widget.entrySearch
                                ? '没有匹配的入口'
                                : '没有符合条件的兼容选项',
                            detail: '试试入口名称、模块名或标识。',
                          ),
                          if (widget.entrySearch)
                            const SettingsNote('清空搜索可查看全部可选入口。'),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) => SettingsGroupSurface(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight,
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: choices.length,
                                separatorBuilder: (_, _) =>
                                    const SettingsDivider(),
                                itemBuilder: (context, index) {
                                  final choice = choices[index];
                                  return SettingsEntry(
                                    title: choice.label,
                                    subtitle: choice.detail.isEmpty
                                        ? null
                                        : choice.detail,
                                    icon: choice.icon,
                                    onTap: () =>
                                        Navigator.pop(context, choice.value),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          NativeUi(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
        ],
      ),
    );
  }
}
