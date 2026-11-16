import 'module_host.dart';
import 'module_package.dart';

/// Display metadata and the verified package for one persisted installation.
class ModuleInstallationSnapshot {
  const ModuleInstallationSnapshot(this.package, this.row);

  final ScriptPackage package;
  final Map<String, Object?> row;
  bool get installed => row['installed'] == 1;
  bool get enabled => row['enabled'] == 1;
  String? get repository => row['repository'] as String?;
}

/// A fresh joined read keeps status and provenance current. Display callers may
/// reuse immutable verified objects; installation callers retain full disk
/// verification by leaving [reuseVerified] disabled.
Future<Map<String, ModuleInstallationSnapshot>> readModuleInstallations(
  ModuleHost host, {
  Map<String, ScriptPackage> verified = const {},
  bool reuseVerified = false,
  String? retainedModuleId,
  bool Function()? isCurrent,
}) async {
  void checkCurrent() {
    if (isCurrent != null && !isCurrent()) {
      throw StateError('模块详情已关闭或宿主已变化');
    }
  }

  checkCurrent();
  final rows = await host.store.sql(
    '''
    SELECT installations.*, packages.digest, packages.origin,
           repositories.value AS repository
    FROM host_installations AS installations
    LEFT JOIN host_packages AS packages
      ON packages.module_id=installations.module_id
      AND packages.version=installations.version
    LEFT JOIN host_meta AS repositories
      ON repositories.key='module-repository:' || installations.module_id
    WHERE installations.installed=1${retainedModuleId == null ? '' : ' OR installations.module_id=?'}
  ''',
    [?retainedModuleId],
  );
  checkCurrent();
  final result = <String, ModuleInstallationSnapshot>{};
  for (final row in rows) {
    checkCurrent();
    final id = row['module_id'] as String;
    final version = row['version'] as String;
    bool matches(ScriptPackage candidate) =>
        candidate.id == id &&
        candidate.version == version &&
        candidate.packageDigest == row['digest'] &&
        candidate.origin == row['origin'];
    final candidates = reuseVerified
        ? [host.instances[id]?.package, verified[id]]
        : const <ScriptPackage?>[];
    final cached = candidates
        .whereType<ScriptPackage>()
        .where(matches)
        .firstOrNull;
    final package = cached ?? await host.packageSource(id, version);
    checkCurrent();
    if (!matches(package)) {
      throw StateError('模块安装状态已变化，请重新读取：$id');
    }
    result[id] = ModuleInstallationSnapshot(package, Map.unmodifiable(row));
  }
  return result;
}
