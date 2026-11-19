import '../ui/ui_icon.dart';
import '../ui/native_ui.dart';
import '../ui/ui_design.dart';
import '../../app/app_toast.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../module_catalog/module_catalog.dart';
import '../module_catalog/catalog_providers.dart';

export '../module_catalog/catalog_providers.dart';
import 'module_host.dart';
import 'module_installation_snapshot.dart';
import 'module_management_widgets.dart';
import 'module_catalog_widgets.dart';
import 'module_package.dart';
import 'script_app_module.dart';
import '../ui/ui_composition.dart';
import 'host_api.dart';
import 'script_detail_page.dart';
import 'module_install_review_dialog.dart';
import 'module_download_dialog.dart';

export 'module_install_review_dialog.dart';
export 'module_download_dialog.dart';

part 'module_catalog_listing.dart';
part 'module_catalog_details_dialog.dart';

Future<Map<String, InstalledCatalogModule>> _installed(
  ModuleHost host, {
  Map<String, InstalledCatalogModule> verified = const {},
  bool reuseVerified = false,
}) async {
  final current = await readModuleInstallations(
    host,
    verified: {
      for (final entry in verified.entries) entry.key: entry.value.package,
    },
    reuseVerified: reuseVerified,
  );
  return {
    for (final entry in current.entries)
      entry.key: InstalledCatalogModule(
        entry.value.package,
        enabled: entry.value.enabled,
        repository: entry.value.repository,
      ),
  };
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

class ModuleCatalogPage extends ConsumerStatefulWidget {
  const ModuleCatalogPage({super.key, required this.host});
  final ModuleHost host;
  @override
  ConsumerState<ModuleCatalogPage> createState() => _ModuleCatalogPageState();
}

class _ModuleCatalogPageState extends ConsumerState<ModuleCatalogPage> {
  _CatalogListing? listing;
  ModuleCatalog? get catalog => listing?.catalog;
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

  void recordIndex(String id, ModuleVersionIndex index) {
    loadedIndexes[id] = index;
    latestVersions.remove(id);
    final latest = _latestStableVersion(index);
    if (latest != null) latestVersions[id] = latest;
    indexFailures.remove(id);
  }

  void showCatalog(ModuleCatalog result) {
    // Cached versions belong to a specific source, never just a module ID.
    for (final id in loadedIndexes.keys.toList()) {
      final before = catalog?.modules[id];
      final after = result.modules[id];
      if (before == null ||
          after == null ||
          before.repository != after.repository ||
          before.indexUrl != after.indexUrl) {
        loadedIndexes.remove(id);
        latestVersions.remove(id);
      }
    }
    indexFailures.clear();
    final updated = _CatalogListing(result);
    listing = updated;
    if (!updated.categories.contains(category)) {
      category = '全部分类';
    }
  }

  Future<void> loadIndexes(
    ModuleCatalog result,
    int generation, {
    ModuleCatalogClient? cachedClient,
  }) async {
    final pending = result.modules.values.iterator;
    Future<void> worker() async {
      while (mounted && generation == loadGeneration && pending.moveNext()) {
        final item = pending.current;
        try {
          final index = cachedClient == null
              ? await indexFor(item)
              : await cachedClient.loadIndex(item, offline: true);
          if (!_isCurrentIndex(item, generation)) return;
          recordIndex(item.id, index);
        } catch (error) {
          if (!_isCurrentIndex(item, generation)) return;
          // A cache miss must not make a module unavailable while the fresh
          // index is still to be requested.
          if (cachedClient == null) indexFailures[item.id] = '$error';
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
    indexFailures.clear();
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final results = await Future.wait<Object>([
        _installed(widget.host, verified: installations, reuseVerified: true),
        ref.read(moduleCatalogClientProvider.future),
      ]);
      final current = results[0] as Map<String, InstalledCatalogModule>;
      final client = results[1] as ModuleCatalogClient;
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        repository = client.repository;
        installations = current;
      });
      if (!offline) {
        try {
          final cached = await client.loadCatalog(offline: true);
          if (!mounted || generation != loadGeneration) return;
          setState(() => showCatalog(cached));
          await loadIndexes(cached, generation, cachedClient: client);
        } catch (_) {
          // Missing or invalid caches are replaced by the online result.
        }
      }
      if (!mounted || generation != loadGeneration) return;
      final result = await client.loadCatalog(
        offline: offline,
        allowCacheFallback: false,
      );
      if (!mounted || generation != loadGeneration) return;
      setState(() => showCatalog(result));
      await loadIndexes(result, generation);
    } catch (error) {
      if (!mounted || generation != loadGeneration) return;
      setState(() => failure = '$error');
      if (!offline && catalog != null) {
        setState(() => offline = true);
        try {
          if (!mounted || generation != loadGeneration) return;
          await loadIndexes(catalog!, generation);
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
      listing = null;
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
      var selectedId = id;
      while (mounted) {
        final target = selectedId;
        final next = await showDialog<_CatalogDetailsAction>(
          context: context,
          builder: (dialogContext) => ModuleDetailsLoader(
            title: catalog?.modules[target]?.name ?? target,
            load: () => _detailsContent(target, dialogContext),
          ),
        );
        if (next == null || !mounted) return;
        if (next.install) {
          await install(next.id);
          return;
        }
        selectedId = next.id;
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
        onDependency: (dependency) => Navigator.pop<_CatalogDetailsAction>(
          dialogContext,
          (id: dependency, install: false),
        ),
      );
    }
    final item = catalog?.modules[id];
    if (item == null) throw StateError('目录未收录模块：$id');
    final index = loadedIndexes[id] ?? await indexFor(item);
    final version = _latestStableVersion(index);
    if (version == null) throw StateError('没有兼容当前宿主的稳定版本：$id');
    if (!mounted) throw StateError('模块商店已关闭');
    return _CatalogListingDetailsDialog(
      item: item,
      index: index,
      version: version,
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

  bool _matchesStatus(CatalogModule item) {
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
    final candidates = listing?.matching(searchController.text, category);
    final modules = filter == '全部'
        ? candidates?.toList() ?? const <CatalogModule>[]
        : candidates?.where(_matchesStatus).toList() ?? const <CatalogModule>[];
    final categories = listing?.categories ?? const <String>[];
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
