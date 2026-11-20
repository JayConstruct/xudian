import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/ui/ui_icon.dart';
import 'settings_widgets.dart';

class SettingsSearchItem {
  const SettingsSearchItem(
    this.title,
    this.path,
    this.icon,
    this.open, {
    this.keywords = '',
    this.page = false,
  });
  final String title, path, keywords;
  final IconData icon;
  final VoidCallback open;
  final bool page;
}

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key, required this.items});
  final List<SettingsSearchItem> items;
  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final matches = widget.items
        .where(
          (item) => query.isEmpty
              ? item.page
              : '${item.title} ${item.path} ${item.keywords}'
                    .toLowerCase()
                    .contains(query),
        )
        .toList();
    void clear() => setState(search.clear);
    return DetailPage(
      settingsStyle: true,
      title: '搜索设置',
      child: SettingsList(
        children: [
          SettingsSearchField(
            controller: search,
            hint: '搜索设置',
            autofocus: true,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 18),
          for (final page in [false, true])
            if (matches.any((i) => i.page == page))
              SettingsGroup(
                title: page ? '设置页面' : '设置项',
                children: [
                  for (final item in matches.where((i) => i.page == page))
                    SettingsEntry(
                      title: item.title,
                      subtitle: item.path,
                      icon: item.icon,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        item.open();
                      },
                    ),
                ],
              ),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 58),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      shape: AppDesign.smoothShape(
                        radius: AppDesign.controlRadius,
                      ),
                    ),
                    child: const UiIcon(Icons.search, size: 24),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '没有匹配的设置',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '试试功能名，例如「主题」或「更新」。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppDesign.muted(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: clear,
                    child: const Text('清空搜索'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
