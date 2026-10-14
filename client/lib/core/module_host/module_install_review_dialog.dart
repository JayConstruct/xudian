import 'dart:convert';

import 'package:flutter/material.dart';

import '../module_catalog/module_catalog.dart';
import '../ui/native_ui.dart';
import '../ui/ui_design.dart';
import 'module_package.dart';

/// The summary and the full plan share the resolver's immutable selection.
class ModuleBatchReviewDialog extends StatelessWidget {
  const ModuleBatchReviewDialog({
    super.key,
    required this.modules,
    required this.packages,
    this.requestedIds = const {},
  });

  final List<ResolvedCatalogModule> modules;
  final List<ScriptPackage> packages;
  final Set<String> requestedIds;

  ScriptPackage? _package(ResolvedCatalogModule item) =>
      packages.where((package) => package.id == item.id).firstOrNull ??
      item.package ??
      item.installed?.package;

  static String _action(ResolvedCatalogModule item) => switch (item.action) {
    ModuleResolutionAction.install => '安装并启用 · ${item.version}',
    ModuleResolutionAction.upgrade =>
      '升级并启用 · ${item.installed!.package.version} → ${item.version}',
    ModuleResolutionAction.enable => '启用 · ${item.version}',
    ModuleResolutionAction.reuse => '继续使用 · ${item.version}（无需安装）',
  };

  String get _summary {
    final counts = <ModuleResolutionAction, int>{};
    for (final item in modules) {
      counts.update(item.action, (count) => count + 1, ifAbsent: () => 1);
    }
    return [
      for (final action in ModuleResolutionAction.values)
        if (counts[action] case final count?)
          '${switch (action) {
            ModuleResolutionAction.install => '安装',
            ModuleResolutionAction.upgrade => '升级',
            ModuleResolutionAction.enable => '启用',
            ModuleResolutionAction.reuse => '继续使用',
          }} $count 个',
    ].join('，');
  }

  Set<String> _dependencies(ResolvedCatalogModule item) => {
    for (final raw in item.manifest['dependencies'] as List? ?? [])
      raw is String ? raw : object(raw)['moduleId'] as String,
    for (final raw in item.manifest['serviceDependencies'] as List? ?? [])
      object(raw)['moduleId'] as String,
    for (final permission
        in (item.manifest['permissions'] as List? ?? []).cast<String>())
      if (!optionalServicePermissions(item.manifest).contains(permission))
        if (RegExp(r'^services\.(query|command):([^/]+)/')
                .firstMatch(permission)
            case final match?)
          match[2]!,
  };

  String _reason(ResolvedCatalogModule item) {
    final consumers = [
      for (final consumer in modules)
        if (consumer.id != item.id && _dependencies(consumer).contains(item.id))
          consumer.name,
    ];
    return consumers.isEmpty
        ? '用于满足本次安装计划的完整依赖关系。'
        : '「${consumers.join('」、「')}」需要此模块才能运行。';
  }

  String _permission(String permission) {
    final service = RegExp(
      r'^services\.(query|command):([^/]+)/([^@]+)@([1-9]\d*)$',
    ).firstMatch(permission);
    if (service != null) {
      final provider = modules
          .where((item) => item.id == service[2])
          .firstOrNull;
      final providerName = service[2] == 'app.host'
          ? '宿主'
          : provider?.name ?? '其他模块';
      final definition = provider?.services
          .map(object)
          .where(
            (value) =>
                value['id'] == service[3] &&
                value['major'] == int.parse(service[4]!),
          )
          .firstOrNull;
      final description = definition?['description'] as String?;
      final detail = description == null || description.trim().isEmpty
          ? ''
          : '：$description';
      return service[1] == 'query'
          ? '读取「$providerName」提供的数据$detail'
          : '调用「$providerName」的变更服务，可能修改其数据$detail';
    }
    if (permission.startsWith('events.subscribe:')) {
      return '订阅其他模块声明的事件，接收变更通知';
    }
    return switch (permission) {
      'ui' => '显示模块界面、交互提示和保存界面偏好',
      'files' => '读取或保存由你选择的文本文件',
      'files.readText' => '读取由你选择的文本文件',
      'files.saveText' => '保存文本文件到你选择的位置',
      'http' => '向声明的网络地址或已配置凭据对应的地址发送请求',
      'browser' || 'browser.capture' => '打开网页；在你点击执行采集后运行模块脚本并读取网页内容',
      'secrets' => '通过安全输入配置或删除此模块的网络凭据',
      'secrets.configure' => '通过安全输入配置此模块的网络凭据',
      'secrets.delete' => '删除此模块保存的网络凭据',
      'grants.request' => '请求临时服务授权，需要另行确认',
      'packages.prepare' => '生成并预览模块包，安装需要另行审核',
      'extensions.query' => '读取其他模块为本模块数据提供的扩展信息',
      'automation.execute' => '执行已配置的自动化流程',
      'clock' || 'clock.now' || 'clock.today' || 'clock.local' => '读取日期和时间',
      'clock.systemTimezone' => '读取系统时区，用于新建记录的时间设置',
      'ids' || 'ids.new' => '生成记录的唯一标识',
      _ => '其他声明权限（用途未识别，请展开技术详情核对）',
    };
  }

  String _trust(ScriptPackage package) => switch (package.origin) {
    'market' when package.trusted => '发布者签名已验证，发布审核已通过',
    'preinstalled' => '已通过内置包摘要校验；未在此流程单独验证发布者签名',
    'local' => '未签名包；摘要验证不代表发布者签名',
    _ => '未确认发布者签名，请核对技术详情',
  };

  Widget _heading(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _module(BuildContext context, ResolvedCatalogModule item) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.name, style: Theme.of(context).textTheme.titleMedium),
        Text(item.description),
        Text(_action(item)),
        if (!requestedIds.contains(item.id) && requestedIds.isNotEmpty)
          Text(_reason(item)),
      ],
    ),
  );

  Widget _permissions(BuildContext context, ResolvedCatalogModule item) {
    final permissions =
        _package(item)?.permissions ??
        (item.manifest['permissions'] as List? ?? []).cast<String>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: Theme.of(context).textTheme.labelLarge),
          Text(
            permissions.isEmpty
                ? '无需声明权限'
                : item.addedPermissions.isEmpty
                ? '权限保持不变'
                : '新增 ${item.addedPermissions.length} 项权限',
          ),
          for (final permission in permissions)
            Text(
              '${item.addedPermissions.contains(permission) ? '新增 · ' : ''}${_permission(permission)}',
              style: item.addedPermissions.contains(permission)
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
          if (_package(item) case final package?) Text(_trust(package)),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) => NativeUi(
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('技术详情与完整计划'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('以下按依赖顺序列出完整计划；继续使用的模块不重复安装。'),
              for (var index = 0; index < modules.length; index++) ...[
                _heading(context, '${index + 1}. ${modules[index].name}'),
                SelectableText(
                  '模块标识：${modules[index].id}',
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
                Text(_action(modules[index])),
                SelectableText(
                  '来源：${modules[index].repository ?? '本地模块包'}',
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
                SelectableText(
                  '新增权限标识：${modules[index].addedPermissions.isEmpty ? '无' : modules[index].addedPermissions.join('、')}',
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
                if (_package(modules[index]) case final package?) ...[
                  SelectableText(
                    '全部权限标识：${package.permissions.isEmpty ? '无' : package.permissions.join('、')}',
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                  ),
                  Text(_trust(package)),
                  SelectableText(
                    '验证来源：${package.origin}',
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                  ),
                  SelectableText(
                    'SHA-256：${package.packageDigest}',
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                  ),
                  SelectableText(
                    '发布信息：${jsonEncode(package.release)}',
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                  ),
                ],
                SelectableText(
                  '依赖声明：${jsonEncode(modules[index].manifest['dependencies'] ?? [])}',
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
                SelectableText(
                  '服务依赖：${jsonEncode(modules[index].manifest['serviceDependencies'] ?? [])}',
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
                SelectableText(
                  '可选服务：${jsonEncode(modules[index].manifest['optionalServices'] ?? [])}',
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
                SelectableText(
                  '网络地址：${jsonEncode(modules[index].manifest['httpOrigins'] ?? [])}',
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
                SelectableText(
                  '完整模块声明：${const JsonEncoder.withIndent('  ').convert(modules[index].manifest)}',
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = modules
        .where((item) => requestedIds.isEmpty || requestedIds.contains(item.id))
        .toList();
    final dependencies = modules
        .where(
          (item) => requestedIds.isNotEmpty && !requestedIds.contains(item.id),
        )
        .toList();
    return NativeUi(
      protected: true,
      child: AlertDialog(
        titlePadding: AppDesign.dialogTitlePadding,
        contentPadding: AppDesign.dialogContentPadding,
        actionsPadding: AppDesign.dialogActionsPadding,
        title: const Text('确认模块安装计划'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_summary),
                _heading(context, '你选择的模块'),
                for (final item in selected) _module(context, item),
                if (dependencies.isNotEmpty) ...[
                  _heading(context, '自动加入的依赖'),
                  for (final item in dependencies) _module(context, item),
                ],
                _heading(context, '权限与影响'),
                for (final item in [...selected, ...dependencies])
                  _permissions(context, item),
                const Text('按依赖顺序统一执行；失败时恢复原版本、数据和启用状态。'),
                _details(context),
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
              child: const Text('确认安装'),
            ),
          ),
        ],
      ),
    );
  }
}
