import '../../features/settings/entry_directory.dart';
import '../../features/settings/settings_focus.dart';
import '../../features/settings/settings_search.dart';
import '../../features/settings/display_diagnostics_page.dart';
import '../ui/ui_pack_settings_page.dart';
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
  const HostSettingsPage({
    super.key,
    required this.registry,
    this.onOpenEntry,
    this.onLocate,
    this.onClose,
    this.returnToSearch = false,
  });
  final ModuleRegistry registry;
  final OpenShellEntry? onOpenEntry;
  final LocateShellEntry? onLocate;
  final bool returnToSearch;
  final VoidCallback? onClose;

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
        Widget layoutPage() => UiLayoutPage(
          registry: registry,
          initialDesktop: MediaQuery.sizeOf(context).width >= 820,
          onOpenEntry: onOpenEntry,
          onLocate: onLocate,
        );
        void directory() => open(
          EntryDirectoryPage(
            registry: registry,
            openShellEntry: onOpenEntry,
            locateShellEntry: onLocate,
          ),
        );
        void search() => open(
          ListenableBuilder(
            listenable: registry,
            builder: (context, _) {
              final items = <SettingsSearchItem>[];
              void index(
                String title,
                String path,
                IconData icon,
                Widget Function() destination, {
                List<String> labels = const [],
                String aliases = '',
              }) {
                items.add(
                  SettingsSearchItem(
                    title,
                    path,
                    icon,
                    () => open(destination()),
                    keywords: aliases,
                    page: true,
                  ),
                );
                for (final label in labels) {
                  items.add(
                    SettingsSearchItem(
                      label,
                      title,
                      icon,
                      () => open(
                        SettingsFocus(label: label, child: destination()),
                      ),
                      keywords: aliases,
                    ),
                  );
                }
              }

              index(
                '外观与交互',
                '设置 › 个性化',
                Icons.palette_outlined,
                () => AppearanceSettingsPage(registry: registry),
                labels: ['外观主题', '触感反馈'],
                aliases: '主题 深色 浅色 振动',
              );
              index(
                '界面风格',
                '外观与交互',
                Icons.style_outlined,
                () => UiPackSettingsPage(registry: registry),
                labels: ['全局风格', '模块专属界面', '保存与恢复'],
              );
              index(
                '布局与导航',
                '设置 › 个性化',
                Icons.dashboard_outlined,
                layoutPage,
                labels: ['编排入口', '常用与隐藏入口', '高级编辑'],
                aliases: '底栏 菜单 侧栏 更多 拖动',
              );
              index(
                '入口目录',
                '设置',
                Icons.list,
                () => EntryDirectoryPage(
                  registry: registry,
                  openShellEntry: onOpenEntry,
                  locateShellEntry: onLocate,
                ),
                aliases: '打开入口 查找位置',
              );
              index(
                '模块与连接',
                '设置 › 应用与数据',
                Icons.grid_view_outlined,
                () => ModuleSettingsPage(registry: registry),
                labels: ['模块管理与恢复', '模块商店'],
              );
              index(
                '更新设置',
                '设置 › 应用与数据',
                Icons.refresh,
                () => const UpdateSettingsPage(),
                labels: ['启动时检查更新', '检查 App 更新', '检查模块更新'],
              );
              index(
                '检查 App 更新',
                '更新设置 › 手动检查',
                Icons.system_update,
                () => const AppUpdatePage(),
                labels: ['测试通道'],
              );
              index(
                '导出所有配置',
                '设置 › 应用与数据',
                Icons.download_outlined,
                () => const ConfigurationExportPage(),
                labels: ['包含 API 密钥'],
                aliases: '备份 JSON',
              );
              index(
                '辅助工具',
                '设置 › 支持与关于',
                Icons.build_outlined,
                () => const SettingsToolsPage(),
                labels: ['界面标注模式'],
              );
              index(
                '显示与布局信息',
                '辅助工具',
                Icons.aspect_ratio,
                () => const DisplayDiagnosticsPage(),
                aliases: '诊断 字号 分辨率 安全区',
              );
              index(
                '关于序点',
                '设置 › 支持与关于',
                Icons.info_outline,
                () => const AboutSettingsPage(),
                labels: ['本机数据', '项目地址', '模块仓库'],
              );
              for (final page in registry.ui.pages) {
                final entry = registry.ui.entries
                    .where(
                      (e) =>
                          e.pageId == page.id &&
                          profile.mountFor(e).placement == UiPlacement.settings,
                    )
                    .firstOrNull;
                if (entry == null &&
                    page.settingsPath == null &&
                    page.settingsLabels.isEmpty) {
                  continue;
                }
                final source =
                    page.settingsPath ??
                    (entry == null
                        ? '模块设置'
                        : entry.content
                        ? '模块与连接'
                        : '设置 › 常用入口');
                index(
                  page.title,
                  source,
                  entry?.icon ?? Icons.tune,
                  () => ModuleDetailPage(
                    registry: registry,
                    pageId: page.id,
                    pageContext: entry == null
                        ? const PageContext()
                        : profile.mountFor(entry).context,
                    title: page.title,
                  ),
                  labels: page.settingsLabels,
                  aliases: '${page.moduleId} ${entry?.label ?? ''}',
                );
              }
              return SettingsSearchPage(items: items);
            },
          ),
        );
        return SettingsHome(
          onClose: onClose,
          onSearch: search,
          onDirectory: directory,
          returnToSearch: returnToSearch,
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
            onTap: () => open(layoutPage()),
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
          settingsStyle: true,
          child: SettingsList(
            children: [
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
                          settingsStyle: true,
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
  Widget build(BuildContext context, WidgetRef ref) {
    final installedVersion = ref.watch(installedAppVersionProvider);
    return DetailPage(
      title: '关于序点',
      settingsStyle: true,
      child: SettingsList(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final twoColumns =
                  MediaQuery.sizeOf(context).width >= 820 &&
                  constraints.maxWidth >= 680 * textScale;
              final version = [
                SettingsSummary(
                  label: '应用版本',
                  title: '序点',
                  icon: Icons.grid_view_rounded,
                  detail: installedVersion.when(
                    data: (v) => v.label,
                    loading: () => '正在读取版本…',
                    error: (_, _) => '无法读取版本信息',
                  ),
                ),
                SettingsGroup(
                  children: [
                    SettingsEntry(
                      title: '检查更新',
                      subtitle: '从 GitHub 检查应用新版本',
                      icon: Icons.system_update_rounded,
                      protected: true,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppUpdatePage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ];
              final information = [
                const SettingsGroup(
                  title: '数据',
                  children: [
                    SettingsEntry(
                      title: '本机数据',
                      subtitle: '数据与设置保存在本机，在线模块功能需要网络连接',
                      icon: Icons.storage_outlined,
                      protected: true,
                    ),
                  ],
                ),
                AppRepositoryLinks(
                  title: '项目与社区',
                  onBrowseModules: () => _openCatalog(context, ref),
                ),
              ];
              Widget column(List<Widget> children) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
              return twoColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 28,
                      children: [
                        Expanded(flex: 288, child: column(version)),
                        Expanded(flex: 444, child: column(information)),
                      ],
                    )
                  : column([...version, ...information]);
            },
          ),
        ],
      ),
    );
  }
}
