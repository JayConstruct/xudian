import '../ui/tab_content_transition.dart';
import '../../features/settings/settings_widgets.dart';
import '../ui/ui_icon.dart';
import '../ui/native_ui.dart';
import '../ui/ui_component.dart';
import '../ui/ui_surfaces.dart';
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
      builder: (_) => UiPackScope(
        defaultOnly: true,
        child: ModuleDownloadDialog(
          client: client,
          modules: changes,
          offline: offline,
        ),
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
      final confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ModuleBatchReviewDialog(
            modules: resolution.ordered
                .where((item) => reviewedIds.contains(item.id))
                .toList(),
            packages: packages,
            requestedIds: {...requests.keys, ...localPackages.map((p) => p.id)},
          ),
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

({UiPageRegistration page, IconData? icon})? _moduleEntry(
  ModuleHost host,
  String id,
) {
  final package = host.instances[id]?.package;
  if (package == null) return null;
  final registrations = ScriptAppModule(host, package).ui;
  final page = registrations
      .whereType<UiPageRegistration>()
      .where((page) => page.requiredContext.isEmpty)
      .firstOrNull;
  if (page == null) return null;
  final entry = registrations
      .whereType<UiEntryRegistration>()
      .where((entry) => !entry.content && entry.pageId == page.id)
      .firstOrNull;
  return (page: page, icon: entry?.icon);
}

IconData _catalogModuleIcon(String category, {required bool uiPack}) =>
    switch ((uiPack, category)) {
      (true, _) || (_, '界面') => Icons.layers_outlined,
      (_, '学习') => Icons.school_outlined,
      (_, '效率') => Icons.checklist,
      (_, 'AI') => Icons.auto_awesome,
      _ => Icons.extension_outlined,
    };

void _openModule(BuildContext context, ModuleHost host, String id) {
  final page = _moduleEntry(host, id)?.page;
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

  Future<void> _storeSettings(BuildContext context) async {
    final choice = await showSettingsModal<String>(
      context: context,
      useGlobalStyle: true,
      builder: (context) => SettingsSheet(
        title: const Text('商店设置'),
        expandedActions: true,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsGroupSurface(
                children: [
                  SettingsEntry(
                    title: '修改目录仓库',
                    subtitle: repository,
                    icon: Icons.public,
                    enabled: !loading && !busy,
                    onTap: () => Navigator.pop(context, 'repository'),
                  ),
                  SwitchListTile(
                    secondary: const SettingsGlyph(Icons.offline_bolt_outlined),
                    title: const Text('离线浏览缓存'),
                    value: offline,
                    onChanged: loading || busy
                        ? null
                        : (_) => Navigator.pop(context, 'offline'),
                  ),
                ],
              ),
              const SettingsNote('安装前核对模块身份、摘要、权限与依赖。'),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'repository') await configure(context);
    if (choice == 'offline') {
      setState(() => offline = !offline);
      await load();
    }
  }

  Future<void> configure(BuildContext context) async {
    final next = await showSettingsModal<String>(
      context: context,
      useGlobalStyle: true,
      builder: (_) => _CatalogRepositorySheet(
        repository: repository ?? 'JayConstruct/xudian-modules',
      ),
    );
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

  Future<void> install(
    BuildContext context,
    String id, {
    String? version,
  }) async {
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

  Future<void> details(BuildContext context, String id) async {
    setState(() => busy = true);
    try {
      var selectedId = id;
      while (context.mounted) {
        final target = selectedId;
        final next = await showSettingsModal<_CatalogDetailsAction>(
          context: context,
          useGlobalStyle: true,
          builder: (dialogContext) => ModuleDetailsLoader(
            title: '模块详情',
            sheet: true,
            load: () => _detailsContent(target, dialogContext),
          ),
        );
        if (next == null || !context.mounted) return;
        if (next.install) {
          await install(context, next.id);
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
        sheet: true,
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
      icon: _catalogModuleIcon(
        item.category,
        uiPack: version.manifest['kind'] == 'uiPack',
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

  Widget moduleCard(
    BuildContext context,
    CatalogModule item, {
    bool grouped = false,
  }) {
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
      icon:
          entry?.icon ??
          _catalogModuleIcon(
            item.category,
            uiPack:
                installed?.package.isUiPack ??
                latest?.manifest['kind'] == 'uiPack',
          ),
      grouped: grouped,
      action: action,
      onDetails: busy ? null : () => details(context, item.id),
      onAction: action == '打开模块'
          ? (busy ? null : () => _openModule(context, widget.host, item.id))
          : actionable
          ? () => install(
              context,
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
                      context,
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
  Widget build(BuildContext context) =>
      UiPackScope.global(child: Builder(builder: _buildCatalog));

  Widget _buildCatalog(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final searching = searchController.text.trim().isNotEmpty;
    final candidates = listing?.matching(searchController.text, category);
    final modules = filter == '全部'
        ? candidates?.toList() ?? const <CatalogModule>[]
        : candidates?.where(_matchesStatus).toList() ?? const <CatalogModule>[];
    final resultLabel = switch (filter) {
      '全部' => searching ? '搜索结果' : '模块目录',
      _ => '$filter模块',
    };
    return DetailPage(
      title: '模块商店',
      settingsStyle: true,
      maxBodyWidth: 1360,
      actions: [
        IconButton(
          tooltip: '刷新 / 重试',
          onPressed: loading || busy ? null : load,
          icon: const UiIcon(Icons.refresh, size: 21),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: IconButton(
            tooltip: '商店设置',
            onPressed: () => _storeSettings(context),
            icon: const UiIcon(Icons.tune, size: 21),
          ),
        ),
      ],
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppDesign.pageGutter,
              8,
              AppDesign.pageGutter,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSearchField(
                    controller: searchController,
                    hint: '搜索名称、作用、作者或模块 ID',
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  ModuleCatalogFilters(
                    status: filter,
                    category: category,
                    categories: listing?.categories ?? const [],
                    resultLabel: resultLabel,
                    count: modules.length,
                    onStatusChanged: (value) => setState(() => filter = value),
                    onCategoryChanged: (value) =>
                        setState(() => category = value),
                  ),
                  if (offline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      padding: const EdgeInsets.all(12),
                      decoration: ShapeDecoration(
                        color: colors.primaryContainer,
                        shape: AppDesign.smoothShape(radius: 12),
                      ),
                      child: Text(
                        '正在浏览缓存。离线安装需要已缓存的模块包。',
                        style: TextStyle(
                          color: colors.onPrimaryContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  if (failure != null) ...[
                    SelectableText(
                      failure!,
                      style: TextStyle(color: colors.error),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: loading || busy ? null : load,
                        icon: const UiIcon(Icons.refresh),
                        label: const Text('刷新 / 重试'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          TabContentTransition.sliver(
            index: ModuleCatalogFilters.statuses.indexOf(filter),
            child: SliverMainAxisGroup(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesign.pageGutter,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (catalog?.modules.isEmpty == true)
                          const SettingsEmptyState(
                            icon: Icons.extension_outlined,
                            title: '目录中没有模块',
                            detail: '请在商店设置中检查目录仓库。',
                          )
                        else if (catalog != null && modules.isEmpty)
                          if (loading && filter == '可更新')
                            const SettingsNote('正在检查模块版本…')
                          else ...[
                            const SettingsEmptyState(
                              title: '没有符合筛选条件的模块',
                              detail: '调整分类或安装状态，或清除筛选。',
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 15),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: OutlinedButton(
                                  onPressed: clearFilters,
                                  child: const Text('清除筛选'),
                                ),
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDesign.pageGutter,
                    0,
                    AppDesign.pageGutter,
                    20,
                  ),
                  sliver: ModuleCatalogSliverGrid(
                    itemCount: modules.length,
                    itemBuilder: (tileContext, index) =>
                        moduleCard(context, modules[index]),
                    groupedItemBuilder: (tileContext, index) =>
                        moduleCard(context, modules[index], grouped: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogRepositorySheet extends StatefulWidget {
  const _CatalogRepositorySheet({required this.repository});

  final String repository;

  @override
  State<_CatalogRepositorySheet> createState() =>
      _CatalogRepositorySheetState();
}

class _CatalogRepositorySheetState extends State<_CatalogRepositorySheet> {
  late final controller = TextEditingController(text: widget.repository);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NativeUi(
    child: SettingsSheet(
      title: const Text('模块目录仓库'),
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
  );
}
