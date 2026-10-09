import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/modules/module_registry.dart';
import '../../core/ui/ui_component.dart';
import '../../core/ui/ui_pack_settings_page.dart';
import 'app_preferences.dart';
import 'settings_widgets.dart';

String appearanceThemeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

class AppearanceSettingsPage extends ConsumerStatefulWidget {
  const AppearanceSettingsPage({super.key, required this.registry});
  final ModuleRegistry registry;

  @override
  ConsumerState<AppearanceSettingsPage> createState() =>
      _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState
    extends ConsumerState<AppearanceSettingsPage> {
  bool saving = false;

  Future<void> _update(AppPreferences preferences) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await ref.read(appPreferencesProvider.notifier).save(preferences);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _chooseTheme(AppPreferences preferences) async {
    final mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SectionHeading(title: '外观主题'),
              for (final mode in ThemeMode.values)
                ListTile(
                  title: Text(appearanceThemeLabel(mode)),
                  selected: mode == preferences.themeMode,
                  trailing: mode == preferences.themeMode
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, mode),
                ),
            ],
          ),
        ),
      ),
    );
    if (mode != null && mounted) {
      await _update(preferences.copyWith(themeMode: mode));
    }
  }

  @override
  Widget build(BuildContext context) => UiPackScope(
    defaultOnly: true,
    child: DetailPage(
      title: '外观与交互',
      child: ref
          .watch(appPreferencesProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('读取外观设置失败'),
                  TextButton(
                    onPressed: () => ref.invalidate(appPreferencesProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
            data: (preferences) => SettingsList(
              children: [
                const SettingsNote('调整整体外观和操作反馈。修改后自动保存。'),
                SettingsGroup(
                  title: '外观',
                  children: [
                    SettingsEntry(
                      title: '外观主题',
                      subtitle: appearanceThemeLabel(preferences.themeMode),
                      icon: Icons.brightness_6_outlined,
                      enabled: !saving,
                      onTap: () => _chooseTheme(preferences),
                    ),
                    SettingsEntry(
                      title: '界面风格',
                      subtitle: '全局风格、模块专属界面与恢复默认',
                      icon: Icons.palette_outlined,
                      protected: true,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UiPackSettingsPage(registry: widget.registry),
                        ),
                      ),
                    ),
                  ],
                ),
                SettingsGroup(
                  title: '交互反馈',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.animation_rounded),
                      title: const Text('减少动画'),
                      subtitle: const Text('减少位移与按压动效；系统减少动画偏好始终生效'),
                      value: preferences.reduceMotion,
                      onChanged: saving
                          ? null
                          : (value) => _update(
                              preferences.copyWith(reduceMotion: value),
                            ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.vibration_rounded),
                      title: const Text('触感反馈'),
                      subtitle: const Text('切换底部导航时轻触振动'),
                      value: preferences.haptics,
                      onChanged: saving
                          ? null
                          : (value) =>
                                _update(preferences.copyWith(haptics: value)),
                    ),
                  ],
                ),
              ],
            ),
          ),
    ),
  );
}
