import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/modules/module_registry.dart';
import '../ai/settings/ai_connection_page.dart';
import '../ai/settings/ai_settings_store.dart';
import '../module_manager/module_manager_page.dart';
import '../tasks/application/providers.dart';
import 'app_preferences.dart';

String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.registry});

  final ModuleRegistry registry;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool saving = false;
  late Future<AiSettings> connection;

  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_registryChanged);
    connection = _loadConnection();
  }

  void _registryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.registry.removeListener(_registryChanged);
    super.dispose();
  }

  Future<AiSettings> _loadConnection() async =>
      (await ref.read(aiSettingsStoreProvider.future)).load();

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
                  shape: AppDesign.smoothShape(),
                  title: Text(themeModeLabel(mode)),
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

  Future<void> _openConnection() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AiConnectionPage()),
    );
    if (mounted) {
      setState(() {
        connection = _loadConnection();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appPreferencesProvider);
    return DetailPage(
      title: '设置',
      child: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('读取设置失败'),
              TextButton(
                onPressed: () => ref.invalidate(appPreferencesProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (preferences) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SectionHeading(title: '外观与体验'),
            ContentSurface(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('外观主题'),
                    subtitle: Text(themeModeLabel(preferences.themeMode)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    enabled: !saving,
                    onTap: () => _chooseTheme(preferences),
                  ),
                  const Divider(indent: 56, endIndent: 18),
                  SwitchListTile(
                    secondary: const Icon(Icons.animation_rounded),
                    title: const Text('减少动画'),
                    subtitle: const Text('减少底栏位移与按压动效，遵循系统偏好'),
                    value: preferences.reduceMotion,
                    onChanged: saving
                        ? null
                        : (value) => _update(
                            preferences.copyWith(reduceMotion: value),
                          ),
                  ),
                  const Divider(indent: 56, endIndent: 18),
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
            ),
            const SizedBox(height: 12),
            const SectionHeading(title: '功能与连接'),
            ContentSurface(
              child: Column(
                children: [
                  if (widget.registry.isEnabled('app.ai')) ...[
                    FutureBuilder<AiSettings>(
                      future: connection,
                      builder: (context, snapshot) => ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('AI 连接'),
                        subtitle: Text(
                          snapshot.hasError
                              ? '读取失败，点击重试配置'
                              : snapshot.hasData
                              ? (snapshot.data!.model.isEmpty
                                    ? '配置模型服务与密钥'
                                    : '当前模型 · ${snapshot.data!.model}')
                              : '读取连接配置…',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _openConnection,
                      ),
                    ),
                    const Divider(indent: 56, endIndent: 18),
                  ],
                  ListTile(
                    leading: const Icon(Icons.extension_outlined),
                    title: const Text('模块管理'),
                    subtitle: const Text('导入、启停与管理功能模块'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailPage(
                          title: '模块管理',
                          child: ModuleManagerPage(registry: widget.registry),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SectionHeading(title: '关于'),
            ContentSurface(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.grid_view_rounded),
                    title: Text('序点'),
                    subtitle: Text('专注当下，逐项完成'),
                    trailing: Text('0.1.0'),
                  ),
                  const Divider(indent: 56, endIndent: 18),
                  const ListTile(
                    leading: Icon(Icons.storage_outlined),
                    title: Text('本机数据'),
                    subtitle: Text('任务、项目和设置保存在本机，可离线使用'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
