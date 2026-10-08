import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/module_registry.dart';
import '../ui/app_repository_links.dart';
import '../ui/ui_annotation.dart';
import '../ui/ui_component.dart';
import '../ui/ui_composition.dart';
import '../ui/ui_page_host.dart';
import '../ui/ui_registration.dart';
import '../ui/ui_slot.dart';
import '../ui/ui_pack_settings_page.dart';
import '../../features/settings/app_preferences.dart';
import '../../features/settings/ui_layout.dart';
import '../../features/settings/ui_layout_page.dart';
import 'host_manager_page.dart';
import 'host_providers.dart';
import 'module_catalog_page.dart';

class HostSettingsPage extends ConsumerWidget {
  const HostSettingsPage({super.key, required this.registry});
  final ModuleRegistry registry;

  Widget _template(Widget sections) => UiComponent(
    ref: 'ui.page.settings@1',
    props: const {'title': '设置'},
    slots: {'sections': sections},
    fallback: sections,
  );

  Widget _entry({
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    IconData? icon,
    bool protected = false,
  }) => UiComponent(
    ref: 'ui.listTile@1',
    defaultOnly: protected,
    props: {'title': title, 'subtitle': ?subtitle},
    events: {'press': (_) => onTap()},
    fallback: ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      leading: icon == null ? null : Icon(icon),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(appPreferencesProvider).asData?.value ??
        const AppPreferences();
    final profile = (ref.watch(uiLayoutProvider).asData?.value ?? UiLayout())
        .profile(MediaQuery.sizeOf(context).width >= 820);
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: _template(
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<ThemeMode>(
                initialValue: preferences.themeMode,
                decoration: const InputDecoration(labelText: '外观主题'),
                items: [
                  for (final mode in ThemeMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(switch (mode) {
                        ThemeMode.system => '跟随系统',
                        ThemeMode.light => '浅色',
                        ThemeMode.dark => '深色',
                      }),
                    ),
                ],
                onChanged: (v) => ref
                    .read(appPreferencesProvider.notifier)
                    .save(preferences.copyWith(themeMode: v)),
              ),
              SwitchListTile(
                title: const Text('减少动画'),
                value: preferences.reduceMotion,
                onChanged: (v) => ref
                    .read(appPreferencesProvider.notifier)
                    .save(preferences.copyWith(reduceMotion: v)),
              ),
              SwitchListTile(
                title: const Text('触感反馈'),
                value: preferences.haptics,
                onChanged: (v) => ref
                    .read(appPreferencesProvider.notifier)
                    .save(preferences.copyWith(haptics: v)),
              ),
              SwitchListTile(
                title: const Text('界面标注模式'),
                value: ref.watch(uiAnnotationProvider),
                onChanged: (v) =>
                    ref.read(uiAnnotationProvider.notifier).setEnabled(v),
              ),
              _entry(
                title: '界面风格',
                subtitle: '全局风格、模块专属界面与恢复默认',
                icon: Icons.palette_outlined,
                protected: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UiPackSettingsPage(registry: registry),
                  ),
                ),
              ),
              _entry(
                title: '入口与页面布局',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UiLayoutPage(registry: registry),
                  ),
                ),
              ),
              _entry(
                title: '模块管理与恢复',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('模块管理')),
                      body: const HostManagerPage(),
                    ),
                  ),
                ),
              ),
              for (final contribution
                  in registry.ui
                      .forSlot(UiSlot.settingsSections)
                      .whereType<WidgetRegistration>())
                contribution.builder(context),
              for (final entry in registry.ui.entries.where(
                (e) => profile.mountFor(e).placement == UiPlacement.settings,
              ))
                ListTile(
                  title: Text(entry.label),
                  leading: Icon(entry.icon),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(entry.label)),
                        body: UiPageHost(
                          registry: registry,
                          pageId: entry.pageId,
                          pageContext: profile.mountFor(entry).context,
                        ),
                      ),
                    ),
                  ),
                ),
              for (final page in registry.ui.entries.where(
                (e) =>
                    e.content &&
                    profile.mountFor(e).placement == UiPlacement.settings,
              ))
                SizedBox(
                  height: 320,
                  child: UiPageHost(registry: registry, pageId: page.pageId),
                ),
              AppRepositoryLinks(
                onBrowseModules: () async {
                  try {
                    final host = await ref.read(moduleHostProvider.future);
                    if (!context.mounted) return;
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ModuleCatalogPage(host: host),
                      ),
                    );
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('无法打开模块目录：$error')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
