import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/design_system.dart';
import '../../core/app_updates/github_app_updates.dart';
import '../../core/ui/app_repository_links.dart';
import '../../core/ui/native_ui.dart';
import '../../core/ui/ui_icon.dart';
import 'settings_widgets.dart';

class AppUpdatePage extends ConsumerStatefulWidget {
  const AppUpdatePage({super.key});

  @override
  ConsumerState<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends ConsumerState<AppUpdatePage> {
  bool checking = false;
  AppUpdateResult? result;
  String? error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (checking) return;
    setState(() {
      checking = true;
      error = null;
      result = null;
    });
    try {
      if (ref.read(installedAppVersionProvider).hasError) {
        ref.invalidate(installedAppVersionProvider);
      }
      final installed = await ref.read(installedAppVersionProvider.future);
      if (!mounted) return;
      final checked = await ref
          .read(githubAppUpdatesProvider)
          .check(installed, ref.read(appUpdatePlatformProvider));
      if (mounted) setState(() => result = checked);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is AppUpdateException
              ? failure.message
              : '检查更新失败，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  void _notify(String message) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _open(Uri url) async {
    try {
      if (await ref.read(externalUrlLauncherProvider)(url)) return;
    } catch (_) {
      // Keep a copy action available if this device has no browser.
    }
    if (mounted) _notify('无法打开浏览器，请复制链接');
  }

  Future<void> _copy(Uri url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url.toString()));
      if (mounted) _notify('下载页链接已复制');
    } catch (_) {
      if (mounted) _notify('复制失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(installedAppVersionProvider);
    final release = result?.release;
    final update = result?.updateAvailable == true;
    final status = checking
        ? '正在检查更新…'
        : error != null
        ? '检查未完成'
        : release == null
        ? '暂未发布 App 正式版本'
        : update
        ? '发现新版本 ${release.version}'
        : '当前已是最新版本';
    final url = release?.url ?? appReleasesUrl;
    return DetailPage(
      title: '检查更新',
      child: SettingsList(
        children: [
          SettingsGroup(
            title: '当前版本',
            children: [
              NativeUi(
                child: ListTile(
                  leading: const UiIcon(Icons.grid_view_rounded),
                  title: const Text('序点'),
                  subtitle: Text(
                    installed.when(
                      data: (value) => value.label,
                      loading: () => '正在读取版本…',
                      error: (_, _) => '无法读取版本信息',
                    ),
                  ),
                ),
              ),
            ],
          ),
          ContentSurface(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (checking)
                    const NativeUi(child: CircularProgressIndicator())
                  else
                    UiIcon(
                      error != null
                          ? Icons.cloud_off_rounded
                          : update
                          ? Icons.system_update_rounded
                          : Icons.check_circle_outline,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  const SizedBox(height: 16),
                  Text(status, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    error ??
                        (checking
                            ? '正在查询 GitHub 上的应用发布版本。'
                            : release == null
                            ? '发布正式安装包后，可在这里检查并查看更新。'
                            : update
                            ? '可查看更新说明，并在 GitHub 下载适合设备的安装包。'
                            : '没有发现比当前安装版本更新的正式版本。'),
                  ),
                  if (release?.publishedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '发布于 ${DateFormat('yyyy年M月d日').format(release!.publishedAt!.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      NativeUi(
                        protected: true,
                        child: FilledButton(
                          onPressed: checking
                              ? null
                              : update
                              ? () => _open(url)
                              : _check,
                          child: Text(
                            checking
                                ? '检查中…'
                                : update
                                ? '查看更新并下载'
                                : error != null
                                ? '重试'
                                : '重新检查',
                          ),
                        ),
                      ),
                      if (update)
                        NativeUi(
                          protected: true,
                          child: OutlinedButton(
                            onPressed: _check,
                            child: const Text('重新检查'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (release != null && release.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionHeading(title: '更新说明'),
            ContentSurface(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  release.notes.length > 20000
                      ? '${release.notes.substring(0, 20000)}\n完整说明请查看 GitHub 发布页。'
                      : release.notes,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SettingsGroup(
            title: 'GitHub',
            children: [
              NativeUi(
                protected: true,
                child: ListTile(
                  title: const Text('打开发布页'),
                  subtitle: Text(url.toString()),
                  trailing: IconButton(
                    tooltip: '复制下载页链接',
                    icon: const UiIcon(Icons.copy_outlined),
                    onPressed: () => _copy(url),
                  ),
                  onTap: () => _open(url),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
