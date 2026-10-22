import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_toast.dart';
import '../../app/design_system.dart';
import '../../core/app_updates/startup_update_preference.dart';
import '../../core/app_updates/startup_updates.dart';
import '../../core/module_host/host_providers.dart';
import '../../core/module_host/module_catalog_page.dart';
import '../../core/ui/native_ui.dart';
import 'app_update_page.dart';
import 'settings_widgets.dart';

class UpdateSettingsPage extends ConsumerStatefulWidget {
  const UpdateSettingsPage({super.key});

  @override
  ConsumerState<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends ConsumerState<UpdateSettingsPage> {
  bool saving = false;

  Future<void> _save(bool enabled) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await ref.read(startupUpdateEnabledProvider.notifier).save(enabled);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: '设置保存失败，请重试', kind: 'error');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _openModules() async {
    try {
      final host = await ref.read(moduleHostProvider.future);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => ModuleCatalogPage(host: host)),
      );
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: '无法打开模块商店，请重试', kind: 'error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(startupUpdateEnabledProvider);
    final checked = ref.watch(startupUpdatesProvider);
    final appUpdate = checked.app?.updateAvailable == true;
    final updates = checked.modules?.updates ?? const <String, String>{};
    return DetailPage(
      title: '更新设置',
      child: SettingsList(
        children: [
          SettingsGroup(
            title: '自动检查',
            children: [
              enabled.when(
                loading: () => const ListTile(title: Text('正在读取更新设置…')),
                error: (_, _) => ListTile(
                  title: const Text('读取更新设置失败'),
                  trailing: TextButton(
                    onPressed: () =>
                        ref.invalidate(startupUpdateEnabledProvider),
                    child: const Text('重试'),
                  ),
                ),
                data: (value) => NativeUi(
                  protected: true,
                  child: SwitchListTile(
                    title: const Text('启动时检查更新'),
                    subtitle: const Text('下次冷启动起，在后台检查 App 和已安装模块的更新'),
                    value: value,
                    onChanged: saving ? null : _save,
                  ),
                ),
              ),
            ],
          ),
          const SettingsNote('检查不会阻塞启动。发现更新时提醒；下载与安装由你确认。关闭后仍可手动检查。'),
          if (checked.checking) const SettingsNote('正在后台检查 App 和模块更新…'),
          SettingsGroup(
            title: 'App 与模块',
            children: [
              SettingsEntry(
                title: '检查 App 更新',
                subtitle: appUpdate
                    ? '发现新版本 ${checked.app!.release!.version}'
                    : checked.appFailed
                    ? '启动检查未完成，点击重试'
                    : checked.app != null
                    ? '启动检查未发现 App 更新'
                    : '查看当前版本、更新通道与发布说明',
                icon: Icons.system_update_rounded,
                protected: true,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const AppUpdatePage()),
                ),
              ),
              SettingsEntry(
                title: '检查模块更新',
                subtitle: updates.isNotEmpty
                    ? '发现 ${updates.length} 个模块更新：${updates.values.join('、')}'
                    : checked.modulesFailed ||
                          checked.modules?.incomplete == true
                    ? '启动检查未完成，点击前往模块商店重试'
                    : checked.modules != null
                    ? '启动检查未发现可用的模块更新'
                    : '在模块商店查看可更新版本并审核安装',
                icon: Icons.extension_outlined,
                protected: true,
                onTap: _openModules,
              ),
              if (updates.isNotEmpty && checked.modules!.incomplete)
                const SettingsNote('部分模块检查失败，请在模块商店刷新确认。'),
            ],
          ),
        ],
      ),
    );
  }
}
