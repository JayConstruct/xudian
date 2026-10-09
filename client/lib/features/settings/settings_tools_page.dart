import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/ui/ui_annotation.dart';
import 'settings_widgets.dart';

class SettingsToolsPage extends ConsumerWidget {
  const SettingsToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DetailPage(
    title: '辅助工具',
    child: SettingsList(
      children: [
        const SettingsNote('用于描述界面、定位问题和反馈建议。'),
        SettingsGroup(
          title: '界面辅助',
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.label_outline),
              title: const Text('界面标注模式'),
              subtitle: const Text('标记关键界面区域，查看或复制标识用于反馈'),
              value: ref.watch(uiAnnotationProvider),
              onChanged: (value) =>
                  ref.read(uiAnnotationProvider.notifier).setEnabled(value),
            ),
          ],
        ),
        const SettingsNote('标注仅显示界面信息，不包含任务正文或密钥。开启后可通过悬浮工具暂时隐藏或退出。'),
      ],
    ),
  );
}
