import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final externalUrlLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

class AppRepositoryLinks extends ConsumerWidget {
  const AppRepositoryLinks({super.key, required this.onBrowseModules});

  final VoidCallback onBrowseModules;

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      _notify(context, '无法打开链接，请复制地址');
    }
  }

  Future<void> _copy(BuildContext context, String address) async {
    try {
      await Clipboard.setData(ClipboardData(text: address));
      if (context.mounted) {
        _notify(context, '地址已复制');
      }
    } catch (_) {
      if (context.mounted) {
        _notify(context, '复制失败，请重试');
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
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(address, softWrap: true),
    onTap: () => _open(context, ref, address),
    trailing: IconButton(
      tooltip: copyTooltip,
      icon: const Icon(Icons.copy_outlined),
      onPressed: () => _copy(context, address),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text('关于序点', style: Theme.of(context).textTheme.titleMedium),
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
      TextButton.icon(
        onPressed: onBrowseModules,
        icon: const Icon(Icons.public),
        label: const Text('打开模块商店'),
      ),
    ],
  );
}
