import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/settings/settings_focus.dart';
import '../../features/settings/settings_widgets.dart';
import 'ui_icon.dart';
import 'ui_toast.dart';

final externalUrlLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

class AppRepositoryLinks extends ConsumerWidget {
  const AppRepositoryLinks({
    super.key,
    required this.onBrowseModules,
    this.title = '关于序点',
  });

  final VoidCallback onBrowseModules;
  final String title;

  void _notify(BuildContext context, String message, {required String kind}) {
    AppToast.show(context, message: message, kind: kind);
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String address,
  ) async {
    var opened = false;
    try {
      opened = await ref.read(externalUrlLauncherProvider)(Uri.parse(address));
    } catch (_) {
      // The address remains available to copy when no browser can handle it.
    }
    if (!opened && context.mounted) {
      _notify(context, '无法打开链接，请复制地址', kind: 'error');
    }
  }

  Future<void> _copy(BuildContext context, String address) async {
    try {
      await Clipboard.setData(ClipboardData(text: address));
      if (context.mounted) {
        _notify(context, '地址已复制', kind: 'success');
      }
    } catch (_) {
      if (context.mounted) {
        _notify(context, '复制失败，请重试', kind: 'error');
      }
    }
  }

  Widget _link(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String address,
    required String copyTooltip,
    required IconData icon,
  }) => SettingsAnchor(
    title,
    child: ListTile(
      minTileHeight: 62,
      leading: SettingsGlyph(icon),
      title: Text(title),
      subtitle: Text(address),
      onTap: () => _open(context, ref, address),
      trailing: IconButton(
        tooltip: copyTooltip,
        alignment: AlignmentDirectional.centerEnd,
        icon: const UiIcon(Icons.copy_outlined, size: 18),
        onPressed: () => _copy(context, address),
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsGroup(
    title: title,
    children: [
      _link(
        context,
        ref,
        title: '项目地址',
        address: 'https://github.com/JayConstruct/xudian',
        copyTooltip: '复制项目地址',
        icon: Icons.code_rounded,
      ),
      _link(
        context,
        ref,
        title: '模块仓库',
        address: 'https://github.com/JayConstruct/xudian-modules',
        copyTooltip: '复制模块仓库地址',
        icon: Icons.extension_outlined,
      ),
      SettingsEntry(
        title: '打开模块商店',
        icon: Icons.public,
        trailing: const Icon(Icons.chevron_right_rounded, size: 14),
        protected: true,
        onTap: onBrowseModules,
      ),
    ],
  );
}
