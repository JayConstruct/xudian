import 'package:pub_semver/pub_semver.dart';

import '../module_host/module_package.dart';
import '../module_host/host_api.dart';
import 'catalog_client.dart';
import 'catalog_models.dart';

enum ModuleResolutionAction { reuse, install, upgrade, enable }

class InstalledCatalogModule {
  const InstalledCatalogModule(
    this.package, {
    required this.enabled,
    this.repository,
  });
  final ScriptPackage package;
  final bool enabled;
  final String? repository;
}

class ResolvedCatalogModule {
  ResolvedCatalogModule._({
    required this.id,
    required this.manifest,
    required this.services,
    this.package,
    this.release,
    this.installed,
    this.catalogModule,
  });
  final String id;
  final Map<String, Object?> manifest;
  final List<Object?> services;
  final ScriptPackage? package;
  final CatalogVersion? release;
  final InstalledCatalogModule? installed;
  final CatalogModule? catalogModule;
  String get name => manifest['name'] as String? ?? catalogModule?.name ?? id;
  String get description =>
      manifest['description'] as String? ??
      catalogModule?.description ??
      '作者未提供说明';
  String get version => manifest['version'] as String;
  String? get repository => release?.repository ?? installed?.repository;
  ModuleResolutionAction get action {
    if (installed == null) return ModuleResolutionAction.install;
    if (installed!.package.packageDigest != package?.packageDigest ||
        version != installed!.package.version) {
      return ModuleResolutionAction.upgrade;
    }
    return installed!.enabled
        ? ModuleResolutionAction.reuse
        : ModuleResolutionAction.enable;
  }

  List<String> get addedPermissions => [
    for (final permission
        in (manifest['permissions'] as List? ?? []).cast<String>())
      if (!(installed?.package.permissions ?? []).contains(permission))
        permission,
  ];
  Future<ScriptPackage> loadPackage(
    ModuleCatalogClient client, {
    DownloadCancellation? cancellation,
    void Function(int received, int total)? onProgress,
    bool offline = false,
  }) async {
    cancellation?.check();
    return package ??
        await client.download(
          release!,
          cancellation: cancellation,
          onProgress: onProgress,
          offline: offline,
        );
  }
}

class ModuleResolution {
  ModuleResolution._(
    Map<String, ResolvedCatalogModule> selected,
    List<ResolvedCatalogModule> ordered,
  ) : selected = Map.unmodifiable(selected),
      ordered = List.unmodifiable(ordered);
  final Map<String, ResolvedCatalogModule> selected;
  final List<ResolvedCatalogModule> ordered;
}

class ModuleResolutionException implements Exception {
  const ModuleResolutionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Requirement {
  _Requirement(
    this.id,
    this.range,
    this.from, {
    this.service,
    this.major,
    this.kind,
  });
  final String id, from;
  final VersionConstraint range;
  final String? service, kind;
  final int? major;
  bool accepts(ResolvedCatalogModule module) =>
      range.allows(Version.parse(module.version)) &&
      (service == null ||
          module.services.any((raw) {
            final value = object(raw);
            return value['id'] == service &&
                value['major'] == major &&
                (kind == null || value['kind'] == kind);
          }));
  String get label => service == null
      ? '$id $range（$from）'
      : '$id/$service@$major${kind == null ? '' : ' $kind'}（$from）';
}

class ModuleDependencyResolver {
  ModuleDependencyResolver(
    this.client, {
    Version? hostVersion,
    this.nativeServices = const {},
  }) : hostVersion = hostVersion ?? hostApiVersion;
  final ModuleCatalogClient client;
  final Version hostVersion;
  final Map<String, int> nativeServices;

  List<_Requirement> _requirements(ResolvedCatalogModule module) {
    final result = <_Requirement>[];
    for (final raw in module.manifest['dependencies'] as List? ?? []) {
      final id = raw is String
          ? raw
          : string(object(raw)['moduleId'], 'dependency');
      final range = raw is String
          ? VersionConstraint.any
          : VersionConstraint.parse(
              string(object(raw)['version'], 'dependency range'),
            );
      result.add(_Requirement(id, range, module.id));
    }
    void service(String id, String service, int major, String? kind) {
      if (major < 1) {
        throw const FormatException('Invalid service major version');
      }
      if (id == 'app.host') {
        if (nativeServices.isNotEmpty && nativeServices[service] != major) {
          throw ModuleResolutionException(
            '宿主服务版本不匹配：$service@$major（${module.id}）',
          );
        }
        return;
      }
      if (id == module.id) {
        final own = _Requirement(
          id,
          VersionConstraint.any,
          module.id,
          service: service,
          major: major,
          kind: kind,
        );
        if (!own.accepts(module)) {
          throw ModuleResolutionException('模块自身服务版本不匹配：${own.label}');
        }
        return;
      }
      result.add(
        _Requirement(
          id,
          VersionConstraint.any,
          module.id,
          service: service,
          major: major,
          kind: kind,
        ),
      );
    }

    for (final raw in module.manifest['serviceDependencies'] as List? ?? []) {
      final ref = object(raw, 'service dependency');
      service(
        string(ref['moduleId'], 'service module'),
        string(ref['serviceId'], 'service id'),
        ref['majorVersion'] as int,
        null,
      );
    }
    for (final permission
        in (module.manifest['permissions'] as List? ?? []).cast<String>()) {
      if (!permission.startsWith('services.query:') &&
          !permission.startsWith('services.command:')) {
        continue;
      }
      final match = RegExp(
        r'^services\.(query|command):([^/]+)/([^@]+)@([1-9][0-9]*)$',
      ).firstMatch(permission);
      if (match == null) {
        throw FormatException('Invalid service permission: $permission');
      }
      service(match[2]!, match[3]!, int.parse(match[4]!), match[1]!);
    }
    return result;
  }

  Future<ModuleResolution> resolve({
    required Map<String, String> requests,
    required Map<String, InstalledCatalogModule> installed,
    List<ScriptPackage> localPackages = const [],
    bool offline = false,
  }) async {
    final local = <String, ScriptPackage>{};
    for (final package in localPackages) {
      if (local.containsKey(package.id)) {
        throw ModuleResolutionException('重复本地模块：${package.id}');
      }
      final old = installed[package.id]?.package;
      if (old != null &&
          Version.parse(package.version) < Version.parse(old.version)) {
        throw ModuleResolutionException(
          '批量安装不自动降级：${package.id} ${old.version} → ${package.version}',
        );
      }
      if (old != null &&
          package.version == old.version &&
          old.packageDigest != package.packageDigest) {
        throw ModuleResolutionException(
          '已发布版本不可变：${package.id} ${package.version}',
        );
      }
      local[package.id] = package;
    }
    // Network lookup is deferred so fully satisfied local imports work offline.
    ModuleCatalog? catalog;
    final indexes = <String, ModuleVersionIndex>{};
    final candidateCache = <String, List<ResolvedCatalogModule>>{};
    Future<List<ResolvedCatalogModule>> candidates(String id) async {
      if (candidateCache.containsKey(id)) return candidateCache[id]!;
      final old = installed[id];
      ResolvedCatalogModule fromPackage(ScriptPackage package) =>
          ResolvedCatalogModule._(
            id: id,
            manifest: package.manifest,
            services: (package.definition['services'] as List? ?? [])
                .cast<Object?>(),
            package: package,
            installed: old,
          );
      if (local.containsKey(id)) return [fromPackage(local[id]!)];
      final result = <ResolvedCatalogModule>[];
      if (old != null) result.add(fromPackage(old.package));
      // Existing candidates are tried before reading remote metadata in search().
      return result;
    }

    Future<List<ResolvedCatalogModule>> remoteCandidates(String id) async {
      if (candidateCache.containsKey(id)) return candidateCache[id]!;
      if (local.containsKey(id)) {
        return candidateCache[id] = await candidates(id);
      }
      final result = await candidates(id);
      catalog ??= await client.loadCatalog(offline: offline);
      final module = catalog!.modules[id];
      if (module != null) {
        final old = installed[id];
        if (old?.repository != null &&
            normalizeRepository(old!.repository!).toLowerCase() !=
                module.repository.toLowerCase()) {
          throw ModuleResolutionException(
            '更新不得切换发布仓库：$id（${old.repository} → ${module.repository}）',
          );
        }
        final index = indexes[id] ??= await client.loadIndex(
          module,
          offline: offline,
        );
        for (final release in index.versions) {
          final version = Version.parse(release.version);
          if (version.isPreRelease ||
              old != null && version <= Version.parse(old.package.version)) {
            continue;
          }
          result.add(
            ResolvedCatalogModule._(
              id: id,
              manifest: release.manifest,
              services: release.services,
              release: release,
              installed: old,
              catalogModule: module,
            ),
          );
        }
      }
      return candidateCache[id] = result;
    }

    final roots = <_Requirement>[
      for (final entry in requests.entries)
        _Requirement(entry.key, VersionConstraint.parse(entry.value), '用户选择'),
      for (final package in localPackages)
        _Requirement(
          package.id,
          VersionConstraint.parse(package.version),
          '本地导入',
        ),
      for (final entry in installed.entries)
        if (entry.value.enabled)
          _Requirement(entry.key, VersionConstraint.any, '已启用模块'),
    ];
    // Preserve constraints imposed by the currently enabled packages. A solver
    // must not silently upgrade an unrelated consumer just to erase its range.
    for (final entry in installed.entries) {
      if (!entry.value.enabled ||
          requests.containsKey(entry.key) ||
          local.containsKey(entry.key)) {
        continue;
      }
      roots.addAll(_requirements((await candidates(entry.key)).first));
    }
    String conflict = '没有满足完整依赖链的版本';
    List<ResolvedCatalogModule>? order(
      Map<String, ResolvedCatalogModule> selected,
    ) {
      final visiting = <String>[], visited = <String>{};
      final output = <ResolvedCatalogModule>[];
      bool visit(String id) {
        if (visiting.contains(id)) {
          conflict = '循环依赖：${[...visiting, id].join(' → ')}';
          return false;
        }
        if (!visited.add(id)) return true;
        visiting.add(id);
        for (final dependency in _requirements(selected[id]!)) {
          if (!visit(dependency.id)) return false;
        }
        visiting.removeLast();
        output.add(selected[id]!);
        return true;
      }

      for (final id in selected.keys) {
        if (!visit(id)) return null;
      }
      return output;
    }

    Future<ModuleResolution?> search(
      Map<String, ResolvedCatalogModule> selected,
    ) async {
      final requirements = [
        ...roots,
        for (final module in selected.values) ..._requirements(module),
      ];
      for (final requirement in requirements) {
        final value = selected[requirement.id];
        if (value != null && !requirement.accepts(value)) {
          conflict =
              '依赖冲突：${requirement.label}；已选 ${value.id} ${value.version}，服务或版本不匹配';
          return null;
        }
      }
      final pending = requirements.where((r) => !selected.containsKey(r.id));
      if (pending.isEmpty) {
        final ordered = order(selected);
        return ordered == null ? null : ModuleResolution._(selected, ordered);
      }
      final id = pending.first.id;
      final required = requirements.where((r) => r.id == id).toList();
      final combined = required.fold<VersionConstraint>(
        VersionConstraint.any,
        (range, requirement) => range.intersect(requirement.range),
      );
      if (combined.isEmpty) {
        conflict = '版本范围冲突：${required.map((r) => r.label).join('；')}';
        return null;
      }
      bool compatible(ResolvedCatalogModule candidate) =>
          VersionConstraint.parse(
            string(candidate.manifest['hostApi'], 'hostApi'),
          ).allows(hostVersion) &&
          required.every((r) => r.accepts(candidate));
      final tried = <String>{};
      Future<ModuleResolution?> attempt(
        List<ResolvedCatalogModule> options,
      ) async {
        for (final candidate in options) {
          if (!tried.add(candidate.version) || !compatible(candidate)) continue;
          ModuleResolution? result;
          try {
            result = await search({...selected, id: candidate});
          } on ModuleResolutionException catch (error) {
            conflict = error.message;
            continue;
          }
          if (result != null) return result;
        }
        return null;
      }

      var result = await attempt(await candidates(id));
      if (result != null) return result;
      if (conflict.startsWith('循环依赖：') &&
          catalog == null &&
          (installed.containsKey(id) || local.containsKey(id))) {
        return null;
      }
      result = await attempt(await remoteCandidates(id));
      if (result != null) return result;
      if (tried.isEmpty || !(await remoteCandidates(id)).any(compatible)) {
        conflict =
            '无法满足依赖：${required.map((r) => r.label).join('；')}；无兼容宿主 $hostVersion 的稳定版本，且不自动降级';
      }
      return null;
    }

    final result = await search({});
    if (result == null) throw ModuleResolutionException(conflict);
    return result;
  }
}
