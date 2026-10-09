import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../features/settings/app_preferences.dart';
import '../../features/settings/appearance_settings_page.dart';
import '../../features/settings/settings_tools_page.dart';
import '../../features/settings/settings_widgets.dart';
import '../../features/settings/ui_layout.dart';
import '../../features/settings/ui_layout_page.dart';
import '../modules/module_registry.dart';
import '../ui/app_repository_links.dart';
import '../ui/ui_annotation.dart';
import '../ui/ui_component.dart';
import '../ui/ui_composition.dart';
import '../ui/ui_layout_resolver.dart';
import '../ui/ui_page_host.dart';
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开模块商店，请重试')));
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
        final sections = SettingsList(
          children: [
            const SettingsNote('按分类调整应用，也可从常用入口直接打开模块页面。'),
            SettingsGroup(
              title: '个性化',
              children: [
                SettingsEntry(
                  title: '外观与交互',
                  subtitle: preferences.when(
                    data: (value) =>
                        '${appearanceThemeLabel(value.themeMode)} · 界面风格与交互反馈',
                    loading: () => '正在读取外观设置…',
                    error: (_, _) => '读取失败，进入后重试',
                  ),
                  icon: Icons.palette_outlined,
                  protected: true,
                  onTap: () => open(AppearanceSettingsPage(registry: registry)),
                ),
                SettingsEntry(
                  title: '布局与导航',
                  subtitle: '入口位置、页面内容与手机和电脑布局',
                  icon: Icons.dashboard_customize_outlined,
                  protected: true,
                  onTap: () => open(
                    UiLayoutPage(
                      registry: registry,
                      initialDesktop: MediaQuery.sizeOf(context).width >= 820,
                    ),
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: '功能与支持',
              children: [
                SettingsEntry(
                  title: '模块与连接',
                  subtitle: '模块管理、商店与模块提供的设置',
                  icon: Icons.extension_outlined,
                  protected: true,
                  onTap: () => open(ModuleSettingsPage(registry: registry)),
                ),
                SettingsEntry(
                  title: '辅助工具',
                  subtitle: annotation ? '界面标注已开启' : '界面标注与问题反馈辅助',
                  icon: Icons.build_outlined,
                  onTap: () => open(const SettingsToolsPage()),
                ),
                SettingsEntry(
                  title: '关于序点',
                  subtitle: '应用信息、项目地址与模块仓库',
                  icon: Icons.info_outline_rounded,
                  onTap: () => open(const AboutSettingsPage()),
                ),
              ],
            ),
            if (shortcuts.isNotEmpty)
              SettingsGroup(
                title: '常用入口',
                children: [
                  for (final entry in shortcuts)
                    SettingsEntry(
                      title: entry.label,
                      icon: entry.icon,
                      onTap: () => open(
                        DetailPage(
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
              ),
          ],
        );
        return DetailPage(
          title: '设置',
          child: UiComponent(
            ref: 'ui.page.settings@1',
            props: const {'title': '设置'},
            slots: {'sections': sections},
            fallback: sections,
          ),
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
                            builder: (_) => DetailPage(
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
        const SettingsGroup(
          title: '应用',
          children: [
            ListTile(
              leading: Icon(Icons.grid_view_rounded),
              title: Text('序点'),
              subtitle: Text('专注当下，逐项完成'),
            ),
            ListTile(
              leading: Icon(Icons.storage_outlined),
              title: Text('本机数据'),
              subtitle: Text('数据与设置保存在本机；在线模块功能需要网络连接'),
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
