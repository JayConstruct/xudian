import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../module_catalog/module_catalog.dart';
import 'host_providers.dart';
import 'module_host.dart';
import 'module_management_widgets.dart';
import 'module_package.dart';
import 'script_app_module.dart';
import '../ui/ui_composition.dart';

final moduleCatalogClientProvider = FutureProvider<ModuleCatalogClient>((
  ref,
) async {
  final host = await ref.watch(moduleHostProvider.future);
  final rows = await host.store.sql(
    "SELECT value FROM host_meta WHERE key='module-catalog-repository'",
  );
  final bundled = jsonDecode(
    await rootBundle.loadString('assets/modules/catalog.json'),
  ) as List;
  final client = ModuleCatalogClient(
    cacheDirectory: Directory('${host.directory.path}/catalog-cache'),
    publishers: await ref.watch(hostPublisherRegistryProvider.future),
    preinstalledDigests: {
      for (final raw in bundled)
        object(raw)['id'] as String: object(raw)['sha256'] as String,
    },
    repository: rows.isEmpty
        ? 'JayConstruct/xudian-modules'
        : rows.first['value'] as String,
  );
  ref.onDispose(client.dispose);
  return client;
});

Future<Map<String, InstalledCatalogModule>> _installed(ModuleHost host) async {
  final result = <String, InstalledCatalogModule>{};
  for (final row in await host.store.sql(
    'SELECT * FROM host_installations WHERE installed=1',
  )) {
    final id = row['module_id'] as String;
    result[id] = InstalledCatalogModule(
      await host.packageSource(id, row['version'] as String),
      enabled: row['enabled'] == 1,
      repository: await host.repositoryFor(id),
    );
  }
  return result;
}

Future<void> installResolvedModules(
  BuildContext context,
  WidgetRef ref,
  ModuleHost host, {
  Map<String, String> requests = const {},
  List<ScriptPackage> localPackages = const [],
  bool offline = false,
}) async {
  final client = await ref.read(moduleCatalogClientProvider.future);
  while (context.mounted) {
    final resolution =
        await ModuleDependencyResolver(
          client,
          nativeServices: {
            for (final entry in host.nativeServices.entries)
              entry.key: entry.value.definition['major'] as int,
          },
        ).resolve(
          requests: requests,
          installed: await _installed(host),
          localPackages: localPackages,
          offline: offline,
        );
    if (!context.mounted) return;
    final changes = resolution.ordered
        .where((item) => item.action != ModuleResolutionAction.reuse)
        .toList();
    final reviewedIds = changes.map((item) => item.id).toSet();
    void includeDependencies(String id) {
      final item = resolution.selected[id];
      if (item == null) return;
      for (final raw in item.manifest['dependencies'] as List? ?? []) {
        final dependency = raw is String
            ? raw
            : object(raw)['moduleId'] as String;
        if (reviewedIds.add(dependency)) includeDependencies(dependency);
      }
      for (final raw in item.manifest['serviceDependencies'] as List? ?? []) {
        final dependency = object(raw)['moduleId'] as String;
        if (reviewedIds.add(dependency)) includeDependencies(dependency);
      }
      for (final permission
          in (item.manifest['permissions'] as List? ?? []).cast<String>()) {
        final match = RegExp(r'^services\.(query|command):([^/]+)/')
            .firstMatch(permission);
        if (match != null && reviewedIds.add(match[2]!)) {
          includeDependencies(match[2]!);
        }
      }
    }

    for (final item in changes) {
      includeDependencies(item.id);
    }
    if (changes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('所需模块已经安装并启用')));
      return;
    }
    final packages = await showDialog<List<ScriptPackage>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ModuleDownloadDialog(
        client: client,
        modules: changes,
        offline: offline,
      ),
    );
    if (packages == null || !context.mounted) return;
    final plan = await host.prepareInstallBatch(
      packages,
      repositories: {
        for (final item in changes)
          if (item.repository != null) item.id: item.repository!,
      },
    );
    if (!context.mounted) {
      host.discardInstallBatch(plan);
      return;
    }
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => ModuleBatchReviewDialog(
          modules: resolution.ordered
              .where((item) => reviewedIds.contains(item.id))
              .toList(),
          packages: packages,
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await host.commitInstallBatch(plan);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('模块安装完成'),
            action: _openModuleAction(context, host, {
              ...requests.keys,
              ...localPackages.map((package) => package.id),
            }),
          ),
        );
      }
      return;
    } on StateError catch (error) {
      if (!error.message.toString().contains('Installation state changed')) {
        rethrow;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('安装状态已变化，正在重新解析依赖，请重新确认')));
      }
    } finally {
      host.discardInstallBatch(plan);
    }
  }
}

SnackBarAction? _openModuleAction(
  BuildContext context,
  ModuleHost host,
  Set<String> ids,
) {
  for (final id in ids) {
    final package = host.instances[id]?.package;
    if (package == null) continue;
    final pages = ScriptAppModule(host, package).ui
        .whereType<UiPageRegistration>()
        .where((page) => page.requiredContext.isEmpty);
    if (pages.isEmpty) continue;
    return SnackBarAction(
      label: '打开模块',
      onPressed: () {
        final current = host.instances[id]?.package;
        if (current == null || !context.mounted) return;
        final page = ScriptAppModule(host, current).ui
            .whereType<UiPageRegistration>()
            .where((page) => page.requiredContext.isEmpty)
            .firstOrNull;
        if (page == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text(page.title)),
              body: page.builder(context, const PageContext()),
            ),
          ),
        );
      },
    );
  }
  return null;
}

class ModuleDownloadDialog extends StatefulWidget {
  const ModuleDownloadDialog({
    super.key,
    required this.client,
    required this.modules,
    this.offline = false,
  });
  final ModuleCatalogClient client;
  final List<ResolvedCatalogModule> modules;
  final bool offline;
  @override
  State<ModuleDownloadDialog> createState() => _ModuleDownloadDialogState();
}

class _ModuleDownloadDialogState extends State<ModuleDownloadDialog> {
  DownloadCancellation cancellation = DownloadCancellation();
  final packages = <ScriptPackage>[];
  String? failure, current;
  int received = 0, total = 0;
  bool running = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(download);
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  Future<void> download() async {
    if (!mounted) return;
    setState(() {
      running = true;
      failure = null;
      cancellation = DownloadCancellation();
    });
    try {
      for (final item in widget.modules.skip(packages.length)) {
        if (!mounted) return;
        setState(() {
          current = item.name;
          received = 0;
          total = 0;
        });
        packages.add(
          await item.loadPackage(
            widget.client,
            cancellation: cancellation,
            offline: widget.offline,
            onProgress: (count, size) {
              if (mounted) {
                setState(() {
                  received = count;
                  total = size;
                });
              }
            },
          ),
        );
      }
      if (mounted) Navigator.pop(context, packages);
    } catch (error) {
      if (mounted) {
        setState(() {
          failure = '$error';
          running = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !running,
    child: AlertDialog(
      title: const Text('下载并验证模块'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('全部模块包验证完成后，将统一确认安装和权限。'),
              for (final item in widget.modules)
                ModuleSummaryTile(
                  name: item.name,
                  description: item.description,
                  version: item.version,
                  status: item.repository ?? '本地模块包',
                ),
              for (final item in widget.modules)
                if (item.release != null)
                  SelectableText('下载来源：${item.release!.url}'),
              Text(
                '${packages.length}/${widget.modules.length} · ${current ?? ''}',
              ),
              if (running)
                LinearProgressIndicator(
                  value: total > 0 ? received / total : null,
                ),
              if (total > 0) Text('$received / $total 字节'),
              if (failure != null)
                SelectableText(
                  failure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            cancellation.cancel();
            Navigator.pop(context);
          },
          child: const Text('取消下载'),
        ),
        if (!running)
          FilledButton(onPressed: download, child: const Text('重试')),
      ],
    ),
  );
}

class ModuleBatchReviewDialog extends StatelessWidget {
  const ModuleBatchReviewDialog({
    super.key,
    required this.modules,
    required this.packages,
  });
  final List<ResolvedCatalogModule> modules;
  final List<ScriptPackage> packages;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认模块安装计划'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('按依赖顺序统一执行；失败时恢复原版本、数据和启用状态。'),
            for (final item in modules) ...[
              const SizedBox(height: 16),
              Text(
                '${item.name} · ${item.version}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(item.description),
              Text(
                '操作：${switch (item.action) {
                  ModuleResolutionAction.install => '安装并启用',
                  ModuleResolutionAction.upgrade => '升级并启用',
                  ModuleResolutionAction.enable => '启用',
                  ModuleResolutionAction.reuse => '复用',
                }}',
              ),
              SelectableText('来源：${item.repository ?? '本地模块包'}'),
              Text(
                '新增权限：${item.addedPermissions.isEmpty ? '无' : item.addedPermissions.join('、')}',
              ),
              for (final package in packages.where(
                (package) => package.id == item.id,
              )) ...[
                Text(
                  '全部权限：${package.permissions.isEmpty ? '无' : package.permissions.join('、')}',
                ),
                if (package.release['channel'] != 'market')
                  const Text('未签名包；摘要验证不代表发布者签名'),
                SelectableText('SHA-256：${package.packageDigest}'),
              ],
            ],
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
        child: const Text('确认安装'),
      ),
    ],
  );
}

class ModuleCatalogPage extends ConsumerStatefulWidget {
  const ModuleCatalogPage({super.key, required this.host});
  final ModuleHost host;
  @override
  ConsumerState<ModuleCatalogPage> createState() => _ModuleCatalogPageState();
}

class _ModuleCatalogPageState extends ConsumerState<ModuleCatalogPage> {
  ModuleCatalog? catalog;
  final indexes = <String, Future<ModuleVersionIndex>>{};
  Map<String, InstalledCatalogModule> installations = {};
  String? failure, repository;
  bool loading = false, busy = false, offline = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<ModuleVersionIndex> indexFor(CatalogModule item) =>
      indexes.putIfAbsent(
        item.id,
        () async =>
            (await ref.read(moduleCatalogClientProvider.future))
                .loadIndex(item, offline: offline),
      );

  Future<void> load() async {
    indexes.clear();
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final client = await ref.read(moduleCatalogClientProvider.future);
      final result = await client.loadCatalog(offline: offline);
      final current = await _installed(widget.host);
      if (mounted) {
        setState(() {
          catalog = result;
          repository = client.repository;
          installations = current;
          if (client.loadedFromCache) offline = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => failure = '$error');
      if (!offline) {
        try {
          final client = await ref.read(moduleCatalogClientProvider.future);
          final cached = await client.loadCatalog(offline: true);
          if (mounted) {
            setState(() {
              catalog = cached;
              repository = client.repository;
              offline = true;
            });
          }
        } catch (_) {
          /* The original network error remains visible. */
        }
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> configure() async {
    final controller = TextEditingController(
      text: repository ?? 'JayConstruct/xudian-modules',
    );
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('模块目录仓库'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'GitHub 仓库（作者/仓库）'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || !mounted) return;
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(next)) {
      setState(() => failure = '仓库格式应为 作者/仓库');
      return;
    }
    await widget.host.store.db.customStatement(
      "INSERT OR REPLACE INTO host_meta(key,value) VALUES('module-catalog-repository',?)",
      [next],
    );
    ref.invalidate(moduleCatalogClientProvider);
    setState(() {
      catalog = null;
      offline = false;
      repository = next;
    });
    await load();
  }

  Future<void> install(String id) async {
    setState(() => busy = true);
    try {
      await installResolvedModules(
        context,
        ref,
        widget.host,
        requests: {id: 'any'},
        offline: offline,
      );
      final current = await _installed(widget.host);
      if (mounted) {
        setState(() {
          failure = null;
          installations = current;
        });
      }
    } catch (error) {
      if (mounted) setState(() => failure = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> details(String id) async {
    setState(() => busy = true);
    try {
      final installations = await _installed(widget.host);
      final installed = installations[id];
      if (installed != null) {
        if (!mounted) return;
        final next = await showDialog<String>(
          context: context,
          builder: (dialogContext) => ModuleDetailsDialog(
            package: installed.package,
            repository: installed.repository,
            status: installed.enabled ? '已启用' : '已停用',
            dependents: widget.host.affectedDependents(id),
            allDependents: [
              for (final entry in installations.entries)
                if (entry.value.package.dependencies.contains(id))
                  '${entry.key}（${entry.value.enabled ? '已启用' : '已停用'}）',
            ],
            onDependency: (dependency) =>
                Navigator.pop(dialogContext, dependency),
          ),
        );
        if (next != null && mounted) await details(next);
        return;
      }
      final item = catalog?.modules[id];
      if (item == null) throw StateError('目录未收录模块：$id');
      final client = await ref.read(moduleCatalogClientProvider.future);
      final index = await client.loadIndex(item, offline: offline);
      final versions = index.versions
          .where(
            (version) =>
                !Version.parse(version.version).isPreRelease &&
                VersionConstraint.parse(version.manifest['hostApi'] as String)
                    .allows(Version(1, 8, 0)),
          )
          .toList();
      if (versions.isEmpty) throw StateError('没有兼容当前宿主的稳定版本：$id');
      final version = versions.first;
      if (!mounted) return;
      final next = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(item.name),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.description),
                  const SizedBox(height: 12),
                  SelectableText('模块 ID：${item.id}'),
                  Text('版本：${version.version} · 可安装'),
                  Text('作者：${item.author.isEmpty ? '作者未提供' : item.author}'),
                  SelectableText('发布仓库：${item.repository}'),
                  SelectableText('下载来源：${version.url}'),
                  Text('宿主兼容性：${version.manifest['hostApi']}'),
                  Text(
                    '权限：${(version.manifest['permissions'] as List? ?? []).join('、')}',
                  ),
                  const Text('模块依赖（点击查看）'),
                  for (final raw
                      in version.manifest['dependencies'] as List? ?? [])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        raw is String ? raw : '${object(raw)['moduleId']}',
                      ),
                      subtitle: Text(
                        raw is String ? '任意兼容版本' : '${object(raw)['version']}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(
                        dialogContext,
                        raw is String ? raw : object(raw)['moduleId'],
                      ),
                    ),
                  const Text('服务依赖（点击查看）'),
                  for (final raw in manifestServiceRequirements(
                    version.manifest,
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${object(raw)['moduleId']}'),
                      subtitle: Text(
                        '${object(raw)['serviceId']} @ ${object(raw)['majorVersion']} ${object(raw)['kind'] ?? ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: object(raw)['moduleId'] == 'app.host'
                          ? () => showHostService(dialogContext, raw)
                          : () => Navigator.pop(
                              dialogContext,
                              object(raw)['moduleId'],
                            ),
                    ),
                  Text(
                    '历史版本：${index.versions.map((entry) => entry.version).join('、')}',
                  ),
                  const SizedBox(height: 12),
                  const Text('安装前验证摘要、身份与包格式，并展示签名状态和完整依赖计划。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'install:$id'),
              child: const Text('解析依赖并安装'),
            ),
          ],
        ),
      );
      if (next != null && mounted) {
        if (next.startsWith('install:')) {
          await install(next.substring('install:'.length));
        } else {
          await details(next);
        }
      }
    } catch (error) {
      if (mounted) setState(() => failure = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('在线模块目录')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: loading || busy ? null : configure,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('修改目录仓库'),
            ),
            OutlinedButton.icon(
              onPressed: loading || busy ? null : load,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新 / 重试'),
            ),
          ],
        ),
        if (repository != null) SelectableText('目录：$repository'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('离线浏览缓存'),
          value: offline,
          onChanged: loading || busy
              ? null
              : (value) {
                  setState(() => offline = value);
                  load();
                },
        ),
        if (loading || busy) const LinearProgressIndicator(),
        if (failure != null)
          SelectableText(
            failure!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (catalog != null && catalog!.modules.isEmpty) const Text('目录中没有模块'),
        for (final item in catalog?.modules.values ?? <CatalogModule>[])
          Card(
            child: FutureBuilder<ModuleVersionIndex>(
              future: indexFor(item),
              builder: (context, snapshot) {
                final installed = installations[item.id];
                final latest = snapshot.data?.versions
                    .where(
                      (version) => !Version.parse(version.version).isPreRelease,
                    )
                    .firstOrNull;
                return ModuleSummaryTile(
                  name: item.name,
                  description: item.description,
                  version:
                      installed?.package.version ?? latest?.version ?? '版本待加载',
                  status: installed != null
                      ? (installed.enabled ? '已启用' : '已停用')
                      : snapshot.hasError
                      ? '版本索引不可用'
                      : offline
                      ? '缓存目录'
                      : '可安装',
                  onTap: busy ? null : () => details(item.id),
                  trailing: IconButton(
                    tooltip: '解析依赖并安装',
                    onPressed: busy ? null : () => install(item.id),
                    icon: const Icon(Icons.download_outlined),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 16),
        const Text('选择模块后解析完整依赖链。离线模式只安装已完整缓存的模块包。'),
      ],
    ),
  );
}
