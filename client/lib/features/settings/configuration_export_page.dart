import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_toast.dart';
import '../../app/design_system.dart';
import '../../core/ui/native_ui.dart';
import '../../core/ui/ui_annotation.dart';
import '../../core/ui/ui_icon.dart';
import 'configuration_export.dart';
import 'settings_focus.dart';
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
    settingsStyle: true,
    child: SettingsList(
      footer: NativeUi(
        child: FilledButton.icon(
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const UiIcon(Icons.file_download_outlined, size: 18),
          label: Text(_exporting ? '正在导出…' : '选择位置并导出'),
        ),
      ),
      children: [
        const SettingsSummary(
          label: '导出格式',
          title: 'JSON 配置文件',
          detail: '保存位置由你选择',
          icon: Icons.description_outlined,
        ),
        const SettingsGroup(
          title: '导出内容',
          children: [
            ListTile(
              leading: SettingsGlyph(Icons.dashboard_outlined),
              title: Text('应用与界面'),
              subtitle: Text('外观、交互、布局与导航、界面风格、更新渠道和界面标注状态'),
            ),
            ListTile(
              leading: SettingsGlyph(Icons.extension_outlined),
              title: Text('模块与连接'),
              subtitle: Text('模块版本与启停状态、仓库来源、各模块界面偏好、AI 连接、课表学期与作息参数、规划设置与规则'),
            ),
          ],
        ),
        SettingsGroup(
          title: '连接密钥',
          children: [
            SettingsAnchor(
              '包含 API 密钥',
              child: NativeUi(
                child: SwitchListTile(
                  secondary: const SettingsGlyph(Icons.key_outlined),
                  title: const Text('包含 API 密钥'),
                  subtitle: const Text('开启后密钥将以明文写入文件，请妥善保管'),
                  value: _includeSecrets,
                  onChanged: _exporting
                      ? null
                      : (value) => setState(() => _includeSecrets = value),
                ),
              ),
            ),
          ],
        ),
        if (_includeSecrets) const _ExportSecretsWarning(),
        const SettingsNote(
          '不包含任务、课程安排、聊天记录或模块安装包。模块集合需声明为配置才会导出，旧版模块可能需要更新。当前仅支持导出，暂不支持从此文件恢复配置。',
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(_status!)),
          ),
      ],
    ),
  );
}

class _ExportSecretsWarning extends StatelessWidget {
  const _ExportSecretsWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF1B5A7) : const Color(0xFF904532);
    final surface = dark ? const Color(0xFF452E2D) : const Color(0xFFF8EBE4);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: surface,
          shape: AppDesign.smoothShape(radius: AppDesign.controlRadius),
        ),
        child: Row(
          children: [
            UiIcon(Icons.warning_amber_rounded, color: ink, size: 17),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                '此文件将包含明文密钥，请保存到可信位置。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ink,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
