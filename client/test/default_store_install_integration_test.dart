import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/declarative/package/module_package.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> _sourcePackage(String id) async {
  final directory = Directory('../packages/modules/$id');
  final definition = object(
    jsonDecode(await File('${directory.path}/module.json').readAsString()),
  );
  final sources = <String, String>{};
  for (final file in directory.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.js')) continue;
    sources[file.path.substring(directory.path.length + 1)] = await file
        .readAsString();
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(definition, sources),
    allowUnsignedLocal: true,
  );
}

Future<Map<String, InstalledCatalogModule>> _installed(ModuleHost host) async =>
    {
      for (final row in await host.store.sql(
        'SELECT * FROM host_installations WHERE installed=1',
      ))
        row['module_id'] as String: InstalledCatalogModule(
          await host.packageSource(
            row['module_id'] as String,
            row['version'] as String,
          ),
          enabled: row['enabled'] == 1,
          repository: await host.repositoryFor(row['module_id'] as String),
        ),
    };

void main() {
  test('APK defaults resolve the real store importer and its course dependency without repository configuration', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final store = CollectionStore(db);
    final directory = await Directory.systemTemp.createTemp('default-store-');
    var host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 13, 6);
    final publishers = TrustedPublisherRegistry.fromJson(
      object(
        jsonDecode(File('assets/trusted_publishers.json').readAsStringSync()),
      ),
    );
    final bundled = (jsonDecode(
      File('assets/modules/catalog.json').readAsStringSync(),
    ) as List).map(object).toList();
    final pins = {
      for (final entry in bundled)
        entry['id'] as String: entry['sha256'] as String,
    };
    final catalogBytes = File('../packages/catalog/catalog.json')
        .readAsBytesSync();
    final catalog = ModuleCatalog.fromJson(
      jsonDecode(utf8.decode(catalogBytes)),
    );
    final sourcePackages = {
      for (final id in ['app.schedule', 'app.import.shiguang'])
        id: await _sourcePackage(id),
    };
    final requests = <Uri>[];
    final documents = <String, List<int>>{};
    final client = ModuleCatalogClient(
      cacheDirectory: Directory('${directory.path}/catalog-cache'),
      publishers: publishers,
      preinstalledDigests: pins,
      transport:
          (url, {cancellation, onProgress, required maximumBytes}) async {
            requests.add(url);
            cancellation?.check();
            final bytes = documents[url.toString()];
            if (bytes == null) {
              throw StateError('Unexpected default-store URL: $url');
            }
            expect(bytes.length, lessThanOrEqualTo(maximumBytes));
            onProgress?.call(bytes.length, bytes.length);
            return bytes;
          },
    );
    addTearDown(() async {
      client.dispose();
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });
    expect(client.repository, 'JayConstruct/xudian-modules');
    expect(
      client.catalogUrl.toString(),
      'https://raw.githubusercontent.com/JayConstruct/xudian-modules/main/catalog.json',
    );
    documents[client.catalogUrl.toString()] = catalogBytes;
    for (final package in sourcePackages.values) {
      final module = catalog.modules[package.id]!;
      final url =
          'https://github.com/${module.repository}/releases/download/'
          'default-store-fixture/${package.id}-${package.version}.xmodule';
      documents[url] = package.bytes;
      documents[module.indexUrl.toString()] = utf8.encode(
        jsonEncode({
          'indexFormat': 1,
          'moduleId': package.id,
          'repository': module.repository,
          'versions': [
            {
              'version': package.version,
              'manifest': package.manifest,
              'services': package.definition['services'],
              'url': url,
              'size': package.bytes.length,
              'sha256': package.packageDigest,
            },
          ],
        }),
      );
    }
    await host.initialize();
    expect(await store.sql('SELECT * FROM host_installations'), isEmpty);
    final defaults = bundled
        .where((entry) => entry['default'] == true)
        .toList();
    final pending = List<Map<String, Object?>>.of(defaults);
    while (pending.isNotEmpty) {
      var progress = false;
      for (final entry in List<Map<String, Object?>>.of(pending)) {
        final package = await ScriptPackage.verify(
          await File(entry['asset'] as String).readAsBytes(),
          preinstalledDigest: entry['sha256'] as String,
          publishers: publishers,
        );
        if (package.dependencies.any((id) => !host.instances.containsKey(id))) {
          continue;
        }
        await host.install(package);
        pending.remove(entry);
        progress = true;
      }
      expect(
        progress,
        isTrue,
        reason: 'The bundled default chain must be installable.',
      );
    }
    expect(host.instances.keys, containsAll(['app.tasks', 'app.views.today']));
    expect(host.instances, isNot(contains('app.schedule')));
    expect(host.instances, isNot(contains('app.import.shiguang')));
    expect(
      await store.sql(
        "SELECT value FROM host_meta WHERE key='module-catalog-repository'",
      ),
      isEmpty,
    );
    final resolution = await ModuleDependencyResolver(client).resolve(
      requests: {'app.import.shiguang': 'any'},
      installed: await _installed(host),
    );
    final changes = resolution.ordered
        .where((item) => item.action != ModuleResolutionAction.reuse)
        .toList();
    expect(changes.map((item) => item.id), [
      'app.schedule',
      'app.import.shiguang',
    ]);
    expect(
      changes.map((item) => item.action),
      everyElement(ModuleResolutionAction.install),
    );
    final packages = <ScriptPackage>[];
    for (final item in changes) {
      final package = await item.loadPackage(client);
      expect(package.packageDigest, sourcePackages[package.id]!.packageDigest);
      expect(package.trusted, isFalse);
      packages.add(package);
    }
    final plan = await host.prepareInstallBatch(
      packages,
      repositories: {for (final item in changes) item.id: item.repository!},
    );
    await host.commitInstallBatch(plan);
    expect(requests.first, client.catalogUrl);
    expect(
      requests.map((url) => url.host),
      containsAll(['raw.githubusercontent.com', 'github.com']),
    );
    expect(await host.repositoryFor('app.schedule'), 'JayConstruct/xudian');
    final immediateSchedule = object(
      await host.invokePage('app.schedule', 'render', {
        'context': {'pageId': 'app.schedule.home'},
      }),
    );
    expect(
      jsonEncode(immediateSchedule['tree']),
      contains('创建课表或导入 JSON 备份后开始使用'),
      reason: 'A fresh store install must work before restarting the APK.',
    );
    final immediateTasks = object(
      await host.invokePage('app.views.today', 'render', {
        'context': {
          'pageId': 'app.views.today.tasks',
          'selectedDate': '2026-10-13',
        },
      }),
    );
    expect(jsonEncode(immediateTasks['tree']), contains('待办事项'));
    final importer = host.instances['app.import.shiguang']!.actor;
    expect(
      object(
        await host.query(
          importer,
          const ServiceRef('app.schedule', 'schedule.query.timetables', 1),
          {},
        ),
      )['timetables'],
      isEmpty,
    );
    final importPlan = await host.prepare(
      importer,
      const ServiceRef('app.schedule', 'schedule.import.prepare', 1),
      {
        'mode': 'new',
        'draft': {
          'draftVersion': 1,
          'scope': 'default-store-compatibility',
          'adapterVersion': 'test@1',
          'complete': true,
          'timetable': {
            'name': '兼容验证',
            'firstMonday': '2026-10-12',
            'totalWeeks': 20,
            'timezone': 'Asia/Shanghai',
            'displayWeekStart': 1,
            'periods': [
              {'number': 1, 'start': '08:00', 'end': '08:45'},
            ],
          },
          'courses': [],
          'meetings': [],
          'occurrenceChanges': [],
          'warnings': [],
        },
      },
    );
    expect(importPlan.id, isNotEmpty);
    await host.close();
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    expect(host.instances.keys, containsAll(sourcePackages.keys));
    expect(host.failures, isEmpty);
    for (final package in sourcePackages.values) {
      expect(host.instances[package.id]!.package.version, package.version);
    }
    final schedule = object(
      await host.invokePage('app.schedule', 'render', {
        'context': {'pageId': 'app.schedule.home'},
      }),
    );
    expect(jsonEncode(schedule['tree']), contains('创建课表或导入 JSON 备份后开始使用'));
    final shiguang = object(
      await host.invokePage('app.import.shiguang', 'render', {
        'context': {'pageId': 'app.import.shiguang.home'},
      }),
    );
    expect(jsonEncode(shiguang['tree']), contains('按学校导入'));
    expect(jsonEncode(shiguang['tree']), contains('通用系统导入'));
  });
}
