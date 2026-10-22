import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../module_catalog/catalog_providers.dart';
import '../module_host/host_api.dart';
import '../module_host/host_providers.dart';
import 'app_update_channel.dart';
import 'github_app_updates.dart';
import 'startup_update_preference.dart';

class ModuleUpdateSummary {
  const ModuleUpdateSummary(this.updates, {this.incomplete = false});
  final Map<String, String> updates;
  // Individual failed indexes cannot establish freshness.
  final bool incomplete;
}

final startupAppCheckProvider = Provider<Future<AppUpdateResult> Function()>(
  (ref) => () async {
    final channel = await ref.read(appUpdateChannelProvider.future);
    final installed = await ref.read(installedAppVersionProvider.future);
    return ref
        .read(githubAppUpdatesProvider)
        .check(
          installed,
          ref.read(appUpdatePlatformProvider),
          channel: channel,
        );
  },
);

final startupModuleCheckProvider =
    Provider<Future<ModuleUpdateSummary> Function()>(
      (ref) => () async {
        final host = await ref.read(moduleHostProvider.future);
        // Include disabled modules, without loading/verifying package archives.
        final installed = await host.store.sql('''
      SELECT i.module_id, i.version, r.value AS repository
      FROM host_installations i
      LEFT JOIN host_meta r ON r.key='module-repository:' || i.module_id
      WHERE i.installed=1
    ''');
        if (installed.isEmpty) return const ModuleUpdateSummary({});
        final client = await ref.read(moduleCatalogClientProvider.future);
        final catalog = await client.loadCatalog(allowCacheFallback: false);
        var incomplete = false;
        final updates = <String, String>{};
        final pending = installed.iterator;
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        Future<void> worker() async {
          while (ref.mounted &&
              DateTime.now().isBefore(deadline) &&
              pending.moveNext()) {
            final row = pending.current;
            final id = row['module_id'] as String;
            final item = catalog.modules[id];
            if (item == null) continue;
            final repository = row['repository'] as String?;
            if (repository != null &&
                repository.toLowerCase() != item.repository.toLowerCase()) {
              continue;
            }
            try {
              final index = await client.loadIndex(
                item,
                allowCacheFallback: false,
              );
              final current = Version.parse(row['version'] as String);
              final latest = index.versions.where((release) {
                final version = Version.parse(release.version);
                return !version.isPreRelease &&
                    version > current &&
                    VersionConstraint.parse(
                      release.manifest['hostApi'] as String,
                    ).allows(hostApiVersion);
              }).firstOrNull;
              if (latest != null) {
                updates[id] = '${item.name} ${latest.version}';
              }
            } catch (_) {
              incomplete = true;
            }
          }
        }

        await Future.wait([for (var i = 0; i < 3; i++) worker()]);
        return ModuleUpdateSummary(
          Map.unmodifiable(updates),
          incomplete: incomplete,
        );
      },
    );

class StartupUpdateState {
  const StartupUpdateState({
    this.checking = false,
    this.app,
    this.modules,
    this.appFailed = false,
    this.modulesFailed = false,
  });
  final bool checking, appFailed, modulesFailed;
  final AppUpdateResult? app;
  final ModuleUpdateSummary? modules;
  bool get hasUpdates =>
      app?.updateAvailable == true || modules?.updates.isNotEmpty == true;
}

final startupUpdatesProvider =
    NotifierProvider<StartupUpdates, StartupUpdateState>(StartupUpdates.new);

/// A provider-scope lifetime matches a cold Dart launch. Rebuilds, preference
/// changes, navigation and background/resume never schedule another check.
class StartupUpdates extends Notifier<StartupUpdateState> {
  bool _attempted = false;

  @override
  StartupUpdateState build() => const StartupUpdateState();

  Future<bool> start() async {
    if (_attempted) return false;
    _attempted = true;
    try {
      if (!await ref.read(startupUpdateEnabledProvider.future) ||
          !ref.mounted) {
        return false;
      }
    } catch (_) {
      return false; // Preference read errors must never affect startup.
    }
    state = const StartupUpdateState(checking: true);
    AppUpdateResult? app;
    ModuleUpdateSummary? modules;
    var appFailed = false, modulesFailed = false;
    await Future.wait([
      () async {
        try {
          app = await ref
              .read(startupAppCheckProvider)()
              .timeout(const Duration(seconds: 30));
        } catch (_) {
          appFailed = true;
        }
      }(),
      () async {
        try {
          modules = await ref
              .read(startupModuleCheckProvider)()
              .timeout(const Duration(seconds: 30));
        } catch (_) {
          modulesFailed = true;
        }
      }(),
    ]);
    if (!ref.mounted) return false;
    state = StartupUpdateState(
      app: app,
      modules: modules,
      appFailed: appFailed,
      modulesFailed: modulesFailed,
    );
    return true;
  }
}
