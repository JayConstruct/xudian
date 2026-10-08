import '../modules/module_registry.dart';
import '../security/capability_registry.dart';
import 'script_app_module.dart';
import 'host_manager_page.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/providers.dart';
import '../declarative/package/module_package.dart';
import 'collection_store.dart';
import 'legacy_migration.dart';
import 'module_host.dart';
import 'module_package.dart';

final moduleHostProvider = FutureProvider<ModuleHost>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final support = await getApplicationSupportDirectory();
  final store = CollectionStore(db);
  final host = ModuleHost(
    store: store,
    directory: Directory('${support.path}/modules-v3'),
  );
  host.validateCandidate = (candidate) {
    final registry = ModuleRegistry([
      HostManagerModule(),
      for (final entry in host.instances.entries)
        if (entry.key != candidate.id)
          ScriptAppModule(host, entry.value.package),
      ScriptAppModule(host, candidate),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
    registry.dispose();
  };
  ref.onDispose(() {
    host.close();
    store.close();
  });
  await host.initialize();
  final catalog = (jsonDecode(
    await rootBundle.loadString('assets/modules/catalog.json'),
  ) as List).map(object).toList();
  // Bundled identities retain the author repository even on older installs.
  for (final entry in catalog) {
    await store.db.customStatement(
      '''INSERT OR IGNORE INTO host_meta(key,value)
      SELECT ?,? WHERE EXISTS(SELECT 1 FROM host_packages
      WHERE module_id=? AND origin='preinstalled')''',
      ['module-repository:${entry['id']}', 'JayConstruct/xudian', entry['id']],
    );
  }
  final marker = await store.sql(
    "SELECT value FROM host_meta WHERE key='defaults-v3'",
  );
  if (marker.isEmpty) {
    final settings = {
      for (final row in await db.select(db.appSettings).get())
        row.key: row.value,
    };
    final pending = catalog
        .where(
          (entry) =>
              entry['default'] == true ||
              settings['modules.builtin.${entry['id']}'] == 'true',
        )
        .toList();
    while (pending.isNotEmpty) {
      var progress = false;
      for (final entry in pending.toList()) {
        final asset = await rootBundle.load(entry['asset'] as String);
        final package = await ScriptPackage.verify(
          asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
          preinstalledDigest: entry['sha256'] as String,
        );
        if (package.dependencies.any(
          (id) => pending.any((v) => v['id'] == id),
        )) {
          continue;
        }
        final current = await store.sql(
          'SELECT installed FROM host_installations WHERE module_id=?',
          [package.id],
        );
        if (current.isEmpty) {
          try {
            await host.install(package);
            await store.db.customStatement(
              'INSERT OR IGNORE INTO host_meta(key,value) VALUES(?,?)',
              ['module-repository:${package.id}', 'JayConstruct/xudian'],
            );
            if (settings['modules.builtin.${package.id}'] == 'false') {
              await host.disable(package.id, cascade: true);
            }
          } catch (error) {
            host.failures[package.id] = '$error';
          }
        }
        pending.remove(entry);
        progress = true;
      }
      if (!progress) throw StateError('Default package dependency cycle');
    }
    await db.customStatement(
      "INSERT INTO host_meta VALUES('defaults-v3','complete')",
    );
  }
  await migrateLegacyInstallations(host);
  return host;
});

final hostPublisherRegistryProvider = FutureProvider<TrustedPublisherRegistry>(
  (ref) async => TrustedPublisherRegistry.fromJson(
    object(
      jsonDecode(await rootBundle.loadString('assets/trusted_publishers.json')),
    ),
  ),
);
