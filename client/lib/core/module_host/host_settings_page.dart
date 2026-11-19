import '../ui/ui_icon.dart';
import '../ui/native_ui.dart';
import '../../app/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../features/settings/app_preferences.dart';
import '../../features/settings/configuration_export_page.dart';
import '../../features/settings/appearance_settings_page.dart';
import '../../features/settings/settings_tools_page.dart';
import '../../features/settings/settings_widgets.dart';
import '../../features/settings/settings_home.dart';
import '../../features/settings/app_update_page.dart';
import '../../features/settings/update_settings_page.dart';
import '../app_updates/startup_updates.dart';
import '../../features/settings/ui_layout.dart';
import '../../features/settings/ui_layout_page.dart';
import '../modules/module_registry.dart';
import '../app_updates/github_app_updates.dart';
import '../ui/app_repository_links.dart';
import '../ui/ui_annotation.dart';
import '../ui/ui_composition.dart';
import '../ui/ui_layout_resolver.dart';
import '../ui/ui_page_host.dart';
import '../ui/module_detail_page.dart';
import '../ui/ui_registration.dart';
import '../ui/ui_slot.dart';
import 'host_manager_page.dart';
import 'host_providers.dart';
import 'module_catalog_page.dart';

Future<void> _openCatalog(BuildContext context, WidgetRef ref) async {
  try {
    final host = await ref.read(moduleHostProvider.future);
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ModuleCatalogPage(host: host)),
    );
  } catch (_) {
    if (context.mounted) {
      AppToast.show(context, message: '无法打开模块商店，请重试', kind: 'error');
    }
  }
}

class HostSettingsPage extends ConsumerWidget {
  const HostSettingsPage({super.key, required this.registry});
  final ModuleRegistry registry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesProvider);
    final profile = (ref.watch(uiLayoutProvider).asData?.value ?? UiLayout())
        .profile(MediaQuery.sizeOf(context).width >= 820);
    final annotation = ref.watch(uiAnnotationProvider);
    final hasUpdates = ref.watch(startupUpdatesProvider).hasUpdates;
    void open(Widget page) =>
        Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final shortcuts = orderedEntries(
          registry.ui,
          profile.mountFor,
          (entry) =>
              !entry.content &&
              profile.mountFor(entry).placement == UiPlacement.settings,
        );
        return SettingsHome(
          appearance: SettingsFeatureCard(
            appearance: true,
            title: '外观与交互',
            subtitle: preferences.when(
              data: (value) =>
                  '当前主题 · ${appearanceThemeLabel(value.themeMode)}',
              loading: () => '正在读取外观设置…',
              error: (_, _) => '读取失败，进入后重试',
            ),
            onTap: () => open(AppearanceSettingsPage(registry: registry)),
          ),
          layout: SettingsFeatureCard(
            title: '布局与导航',
            subtitle: '入口位置与页面布局',
            onTap: () => open(
              UiLayoutPage(
                registry: registry,
                initialDesktop: MediaQuery.sizeOf(context).width >= 820,
              ),
            ),
          ),
          management: [
            SettingsHomeEntry(
              title: '模块与连接',
              subtitle: '模块管理、商店与连接配置',
              icon: Icons.grid_view_outlined,
              protected: true,
              onTap: () => open(ModuleSettingsPage(registry: registry)),
            ),
            SettingsHomeEntry(
              title: '更新设置',
              subtitle: '检查应用与模块更新',
              status: hasUpdates ? '有更新' : null,
              icon: Icons.refresh,
              protected: true,
              onTap: () => open(const UpdateSettingsPage()),
            ),
            SettingsHomeEntry(
              title: '导出所有配置',
              subtitle: '备份设置、偏好与连接配置',
              icon: Icons.download_outlined,
              protected: true,
              onTap: () => open(const ConfigurationExportPage()),
            ),
          ],
          support: [
            SettingsHomeEntry(
              title: '辅助工具',
              subtitle: '界面标注与显示诊断',
              status: annotation ? '标注已开启' : null,
              icon: Icons.build_outlined,
              onTap: () => open(const SettingsToolsPage()),
            ),
            SettingsHomeEntry(
              title: '关于序点',
              subtitle: '应用版本与项目地址',
              icon: Icons.info_outline_rounded,
              onTap: () => open(const AboutSettingsPage()),
            ),
          ],
          shortcuts: [
            for (final entry in shortcuts)
              SettingsHomeEntry(
                title: entry.label,
                icon: entry.icon,
                onTap: () => open(
                  ModuleDetailPage(
                    registry: registry,
                    pageId: entry.pageId,
                    pageContext: profile.mountFor(entry).context,
                    title: entry.label,
                    child: UiPageHost(
                      registry: registry,
                      pageId: entry.pageId,
                      pageContext: profile.mountFor(entry).context,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class ModuleSettingsPage extends ConsumerWidget {
  const ModuleSettingsPage({super.key, required this.registry});
  final ModuleRegistry registry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = (ref.watch(uiLayoutProvider).asData?.value ?? UiLayout())
        .profile(MediaQuery.sizeOf(context).width >= 820);
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final contributions = registry.ui
            .forSlot(UiSlot.settingsSections)
            .whereType<WidgetRegistration>()
            .toList();
        final content = orderedEntries(
          registry.ui,
          profile.mountFor,
          (entry) =>
              entry.content &&
              profile.mountFor(entry).placement == UiPlacement.settings,
        );
        return DetailPage(
          title: '模块与连接',
          child: SettingsList(
            children: [
              const SettingsNote('管理已安装模块。连接配置等专属选项由各模块提供。'),
              SettingsGroup(
                title: '模块管理',
                children: [
                  SettingsEntry(
                    title: '模块管理与恢复',
                    subtitle: '导入、启停、授权与恢复已安装模块',
                    icon: Icons.extension_outlined,
                    protected: true,
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DetailPage(
                          title: '模块管理',
                          child: HostManagerPage(),
                        ),
                      ),
                    ),
                  ),
                  SettingsEntry(
                    title: '模块商店',
                    subtitle: '查找新模块与已安装模块的更新',
                    icon: Icons.public,
                    onTap: () => _openCatalog(context, ref),
                  ),
                ],
              ),
              if (contributions.isNotEmpty)
                SettingsGroup(
                  title: '模块提供的设置',
                  children: [
                    for (final contribution in contributions)
                      contribution.builder(context),
                  ],
                ),
              if (content.isNotEmpty)
                SettingsGroup(
                  title: '模块专属设置',
                  children: [
                    for (final entry in content)
                      SettingsEntry(
                        title: entry.label,
                        icon: entry.icon,
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ModuleDetailPage(
                              registry: registry,
                              pageId: entry.pageId,
                              pageContext: profile.mountFor(entry).context,
                              title: entry.label,
                              child: UiPageHost(
                                registry: registry,
                                pageId: entry.pageId,
                                pageContext: profile.mountFor(entry).context,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              if (contributions.isEmpty && content.isEmpty)
                const SettingsNote('当前没有模块提供额外设置。模块页面仍可从导航或设置首页的常用入口打开。'),
            ],
          ),
        );
      },
    );
  }
}

class AboutSettingsPage extends ConsumerWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DetailPage(
    title: '关于序点',
    child: SettingsList(
      children: [
        SettingsGroup(
          title: '应用',
          children: [
            NativeUi(
              child: ListTile(
                leading: const UiIcon(Icons.grid_view_rounded),
                title: const Text('序点'),
                subtitle: Text(
                  ref
                      .watch(installedAppVersionProvider)
                      .when(
                        data: (value) => value.label,
                        loading: () => '正在读取版本…',
                        error: (_, _) => '专注当下，逐项完成',
                      ),
                ),
              ),
            ),
            SettingsEntry(
              title: '检查更新',
              subtitle: '从 GitHub 检查应用新版本',
              icon: Icons.system_update_rounded,
              protected: true,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const AppUpdatePage()),
              ),
            ),
            const NativeUi(
              child: ListTile(
                leading: UiIcon(Icons.storage_outlined),
                title: Text('本机数据'),
                subtitle: Text('数据与设置保存在本机；在线模块功能需要网络连接'),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '项目与社区',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: AppRepositoryLinks(
                showHeading: false,
                onBrowseModules: () => _openCatalog(context, ref),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
