import 'package:pub_semver/pub_semver.dart';

import '../contracts/json_values.dart';
import '../module_host/module_package.dart';

String normalizeRepository(String value) {
  final source = value.startsWith('https://github.com/')
      ? value.substring('https://github.com/'.length)
      : value;
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(source) ||
      source.split('/').any((part) => part == '.' || part == '..')) {
    throw const FormatException('发布仓库必须是 GitHub owner/repository');
  }
  return source;
}

void validateRepositoryUrl(Uri uri, String repository, {bool release = false}) {
  final parts = uri.pathSegments;
  final repo = normalizeRepository(repository).split('/');
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.hasPort ||
      parts.length < (release ? 6 : 4) ||
      parts[0].toLowerCase() != repo[0].toLowerCase() ||
      parts[1].toLowerCase() != repo[1].toLowerCase() ||
      (release
          ? uri.host != 'github.com' ||
                parts[2] != 'releases' ||
                parts[3] != 'download' ||
                parts[4] == 'latest'
          : uri.host != 'raw.githubusercontent.com')) {
    throw FormatException('地址与发布仓库不符或不是固定 HTTPS 地址：$uri');
  }
}

class CatalogModule {
  CatalogModule._(
    this.id,
    this.name,
    this.description,
    this.author,
    this.repository,
    this.indexUrl,
    this.category,
    this.featured,
  );
  final String id, name, description, author, repository, category;
  final Uri indexUrl;
  final bool featured;
  factory CatalogModule.fromJson(Object? value) {
    final json = object(value, 'catalog module');
    final id = string(json['id'], 'module id');
    if (!RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9_-]*)+$').hasMatch(id)) {
      throw const FormatException('Invalid catalog module ID');
    }
    final repository = normalizeRepository(
      string(json['repository'], 'repository'),
    );
    final indexUrl = Uri.parse(string(json['indexUrl'], 'indexUrl'));
    validateRepositoryUrl(indexUrl, repository);
    var category = '其他';
    if (json.containsKey('category')) {
      final rawCategory = json['category'];
      if (rawCategory is! String ||
          rawCategory.trim().isEmpty ||
          rawCategory.runes.length > 20) {
        throw const FormatException('目录分类必须是 1 至 20 字的非空字符串');
      }
      category = rawCategory.trim();
    }
    if (json.containsKey('featured') && json['featured'] is! bool) {
      throw const FormatException('目录推荐标记必须是布尔值');
    }
    return CatalogModule._(
      id,
      string(json['name'], 'name'),
      json['description'] as String? ?? '作者未提供说明',
      json['author'] as String? ?? '',
      repository,
      indexUrl,
      category,
      json['featured'] as bool? ?? false,
    );
  }
}

class ModuleCatalog {
  ModuleCatalog without(Set<String> moduleIds) => ModuleCatalog._(
    Map.unmodifiable({
      for (final entry in modules.entries)
        if (!moduleIds.contains(entry.key)) entry.key: entry.value,
    }),
  );
  ModuleCatalog._(this.modules);
  final Map<String, CatalogModule> modules;
  factory ModuleCatalog.fromJson(Object? value) {
    final json = object(value, 'catalog');
    if ((json['catalogFormat'] ?? json['formatVersion']) != 1) {
      throw const FormatException('Unsupported catalog format');
    }
    final result = <String, CatalogModule>{};
    for (final raw in json['modules'] as List) {
      final module = CatalogModule.fromJson(raw);
      if (result.containsKey(module.id)) {
        throw FormatException('目录模块 ID 重复：${module.id}');
      }
      result[module.id] = module;
    }
    return ModuleCatalog._(Map.unmodifiable(result));
  }
}

class CatalogVersion {
  CatalogVersion._(
    this.moduleId,
    this.repository,
    this.version,
    this.manifest,
    this.services,
    this.url,
    this.size,
    this.sha256,
  );
  final String moduleId, repository, version, sha256;
  final Map<String, Object?> manifest;
  final List<Object?> services;
  final Uri url;
  final int size;
  factory CatalogVersion.fromJson(Object? value, CatalogModule module) {
    final json = object(value, 'release');
    final version = string(json['version'], 'version');
    Version.parse(version);
    final manifest = object(freezeJson(object(json['manifest'], 'manifest')));
    if (manifest['id'] != module.id || manifest['version'] != version) {
      throw const FormatException('版本索引的模块身份不符');
    }
    VersionConstraint.parse(string(manifest['hostApi'], 'hostApi'));
    if (manifest['dataVersion'] is! int ||
        (manifest['dataVersion'] as int) < 1) {
      throw const FormatException('Invalid indexed data version');
    }
    final url = Uri.parse(
      string(json['url'] ?? json['downloadUrl'], 'release URL'),
    );
    validateRepositoryUrl(url, module.repository, release: true);
    final size = json['size'];
    final sha256 = string(json['sha256'], 'sha256');
    if (size is! int ||
        size < 1 ||
        size > 16 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid release size or SHA-256');
    }
    final services = freezeJson(json['services']) as List<Object?>;
    final seen = <String>{};
    for (final raw in services) {
      final service = object(raw, 'service');
      if (service['major'] is! int ||
          (service['major'] as int) < 1 ||
          !['query', 'command'].contains(service['kind']) ||
          !seen.add(
            '${string(service['id'], 'service id')}@${service['major']}',
          )) {
        throw const FormatException('Invalid indexed service');
      }
    }
    return CatalogVersion._(
      module.id,
      module.repository,
      version,
      manifest,
      services,
      url,
      size,
      sha256,
    );
  }
}

class ModuleVersionIndex {
  ModuleVersionIndex._(this.versions);
  final List<CatalogVersion> versions;
  factory ModuleVersionIndex.fromJson(Object? value, CatalogModule module) {
    final json = object(value, 'version index');
    if ((json['indexFormat'] ?? json['formatVersion']) != 1 ||
        json['moduleId'] != module.id ||
        normalizeRepository(string(json['repository'], 'repository'))
                .toLowerCase() !=
            module.repository.toLowerCase()) {
      throw const FormatException('版本索引格式、模块或仓库不符');
    }
    final versions = <CatalogVersion>[];
    final seen = <String>{};
    for (final raw in json['versions'] as List) {
      final version = CatalogVersion.fromJson(raw, module);
      if (!seen.add(version.version)) throw const FormatException('重复发布版本');
      versions.add(version);
    }
    versions.sort(
      (a, b) => Version.parse(b.version).compareTo(Version.parse(a.version)),
    );
    return ModuleVersionIndex._(List.unmodifiable(versions));
  }
}
