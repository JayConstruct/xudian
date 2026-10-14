import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/bundled_module_retirement.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

import 'ui_pack_lifecycle_test.dart' as fixture;

class _StartupQueries extends QueryInterceptor {
  final selects = <String>[];
  final writes = <String>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add(statement);
    return executor.runSelect(statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    writes.add(statement);
    return executor.runCustom(statement, args);
  }

  void reset() {
    selects.clear();
    writes.clear();
  }
}

class _CountedFile implements File {
  _CountedFile(this.file, this.onRead);
  final File file;
  final void Function() onRead;

  @override
  Future<Uint8List> readAsBytes() {
    onRead();
    return file.readAsBytes();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _StartupQueries queries;
  late CollectionStore store;
  late Directory directory;
  late ModuleHost host;

  setUp(() async {
    queries = _StartupQueries();
    db = AppDatabase(NativeDatabase.memory().interceptWith(queries));
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('module-startup-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<void> seed(ScriptPackage package) async {
    await File('${directory.path}/${package.packageDigest}.xmodule')
        .writeAsBytes(package.bytes);
    await db.customStatement(
      'INSERT INTO host_packages VALUES(?,?,?,?,?,?,?)',
      [
        package.id,
        package.version,
        package.packageDigest,
        package.origin,
        jsonEncode(package.release),
        jsonEncode(package.definition),
        DateTime.now().toIso8601String(),
      ],
    );
    await db.customStatement(
      'INSERT INTO host_installations VALUES(?,?,?,?,?,?,?,?)',
      [package.id, package.version, '${package.id}-space', 1, 1, 1, 1, null],
    );
  }

  Future<Map<String, int>> restart() async {
    await host.close();
    host = ModuleHost(store: store, directory: directory);
    final reads = <String, int>{};
    final parent = Zone.current;
    await IOOverrides.runZoned(
      host.initialize,
      createFile: (path) {
        final file = parent.run(() => File(path));
        if (!path.endsWith('.xmodule')) return file;
        return _CountedFile(
          file,
          () => reads.update(path, (count) => count + 1, ifAbsent: () => 1),
        );
      },
    );
    return reads;
  }

  test(
    'dependency retries read each package once and later starts revalidate',
    () async {
      final a = await fixture.uiPackage(id: 'test.a');
      final b = await fixture.uiPackage(id: 'test.b', dependencies: [a.id]);
      final c = await fixture.uiPackage(id: 'test.c', dependencies: [b.id]);
      // The database deliberately enumerates dependents before their providers.
      for (final package in [c, b, a]) {
        await seed(package);
      }
      for (var start = 0; start < 2; start++) {
        queries.reset();
        final reads = await restart();
        expect(
          queries.selects.where(
            (sql) => sql.contains('LEFT JOIN host_packages'),
          ),
          hasLength(1),
        );
        expect(
          queries.selects.where(
            (sql) => sql.startsWith(
              'SELECT * FROM host_packages WHERE module_id=? AND version=?',
            ),
          ),
          isEmpty,
          reason: 'Restore reads provenance with installations once',
        );
        expect(reads, hasLength(3));
        expect(reads.values, everyElement(1));
        expect(host.instances.keys.toList(), [a.id, b.id, c.id]);
        expect(
          host.instances.values.map((instance) => instance.package.origin),
          everyElement('local'),
          reason: 'Persisted provenance remains the source of package origin',
        );
        expect(host.failures, isEmpty);
      }
      await File('${directory.path}/${a.packageDigest}.xmodule')
          .writeAsBytes([0, 1, 2]);
      final reads = await restart();
      expect(reads.values, everyElement(1));
      expect(host.instances, isEmpty);
      expect(host.failures.keys, containsAll([a.id, b.id, c.id]));
      expect(
        (await store.sql('SELECT enabled FROM host_installations'))
            .map((row) => row['enabled']),
        everyElement(0),
      );
    },
  );

  test(
    'missing, circular and incompatible dependencies keep failure semantics',
    () async {
      final packages = [
        await fixture.uiPackage(id: 'test.a', dependencies: ['test.b']),
        await fixture.uiPackage(id: 'test.b', dependencies: ['test.a']),
        await fixture.uiPackage(
          id: 'test.missing',
          dependencies: ['test.absent'],
        ),
        await fixture.uiPackage(id: 'test.provider'),
        await fixture.uiPackage(
          id: 'test.versioned',
          dependencies: [
            {'moduleId': 'test.provider', 'version': '^2.0.0'},
          ],
        ),
      ];
      for (final package in packages) {
        await seed(package);
      }
      final reads = await restart();
      expect(reads, hasLength(packages.length));
      expect(reads.values, everyElement(1));
      expect(host.instances.keys, ['test.provider']);
      expect(host.failures['test.a'], 'Missing or circular dependency');
      expect(host.failures['test.b'], 'Missing or circular dependency');
      expect(host.failures['test.missing'], contains('Missing dependency'));
      expect(
        host.failures['test.versioned'],
        contains('Incompatible dependency'),
      );
    },
  );

  test(
    'missing provenance and identity mismatches retain restore failures',
    () async {
      final missing = await fixture.uiPackage(id: 'test.provenance.missing');
      final wrongId = await fixture.uiPackage(id: 'test.provenance.identity');
      final wrongVersion = await fixture.uiPackage(
        id: 'test.provenance.version',
      );
      final replacement = await fixture.uiPackage(id: 'test.provenance.other');
      for (final package in [missing, wrongId, wrongVersion, replacement]) {
        await seed(package);
      }
      await db.customStatement('DELETE FROM host_packages WHERE module_id=?', [
        missing.id,
      ]);
      await db.customStatement(
        'UPDATE host_packages SET digest=? WHERE module_id=?',
        [replacement.packageDigest, wrongId.id],
      );
      await db.customStatement(
        'UPDATE host_packages SET version=? WHERE module_id=?',
        ['2.0.0', wrongVersion.id],
      );
      await db.customStatement(
        'UPDATE host_installations SET version=? WHERE module_id=?',
        ['2.0.0', wrongVersion.id],
      );
      await db.customStatement(
        'UPDATE host_installations SET enabled=0 WHERE module_id=?',
        [replacement.id],
      );
      queries.reset();
      final reads = await restart();
      expect(host.instances, isEmpty);
      expect(host.failures[missing.id], 'Bad state: No element');
      expect(
        host.failures[wrongId.id],
        'Bad state: Stored package identity mismatch',
      );
      expect(
        host.failures[wrongVersion.id],
        'Bad state: Stored package identity mismatch',
      );
      expect(reads, hasLength(2));
      expect(reads.values, everyElement(1));
      expect(
        queries.selects.where((sql) => sql.contains('LEFT JOIN host_packages')),
        hasLength(1),
      );
      expect(
        (await store.sql('SELECT enabled FROM host_installations'))
            .map((row) => row['enabled']),
        everyElement(0),
      );
    },
  );

  for (final emptyCatalog in [false, true]) {
    test(
      emptyCatalog ? 'empty bundled catalog does not run repository backfill' : 'repository backfill uses one statement and preserves stored sources',
      () async {
        final preinstalled = await fixture.uiPackage(
          id: 'test.repository.bundled',
        );
        final existing = await fixture.uiPackage(
          id: 'test.repository.existing',
        );
        final local = await fixture.uiPackage(id: 'test.repository.local');
        final absent = await fixture.uiPackage(id: 'test.repository.absent');
        for (final package in [preinstalled, existing, local]) {
          await seed(package);
        }
        await db.customStatement('UPDATE host_installations SET enabled=0');
        await db.customStatement(
          "UPDATE host_packages SET origin='preinstalled' WHERE module_id IN (?,?)",
          [preinstalled.id, existing.id],
        );
        await db.customStatement(
          'INSERT INTO host_meta(key,value) VALUES(?,?)',
          ['module-repository:${existing.id}', 'User/custom-repository'],
        );
        await db.customStatement(
          "INSERT INTO host_meta VALUES('defaults-v3','complete')",
        );
        await db.customStatement(
          "INSERT INTO host_meta VALUES('legacy-packages-v1','complete')",
        );
        final catalog = [
          if (!emptyCatalog)
            for (final package in [
              preinstalled,
              existing,
              local,
              absent,
              preinstalled,
            ])
              {'id': package.id, 'default': false},
        ];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
        messenger.setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          if (key != 'assets/modules/catalog.json') return null;
          return Uint8List.fromList(utf8.encode(jsonEncode(catalog))).buffer
              .asByteData();
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(paths, null);
          messenger.setMockMessageHandler('flutter/assets', null);
          rootBundle.evict('assets/modules/catalog.json');
        });
        for (var start = 0; start < 2; start++) {
          rootBundle.evict('assets/modules/catalog.json');
          final container = ProviderContainer(
            overrides: [
              databaseProvider.overrideWith((_) async => db),
              retiredBundledModuleIdsProvider.overrideWith((_) async => {}),
            ],
          );
          try {
            queries.reset();
            final restored = await container.read(moduleHostProvider.future);
            expect(
              await restored.repositoryFor(preinstalled.id),
              emptyCatalog ? isNull : 'JayConstruct/xudian',
            );
            expect(
              await restored.repositoryFor(existing.id),
              'User/custom-repository',
            );
            expect(await restored.repositoryFor(local.id), isNull);
            expect(await restored.repositoryFor(absent.id), isNull);
            expect(
              queries.writes.where(
                (sql) => sql.contains("'module-repository:' || module_id"),
              ),
              hasLength(emptyCatalog ? 0 : 1),
            );
            expect(restored.failures, isEmpty);
          } finally {
            container.dispose();
          }
        }
      },
    );
  }

  test('first default installation loads each bundled asset once', () async {
    final a = await fixture.uiPackage(id: 'test.default.a');
    final b = await fixture.uiPackage(
      id: 'test.default.b',
      dependencies: [a.id],
    );
    final c = await fixture.uiPackage(
      id: 'test.default.c',
      dependencies: [b.id],
    );
    final packages = [c, b, a];
    final catalog = [
      for (final package in packages)
        {
          'id': package.id,
          'asset': 'assets/startup/${package.id}.xmodule',
          'sha256': package.packageDigest,
          'default': true,
        },
    ];
    final assets = <String, Uint8List>{
      'assets/modules/catalog.json': Uint8List.fromList(
        utf8.encode(jsonEncode(catalog)),
      ),
      for (final package in packages)
        'assets/startup/${package.id}.xmodule': package.bytes,
    };
    final reads = <String, int>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      reads.update(key, (count) => count + 1, ifAbsent: () => 1);
      return assets[key]?.buffer.asByteData();
    });
    rootBundle.evict('assets/modules/catalog.json');
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((_) async => db),
        retiredBundledModuleIdsProvider.overrideWith((_) async => {}),
      ],
    );
    addTearDown(() {
      container.dispose();
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMessageHandler('flutter/assets', null);
      rootBundle.evict('assets/modules/catalog.json');
    });
    final restored = await container.read(moduleHostProvider.future);
    expect(restored.instances.keys.toList(), [a.id, b.id, c.id]);
    for (final entry in catalog) {
      expect(reads[entry['asset']], 1);
    }
    expect(restored.failures, isEmpty);
  });
}
