import '../core/ui/ui_annotation.dart';

import 'package:flutter/material.dart';

import '../core/ui/native_ui.dart';
import '../core/ui/ui_composition.dart';
import '../core/ui/ui_icon.dart';
import 'design_system.dart';

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
  });

  final List<UiEntryRegistration> entries;
  final ValueChanged<UiEntryRegistration> onOpen;
  final VoidCallback onSettings;
  final Widget Function(UiEntryRegistration, Widget)? wrapEntry;
  final Widget? afterEntries;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => NativeUi(
    child: Material(
      type: MaterialType.transparency,
      child: ListView(
        controller: scrollController,
        key: const PageStorageKey('more-workspace-list'),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          WorkspaceContentInsets.bottomOf(context) + 24,
        ),
        children: [
          Text('常用工具', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('可在设置中添加更多常用入口。'),
            ),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Builder(
                builder: (context) {
                  final row = UiAnnotation(
                    id: entry.id,
                    name: entry.label,
                    purpose: '打开常用入口',
                    child: ListTile(
                      key: ValueKey('more-entry-${entry.id}'),
                      tileColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLow,
                      shape: AppDesign.smoothShape(
                        radius: AppDesign.controlRadius,
                      ),
                      leading: UiIcon(entry.icon),
                      title: Text(entry.label),
                      trailing: const UiIcon(
                        Icons.chevron_right_rounded,
                        size: 20,
                      ),
                      onTap: () => onOpen(entry),
                    ),
                  );
                  return wrapEntry?.call(entry, row) ?? row;
                },
              ),
            ),
          ?afterEntries,
          const SizedBox(height: 16),
          const Divider(),
          UiAnnotation(
            id: 'app.shell.settings',
            name: '设置',
            purpose: '打开设置',
            child: ListTile(
              key: const ValueKey('more-workspace-settings'),
              shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
              leading: const UiIcon(Icons.settings_outlined),
              title: const Text('设置'),
              subtitle: const Text('管理页面、入口和外观'),
              trailing: const UiIcon(Icons.chevron_right_rounded, size: 20),
              onTap: onSettings,
            ),
          ),
        ],
      ),
    ),
  );
}
