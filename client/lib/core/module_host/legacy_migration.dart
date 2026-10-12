import 'dart:convert';
import 'dart:io';

import '../contracts/json_values.dart';
import 'module_host.dart';
import 'legacy_converter.dart';
import 'module_package.dart';

export 'legacy_data_migration.dart';

Future<void> migrateLegacyInstallations(ModuleHost host) async {
  final store = host.store;
  if ((await store.sql(
    "SELECT value FROM host_meta WHERE key='legacy-packages-v1'",
  )).isNotEmpty) {
    return;
  }
  final rows = await store.db.select(store.db.moduleInstallations).get();
  final pending = {for (final row in rows) row.id: row};
  while (pending.isNotEmpty) {
    var progress = false;
    for (final id in pending.keys.toList()) {
      final row = pending[id]!;
      if (await host.wasErased(id)) {
        pending.remove(id);
        progress = true;
        continue;
      }
      try {
        final source = object(jsonDecode(row.sourceJson));
        final dependencies =
            (object(source['manifest'])['dependencies'] as List? ?? [])
                .cast<String>();
        if (dependencies.any(pending.containsKey)) continue;
        final existing = await store.sql(
          'SELECT module_id FROM host_installations WHERE module_id=?',
          [id],
        );
        if (existing.isEmpty) {
          await host.install(await convertLegacyModule(source));
          if (!row.installed) {
            await host.uninstall(id, cascade: true);
          } else if (!row.enabled) {
            await host.disable(id, cascade: true);
          }
        }
        pending.remove(id);
        progress = true;
      } catch (error) {
        host.failures[id] = 'Legacy conversion: $error';
        await store.db.customStatement(
          'INSERT OR REPLACE INTO host_meta VALUES(?,?)',
          ['legacy-error:$id', '$error'],
        );
        pending.remove(id);
        progress = true;
      }
    }
    if (!progress) {
      for (final id in pending.keys) {
        host.failures[id] = 'Legacy dependency cycle';
      }
      break;
    }
  }
  // Every historical source uses the same deterministic converter as the
  // active source. Explicitly erased identities must not be restored.
  for (final row in await store.db.select(store.db.moduleVersions).get()) {
    if (await host.wasErased(row.moduleId)) continue;
    try {
      final derived = await convertLegacyModule(
        object(jsonDecode(row.sourceJson)),
      );
      final blob = File(
        '${host.directory.path}/${derived.packageDigest}.xmodule',
      );
      if (!await blob.exists()) {
        await blob.writeAsBytes(derived.bytes, flush: true);
      }
      await store.db.customStatement(
        'INSERT OR IGNORE INTO host_packages VALUES(?,?,?,?,?,?,?)',
        [
          derived.id,
          derived.version,
          derived.packageDigest,
          derived.origin,
          canonicalJson(derived.release),
          canonicalJson(derived.definition),
          row.installedAt.toUtc().toIso8601String(),
        ],
      );
      await store.db.customStatement(
        'INSERT OR IGNORE INTO host_meta VALUES(?,?)',
        [
          'legacy-source:${row.moduleId}:${row.version}',
          canonicalJson(row.toJson()),
        ],
      );
    } catch (error) {
      host.failures['${row.moduleId}@${row.version}'] =
          'Historical conversion: $error';
    }
  }
  await store.db.customStatement(
    "INSERT INTO host_meta VALUES('legacy-packages-v1','complete')",
  );
}
