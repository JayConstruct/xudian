import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';

import '../modules/app_module.dart';
import '../modules/module_manifest.dart';
import '../ui/ui_composition.dart';
import '../ui/ui_component.dart';
import '../ui/ui_registration.dart';
import '../ui/ui_pack.dart';
import '../ui/ui_pack_providers.dart';
import '../ui/ui_pack_settings_page.dart';
import 'module_host.dart';
import 'module_package.dart';
import 'host_providers.dart';
import 'host_dialogs.dart';
import 'legacy_converter.dart';
import 'module_management_widgets.dart';
import 'module_catalog_page.dart';

class HostManagerModule implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.modulemanager',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );
  @override
  List<UiRegistration> get ui => [
    UiPageRegistration(
      id: 'app.modulemanager.page',
      moduleId: manifest.id,
      title: '模块管理',
      builder: (_, _) => const HostManagerPage(),
    ),
    UiEntryRegistration(
      id: 'modules',
      moduleId: manifest.id,
      pageId: 'app.modulemanager.page',
      label: '模块',
      icon: Icons.extension_outlined,
      opening: UiOpening.detail,
      defaultMount: const UiMount(placement: UiPlacement.more),
    ),
  ];
}

class HostManagerPage extends ConsumerStatefulWidget {
  const HostManagerPage({super.key});
  @override
  ConsumerState<HostManagerPage> createState() => _HostManagerPageState();
}

class _HostManagerPageState extends ConsumerState<HostManagerPage> {
  bool busy = false;
  String category = 'all';
  String? error;

  Map<String, Object?> _manifest(Map<String, Object?> row) =>
      row['definition'] is String
      ? object(object(jsonDecode(row['definition'] as String))['manifest'])
      : const {};

  String _description(Map<String, Object?> row) {
    final value = _manifest(row)['description'] as String?;
    return value == null || value.trim().isEmpty ? '作者未提供说明' : value;
  }

  bool _isUiPackRow(Map<String, Object?> row) =>
      row['package_kind'] == 'uiPack';

  Widget _template(Widget items) => UiComponent(
    ref: 'ui.page.list@1',
    props: const {'title': '模块管理'},
    slots: {'items': items},
    fallback: items,
  );

  Widget _importButton(ModuleHost host) {
    final VoidCallback? press = busy
        ? null
        : () => action(() => importPackage(host));
    return UiComponent(
      ref: 'ui.button@1',
      props: {'label': '导入 .xmodule', 'disabled': busy},
      events: {'press': (_) => press?.call()},
      fallback: FilledButton.icon(
        onPressed: press,
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('导入 .xmodule'),
      ),
    );
  }

  Future<void> action(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importPackage(ModuleHost host) async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '序点模块包',
          extensions: ['xmodule', 'json'],
          mimeTypes: [
            'application/octet-stream',
            'application/zip',
            'application/json',
          ],
        ),
      ],
    );
    if (file == null) return;
    final package = file.name.toLowerCase().endsWith('.json')
        ? await convertLegacyModule(
            object(jsonDecode(await file.readAsString())),
          )
        : await ScriptPackage.verify(
            await file.readAsBytes(),
            allowUnsignedLocal: true,
            publishers: await ref.read(hostPublisherRegistryProvider.future),
          );
    if (!mounted) return;
    await installResolvedModules(context, ref, host, localPackages: [package]);
  }

  Future<void> details(ModuleHost host, String id) async {
    final rows = await host.store.sql(
      'SELECT * FROM host_installations WHERE module_id=?',
      [id],
    );
    if (rows.isEmpty) {
      if (!mounted) return;
      await installResolvedModules(context, ref, host, requests: {id: 'any'});
      return;
    }
    final row = rows.first;
    final package = await host.packageSource(id, row['version'] as String);
    final repository = await host.repositoryFor(id);
    final allDependents = await installedDependentLabels(host, id);
    if (!mounted) return;
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ModuleDetailsDialog(
        package: package,
        repository: repository,
        status: moduleState(row),
        dependents: host.affectedDependents(id),
        allDependents: allDependents,
        onDependency: (dependency) => Navigator.pop(dialogContext, dependency),
      ),
    );
    if (next != null && mounted) await details(host, next);
  }

  Future<void> remove(ModuleHost host, String id) async {
    if (await confirmModuleImpact(
      context,
      title: '卸载模块并保留数据',
      moduleId: id,
      affected: host.affectedDependents(id),
      dataEffect: '保留数据和历史；下次启动不会自动安装',
    )) {
      await host.uninstall(id, cascade: true);
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(moduleHostProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (host) => StreamBuilder<void>(
          stream: host.registryChanges.stream,
          builder: (context, _) => FutureBuilder(
            future: host.store.sql(
              r"SELECT i.*, p.definition, json_extract(p.definition, '$.manifest.kind') AS package_kind FROM host_installations i "
              'LEFT JOIN host_packages p ON p.module_id=i.module_id '
              'AND p.version=i.version ORDER BY i.module_id',
            ),
            builder: (context, snapshot) => _template(
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _importButton(host),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ModuleCatalogPage(host: host),
                                ),
                              ),
                        icon: const Icon(Icons.public),
                        label: const Text('模块商店'),
                      ),
                    ],
                  ),
                  if (busy) const LinearProgressIndicator(),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('界面风格与恢复默认'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UiPackSettingsPage(),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in const {
                        'all': '全部',
                        'business': '业务模块',
                        'ui': 'UI 包',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: category == entry.key,
                          onSelected: (_) =>
                              setState(() => category = entry.key),
                        ),
                    ],
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  for (final row in snapshot.data ?? <Map<String, Object?>>[])
                    if (category == 'all' ||
                        (category == 'ui') == _isUiPackRow(row))
                      Card(
                        child: ModuleSummaryTile(
                          name:
                              _manifest(row)['name'] as String? ??
                              row['module_id'] as String,
                          description: _description(row),
                          version: row['version'] as String,
                          status: moduleState(row),
                          uiPack: _isUiPackRow(row),
                          onTap: busy
                              ? null
                              : () => action(
                                  () =>
                                      details(host, row['module_id'] as String),
                                ),
                          trailing: PopupMenuButton<String>(
                            enabled: !busy,
                            onSelected: (value) => action(() async {
                              final id = row['module_id'] as String;
                              if (value == 'previewUi') {
                                final package = await host.packageSource(
                                  id,
                                  row['version'] as String,
                                );
                                final packs = await ref.read(
                                  uiPackRegistryProvider.future,
                                );
                                if (!context.mounted) return;
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UiPackPreviewPage(
                                      packs: {...packs, id: package.uiPack!},
                                      selection: UiSelection(globalPackId: id),
                                    ),
                                  ),
                                );
                              }
                              if (value == 'source') {
                                final package = await host.packageSource(
                                  id,
                                  row['version'] as String,
                                );
                                if (!context.mounted) return;
                                final input =
                                    await showDialog<Map<String, Object?>>(
                                      context: context,
                                      builder: (_) => HostFormDialog(
                                        title: '模块定义与文件源码',
                                        fields: [
                                          {
                                            'key': 'source',
                                            'label': '编辑私人模块时须修改 version；保存后进行隔离预览和审核',
                                            'type': 'multiline',
                                            'value':
                                                const JsonEncoder.withIndent(
                                                  '  ',
                                                ).convert({
                                                  'definition':
                                                      package.definition,
                                                  'files': {
                                                    for (final file
                                                        in package
                                                            .files
                                                            .entries)
                                                      if (file.key !=
                                                              'package.json' &&
                                                          file.key !=
                                                              'module.json')
                                                        file.key: utf8.decode(
                                                          file.value,
                                                        ),
                                                  },
                                                }),
                                          },
                                        ],
                                      ),
                                    );
                                if (input != null) {
                                  final candidate = object(
                                    jsonDecode(input['source'] as String),
                                  );
                                  if (object(
                                        object(
                                          candidate['definition'],
                                        )['manifest'],
                                      )['id'] !=
                                      id) {
                                    throw StateError('编辑时不能改变模块 ID');
                                  }
                                  await host.editLocalPackage(candidate);
                                }
                              }
                              if (value == 'enable' && context.mounted) {
                                await installResolvedModules(
                                  context,
                                  ref,
                                  host,
                                  requests: {id: 'any'},
                                );
                              }
                              if (value == 'disable') {
                                if (!context.mounted) return;
                                if (await confirmModuleImpact(
                                  context,
                                  title: '停用模块',
                                  moduleId: id,
                                  affected: host.affectedDependents(id),
                                  dataEffect: '模块数据和版本继续保留。',
                                )) {
                                  await host.disable(id, cascade: true);
                                }
                              }
                              if (value == 'remove') await remove(host, id);
                              if (value == 'snapshots') {
                                final snapshots = await host.store.sql(
                                  'SELECT * FROM host_snapshots WHERE module_id=? ORDER BY created_at DESC',
                                  [id],
                                );
                                if (!context.mounted) return;
                                final selected = await showDialog<String>(
                                  context: context,
                                  builder: (context) => SimpleDialog(
                                    title: const Text('数据快照恢复'),
                                    children: [
                                      for (final snapshot in snapshots)
                                        SimpleDialogOption(
                                          onPressed: () => Navigator.pop(
                                            context,
                                            snapshot['id'],
                                          ),
                                          child: Text(
                                            '${snapshot['version']} · 数据 ${snapshot['data_version']}\n${snapshot['created_at']}',
                                          ),
                                        ),
                                      if (snapshots.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Text('没有可恢复快照'),
                                        ),
                                    ],
                                  ),
                                );
                                if (selected != null &&
                                    context.mounted &&
                                    await reviewDialog(
                                      context,
                                      '恢复旧快照；当前数据保留为新快照',
                                      {
                                        'moduleId': id,
                                        'snapshotId': selected,
                                        'effect': '切换版本和数据；快照之后的修改不会自动合并',
                                      },
                                    )) {
                                  await host.recoverSnapshot(id, selected);
                                }
                              }
                              if (value == 'history') {
                                final records = await host.automationHistory(
                                  id,
                                );
                                if (!context.mounted) return;
                                final retry = await showDialog<String>(
                                  context: context,
                                  builder: (context) => SimpleDialog(
                                    title: const Text('规则执行记录'),
                                    children: [
                                      for (final record in records)
                                        SimpleDialogOption(
                                          onPressed:
                                              record['status'] == 'failure'
                                              ? () => Navigator.pop(
                                                  context,
                                                  record['id'],
                                                )
                                              : null,
                                          child: Text(
                                            '${record['rule_id']} · ${record['status']}\n${record['created_at']}\n${record['message'] ?? ''}\n重试来源：${record['retry_of'] ?? '无'}${record['status'] == 'failure' ? '\n点击重试' : ''}',
                                          ),
                                        ),
                                      if (records.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Text('没有执行记录'),
                                        ),
                                    ],
                                  ),
                                );
                                if (retry != null) {
                                  await host.retryHistoricalAutomation(
                                    id,
                                    retry,
                                  );
                                }
                              }
                              if (value == 'erase' &&
                                  context.mounted &&
                                  await confirmModuleImpact(
                                    context,
                                    title: '彻底删除模块数据和历史',
                                    moduleId: id,
                                    affected: host.affectedDependents(id),
                                    dataEffect: '删除此模块的全部数据、版本包、快照、历史和旧迁移记录，并从列表移除；其他模块的数据与旧迁移备份文件保留，无法通过宿主恢复。',
                                  )) {
                                await host.uninstall(
                                  id,
                                  cascade: true,
                                  deleteData: true,
                                );
                              }
                              if (value == 'versions') {
                                final versions = await host.store.sql(
                                  'SELECT version,origin,digest FROM host_packages WHERE module_id=?',
                                  [id],
                                );
                                if (!context.mounted) return;
                                final selected = await showDialog<String>(
                                  context: context,
                                  builder: (context) => SimpleDialog(
                                    title: const Text('版本历史'),
                                    children: [
                                      for (final v in versions)
                                        SimpleDialogOption(
                                          onPressed: () => Navigator.pop(
                                            context,
                                            v['version'],
                                          ),
                                          child: Text(
                                            '${v['version']} · ${v['origin']}\n${v['digest']}',
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                                if (selected != null &&
                                    context.mounted &&
                                    await reviewDialog(
                                      context,
                                      '回退版本并保留当前兼容数据',
                                      {'module': id, 'version': selected},
                                    )) {
                                  await host.rollback(id, selected);
                                }
                              }
                            }),
                            itemBuilder: (_) => [
                              if (_isUiPackRow(row))
                                const PopupMenuItem(
                                  value: 'previewUi',
                                  child: Text('预览 UI 包'),
                                ),
                              const PopupMenuItem(
                                value: 'source',
                                child: Text('模块定义与文件源码'),
                              ),
                              if (row['installed'] == 1)
                                PopupMenuItem(
                                  value: row['enabled'] == 1
                                      ? 'disable'
                                      : 'enable',
                                  child: Text(
                                    row['enabled'] == 1 ? '停用' : '启用',
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'versions',
                                child: Text('版本与回退'),
                              ),
                              const PopupMenuItem(
                                value: 'snapshots',
                                child: Text('数据快照恢复'),
                              ),
                              const PopupMenuItem(
                                value: 'history',
                                child: Text('规则执行记录'),
                              ),
                              const PopupMenuItem(
                                value: 'erase',
                                child: Text('彻底删除数据与历史'),
                              ),
                              if (row['installed'] == 1)
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('卸载（保留数据）'),
                                ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 24),
                  const Text('恢复随客户端发布的模块'),
                  FutureBuilder(
                    future: rootBundle.loadString(
                      'assets/modules/catalog.json',
                    ),
                    builder: (context, snapshot) => Column(
                      children: [
                        if (snapshot.hasData)
                          for (final raw in jsonDecode(snapshot.data!) as List)
                            ListTile(
                              title: Text('${object(raw)['id']}'),
                              trailing: TextButton(
                                onPressed: busy
                                    ? null
                                    : () => action(() async {
                                        final entry = object(raw),
                                            asset = await rootBundle.load(
                                              entry['asset'] as String,
                                            );
                                        final package =
                                            await ScriptPackage.verify(
                                              asset.buffer.asUint8List(
                                                asset.offsetInBytes,
                                                asset.lengthInBytes,
                                              ),
                                              preinstalledDigest:
                                                  entry['sha256'] as String,
                                            );
                                        if (!context.mounted) return;
                                        await installResolvedModules(
                                          context,
                                          ref,
                                          host,
                                          localPackages: [package],
                                        );
                                      }),
                                child: const Text('安装 / 恢复'),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
