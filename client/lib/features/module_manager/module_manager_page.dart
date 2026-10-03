import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/modules/module_registry.dart';
import '../../core/modules/builtin_module_registration.dart';
import '../../core/declarative/package/module_package.dart';
import '../ai/proposal/module_proposal_coordinator.dart';
import '../ai/proposal/module_proposal_service.dart';
import '../../data/app_database.dart';
import '../declarative_runtime/declarative_runtime_controller.dart';
import '../tasks/application/providers.dart';
import 'template_parameter_dialog.dart';
import 'builtin_module_controller.dart';

class ModuleManagerPage extends ConsumerStatefulWidget {
  const ModuleManagerPage({super.key, required this.registry});

  final ModuleRegistry registry;

  @override
  ConsumerState<ModuleManagerPage> createState() => _ModuleManagerPageState();
}

class _ModuleManagerPageState extends ConsumerState<ModuleManagerPage> {
  late Future<List<ModuleInstallation>> future;
  bool changingBuiltin = false;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<List<ModuleInstallation>> _load() async {
    final store = await ref.read(declarativeModuleStoreProvider.future);
    final rows = await store.listInstalled();
    rows.sort((a, b) => a.id.compareTo(b.id));
    return rows;
  }

  Future<DeclarativeRuntimeController> _runtime() async {
    final store = await ref.read(declarativeModuleStoreProvider.future);
    return DeclarativeRuntimeController(
      store: store,
      registry: widget.registry,
      ruleEngine: await ref.read(ruleEngineProvider.future),
      templateEngine: await ref.read(templateEngineProvider.future),
    );
  }

  void _reload() => setState(() {
    future = _load();
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionHeading(
          title: '功能模块',
          action: FilledButton.tonalIcon(
            onPressed: _importPackage,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('导入包'),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.registry,
            builder: (context, _) => FutureBuilder<List<ModuleInstallation>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  if (snapshot.hasError) {
                    return Center(child: Text('读取模块失败：${snapshot.error}'));
                  }
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    WorkspaceContentInsets.bottomOf(context) + 16,
                  ),
                  children: [
                    if (widget.registry.builtins.isNotEmpty) ...[
                      const SectionHeading(title: '内置功能'),
                      for (final module in widget.registry.builtins) ...[
                        _builtinCard(module),
                        const SizedBox(height: 10),
                      ],
                    ],
                    const SectionHeading(title: '扩展模块'),
                    if (items.isEmpty)
                      const ContentSurface(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('还没有扩展模块，可导入模块包或用 AI 创建'),
                        ),
                      ),
                    for (final module in items) ...[
                      _moduleCard(module),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _builtinCard(BuiltinModuleRegistration module) {
    final enabled = widget.registry.isEnabled(module.id);
    return Card(
      key: ValueKey('builtin-module-${module.id}'),
      child: ListTile(
        leading: Icon(switch (module.id) {
          'app.views.today' => Icons.today_outlined,
          'app.views.inbox' => Icons.inbox_outlined,
          'app.views.projects' => Icons.folder_outlined,
          'app.ai' => Icons.auto_awesome_outlined,
          _ => Icons.extension_outlined,
        }),
        title: Text(module.title),
        subtitle: Text(
          '${module.description}\n${module.canDisable ? '${module.kind == BuiltinModuleKind.native ? '原生' : '声明式'} · ${enabled ? '已启用' : '已关闭，数据保留'}' : '基础功能 · 保持可用'}',
        ),
        isThreeLine: true,
        trailing: module.canDisable
            ? Switch(
                key: ValueKey('builtin-switch-${module.id}'),
                value: enabled,
                onChanged: changingBuiltin
                    ? null
                    : (value) => _setBuiltinEnabled(module, value),
              )
            : const Tooltip(
                message: '模块管理必须保持可用',
                child: Icon(Icons.lock_outline_rounded),
              ),
      ),
    );
  }

  Future<void> _setBuiltinEnabled(
    BuiltinModuleRegistration module,
    bool enabled,
  ) async {
    if (changingBuiltin) return;
    setState(() => changingBuiltin = true);
    try {
      await (await ref.read(
        builtinModuleControllerProvider(widget.registry).future,
      )).setEnabled(module.id, enabled);
    } catch (error) {
      _message('无法更改${module.title}：$error');
    } finally {
      if (mounted) setState(() => changingBuiltin = false);
    }
  }

  Widget _moduleCard(ModuleInstallation module) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.extension_outlined),
        title: Text(module.id),
        subtitle: Text(
          module.installed
              ? '版本 ${module.version} · '
                    '${module.enabled ? '已启用' : '已停用'} · '
                    '${_originLabel(module)}'
              : '已卸载 · 数据已保留 · '
                    '${_originLabel(module)}',
        ),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (module.installed)
              Switch(
                value: module.enabled,
                onChanged: (value) => _setEnabled(module, value),
              ),
            PopupMenuButton<String>(
              onSelected: (value) => _action(module, value),
              itemBuilder: (_) => [
                if (module.installed && module.enabled)
                  const PopupMenuItem(value: 'templates', child: Text('应用模板')),
                if (module.installed)
                  const PopupMenuItem(value: 'ruleLogs', child: Text('规则运行记录')),
                if (module.installed)
                  const PopupMenuItem(value: 'versions', child: Text('版本历史')),
                if (!module.installed)
                  const PopupMenuItem(value: 'reinstall', child: Text('重新安装')),
                if (module.installed)
                  const PopupMenuItem(
                    value: 'uninstall',
                    child: Text('卸载并保留数据'),
                  ),
                const PopupMenuItem(value: 'delete', child: Text('彻底删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _originLabel(ModuleInstallation module) {
    return switch (module.origin) {
      'market' => '市场 · ${module.publisherId ?? '未知发布者'}',
      'ai' => 'AI',
      'local-package' => '本地包',
      _ => '本地',
    };
  }

  Future<void> _importPackage() async {
    try {
      const group = XTypeGroup(
        label: '序点模块包',
        extensions: ['json', 'xudianmodule'],
      );
      final file = await openFile(acceptedTypeGroups: const [group]);
      if (file == null) return;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('模块包必须是 JSON 对象');
      }
      final package = decoded.map((key, value) => MapEntry('$key', value));
      final verifier = await ref.read(modulePackageVerifierProvider.future);
      final verified = await verifier.verify(package, allowUnsignedLocal: true);
      if (!mounted) return;

      final accepted = await _confirmPackageImport(verified);
      if (!accepted || !mounted) return;

      final store = await ref.read(declarativeModuleStoreProvider.future);
      final service = ModuleProposalService(
        store: store,
        registry: widget.registry,
        runtime: await _runtime(),
      );
      if (!mounted) return;

      final applied = await ModuleProposalCoordinator(service).reviewAndApply(
        context,
        verified.moduleSource,
        provenance: verified.provenance,
      );
      if (applied && mounted) {
        _reload();
        _message('模块包已安装');
      }
    } catch (error) {
      _message('导入模块包失败：$error');
    }
  }

  Future<bool> _confirmPackageImport(VerifiedModulePackage package) async {
    final manifest = package.moduleSource['manifest'];
    final manifestMap = manifest is Map
        ? manifest.cast<String, Object?>()
        : const <String, Object?>{};
    final permissions =
        (manifestMap['permissions'] as List?)?.cast<String>() ??
        const <String>[];
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(package.trusted ? '已验证市场模块包' : '导入本地开发包'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模块：${manifestMap['id'] ?? '-'} '
                    '${manifestMap['version'] ?? ''}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    package.trusted
                        ? '发布者：${package.publisherId ?? '-'} · '
                              '审核：${package.provenance.reviewId ?? '-'}'
                        : '此包未经过市场审核和受信任签名验证。',
                  ),
                  if (package.summary != null) ...[
                    const SizedBox(height: 8),
                    Text('说明：${package.summary}'),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'SHA-256：'
                    '${package.provenance.packageDigest ?? '-'}',
                    maxLines: 2,
                  ),
                  if (permissions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('声明权限', style: Theme.of(context).textTheme.titleSmall),
                    for (final permission in permissions) Text('• $permission'),
                  ],
                  if (!package.trusted) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '仅在你明确知道此文件来源时继续。'
                      '后续仍会进行 Schema、语义、权限和 Diff 校验。',
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(package.trusted ? '继续审核' : '仍然继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _setEnabled(ModuleInstallation module, bool enabled) async {
    try {
      await (await _runtime()).setEnabled(module.id, enabled);
      _reload();
    } catch (error) {
      _message('操作失败：$error');
    }
  }

  Future<void> _action(ModuleInstallation module, String action) async {
    switch (action) {
      case 'templates':
        await _showTemplates(module);
      case 'ruleLogs':
        await _showRuleLogs(module);
      case 'versions':
        await _showVersions(module);
      case 'reinstall':
        final store = await ref.read(declarativeModuleStoreProvider.future);
        final source = await store.versionSource(module.id, module.version);
        await (await _runtime()).install(source);
        _reload();
      case 'uninstall':
        await (await _runtime()).uninstall(module.id);
        _reload();
      case 'delete':
        await _deleteModule(module);
    }
  }

  Future<void> _showTemplates(ModuleInstallation module) async {
    final engine = await ref.read(templateEngineProvider.future);
    final templates = engine.templatesFor(module.id);
    if (!mounted) return;
    if (templates.isEmpty) {
      _message('该模块没有可应用的模板');
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('应用模板 · ${module.id}'),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final template in templates)
                ListTile(
                  title: Text(template['title'] as String),
                  subtitle: Text(template['id'] as String),
                  trailing: TextButton(
                    onPressed: () =>
                        Navigator.pop(context, template['id'] as String),
                    child: const Text('应用'),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

    if (selected == null || !mounted) return;
    final template = templates.where((item) => item['id'] == selected).single;
    final parameters = await showTemplateParameterDialog(
      context: context,
      template: template,
    );
    if (parameters == null) return;

    try {
      final result = await engine.apply(
        module.id,
        selected,
        parameters: parameters,
      );
      _message(
        '模板已创建 ${result.createdTasks} 个任务'
        '${result.projectId == null ? '' : '，并创建项目'}',
      );
    } catch (error) {
      _message('模板应用失败：$error');
    }
  }

  Future<void> _showRuleLogs(ModuleInstallation module) async {
    final store = await ref.read(ruleExecutionStoreProvider.future);
    final engine = await ref.read(ruleEngineProvider.future);
    var statusFilter = 'all';
    var logs = await store.listForModule(module.id);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refresh() async {
            logs = await store.listForModule(
              module.id,
              status: statusFilter == 'all' ? null : statusFilter,
            );
            setDialogState(() {});
          }

          return AlertDialog(
            title: Text('规则运行记录 · ${module.id}'),
            content: SizedBox(
              width: 680,
              height: 520,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('全部')),
                        ButtonSegment(value: 'failure', label: Text('失败')),
                        ButtonSegment(value: 'skipped', label: Text('跳过')),
                        ButtonSegment(value: 'success', label: Text('成功')),
                      ],
                      selected: {statusFilter},
                      onSelectionChanged: (value) async {
                        statusFilter = value.first;
                        await refresh();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: logs.isEmpty
                        ? const Center(child: Text('暂无运行记录'))
                        : ListView.separated(
                            itemCount: logs.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final log = logs[index];
                              final detail = <String>[
                                log.eventType,
                                '${log.entityType}:${log.entityId}',
                                '动作 ${log.actionCount}',
                                '深度 ${log.automationDepth}',
                                if (log.sourceExecutionId != null)
                                  '重试 #${log.sourceExecutionId}',
                              ].join(' · ');
                              return ListTile(
                                dense: true,
                                leading: Icon(_ruleStatusIcon(log.status)),
                                title: Text(
                                  '${log.ruleId} · '
                                  '${_ruleStatusText(log.status)}',
                                ),
                                subtitle: Text(
                                  log.message == null
                                      ? detail
                                      : '$detail\n${log.message}',
                                ),
                                isThreeLine: log.message != null,
                                trailing: Wrap(
                                  spacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (log.status == 'failure')
                                      IconButton(
                                        tooltip: '重试此规则',
                                        icon: const Icon(Icons.replay),
                                        onPressed: () async {
                                          await engine.retry(log);
                                          await refresh();
                                        },
                                      ),
                                    Text(
                                      _formatTime(log.createdAt),
                                      textAlign: TextAlign.end,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              if (logs.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await store.clearForModule(module.id);
                    await refresh();
                  },
                  child: const Text('清空记录'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _ruleStatusIcon(String status) => switch (status) {
    'success' => Icons.check_circle_outline,
    'failure' => Icons.error_outline,
    'skipped' => Icons.skip_next_outlined,
    _ => Icons.play_circle_outline,
  };

  String _ruleStatusText(String status) => switch (status) {
    'success' => '成功',
    'failure' => '失败',
    'skipped' => '跳过',
    'triggered' => '触发',
    _ => status,
  };

  String _versionOriginLabel(ModuleVersion version) {
    return switch (version.origin) {
      'market' => '市场 · ${version.publisherId ?? '未知发布者'}',
      'ai' => 'AI',
      'local-package' => '本地包',
      _ => '本地',
    };
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showVersions(ModuleInstallation module) async {
    final store = await ref.read(declarativeModuleStoreProvider.future);
    final versions = await store.listVersions(module.id);
    if (!mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('版本历史 · ${module.id}'),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final version in versions)
                ListTile(
                  title: Text(version.version),
                  subtitle: Text(
                    '${version.installedAt.toLocal()} · '
                    '${_versionOriginLabel(version)}',
                  ),
                  trailing: version.version == module.version
                      ? const Chip(label: Text('当前'))
                      : TextButton(
                          onPressed: () =>
                              Navigator.pop(context, version.version),
                          child: const Text('回退'),
                        ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

    if (selected == null) return;
    try {
      await (await _runtime()).rollback(module.id, selected);
      _reload();
    } catch (error) {
      _message('回退失败：$error');
    }
  }

  Future<void> _deleteModule(ModuleInstallation module) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('彻底删除模块'),
        content: Text(
          '将删除 ${module.id} 的版本历史、字段定义和字段值。'
          '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await (await _runtime()).uninstall(module.id, deleteData: true);
      _reload();
    } catch (error) {
      _message('删除失败：$error');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
