import '../ui/tab_content_transition.dart';
import '../../features/settings/settings_widgets.dart';
import '../ui/ui_surfaces.dart' show DetailPage;
import '../ui/ui_icon.dart';
import '../ui/native_ui.dart';
import '../ui/ui_feedback.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import 'module_installation_snapshot.dart';
import 'module_package.dart';
import 'host_providers.dart';
import 'module_history_sheet.dart';
import 'legacy_converter.dart';
import 'module_management_widgets.dart';
import 'module_catalog_page.dart';
import 'module_source_dialog.dart';

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
  ModuleHost? _rowsHost;
  Future<List<Map<String, Object?>>>? _installationRows;
  Stream<void>? _installationChanges;
  Map<String, ScriptPackage> _verifiedDetails = {};
  int _detailsGeneration = 0;
  late final _bundledCatalog = rootBundle
      .loadString('assets/modules/catalog.json')
      .then((text) => (jsonDecode(text) as List).map(object).toList());

  Future<List<Map<String, Object?>>> _readInstallations(ModuleHost host) {
    final future = host.store.sql(
      r"SELECT i.*, json_extract(p.definition, '$.manifest.kind') AS package_kind, "
      r"json_extract(p.definition, '$.manifest.name') AS package_name, "
      r"json_extract(p.definition, '$.manifest.description') AS package_description "
      'FROM host_installations i LEFT JOIN host_packages p '
      'ON p.module_id=i.module_id AND p.version=i.version ORDER BY i.module_id',
    );
    // Registry events can arrive between frames. Observe failures immediately;
    // FutureBuilder still receives the original future and displays its error.
    future.ignore();
    return future;
  }

  Stream<void> _watchInstallations(ModuleHost host) {
    if (!identical(_rowsHost, host)) {
      _detailsGeneration++;
      _verifiedDetails = {};
      _rowsHost = host;
      _installationRows = _readInstallations(host);
      _installationChanges = host.registryChanges.stream.map((_) {
        _installationRows = _readInstallations(host);
      });
    }
    return _installationChanges!;
  }

  String _description(Map<String, Object?> row) {
    final value = row['package_description'] as String?;
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
        icon: const UiIcon(Icons.file_open_outlined),
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
    if (file == null || !mounted) return;
    final ScriptPackage package;
    if (file.name.toLowerCase().endsWith('.json')) {
      package = await convertLegacyModule(
        object(jsonDecode(await file.readAsString())),
      );
    } else {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final publishers = await ref.read(hostPublisherRegistryProvider.future);
      if (!mounted) return;
      package = await ScriptPackage.verify(
        bytes,
        allowUnsignedLocal: true,
        publishers: publishers,
      );
    }
    if (!mounted) return;
    await installResolvedModules(context, ref, host, localPackages: [package]);
  }

  Future<void> restoreBundled(
    ModuleHost host,
    Map<String, Object?> entry,
  ) async {
    final asset = await rootBundle.load(entry['asset'] as String);
    final package = await ScriptPackage.verify(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
      preinstalledDigest: entry['sha256'] as String,
    );
    if (!mounted) return;
    await installResolvedModules(context, ref, host, localPackages: [package]);
  }

  Future<void> details(ModuleHost host, String id) async {
    final generation = ++_detailsGeneration;
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ModuleDetailsLoader(
        title: id,
        load: () async {
          bool isCurrent() =>
              mounted &&
              dialogContext.mounted &&
              ModalRoute.of(dialogContext)?.isCurrent == true &&
              generation == _detailsGeneration &&
              identical(_rowsHost, host) &&
              identical(ref.read(moduleHostProvider).asData?.value, host);
          final current = await readModuleInstallations(
            host,
            verified: _verifiedDetails,
            reuseVerified: true,
            retainedModuleId: id,
            isCurrent: isCurrent,
          );
          if (!dialogContext.mounted || !isCurrent()) {
            throw StateError('模块详情已关闭或宿主已变化');
          }
          _verifiedDetails = {
            for (final entry in current.entries) entry.key: entry.value.package,
          };
          final selected = current[id];
          if (selected == null) {
            Navigator.pop(dialogContext, 'install:$id');
            return const SizedBox.shrink();
          }
          return ModuleDetailsDialog(
            package: selected.package,
            repository: selected.repository,
            status: moduleState(selected.row),
            dependents: host.affectedDependents(id),
            allDependents: [
              for (final entry in current.entries)
                if (entry.key != id &&
                    entry.value.installed &&
                    entry.value.package.dependencies.contains(id))
                  '${entry.key}（${entry.value.enabled ? '已启用' : '已停用'}）',
            ],
            onDependency: (dependency) =>
                Navigator.pop(dialogContext, dependency),
          );
        },
      ),
    );
    if (generation != _detailsGeneration ||
        !mounted ||
        !identical(_rowsHost, host) ||
        !identical(ref.read(moduleHostProvider).asData?.value, host)) {
      return;
    }
    _detailsGeneration++;
    if (next != null) {
      if (next.startsWith('install:')) {
        await installResolvedModules(
          context,
          ref,
          host,
          requests: {next.substring('install:'.length): 'any'},
        );
      } else {
        await details(host, next);
      }
    }
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
        loading: () =>
            const Center(child: NativeUi(child: CircularProgressIndicator())),
        error: (e, _) => UiPackScope(
          defaultOnly: true,
          child: _template(
            Center(
              child: SingleChildScrollView(
                child: AppErrorState(
                  message: '无法加载模块管理：$e',
                  onRetry: () => ref.invalidate(moduleHostProvider),
                ),
              ),
            ),
          ),
        ),
        data: (host) => StreamBuilder<void>(
          stream: _watchInstallations(host),
          builder: (context, _) => FutureBuilder(
            future: _installationRows,
            builder: (context, snapshot) => _template(
              SettingsList(
                children: [
                  SlidingSegments<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('全部')),
                      ButtonSegment(value: 'business', label: Text('业务模块')),
                      ButtonSegment(value: 'ui', label: Text('UI 包')),
                    ],
                    selected: category,
                    onChanged: (value) => setState(() => category = value),
                  ),
                  if (busy) const NativeUi(child: LinearProgressIndicator()),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (snapshot.hasError) ...[
                    Text(
                      '无法读取模块列表：${snapshot.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    NativeUi(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _installationRows = _readInstallations(host);
                        }),
                        child: const Text('重试读取模块列表'),
                      ),
                    ),
                  ],
                  TabContentTransition(
                    index: const ['all', 'business', 'ui'].indexOf(category),
                    child: SettingsGroup(
                      title: '已安装',
                      children: [
                        for (final row
                            in snapshot.data ?? <Map<String, Object?>>[])
                          if (category == 'all' ||
                              (category == 'ui') == _isUiPackRow(row))
                            ModuleSummaryTile(
                              name:
                                  row['package_name'] as String? ??
                                  row['module_id'] as String,
                              description: _description(row),
                              version: row['version'] as String,
                              status: moduleState(row),
                              uiPack: _isUiPackRow(row),
                              onTap: busy
                                  ? null
                                  : () => action(
                                      () => details(
                                        host,
                                        row['module_id'] as String,
                                      ),
                                    ),
                              trailing: _ModuleActions(
                                title:
                                    row['package_name'] as String? ??
                                    row['module_id'] as String,
                                enabled: !busy,
                                onSelected: (value) => action(() async {
                                  final id = row['module_id'] as String;
                                  if (value == 'previewUi') {
                                    final package = await host.packageSource(
                                      id,
                                      row['version'] as String,
                                    );
                                    if (!mounted) return;
                                    final packs = await ref.read(
                                      uiPackRegistryProvider.future,
                                    );
                                    if (!context.mounted) return;
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => UiPackPreviewPage(
                                          packs: {
                                            ...packs,
                                            id: package.uiPack!,
                                          },
                                          selection: UiSelection(
                                            globalPackId: id,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  if (value == 'source') {
                                    if (!context.mounted) return;
                                    final input =
                                        await showDialog<Map<String, Object?>>(
                                          context: context,
                                          builder: (_) => ModuleSourceDialog(
                                            loadDocuments: () async {
                                              final package = await host
                                                  .packageSource(
                                                    id,
                                                    row['version'] as String,
                                                  );
                                              return compute(
                                                prepareModuleSource,
                                                {
                                                  'definition':
                                                      package.definition,
                                                  'files': package.files,
                                                },
                                              );
                                            },
                                          ),
                                        );
                                    if (input != null) {
                                      final candidate = input;
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
                                  final name =
                                      row['package_name'] as String? ?? id;
                                  if (value == 'snapshots' && context.mounted) {
                                    await showModuleSnapshots(
                                      context,
                                      host,
                                      id,
                                      name,
                                    );
                                  }
                                  if (value == 'history' && context.mounted) {
                                    await showModuleRuns(context, host, id);
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
                                  if (value == 'versions' && context.mounted) {
                                    await showModuleVersions(
                                      context,
                                      host,
                                      id,
                                      name,
                                      row['version'] as String,
                                    );
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
                      ],
                    ),
                  ),
                  const SettingsHeading('安装与恢复'),
                  _importButton(host),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsEntry(
                        title: '模块商店',
                        icon: Icons.public,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ModuleCatalogPage(host: host),
                          ),
                        ),
                      ),
                      SettingsEntry(
                        title: '恢复随客户端发布的模块',
                        icon: Icons.restore,
                        enabled: !busy,
                        onTap: () => action(() async {
                          final modules = await _bundledCatalog;
                          if (!context.mounted) return;
                          final selected =
                              await Navigator.push<Map<String, Object?>>(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => DetailPage(
                                    title: '恢复内置模块',
                                    child: SettingsList(
                                      children: [
                                        const SettingsNote('从当前客户端内置的模块包恢复。'),
                                        SettingsGroup(
                                          title: '可恢复的模块',
                                          children: [
                                            for (final raw in modules)
                                              ListTile(
                                                title: Text('${raw['id']}'),
                                                trailing: TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c, raw),
                                                  child: const Text('安装 / 恢复'),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                          if (selected != null && mounted) {
                            await restoreBundled(host, selected);
                          }
                        }),
                      ),
                      SettingsEntry(
                        title: '界面风格与恢复默认',
                        icon: Icons.palette_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UiPackSettingsPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ModuleActions extends StatelessWidget {
  const _ModuleActions({
    required this.title,
    required this.enabled,
    required this.itemBuilder,
    required this.onSelected,
  });
  final String title;
  final bool enabled;
  final List<PopupMenuItem<String>> Function(BuildContext) itemBuilder;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '模块操作',
    icon: const UiIcon(Icons.more_horiz),
    onPressed: !enabled
        ? null
        : () async {
            final selected = await showModalBottomSheet<String>(
              context: context,
              useSafeArea: true,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (c) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(c).height * .8,
                ),
                child: SettingsList(
                  children: [
                    SettingsGroup(
                      title: title,
                      children: [
                        for (final item in itemBuilder(c))
                          ListTile(
                            title: item.child,
                            onTap: () => Navigator.pop(c, item.value),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
            if (selected != null && context.mounted) onSelected(selected);
          },
  );
}
