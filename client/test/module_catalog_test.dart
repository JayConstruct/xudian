import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/module_host/module_package.dart';

Future<ScriptPackage> makePackage(
  String id, {
  String version = '1.0.0',
  List<Object?> dependencies = const [],
  List<Object?> services = const [],
  List<Object?> serviceDependencies = const [],
  List<String> permissions = const [],
  String hostApi = '^1.8.0',
}) async => ScriptPackage.verify(
  await ScriptPackage.build(
    {
      'formatVersion': 3,
      'manifest': {
        'id': id,
        'name': id,
        'version': version,
        'hostApi': hostApi,
        'dataVersion': 1,
        'dependencies': dependencies,
        'serviceDependencies': serviceDependencies,
        'permissions': permissions,
      },
      'entryPoint': 'main.js',
      'collections': [],
      'pages': [],
      'services': services,
    },
    {'main.js': 'export function main(){return {};}'},
  ),
  allowUnsignedLocal: true,
);

Map<String, Object?> service({int major = 1, String kind = 'query'}) => {
  'id': 'data.read',
  'major': major,
  'kind': kind,
  'handler': 'main',
  'input': <String, Object?>{},
  'output': <String, Object?>{},
};

class Fixture {
  Fixture(this.directory) {
    client = ModuleCatalogClient(cacheDirectory: directory, transport: fetch);
  }
  final Directory directory;
  late final ModuleCatalogClient client;
  final documents = <String, List<int>>{};
  final modules = <String, Map<String, Object?>>{};
  final indexes = <String, Map<String, Object?>>{};
  int requests = 0;
  int networkFailures = 0;
  bool cancelDuringDownload = false;
  Future<List<int>> fetch(
    Uri uri, {
    DownloadCancellation? cancellation,
    void Function(int, int)? onProgress,
    required int maximumBytes,
  }) async {
    requests++;
    if (networkFailures-- > 0) throw const SocketException('offline');
    final bytes = documents[uri.toString()];
    if (bytes == null) throw HttpException('not found', uri: uri);
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    if (cancelDuringDownload && uri.host == 'github.com') {
      cancellation?.cancel();
    }
    cancellation?.check();
    onProgress?.call(bytes.length, bytes.length);
    return bytes;
  }

  void sync() {
    documents[client.catalogUrl.toString()] = utf8.encode(
      jsonEncode({'catalogFormat': 1, 'modules': modules.values.toList()}),
    );
    for (final id in modules.keys) {
      documents[modules[id]!['indexUrl'] as String] = utf8.encode(
        jsonEncode(indexes[id]),
      );
    }
  }

  Future<void> add(
    ScriptPackage package, {
    String repository = 'Alice/modules',
  }) async {
    final id = package.id;
    final indexUrl =
        'https://raw.githubusercontent.com/$repository/main/module-index/$id.json';
    modules[id] = {
      'id': id,
      'name': id,
      'repository': repository,
      'indexUrl': indexUrl,
      'description': '作用 $id',
      'author': repository.split('/').first,
    };
    final url =
        'https://github.com/$repository/releases/download/v${package.version}/$id.xmodule';
    final index = indexes.putIfAbsent(
      id,
      () => {
        'indexFormat': 1,
        'moduleId': id,
        'repository': repository,
        'versions': <Object?>[],
      },
    );
    (index['versions'] as List).add({
      'version': package.version,
      'manifest': package.manifest,
      'services': package.definition['services'],
      'url': url,
      'size': package.bytes.length,
      'sha256': package.packageDigest,
    });
    documents[url] = package.bytes;
    sync();
  }

  Future<CatalogVersion> release(String id) async =>
      (await client.loadIndex((await client.loadCatalog()).modules[id]!))
          .versions
          .first;
}

void main() {
  late Directory directory;
  late Fixture fixture;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('catalog-test-');
    fixture = Fixture(directory);
  });
  tearDown(() async {
    fixture.client.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'withdrawn defaults are excluded from online and cached catalogs',
    () async {
      await fixture.add(await makePackage('test.withdrawn'));
      await fixture.add(await makePackage('test.kept'));
      final client = ModuleCatalogClient(
        cacheDirectory: directory,
        transport: fixture.fetch,
        excludedModuleIds: {'test.withdrawn'},
      );
      addTearDown(client.dispose);
      expect((await client.loadCatalog()).modules.keys, ['test.kept']);
      expect((await client.loadCatalog(offline: true)).modules.keys, [
        'test.kept',
      ]);
      expect(
        (await fixture.client.loadCatalog(offline: true)).modules.keys,
        containsAll(['test.withdrawn', 'test.kept']),
      );
      expect(
      () => client.excludedModuleIds.add('test.kept'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'different authors resolve service chain once in dependency order',
    () async {
      await fixture.add(
        await makePackage('test.schedule', services: [service()]),
        repository: 'Bob/schedule',
      );
      await fixture.add(
        await makePackage(
          'test.shiguang',
          dependencies: [
            {'moduleId': 'test.schedule', 'version': '^1.0.0'},
          ],
          services: [service()],
          permissions: ['services.query:test.schedule/data.read@1'],
        ),
        repository: 'Carol/importers',
      );
      await fixture.add(
        await makePackage(
          'test.zhengfang',
          dependencies: ['test.shiguang'],
          serviceDependencies: [
            {
              'moduleId': 'test.shiguang',
              'serviceId': 'data.read',
              'majorVersion': 1,
            },
          ],
        ),
      );
      final resolution = await ModuleDependencyResolver(fixture.client).resolve(
        requests: {'test.zhengfang': 'any', 'test.schedule': 'any'},
        installed: {},
      );
      expect(resolution.ordered.map((m) => m.id), [
        'test.schedule',
        'test.shiguang',
        'test.zhengfang',
      ]);
      for (final module in resolution.ordered) {
        final package = await module.loadPackage(fixture.client);
        expect(package.id, module.id);
        expect(package.trusted, isFalse);
        expect(package.origin, 'local');
      }
    },
  );

  test(
    'reuse and enable satisfying installed dependencies without network',
    () async {
      final dependency = await makePackage(
        'test.provider',
        version: '1.1.0',
        services: [service()],
      );
      final local = await makePackage(
        'test.consumer',
        permissions: ['services.query:test.provider/data.read@1'],
      );
      final resolution = await ModuleDependencyResolver(fixture.client).resolve(
        requests: {},
        localPackages: [local],
        installed: {
          'test.provider': InstalledCatalogModule(dependency, enabled: false),
        },
        offline: true,
      );
      expect(resolution.ordered.first.action, ModuleResolutionAction.enable);
      expect(resolution.selected['test.provider']!.version, '1.1.0');
      expect(fixture.requests, 0);
    },
  );

  test(
    'backtracking selects highest stable chain preserving enabled constraints',
    () async {
      final installed = await makePackage('test.provider');
      await fixture.add(await makePackage('test.provider', version: '2.0.0'));
      await fixture.add(await makePackage('test.provider', version: '1.9.0'));
      await fixture.add(
        await makePackage('test.provider', version: '1.10.0-beta.1'),
      );
      await fixture.add(
        await makePackage(
          'test.consumer',
          version: '2.0.0',
          dependencies: [
            {'moduleId': 'test.provider', 'version': '^2.0.0'},
          ],
        ),
      );
      await fixture.add(
        await makePackage(
          'test.consumer',
          dependencies: [
            {'moduleId': 'test.provider', 'version': '>=1.5.0 <2.0.0'},
          ],
        ),
      );
      final existing = await makePackage(
        'test.existing',
        dependencies: [
          {'moduleId': 'test.provider', 'version': '^1.0.0'},
        ],
      );
      final resolution = await ModuleDependencyResolver(fixture.client).resolve(
        requests: {'test.consumer': 'any'},
        installed: {
          'test.provider': InstalledCatalogModule(installed, enabled: true),
          'test.existing': InstalledCatalogModule(existing, enabled: true),
        },
      );
      expect(resolution.selected['test.consumer']!.version, '1.0.0');
      expect(resolution.selected['test.provider']!.version, '1.9.0');
      expect(
        resolution.selected['test.provider']!.action,
        ModuleResolutionAction.upgrade,
      );
    },
  );

  test('service major mismatch and cycles report concrete failures', () async {
    await fixture.add(
      await makePackage('test.provider', services: [service(major: 2)]),
    );
    await fixture.add(
      await makePackage(
        'test.consumer',
        permissions: ['services.query:test.provider/data.read@1'],
      ),
    );
    await expectLater(
      ModuleDependencyResolver(fixture.client)
          .resolve(requests: {'test.consumer': 'any'}, installed: {}),
      throwsA(
        isA<ModuleResolutionException>().having(
          (e) => e.message,
          'conflict',
          contains('data.read@1'),
        ),
      ),
    );
    await fixture.add(
      await makePackage('test.first', dependencies: ['test.second']),
    );
    await fixture.add(
      await makePackage('test.second', dependencies: ['test.first']),
    );
    await expectLater(
      ModuleDependencyResolver(fixture.client)
          .resolve(requests: {'test.first': 'any'}, installed: {}),
      throwsA(
        isA<ModuleResolutionException>().having(
          (e) => e.message,
          'cycle',
          contains('循环依赖'),
        ),
      ),
    );
  });

  test('no downgrade and publishing repository is pinned', () async {
    final current = await makePackage('test.provider', version: '2.0.0');
    final lower = await makePackage('test.provider');
    await expectLater(
      ModuleDependencyResolver(fixture.client).resolve(
        requests: {},
        installed: {
          'test.provider': InstalledCatalogModule(current, enabled: true),
        },
        localPackages: [lower],
      ),
      throwsA(
        isA<ModuleResolutionException>().having(
          (e) => e.message,
          'downgrade',
          contains('不自动降级'),
        ),
      ),
    );
    await fixture.add(
      await makePackage('test.provider', version: '3.0.0'),
      repository: 'Other/repository',
    );
    await expectLater(
      ModuleDependencyResolver(fixture.client).resolve(
        requests: {'test.provider': '^3.0.0'},
        installed: {
          'test.provider': InstalledCatalogModule(
            current,
            enabled: true,
            repository: 'Alice/modules',
          ),
        },
      ),
      throwsA(
        isA<ModuleResolutionException>().having(
          (e) => e.message,
          'repository',
          contains('不得切换'),
        ),
      ),
    );
  });

  test(
    'only an immutable bundled digest pin grants preinstalled origin',
    () async {
      final package = await makePackage('test.official');
      await fixture.add(package, repository: 'JayConstruct/xudian');
      final release = await fixture.release('test.official');
      final unsigned = await fixture.client.download(release);
      expect(unsigned.origin, 'local');
      expect(unsigned.trusted, isFalse);
      final trusted = ModuleCatalogClient(
        cacheDirectory: directory,
        transport: fixture.fetch,
        preinstalledDigests: {'test.official': package.packageDigest},
      );
      addTearDown(trusted.dispose);
      final pinned = await trusted.download(release);
      expect(pinned.origin, 'preinstalled');
      expect(pinned.trusted, isTrue);
      expect(pinned.release['channel'], 'local');
      final mutablePins = {'test.official': '0' * 64};
      final wrongPin = ModuleCatalogClient(
        cacheDirectory: directory,
        transport: fixture.fetch,
        preinstalledDigests: mutablePins,
      );
      mutablePins['test.official'] = package.packageDigest;
      addTearDown(wrongPin.dispose);
      expect((await wrongPin.download(release)).trusted, isFalse);
      expect((await fixture.client.download(release)).origin, 'local');
    },
  );

  test(
    'cache persists metadata and verified unsigned packages across clients',
    () async {
      await fixture.add(await makePackage('test.cached'));
      final release = await fixture.release('test.cached');
      await fixture.client.download(release);
      final offline = ModuleCatalogClient(
        cacheDirectory: directory,
        transport: (
          url, {
          cancellation,
          onProgress,
          required maximumBytes,
        }) async => throw const SocketException('offline'),
      );
      addTearDown(offline.dispose);
      final catalog = await offline.loadCatalog(offline: true);
      final index = await offline.loadIndex(
        catalog.modules['test.cached']!,
        offline: true,
      );
      expect(
        (await offline.download(index.versions.first, offline: true)).trusted,
        isFalse,
      );
      expect((await offline.loadCatalog()).modules.keys, ['test.cached']);
    },
  );

  test(
    'download retry, progress, cancellation and missing offline package',
    () async {
      await fixture.add(await makePackage('test.network'));
      final release = await fixture.release('test.network');
      await expectLater(
        fixture.client.download(release, offline: true),
        throwsStateError,
      );
      fixture.cancelDuringDownload = true;
      final cancellation = DownloadCancellation();
      await expectLater(
        fixture.client.download(release, cancellation: cancellation),
        throwsA(isA<DownloadCancelled>()),
      );
      fixture.cancelDuringDownload = false;
      fixture.networkFailures = 1;
      final progress = <int>[];
      expect(
        (await fixture.client.download(
          release,
          onProgress: (received, total) => progress.add(received),
        )).id,
        'test.network',
      );
      expect(progress.last, release.size);
    },
  );

  test(
    'tampered digest or full metadata cannot populate package cache',
    () async {
      await fixture.add(await makePackage('test.integrity'));
      final release = await fixture.release('test.integrity');
      final bytes = List<int>.of(fixture.documents[release.url.toString()]!);
      bytes[10] ^= 1;
      fixture.documents[release.url.toString()] = bytes;
      await expectLater(
        fixture.client.download(release),
        throwsFormatException,
      );
      await expectLater(
        fixture.client.download(release, offline: true),
        throwsStateError,
      );
      final original = await makePackage('test.integrity');
      fixture.documents[release.url.toString()] = original.bytes;
      final indexed =
          (fixture.indexes['test.integrity']!['versions'] as List).first as Map;
      indexed['manifest'] = {
        ...original.manifest,
        'permissions': ['files'],
      };
      fixture.sync();
      final misleading = await fixture.release('test.integrity');
      await expectLater(
        fixture.client.download(misleading),
        throwsFormatException,
      );
    },
  );

  test(
    'enabled consumer upgrade cannot erase current dependency requirements',
    () async {
      final provider = await makePackage('test.provider');
      final consumer = await makePackage(
        'test.consumer',
        dependencies: [
          {'moduleId': 'test.provider', 'version': '^1.0.0'},
        ],
      );
      await fixture.add(await makePackage('test.provider', version: '2.0.0'));
      await fixture.add(
        await makePackage(
          'test.consumer',
          version: '2.0.0',
          dependencies: [
            {'moduleId': 'test.provider', 'version': '^2.0.0'},
          ],
        ),
      );
      await expectLater(
        ModuleDependencyResolver(fixture.client).resolve(
          requests: {'test.provider': '^2.0.0'},
          installed: {
            'test.provider': InstalledCatalogModule(provider, enabled: true),
            'test.consumer': InstalledCatalogModule(consumer, enabled: true),
          },
        ),
        throwsA(
          isA<ModuleResolutionException>().having(
            (e) => e.message,
            'range conflict',
            contains('版本范围冲突'),
          ),
        ),
      );
      expect(fixture.requests, 0);
    },
  );

  test(
    'installed-only cycle fails without reading absent network catalog',
    () async {
      final first = await makePackage(
        'test.first',
        dependencies: ['test.second'],
      );
      final second = await makePackage(
        'test.second',
        dependencies: ['test.first'],
      );
      await expectLater(
        ModuleDependencyResolver(fixture.client).resolve(
          requests: {},
          installed: {
            'test.first': InstalledCatalogModule(first, enabled: true),
            'test.second': InstalledCatalogModule(second, enabled: true),
          },
        ),
        throwsA(
          isA<ModuleResolutionException>().having(
            (e) => e.message,
            'cycle',
            contains('循环依赖'),
          ),
        ),
      );
      expect(fixture.requests, 0);
    },
  );

  test('cancellation immediately releases a pending transport', () async {
    await fixture.add(await makePackage('test.pending'));
    final release = await fixture.release('test.pending');
    final started = Completer<void>();
    final pending = Completer<List<int>>();
    final client = ModuleCatalogClient(
      cacheDirectory: directory,
      transport: (url, {cancellation, onProgress, required maximumBytes}) {
        started.complete();
        return pending.future;
      },
    );
    addTearDown(client.dispose);
    final token = DownloadCancellation();
    final download = client.download(release, cancellation: token);
    await started.future;
    final check = expectLater(download, throwsA(isA<DownloadCancelled>()));
    token.cancel();
    await check.timeout(const Duration(seconds: 1));
    pending.completeError(const SocketException('late failure'));
    await Future<void>.delayed(Duration.zero);
  });

  test('redirects preserve pinned repositories and accept only release CDNs', () {
    final metadata = Uri.parse(
      'https://raw.githubusercontent.com/Alice/modules/main/index.json',
    );
    final release = Uri.parse(
      'https://github.com/Alice/modules/releases/download/v1/test.xmodule',
    );
    expect(
      isAllowedCatalogRedirect(
        metadata,
        Uri.parse(
          'https://raw.githubusercontent.com/alice/Modules/main/index.json',
        ),
      ),
      isTrue,
    );
    expect(
      isAllowedCatalogRedirect(
        metadata,
        Uri.parse(
          'https://raw.githubusercontent.com/Other/modules/main/index.json',
        ),
      ),
      isFalse,
    );
    expect(
      isAllowedCatalogRedirect(
        release,
        Uri.parse(
          'https://github.com/Other/modules/releases/download/v1/test.xmodule',
        ),
      ),
      isFalse,
    );
    expect(
      isAllowedCatalogRedirect(
        release,
        Uri.parse(
          'https://github.com/Alice/modules/releases/download/v1/test.xmodule',
        ),
      ),
      isTrue,
    );
    expect(
      isAllowedCatalogRedirect(
        release,
        Uri.parse(
          'https://release-assets.githubusercontent.com/assets/package?token=value',
        ),
      ),
      isTrue,
    );
    expect(
      isAllowedCatalogRedirect(
        release,
        Uri.parse(
          'https://objects.githubusercontent.com/assets/package?token=value',
        ),
      ),
      isTrue,
    );
    expect(
      isAllowedCatalogRedirect(
        metadata,
        Uri.parse('https://objects.githubusercontent.com/assets/package'),
      ),
      isFalse,
    );
    for (final target in [
      'https://evil.example/package',
      'http://release-assets.githubusercontent.com/package',
      'https://credentials@objects.githubusercontent.com/package',
      'https://github.com/Alice/modules/blob/main/package',
    ]) {
      expect(isAllowedCatalogRedirect(release, Uri.parse(target)), isFalse);
    }
  });

  test('catalog rejects duplicate IDs and release URLs outside author repository', () async {
    await fixture.add(await makePackage('test.identity'));
    final module = fixture.modules['test.identity']!;
    expect(
      () => ModuleCatalog.fromJson({
        'catalogFormat': 1,
        'modules': [module, module],
      }),
      throwsFormatException,
    );
    final indexed =
        (fixture.indexes['test.identity']!['versions'] as List).first as Map;
    indexed['url'] =
        'https://github.com/Attacker/modules/releases/download/v1/test.xmodule';
    fixture.sync();
    await expectLater(fixture.release('test.identity'), throwsFormatException);
  });
}
