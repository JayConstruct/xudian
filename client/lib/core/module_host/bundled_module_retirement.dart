import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'module_host.dart';

final retiredBundledModuleIdsProvider = FutureProvider<Set<String>>((
  ref,
) async {
  final ids = jsonDecode(
    await rootBundle.loadString('assets/modules/retired.json'),
  ) as List;
  return Set<String>.unmodifiable(ids.cast<String>());
});

/// Remove withdrawn defaults once, retaining data, packages and user recovery.
Future<void> retireBundledModules(
  ModuleHost host,
  Iterable<String> moduleIds,
) async {
  for (final id in moduleIds.toSet()) {
    final marker = 'retired-bundle:$id';
    if ((await host.store.sql('SELECT value FROM host_meta WHERE key=?', [
      marker,
    ])).isNotEmpty) {
      continue;
    }
    final rows = await host.store.sql(
      'SELECT installed FROM host_installations WHERE module_id=?',
      [id],
    );
    if (rows.isNotEmpty && rows.single['installed'] == 1) {
      await host.uninstall(id, cascade: true, deleteData: false);
    }
    await host.store.db.customStatement(
      'INSERT OR IGNORE INTO host_meta(key,value) VALUES(?,?)',
      [marker, 'complete'],
    );
  }
}
