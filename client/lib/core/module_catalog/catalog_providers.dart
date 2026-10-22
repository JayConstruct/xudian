import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../module_host/host_providers.dart';
import '../module_host/bundled_module_retirement.dart';
import '../module_host/module_package.dart';
import 'module_catalog.dart';

final moduleCatalogClientProvider = FutureProvider<ModuleCatalogClient>((
  ref,
) async {
  final host = await ref.watch(moduleHostProvider.future);
  final rows = await host.store.sql(
    "SELECT value FROM host_meta WHERE key='module-catalog-repository'",
  );
  final bundled = jsonDecode(
    await rootBundle.loadString('assets/modules/catalog.json'),
  ) as List;
  final client = ModuleCatalogClient(
    cacheDirectory: Directory('${host.directory.path}/catalog-cache'),
    publishers: await ref.watch(hostPublisherRegistryProvider.future),
    excludedModuleIds: await ref.watch(retiredBundledModuleIdsProvider.future),
    preinstalledDigests: {
      for (final raw in bundled)
        object(raw)['id'] as String: object(raw)['sha256'] as String,
    },
    repository: rows.isEmpty
        ? 'JayConstruct/xudian-modules'
        : rows.first['value'] as String,
  );
  ref.onDispose(client.dispose);
  return client;
});
