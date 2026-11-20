import 'settings_focus.dart';
import '../../core/ui/native_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../app/app_toast.dart';
import '../../core/modules/module_registry.dart';
import '../../core/ui/ui_component.dart';
import '../../core/ui/ui_pack_settings_page.dart';
import '../../core/ui/ui_feedback.dart';
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
        AppToast.show(context, message: '设置保存失败，请重试', kind: 'error');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _themeCard(ThemeMode mode, AppPreferences preferences) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = mode == preferences.themeMode;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        enabled: !saving,
        child: Material(
          color: selected ? colors.primaryContainer : colors.surface,
          shape: AppDesign.smoothShape(
            radius: 17,
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.4 : .8,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: saving
                ? null
                : () => _update(preferences.copyWith(themeMode: mode)),
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 105),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 15, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(child: _ThemePreview(mode: mode)),
                        const SizedBox(height: 11),
                        Text(
                          appearanceThemeLabel(mode),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (selected)
                  PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: colors.primary,
                          shape: const CircleBorder(),
                        ),
                        child: SizedBox.square(
                          dimension: 15,
                          child: Icon(
                            Icons.check_rounded,
                            color: colors.onPrimary,
                            size: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => UiPackScope(
    child: DetailPage(
      title: '外观与交互',
      settingsStyle: true,
      child: ref
          .watch(appPreferencesProvider)
          .when(
            loading: () => const Center(
              child: NativeUi(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Center(
              child: AppErrorState(
                message: '读取外观设置失败，请重试',
                onRetry: () => ref.invalidate(appPreferencesProvider),
              ),
            ),
            data: (preferences) => SettingsList(
              children: [
                SettingsAnchor(
                  '外观主题',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SettingsHeading('外观主题'),
                      const SizedBox(height: 10),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 8,
                          children: [
                            for (final mode in ThemeMode.values)
                              _themeCard(mode, preferences),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const SettingsNote('主题和交互偏好会自动保存。'),
                    ],
                  ),
                ),
                SettingsGroup(
                  children: [
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
                    SettingsAnchor(
                      '减少动画',
                      child: NativeUi(
                        child: SwitchListTile(
                          secondary: const SettingsGlyph(
                            Icons.animation_rounded,
                          ),
                          title: const Text('减少动画'),
                          subtitle: const Text('减少位移与按压动效；系统减少动画偏好始终生效'),
                          value: preferences.reduceMotion,
                          onChanged: saving
                              ? null
                              : (value) => _update(
                                  preferences.copyWith(reduceMotion: value),
                                ),
                        ),
                      ),
                    ),
                    SettingsAnchor(
                      '触感反馈',
                      child: NativeUi(
                        child: SwitchListTile(
                          secondary: const SettingsGlyph(
                            Icons.vibration_rounded,
                          ),
                          title: const Text('触感反馈'),
                          subtitle: const Text('切换底部导航时轻触振动'),
                          value: preferences.haptics,
                          onChanged: saving
                              ? null
                              : (value) => _update(
                                  preferences.copyWith(haptics: value),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    ),
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 45,
    clipBehavior: Clip.antiAlias,
    foregroundDecoration: BoxDecoration(
      border: Border.all(color: const Color(0xff9699a2), width: .8),
      borderRadius: BorderRadius.circular(7),
    ),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(7)),
    child: Row(
      children: [
        for (final dark in [mode == ThemeMode.dark, mode != ThemeMode.light])
          Expanded(
            child: ColoredBox(
              color: dark ? const Color(0xff32343a) : const Color(0xfffcfcf8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 14, 3, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 5,
                  children: [
                    for (final width in [15.0, 10.0])
                      Container(
                        width: width,
                        height: 2,
                        decoration: BoxDecoration(
                          color: dark
                              ? const Color(0xffd6d6dd)
                              : const Color(0xff888b94),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
