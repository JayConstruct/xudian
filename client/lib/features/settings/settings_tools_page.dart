import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/ui/native_ui.dart';
import '../../core/ui/ui_annotation.dart';
import 'display_diagnostics_page.dart';
import 'settings_focus.dart';
import 'settings_widgets.dart';

class SettingsToolsPage extends ConsumerWidget {
  const SettingsToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DetailPage(
    title: '辅助工具',
    settingsStyle: true,
    child: SettingsList(
      children: [
        SettingsGroup(
          title: '显示诊断',
          children: [
            SettingsEntry(
              title: '显示与布局信息',
              subtitle: '查看当前视图尺寸、字号缩放与安全区，用于高级问题反馈',
              icon: Icons.aspect_ratio_rounded,
              protected: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const DisplayDiagnosticsPage(),
                ),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '界面反馈',
          children: [
            SettingsAnchor(
              '界面标注模式',
              child: NativeUi(
                child: SwitchListTile(
                  secondary: const SettingsGlyph(Icons.label_outline),
                  title: const Text('界面标注模式'),
                  subtitle: const Text('标记关键界面区域，查看或复制标识用于反馈'),
                  value: ref.watch(uiAnnotationProvider),
                  onChanged: (value) =>
                      ref.read(uiAnnotationProvider.notifier).setEnabled(value),
                ),
              ),
            ),
          ],
        ),
        const SettingsNote('标注仅显示界面信息，不包含任务正文或密钥。开启后可通过悬浮工具暂时隐藏或退出。'),
      ],
    ),
  );
}
