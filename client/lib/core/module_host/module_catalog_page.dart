import '../ui/ui_icon.dart';
import '../ui/native_ui.dart';
import '../ui/ui_design.dart';
import '../../app/app_toast.dart';

import 'dart:async';
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
import 'module_catalog_widgets.dart';
import 'module_package.dart';
import 'script_app_module.dart';
import '../ui/ui_composition.dart';
import 'host_api.dart';
import 'script_detail_page.dart';
import 'bundled_module_retirement.dart';
import 'module_install_review_dialog.dart';

export 'module_install_review_dialog.dart';

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
    excludedModuleIds: await ref.watch(retiredBundledModuleIdsProvider.future),
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

Future<Map<String, InstalledCatalogModule>> _installed(
  ModuleHost host, {
  Map<String, InstalledCatalogModule> verified = const {},
  bool reuseVerified = false,
}) async {
  final result = <String, InstalledCatalogModule>{};
  final rows = await host.store.sql("""
    SELECT installations.module_id, installations.version, installations.enabled,
           packages.digest, packages.origin, repositories.value AS repository
    FROM host_installations AS installations
    LEFT JOIN host_packages AS packages
      ON packages.module_id=installations.module_id
      AND packages.version=installations.version
    LEFT JOIN host_meta AS repositories
      ON repositories.key='module-repository:' || installations.module_id
    WHERE installations.installed=1
  """);
  for (final row in rows) {
    final id = row['module_id'] as String;
    final version = row['version'] as String;
    // Both candidates have already passed full verification. Match immutable
    // persisted identity and provenance before reusing either in-memory object.
    final candidates = reuseVerified
        ? [host.instances[id]?.package, verified[id]?.package]
        : const <ScriptPackage?>[];
    final package = candidates
        .whereType<ScriptPackage>()
        .where(
          (candidate) =>
              candidate.id == id &&
              candidate.version == version &&
              candidate.packageDigest == row['digest'] &&
              candidate.origin == row['origin'],
        )
        .firstOrNull;
    result[id] = InstalledCatalogModule(
      package ?? await host.packageSource(id, version),
      enabled: row['enabled'] == 1,
      repository: row['repository'] as String?,
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
    final reviewedIds = {
      ...changes.map((item) => item.id),
      ...requests.keys,
      ...localPackages.map((package) => package.id),
    };
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
        if (optionalServicePermissions(item.manifest).contains(permission)) {
          continue;
        }
        final match = RegExp(r'^services\.(query|command):([^/]+)/')
            .firstMatch(permission);
        if (match != null && reviewedIds.add(match[2]!)) {
          includeDependencies(match[2]!);
        }
      }
    }

    for (final id in reviewedIds.toList()) {
      includeDependencies(id);
    }
    if (changes.isEmpty) {
      AppToast.show(context, message: '所需模块已经安装并启用', kind: 'info');
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
          requestedIds: {...requests.keys, ...localPackages.map((p) => p.id)},
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await host.commitInstallBatch(plan);
      if (context.mounted) {
        AppToast.show(
          context,
          message: '模块安装完成，共 ${changes.length} 个',
          kind: 'success',
        );
      }
      return;
    } on StateError catch (error) {
      if (!error.message.toString().contains('Installation state changed')) {
        rethrow;
      }
      if (context.mounted) {
        AppToast.show(context, message: '安装状态已变化，正在重新解析依赖，请重新确认', kind: 'info');
      }
    } finally {
      host.discardInstallBatch(plan);
    }
  }
}

UiPageRegistration? _moduleEntry(ModuleHost host, String id) {
  final package = host.instances[id]?.package;
  if (package == null) return null;
  return ScriptAppModule(host, package).ui
      .whereType<UiPageRegistration>()
      .where((page) => page.requiredContext.isEmpty)
      .firstOrNull;
}

void _openModule(BuildContext context, ModuleHost host, String id) {
  final page = _moduleEntry(host, id);
  if (page == null || !context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) =>
          ScriptDetailPage(host: host, pageId: page.id, title: page.title),
    ),
  );
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
  String? failure;
  ResolvedCatalogModule? current;
  ModuleDownloadStage stage = ModuleDownloadStage.preparing;
  int received = 0, total = 0;
  bool running = true;
  bool attemptActive = false;

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
    if (!mounted || attemptActive) return;
    attemptActive = true;
    final token = DownloadCancellation();
    setState(() {
      running = true;
      failure = null;
      cancellation = token;
    });
    try {
      for (final item in widget.modules.skip(packages.length)) {
        if (!mounted || token.isCancelled) return;
        setState(() {
          current = item;
          stage = ModuleDownloadStage.preparing;
          received = 0;
          total = item.release?.size ?? 0;
        });
        final package = await item.loadPackage(
          widget.client,
          cancellation: token,
          offline: widget.offline,
          onStage: (value) {
            if (mounted && !token.isCancelled) {
              setState(() => stage = value);
            }
          },
          onProgress: (count, size) {
            if (mounted && !token.isCancelled) {
              setState(() {
                received = count;
                total = size;
              });
            }
          },
        );
        if (!mounted || token.isCancelled) return;
        setState(() => packages.add(package));
      }
      if (mounted && !token.isCancelled) Navigator.pop(context, packages);
    } catch (error) {
      if (mounted && !token.isCancelled) {
        setState(() {
          failure =
              error is SocketException &&
                  error.message.contains('Failed host lookup')
              ? '无法解析下载服务器地址，请检查网络或 DNS 后重试。\n$error'
              : '$error';
          running = false;
        });
      }
    } finally {
      attemptActive = false;
    }
  }

  String get stageLabel => switch (stage) {
    ModuleDownloadStage.preparing => '准备下载',
    ModuleDownloadStage.downloading => '下载中',
    ModuleDownloadStage.retrying => '网络连接失败，正在等待自动重试…',
    ModuleDownloadStage.verifying => '校验中',
    ModuleDownloadStage.saving => '保存已验证模块',
    ModuleDownloadStage.ready => '准备安装',
  };

  // This measures package bytes, not verification or the install transaction.
  double? get overallProgress {
    if (widget.modules.isEmpty ||
        widget.modules.any((item) => (item.release?.size ?? 0) <= 0)) {
      return null;
    }
    final size = widget.modules.fold<int>(
      0,
      (sum, item) => sum + item.release!.size,
    );
    final complete = widget.modules
        .take(packages.length)
        .fold<int>(0, (sum, item) => sum + item.release!.size);
    return ((complete +
                (packages.length < widget.modules.length ? received : 0)) /
            size)
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !running,
    child: NativeUi(
      child: AlertDialog(
        titlePadding: AppDesign.dialogTitlePadding,
        contentPadding: AppDesign.dialogContentPadding,
        actionsPadding: AppDesign.dialogActionsPadding,
        title: const Text('下载并验证模块'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failure == null ? stageLabel : '下载或校验失败',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (current != null) Text(current!.name),
                const SizedBox(height: 8),
                if (running)
                  NativeUi(
                    child: LinearProgressIndicator(
                      value:
                          stage == ModuleDownloadStage.downloading && total > 0
                          ? (received / total).clamp(0.0, 1.0)
                          : null,
                      semanticsLabel: '当前模块：$stageLabel',
                    ),
                  ),
                const SizedBox(height: 8),
                if (stage == ModuleDownloadStage.downloading || failure != null)
                  Text(
                    total > 0
                        ? '${_readableBytes(received)} / ${_readableBytes(total)}'
                        : '已下载 ${_readableBytes(received)}',
                  ),
                Text('已完成 ${packages.length}/${widget.modules.length} 个模块'),
                if (overallProgress case final progress?) ...[
                  const SizedBox(height: 8),
                  Text('整体下载进度 ${(progress * 100).floor()}%'),
                  NativeUi(
                    child: LinearProgressIndicator(
                      value: progress,
                      semanticsLabel: '整体下载进度',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('全部模块包验证完成后，将统一确认安装和权限。'),
                if (failure != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    failure!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const Text('已完成的模块会保留，重试将从当前模块继续。'),
                ],
                NativeUi(
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('模块与下载来源'),
                    children: [
                      for (final item in widget.modules)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item.name} · ${item.version}'),
                              Text(item.description),
                              SelectableText(
                                item.release?.url.toString() ?? '本地已验证模块包',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          NativeUi(
            child: TextButton(
              onPressed: () {
                cancellation.cancel();
                Navigator.pop(context);
              },
              child: Text(running ? '取消下载' : '关闭'),
            ),
          ),
          if (!running)
            NativeUi(
              child: FilledButton(onPressed: download, child: const Text('重试')),
            ),
        ],
      ),
    ),
  );
}

String _readableBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class ModuleCatalogPage extends ConsumerStatefulWidget {
  const ModuleCatalogPage({super.key, required this.host});
  final ModuleHost host;
  @override
  ConsumerState<ModuleCatalogPage> createState() => _ModuleCatalogPageState();
}

class _ModuleCatalogPageState extends ConsumerState<ModuleCatalogPage> {
  ModuleCatalog? catalog;
  final indexes =
      <
        ({
          String id,
          String repository,
          Uri indexUrl,
          bool offline,
          int generation,
        }),
        Future<ModuleVersionIndex>
      >{};
  final loadedIndexes = <String, ModuleVersionIndex>{};
  final indexFailures = <String, String>{};
  final latestVersions = <String, CatalogVersion>{};
  bool indexRebuildScheduled = false;
  final searchController = TextEditingController();
  String category = '全部分类', filter = '全部';
  int loadGeneration = 0;
  Map<String, InstalledCatalogModule> installations = {};
  String? failure, repository;
  bool loading = true, busy = false, offline = false;
  @override
  void initState() {
    super.initState();
    // Let the first frame paint the responsive shell before starting I/O.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(load());
    });
  }

  @override
  void dispose() {
    loadGeneration++;
    searchController.dispose();
    super.dispose();
  }

  Future<ModuleVersionIndex> indexFor(CatalogModule item) {
    final key = (
      id: item.id,
      repository: item.repository,
      indexUrl: item.indexUrl,
      offline: offline,
      generation: loadGeneration,
    );
    return indexes.putIfAbsent(
      key,
      () async =>
          (await ref.read(moduleCatalogClientProvider.future))
              .loadIndex(item, offline: key.offline),
    );
  }

  bool _isCurrentIndex(CatalogModule item, int generation) =>
      mounted &&
      generation == loadGeneration &&
      identical(catalog?.modules[item.id], item);

  void _scheduleIndexRebuild() {
    if (indexRebuildScheduled) return;
    indexRebuildScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      indexRebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> loadIndexes(ModuleCatalog result, int generation) async {
    final pending = result.modules.values.iterator;
    Future<void> worker() async {
      while (mounted && generation == loadGeneration && pending.moveNext()) {
        final item = pending.current;
        try {
          final index = await indexFor(item);
          if (!_isCurrentIndex(item, generation)) return;
          loadedIndexes[item.id] = index;
          final latest = index.versions
              .where(
                (version) =>
                    !Version.parse(version.version).isPreRelease &&
                    VersionConstraint.parse(
                      version.manifest['hostApi'] as String,
                    ).allows(hostApiVersion),
              )
              .firstOrNull;
          if (latest != null) latestVersions[item.id] = latest;
        } catch (error) {
          if (!_isCurrentIndex(item, generation)) return;
          indexFailures[item.id] = '$error';
        }
        // Coalesce indexes completing together into one update per frame.
        _scheduleIndexRebuild();
      }
    }

    // Bound concurrent network/parse/cache work instead of starting every
    // module at once. Opening a detail still shares its in-flight index.
    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
  }

  Future<void> load() async {
    if (!mounted) return;
    final generation = ++loadGeneration;
    indexes.clear();
    loadedIndexes.clear();
    indexFailures.clear();
    latestVersions.clear();
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final results = await Future.wait<Object>([
        _installed(widget.host, verified: installations, reuseVerified: true),
        () async {
          final client = await ref.read(moduleCatalogClientProvider.future);
          return (client, await client.loadCatalog(offline: offline));
        }(),
      ]);
      final current = results[0] as Map<String, InstalledCatalogModule>;
      final (client, result) =
          results[1] as (ModuleCatalogClient, ModuleCatalog);
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        catalog = result;
        repository = client.repository;
        installations = current;
        if (client.loadedFromCache) offline = true;
        if (!result.modules.values.any((item) => item.category == category)) {
          category = '全部分类';
        }
      });
      await loadIndexes(result, generation);
    } catch (error) {
      if (!mounted || generation != loadGeneration) return;
      setState(() => failure = '$error');
      if (!offline) {
        try {
          final client = await ref.read(moduleCatalogClientProvider.future);
          final cached = await client.loadCatalog(offline: true);
          final current = await _installed(
            widget.host,
            verified: installations,
            reuseVerified: true,
          );
          if (!mounted || generation != loadGeneration) return;
          setState(() {
            catalog = cached;
            repository = client.repository;
            installations = current;
            offline = true;
          });
          await loadIndexes(cached, generation);
        } catch (_) {
          // The original network error remains visible.
        }
      }
    } finally {
      if (mounted && generation == loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> configure() async {
    final controller = TextEditingController(
      text: repository ?? 'JayConstruct/xudian-modules',
    );
    final next = await showDialog<String>(
      context: context,
      builder: (context) => NativeUi(
        child: AlertDialog(
          title: const Text('模块目录仓库'),
          titlePadding: AppDesign.dialogTitlePadding,
          contentPadding: AppDesign.dialogContentPadding,
          actionsPadding: AppDesign.dialogActionsPadding,
          content: NativeUi(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'GitHub 仓库（作者/仓库）'),
            ),
          ),
          actions: [
            NativeUi(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
            NativeUi(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
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
    if (!mounted) return;
    ref.invalidate(moduleCatalogClientProvider);
    setState(() {
      catalog = null;
      offline = false;
      repository = next;
    });
    await load();
  }

  Future<void> install(String id, {String? version}) async {
    setState(() => busy = true);
    try {
      await installResolvedModules(
        context,
        ref,
        widget.host,
        requests: {id: version ?? 'any'},
        offline: offline,
      );
      final current = await _installed(
        widget.host,
        verified: installations,
        reuseVerified: true,
      );
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
      final next = await showDialog<String>(
        context: context,
        builder: (dialogContext) => _CatalogDetailsLoader(
          title: catalog?.modules[id]?.name ?? id,
          load: () => _detailsContent(id, dialogContext),
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

  Future<Widget> _detailsContent(String id, BuildContext dialogContext) async {
    final current = await _installed(
      widget.host,
      verified: installations,
      reuseVerified: true,
    );
    if (!mounted) throw StateError('模块商店已关闭');
    installations = current;
    final installed = current[id];
    if (installed != null) {
      return ModuleDetailsDialog(
        package: installed.package,
        repository: installed.repository,
        status: installed.enabled ? '已启用' : '已停用',
        dependents: widget.host.affectedDependents(id),
        allDependents: [
          for (final entry in current.entries)
            if (entry.value.package.dependencies.contains(id))
              '${entry.key}（${entry.value.enabled ? '已启用' : '已停用'}）',
        ],
        onDependency: (dependency) => Navigator.pop(dialogContext, dependency),
      );
    }
    final item = catalog?.modules[id];
    if (item == null) throw StateError('目录未收录模块：$id');
    final index = await indexFor(item);
    final versions = index.versions
        .where(
          (version) =>
              !Version.parse(version.version).isPreRelease &&
              VersionConstraint.parse(version.manifest['hostApi'] as String)
                  .allows(hostApiVersion),
        )
        .toList();
    if (versions.isEmpty) throw StateError('没有兼容当前宿主的稳定版本：$id');
    final version = versions.first;
    if (!mounted) throw StateError('模块商店已关闭');
    return NativeUi(
      child: AlertDialog(
        title: Text(item.name),
        titlePadding: AppDesign.dialogTitlePadding,
        contentPadding: AppDesign.dialogContentPadding,
        actionsPadding: AppDesign.dialogActionsPadding,
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
                      onTap: () => Navigator.pop(
                        dialogContext,
                        raw is String ? raw : object(raw)['moduleId'],
                      ),
                    ),
                  ),
                const Text('服务依赖（点击查看）'),
                for (final raw in manifestServiceRequirements(version.manifest))
                  NativeUi(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${object(raw)['moduleId']}'),
                      subtitle: Text(
                        '${object(raw)['serviceId']} @ ${object(raw)['majorVersion']} ${object(raw)['kind'] ?? ''}',
                      ),
                      trailing: const UiIcon(Icons.chevron_right),
                      onTap: object(raw)['moduleId'] == 'app.host'
                          ? () => showHostService(dialogContext, raw)
                          : () => Navigator.pop(
                              dialogContext,
                              object(raw)['moduleId'],
                            ),
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
          NativeUi(
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ),
          NativeUi(
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'install:$id'),
              child: const Text('解析依赖并安装'),
            ),
          ),
        ],
      ),
    );
  }

  CatalogVersion? latestCompatible(CatalogModule item) =>
      latestVersions[item.id];

  bool canUpdate(CatalogModule item) {
    final installed = installations[item.id];
    final latest = latestCompatible(item);
    return installed != null &&
        latest != null &&
        Version.parse(latest.version) >
            Version.parse(installed.package.version);
  }

  bool matches(CatalogModule item) {
    final query = searchController.text.trim().toLowerCase();
    if (query.isNotEmpty &&
        ![
          item.name,
          item.description,
          item.author,
          item.id,
          item.repository,
        ].any((value) => value.toLowerCase().contains(query))) {
      return false;
    }
    if (category != '全部分类' && item.category != category) return false;
    final installed = installations.containsKey(item.id);
    return switch (filter) {
      '推荐' => item.featured,
      '已安装' => installed,
      '未安装' => !installed,
      '可更新' => canUpdate(item),
      _ => true,
    };
  }

  void clearFilters() {
    setState(() {
      searchController.clear();
      category = '全部分类';
      filter = '全部';
    });
  }

  Widget moduleCard(CatalogModule item) {
    final installed = installations[item.id];
    final latest = latestCompatible(item);
    final hasIndex = loadedIndexes.containsKey(item.id);
    final unavailable = indexFailures.containsKey(item.id);
    final update = canUpdate(item);
    final enableExisting = installed != null && !installed.enabled;
    final entry = _moduleEntry(widget.host, item.id);
    final action = enableExisting
        ? '启用'
        : update
        ? '更新'
        : installed == null
        ? '安装'
        : entry != null
        ? '打开模块'
        : '已安装';
    final status = installed != null
        ? '${installed.enabled ? '已启用' : '已停用'}${update ? ' · 可更新' : ''}'
        : unavailable
        ? '版本索引不可用'
        : !hasIndex
        ? '正在读取版本'
        : latest == null
        ? '没有兼容当前宿主的稳定版本'
        : '可安装';
    final version = installed == null
        ? latest?.version ?? '版本待加载'
        : update
        ? '${installed.package.version} → ${latest!.version}'
        : installed.package.version;
    final actionable =
        !busy &&
        (enableExisting ||
            (!unavailable && latest != null && (installed == null || update)));
    return ModuleCatalogCard(
      name: item.name,
      description: item.description,
      status: status,
      version: version,
      featured: item.featured,
      action: action,
      onDetails: busy ? null : () => details(item.id),
      onAction: action == '打开模块'
          ? (busy ? null : () => _openModule(context, widget.host, item.id))
          : actionable
          ? () => install(
              item.id,
              version: action == '更新' ? '>${installed!.package.version}' : null,
            )
          : null,
      unavailableHint: unavailable
          ? '请刷新重试，或在商店设置中检查目录仓库。'
          : hasIndex && latest == null
          ? '请等待兼容当前宿主的稳定版本。'
          : null,
      secondaryActions: [
        if (entry != null && action != '打开模块')
          NativeUi(
            child: TextButton(
              onPressed: busy
                  ? null
                  : () => _openModule(context, widget.host, item.id),
              child: const Text('打开模块'),
            ),
          ),
        if (enableExisting && update)
          NativeUi(
            child: TextButton(
              onPressed: busy
                  ? null
                  : () => install(
                      item.id,
                      version: '>${installed.package.version}',
                    ),
              child: const Text('更新'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final modules =
        (catalog?.modules.values ?? <CatalogModule>[]).where(matches).toList()
          ..sort((a, b) {
            final recommended = (b.featured ? 1 : 0).compareTo(
              a.featured ? 1 : 0,
            );
            return recommended != 0 ? recommended : a.name.compareTo(b.name);
          });
    final categories =
        (catalog?.modules.values.map((item) => item.category).toSet() ??
                <String>{})
            .toList()
          ..sort();
    return NativeUi(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('模块商店'),
          actions: [
            NativeUi(
              child: IconButton(
                tooltip: '刷新 / 重试',
                onPressed: loading || busy ? null : load,
                icon: const UiIcon(Icons.refresh),
              ),
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NativeUi(
                      child: TextField(
                        controller: searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索名称、作用、作者或模块 ID',
                          prefixIcon: const UiIcon(Icons.search),
                          suffixIcon: searchController.text.isEmpty
                              ? null
                              : NativeUi(
                                  child: IconButton(
                                    tooltip: '清空搜索',
                                    onPressed: () => setState(
                                      () => searchController.clear(),
                                    ),
                                    icon: const UiIcon(Icons.close),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ModuleCatalogFilters(
                      status: filter,
                      category: category,
                      categories: categories,
                      onStatusChanged: (value) =>
                          setState(() => filter = value),
                      onCategoryChanged: (value) =>
                          setState(() => category = value),
                    ),
                    if (offline) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: ShapeDecoration(
                          color: colors.surfaceContainerHighest,
                          shape: AppDesign.smoothShape(
                            radius: AppDesign.compactRadius,
                          ),
                        ),
                        child: const Text('正在浏览缓存。离线安装需要全部模块包已缓存；可在商店设置中恢复联网。'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (loading || busy)
                      const NativeUi(child: LinearProgressIndicator()),
                    if (failure != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        failure!,
                        style: TextStyle(color: colors.error),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: NativeUi(
                          child: TextButton.icon(
                            onPressed: loading || busy ? null : load,
                            icon: const UiIcon(Icons.refresh),
                            label: const Text('刷新 / 重试'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '找到 ${modules.length} 个模块 · 目录共 ${catalog?.modules.length ?? 0} 个',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    if (catalog != null && catalog!.modules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('目录中没有模块，请在商店设置中检查目录仓库。'),
                      )
                    else if (catalog != null && modules.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loading && filter == '可更新'
                                  ? '正在检查模块版本…'
                                  : '没有符合筛选条件的模块',
                            ),
                            const SizedBox(height: 8),
                            const Text('试试其他关键词、分类或安装状态。'),
                            NativeUi(
                              child: TextButton(
                                onPressed: clearFilters,
                                child: const Text('清除筛选'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: ModuleCatalogSliverGrid(
                itemCount: modules.length,
                itemBuilder: (context, index) => moduleCard(modules[index]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: ExpansionTile(
                    title: const Text('商店设置'),
                    leading: const UiIcon(Icons.settings_outlined),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('选择所需功能，商店会准备依赖模块并在安装前统一确认。'),
                      const SizedBox(height: 8),
                      if (repository != null) SelectableText('目录：$repository'),
                      const SizedBox(height: 8),
                      NativeUi(
                        child: OutlinedButton.icon(
                          onPressed: loading || busy ? null : configure,
                          icon: const UiIcon(Icons.edit_outlined),
                          label: const Text('修改目录仓库'),
                        ),
                      ),
                      NativeUi(
                        child: SwitchListTile(
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
                      ),
                      const Text('安装前检查模块身份、摘要、权限与完整依赖；摘要校验不代表发布者签名。'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paint the dialog shell before any installed-package or index work begins.
class _CatalogDetailsLoader extends StatefulWidget {
  const _CatalogDetailsLoader({required this.title, required this.load});
  final String title;
  final Future<Widget> Function() load;

  @override
  State<_CatalogDetailsLoader> createState() => _CatalogDetailsLoaderState();
}

class _CatalogDetailsLoaderState extends State<_CatalogDetailsLoader> {
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
