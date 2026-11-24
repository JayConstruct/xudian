import '../core/ui/ui_annotation.dart';

import 'package:flutter/material.dart';

import '../core/ui/native_ui.dart';
import '../core/ui/ui_composition.dart';
import '../core/ui/ui_icon.dart';
import 'design_system.dart';
import '../features/settings/settings_widgets.dart';

/// A workspace directory, so opening More uses the same navigation as a page.
class MoreWorkspacePage extends StatelessWidget {
  const MoreWorkspacePage({
    super.key,
    required this.entries,
    required this.onOpen,
    required this.onSettings,
    this.wrapEntry,
    this.afterEntries,
    this.scrollController,
    this.padding,
  });

  final List<UiEntryRegistration> entries;
  final ValueChanged<UiEntryRegistration> onOpen;
  final VoidCallback onSettings;
  final Widget Function(UiEntryRegistration, Widget)? wrapEntry;
  final Widget? afterEntries;
  final ScrollController? scrollController;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => NativeUi(
    child: Material(
      type: MaterialType.transparency,
      child: ListView(
        controller: scrollController,
        key: const PageStorageKey('more-workspace-list'),
        padding:
            padding ??
            EdgeInsets.fromLTRB(
              AppDesign.pageGutter,
              8,
              AppDesign.pageGutter,
              WorkspaceContentInsets.bottomOf(context) + 24,
            ),
        children: [
          SettingsGroup(
            title: '常用工具',
            children: [
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 28,
                  ),
                  child: Column(
                    children: [
                      const SettingsGlyph(
                        Icons.grid_view_outlined,
                        size: 46,
                        radius: 14,
                        iconSize: 22,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '还没有常用入口',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '可在设置的「布局与导航」中添加入口。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              for (final entry in entries)
                Builder(
                  builder: (context) {
                    final row = UiAnnotation(
                      id: entry.id,
                      name: entry.label,
                      purpose: '打开常用入口',
                      child: ListTile(
                        key: ValueKey('more-entry-${entry.id}'),
                        minTileHeight: 54,
                        leading: SizedBox(
                          width: SettingsListTileTheme.glyphSize,
                          child: UiIcon(
                            entry.icon,
                            size: 18,
                            color: AppDesign.muted(context),
                          ),
                        ),
                        title: Text(entry.label),
                        trailing: const UiIcon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        onTap: () => onOpen(entry),
                      ),
                    );
                    return wrapEntry?.call(entry, row) ?? row;
                  },
                ),
              ?afterEntries,
            ],
          ),
          SettingsGroup(
            title: '应用',
            children: [
              UiAnnotation(
                id: 'app.shell.settings',
                name: '设置',
                purpose: '打开设置',
                child: SettingsEntry(
                  tileKey: const ValueKey('more-workspace-settings'),
                  icon: Icons.settings_outlined,
                  title: '设置',
                  subtitle: '管理页面、入口和外观',
                  onTap: onSettings,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
