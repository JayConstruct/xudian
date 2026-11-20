import '../../features/settings/settings_widgets.dart';

import 'dart:async';

import '../ui/ui_icon.dart';
import '../ui/native_ui.dart';
import '../ui/ui_component.dart';
import '../ui/ui_design.dart';

import 'package:flutter/material.dart';

import 'module_package.dart';

List<Map<String, Object?>> deduplicateServices(
  Iterable<Map<String, Object?>> services,
) => {
  for (final service in services)
    '${service['moduleId']}/${service['serviceId']}@${service['majorVersion']}':
        service,
}.values.toList();

List<Map<String, Object?>> manifestServiceRequirements(
  Map<String, Object?> manifest,
) => deduplicateServices([
  for (final raw in manifest['serviceDependencies'] as List? ?? []) object(raw),
  for (final permission
      in (manifest['permissions'] as List? ?? []).cast<String>())
    if (RegExp(r'^services\.(query|command):([^/]+)/(.+)@([1-9]\d*)$')
            .firstMatch(permission)
        case final match?)
      {
        'moduleId': match[2],
        'serviceId': match[3],
        'majorVersion': int.parse(match[4]!),
        'kind': match[1],
      },
]);

void showHostService(
  BuildContext context,
  Map<String, Object?> service, {
  bool useGlobalStyle = false,
}) => showDialog<void>(
  context: context,
  builder: (context) {
    final dialog = NativeUi(
      protected: !useGlobalStyle,
      child: AlertDialog(
        titlePadding: AppDesign.dialogTitlePadding,
        contentPadding: AppDesign.dialogContentPadding,
        actionsPadding: AppDesign.dialogActionsPadding,
        title: const Text('宿主内置服务'),
        content: Text(
          '${service['serviceId']} @ ${service['majorVersion']} 由宿主提供，无需安装。',
        ),
        actions: [
          NativeUi(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ),
        ],
      ),
    );
    return useGlobalStyle ? UiPackScope.global(child: dialog) : dialog;
  },
);

String moduleState(Map<String, Object?> row) =>
    row['error'] as String? ??
    (row['installed'] == 0
        ? '已卸载，数据保留'
        : row['enabled'] == 1
        ? '已启用'
        : '已停用');

class ModuleSummaryTile extends StatelessWidget {
  const ModuleSummaryTile({
    super.key,
    required this.name,
    required this.description,
    required this.version,
    required this.status,
    this.uiPack = false,
    this.onTap,
    this.trailing,
  });
  final String name, description, version, status;
  final bool uiPack;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => NativeUi(
    child: ListTile(
      leading: Tooltip(
        message: description,
        child: SettingsGlyph(
          uiPack ? Icons.palette_outlined : Icons.extension_outlined,
        ),
      ),
      title: Text(name),
      subtitle: Text('$version · $status'),
      onTap: onTap,
      trailing: trailing,
    ),
  );
}

class ModuleDetailsDialog extends StatelessWidget {
  const ModuleDetailsDialog({
    super.key,
    required this.package,
    required this.dependents,
    required this.onDependency,
    this.repository,
    this.status,
    this.allDependents,
    this.sheet = false,
  });
  final bool sheet;
  final ScriptPackage package;
  final List<String> dependents;
  final void Function(String id) onDependency;
  final String? repository, status;
  final List<String>? allDependents;

  Widget _field(BuildContext context, String title, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dialog = AlertDialog(
      titlePadding: AppDesign.dialogTitlePadding,
      contentPadding: AppDesign.dialogContentPadding,
      actionsPadding: AppDesign.dialogActionsPadding,
      title: Text(package.title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sheet) ...[
                Text(
                  package.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
              ],
              _field(context, '作用', package.description),
              _field(context, '模块 ID', package.id),
              _field(
                context,
                '版本与状态',
                '${package.version} · ${status ?? '待安装'}',
              ),
              _field(context, '作者', package.author),
              _field(context, '来源', repository ?? package.origin),
              _field(
                context,
                '签名',
                package.release['channel'] == 'market'
                    ? '发布者签名已验证'
                    : '未签名包；SHA-256 摘要校验不代表作者签名',
              ),
              _field(context, 'SHA-256', package.packageDigest),
              _field(context, '宿主兼容性', '${package.manifest['hostApi']}'),
              _field(
                context,
                '权限',
                package.permissions.isEmpty
                    ? '无'
                    : package.permissions.join('\n'),
              ),
              const Text('模块依赖（点击查看或安装）'),
              for (final raw in package.manifest['dependencies'] as List? ?? [])
                NativeUi(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      raw is String ? raw : '${object(raw)['moduleId']}',
                    ),
                    subtitle: Text(
                      raw is String ? '任意兼容版本' : '${object(raw)['version']}',
                    ),
                    trailing: const UiIcon(Icons.chevron_right),
                    onTap: () => onDependency(
                      raw is String ? raw : object(raw)['moduleId'] as String,
                    ),
                  ),
                ),
              if ((package.manifest['dependencies'] as List? ?? []).isEmpty)
                const Text('无模块依赖'),
              const SizedBox(height: 12),
              const Text('服务依赖（点击查看或安装提供模块）'),
              for (final raw in deduplicateServices(package.requiredServices))
                NativeUi(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${raw['moduleId']}'),
                    subtitle: Text(
                      '${raw['serviceId']} @ ${raw['majorVersion']} ${raw['kind'] ?? ''}',
                    ),
                    trailing: const UiIcon(Icons.chevron_right),
                    onTap: raw['moduleId'] == 'app.host'
                        ? () => showHostService(
                            context,
                            raw,
                            useGlobalStyle: sheet,
                          )
                        : () => onDependency(raw['moduleId'] as String),
                  ),
                ),
              if (package.requiredServices.isEmpty) const Text('无服务依赖'),
              const SizedBox(height: 12),
              if (allDependents != null)
                _field(
                  context,
                  '被依赖情况（所有已安装模块）',
                  allDependents!.isEmpty ? '无' : allDependents!.join('\n'),
                ),
              _field(
                context,
                '受影响的已启用模块',
                dependents.isEmpty ? '无' : dependents.join('\n'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        NativeUi(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ),
      ],
    );
    return NativeUi(
      child: sheet
          ? SettingsSheet(
              title: const Text('模块详情'),
              content: dialog.content!,
              expandedActions: true,
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            )
          : dialog,
    );
  }
}

Future<bool> confirmModuleImpact(
  BuildContext context, {
  required String title,
  required String moduleId,
  required List<String> affected,
  required String dataEffect,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => NativeUi(
        protected: true,
        child: AlertDialog(
          titlePadding: AppDesign.dialogTitlePadding,
          contentPadding: AppDesign.dialogContentPadding,
          actionsPadding: AppDesign.dialogActionsPadding,
          title: Text(title),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(moduleId),
                  const SizedBox(height: 12),
                  Text(affected.isEmpty ? '没有其他模块会停用。' : '以下模块会一起停用：'),
                  for (final id in affected)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(id),
                    ),
                  const SizedBox(height: 12),
                  Text(dataEffect),
                ],
              ),
            ),
          ),
          actions: [
            NativeUi(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
            ),
            NativeUi(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ),
          ],
        ),
      ),
    ) ??
    false;

/// Paint the dialog shell before any installed-package or index work begins.
class ModuleDetailsLoader extends StatefulWidget {
  const ModuleDetailsLoader({
    super.key,
    required this.title,
    required this.load,
    this.sheet = false,
  });
  final String title;
  final Future<Widget> Function() load;
  final bool sheet;

  @override
  State<ModuleDetailsLoader> createState() => _ModuleDetailsLoaderState();
}

class _ModuleDetailsLoaderState extends State<ModuleDetailsLoader> {
  final content = Completer<Widget>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Future<Widget>.sync(widget.load)
            .then<void>(content.complete, onError: content.completeError),
      );
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: content.future,
    builder: (context, snapshot) {
      if (snapshot.hasData) return snapshot.data!;
      if (widget.sheet) {
        return SettingsSheet(
          title: Text(widget.title),
          expandedActions: true,
          content: snapshot.hasError
              ? SingleChildScrollView(
                  child: SelectableText('${snapshot.error}'),
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(minHeight: 3),
                    SizedBox(height: 12),
                    Text('正在读取模块详情…'),
                  ],
                ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      }
      return NativeUi(
        child: AlertDialog(
          title: Text(widget.title),
          titlePadding: AppDesign.dialogTitlePadding,
          contentPadding: AppDesign.dialogContentPadding,
          actionsPadding: AppDesign.dialogActionsPadding,
          content: SizedBox(
            width: 620,
            child: snapshot.hasError
                ? SelectableText('${snapshot.error}')
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 12),
                      Text('正在读取模块详情…'),
                    ],
                  ),
          ),
          actions: [
            NativeUi(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
