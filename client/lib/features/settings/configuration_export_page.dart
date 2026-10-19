import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_toast.dart';
import '../../app/design_system.dart';
import '../../core/ui/native_ui.dart';
import '../../core/ui/ui_annotation.dart';
import 'configuration_export.dart';
import 'settings_widgets.dart';

class ConfigurationExportPage extends ConsumerStatefulWidget {
  const ConfigurationExportPage({super.key});

  @override
  ConsumerState<ConfigurationExportPage> createState() =>
      _ConfigurationExportPageState();
}

class _ConfigurationExportPageState
    extends ConsumerState<ConfigurationExportPage> {
  bool _includeSecrets = false;
  bool _exporting = false;
  String? _status;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _status = null;
    });
    try {
      final exporter = await ref.read(configurationExporterProvider.future);
      if (!mounted) return;
      final now = DateTime.now();
      final snapshot = await exporter.capture(
        includeSecrets: _includeSecrets,
        annotationEnabled: ref.read(uiAnnotationProvider),
        now: now,
      );
      if (!mounted) return;
      final name =
          'xudian-config-${now.toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.json';
      final saved = await ref
          .read(configurationFileSaverProvider)
          .save(
            name: name,
            text: '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
          );
      if (!mounted) return;
      setState(() => _status = saved ? '配置已导出到所选位置' : '已取消导出');
    } catch (error) {
      if (!mounted) return;
      final message =
          error is FormatException && error.message == '配置文件超过 2 MiB，无法导出'
          ? error.message
          : '配置导出失败，请重试';
      setState(() => _status = message);
      // Do not surface database contents, platform errors or secret values.
      AppToast.show(context, message: message, kind: 'error');
      ref.invalidate(configurationExporterProvider);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => DetailPage(
    title: '导出所有配置',
    child: SettingsList(
      children: [
        const SettingsNote('将当前配置保存为 JSON 文件，保存位置由你选择。'),
        const SettingsGroup(
          title: '导出内容',
          children: [
            ListTile(
              title: Text('应用与界面'),
              subtitle: Text('外观、交互、布局与导航、界面风格、更新渠道和界面标注状态'),
            ),
            ListTile(
              title: Text('模块与连接'),
              subtitle: Text('模块版本与启停状态、仓库来源、各模块界面偏好、AI 连接、课表学期与作息参数、规划设置与规则'),
            ),
          ],
        ),
        SettingsGroup(
          title: '连接密钥',
          children: [
            NativeUi(
              child: SwitchListTile(
                title: const Text('包含 API 密钥'),
                subtitle: const Text('开启后密钥将以明文写入文件，请妥善保管'),
                value: _includeSecrets,
                onChanged: _exporting
                    ? null
                    : (value) => setState(() => _includeSecrets = value),
              ),
            ),
          ],
        ),
        const SettingsNote(
          '不包含任务、课程安排、聊天记录或模块安装包。模块集合需声明为配置才会导出，旧版模块可能需要更新。当前仅支持导出，暂不支持从此文件恢复配置。',
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(_status!)),
          ),
        NativeUi(
          child: FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            label: Text(_exporting ? '正在导出…' : '选择位置并导出'),
          ),
        ),
      ],
    ),
  );
}
