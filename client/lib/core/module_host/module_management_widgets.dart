import 'package:flutter/material.dart';

import 'module_package.dart';
import 'module_host.dart';

Future<List<String>> installedDependentLabels(
  ModuleHost host,
  String id,
) async {
  final result = <String>[];
  for (final row in await host.store.sql(
    'SELECT * FROM host_installations WHERE installed=1',
  )) {
    final moduleId = row['module_id'] as String;
    if (moduleId == id) continue;
    final source = await host.packageSource(moduleId, row['version'] as String);
    if (source.dependencies.contains(id)) {
      result.add('$moduleId（${row['enabled'] == 1 ? '已启用' : '已停用'}）');
    }
  }
  return result;
}

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

void showHostService(BuildContext context, Map<String, Object?> service) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('宿主内置服务'),
        content: Text(
          '${service['serviceId']} @ ${service['majorVersion']} 由宿主提供，无需安装。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => ListTile(
    leading: Icon(uiPack ? Icons.palette_outlined : Icons.extension_outlined),
    title: Text(name),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(description),
        const SizedBox(height: 4),
        Text('$version · $status'),
      ],
    ),
    onTap: onTap,
    trailing: trailing,
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
  });
  final ScriptPackage package;
  final List<String> dependents;
  final void Function(String id) onDependency;
  final String? repository, status;
  final List<String>? allDependents;

  Widget _field(String title, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(title), SelectableText(value)],
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(package.title),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('作用', package.description),
            _field('模块 ID', package.id),
            _field('版本与状态', '${package.version} · ${status ?? '待安装'}'),
            _field('作者', package.author),
            _field('来源', repository ?? package.origin),
            _field(
              '签名',
              package.release['channel'] == 'market'
                  ? '发布者签名已验证'
                  : '未签名包；SHA-256 摘要校验不代表作者签名',
            ),
            _field('SHA-256', package.packageDigest),
            _field('宿主兼容性', '${package.manifest['hostApi']}'),
            _field(
              '权限',
              package.permissions.isEmpty
                  ? '无'
                  : package.permissions.join('\n'),
            ),
            const Text('模块依赖（点击查看或安装）'),
            for (final raw in package.manifest['dependencies'] as List? ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(raw is String ? raw : '${object(raw)['moduleId']}'),
                subtitle: Text(
                  raw is String ? '任意兼容版本' : '${object(raw)['version']}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onDependency(
                  raw is String ? raw : object(raw)['moduleId'] as String,
                ),
              ),
            if ((package.manifest['dependencies'] as List? ?? []).isEmpty)
              const Text('无模块依赖'),
            const SizedBox(height: 12),
            const Text('服务依赖（点击查看或安装提供模块）'),
            for (final raw in deduplicateServices(package.requiredServices))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${raw['moduleId']}'),
                subtitle: Text(
                  '${raw['serviceId']} @ ${raw['majorVersion']} ${raw['kind'] ?? ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: raw['moduleId'] == 'app.host'
                    ? () => showHostService(context, raw)
                    : () => onDependency(raw['moduleId'] as String),
              ),
            if (package.requiredServices.isEmpty) const Text('无服务依赖'),
            const SizedBox(height: 12),
            if (allDependents != null)
              _field(
                '被依赖情况（所有已安装模块）',
                allDependents!.isEmpty ? '无' : allDependents!.join('\n'),
              ),
            _field(
              '受影响的已启用模块',
              dependents.isEmpty ? '无' : dependents.join('\n'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
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
      builder: (context) => AlertDialog(
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;
