import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/app_database.dart';
import '../declarative_module.dart';
import '../package/module_install_provenance.dart';

class DeclarativeModuleStore {
  DeclarativeModuleStore(this.db);

  final AppDatabase db;

  Future<void> install(
    DeclarativeModule module,
    Map<String, Object?> source, {
    ModuleInstallProvenance? provenance,
  }) async {
    final now = DateTime.now();
    final encoded = _canonicalEncode(source);
    final existingVersion = await (db.select(db.moduleVersions)
          ..where((row) =>
              row.moduleId.equals(module.manifest.id) &
              row.version.equals(module.manifest.version)))
        .getSingleOrNull();

    if (existingVersion != null && existingVersion.sourceJson != encoded) {
      throw StateError(
        'Module ${module.manifest.id} version '
        '${module.manifest.version} is immutable',
      );
    }

    final current = await (db.select(db.moduleInstallations)
          ..where((row) => row.id.equals(module.manifest.id)))
        .getSingleOrNull();
    final effectiveProvenance = provenance ??
        (existingVersion != null
            ? _versionProvenance(existingVersion)
            : current == null
                ? const ModuleInstallProvenance()
                : ModuleInstallProvenance(
                    origin: current.origin,
                    publisherId: current.publisherId,
                    packageDigest: current.packageDigest,
                    reviewId: current.reviewId,
                    signatureKeyId: current.signatureKeyId,
                  ));

    if (existingVersion != null && provenance != null) {
      final stored = _versionProvenance(existingVersion);
      if (!_sameProvenance(stored, provenance)) {
        throw StateError(
          'Module ${module.manifest.id} version '
          '${module.manifest.version} provenance is immutable',
        );
      }
    }

    await db.transaction(() async {
      if (existingVersion == null) {
        await db.into(db.moduleVersions).insert(
              ModuleVersion(
                moduleId: module.manifest.id,
                version: module.manifest.version,
                sourceJson: encoded,
                origin: effectiveProvenance.origin,
                publisherId: effectiveProvenance.publisherId,
                packageDigest: effectiveProvenance.packageDigest,
                reviewId: effectiveProvenance.reviewId,
                signatureKeyId: effectiveProvenance.signatureKeyId,
                installedAt: now,
              ),
            );
      }

      await db.into(db.moduleInstallations).insertOnConflictUpdate(
            ModuleInstallation(
              id: module.manifest.id,
              version: module.manifest.version,
              sourceJson: encoded,
              installed: true,
              enabled: true,
              origin: effectiveProvenance.origin,
              publisherId: effectiveProvenance.publisherId,
              packageDigest: effectiveProvenance.packageDigest,
              reviewId: effectiveProvenance.reviewId,
              signatureKeyId: effectiveProvenance.signatureKeyId,
              installedAt: current?.installedAt ?? now,
              updatedAt: now,
            ),
          );

      await (db.update(db.fieldDefinitions)
            ..where((row) => row.moduleId.equals(module.manifest.id)))
          .write(const FieldDefinitionsCompanion(active: Value(false)));

      await _activateFields(module, now);
    });
  }

  Future<void> _activateFields(
    DeclarativeModule module,
    DateTime now,
  ) async {
    for (final field in module.fields) {
      final id = field['id'] as String;
      final type = field['type'];
      final label = field['label'];
      if (type is! String || label is! String) {
        throw FormatException('Field $id requires type and label');
      }
      if (!const {
        'text', 'number', 'boolean', 'date',
        'datetime', 'select', 'multiSelect',
      }.contains(type)) {
        throw FormatException('Unsupported field type: $type');
      }

      final key = '${module.manifest.id}:$id';
      final existing = await (db.select(db.fieldDefinitions)
            ..where((row) => row.key.equals(key)))
          .getSingleOrNull();
      await db.into(db.fieldDefinitions).insertOnConflictUpdate(
            FieldDefinition(
              key: key,
              moduleId: module.manifest.id,
              resourceId: id,
              label: label,
              type: type,
              configJson: jsonEncode(field['config'] ?? const {}),
              active: true,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
    }
  }
  Future<List<ModuleVersion>> listVersions(String moduleId) =>
      (db.select(db.moduleVersions)
            ..where((row) => row.moduleId.equals(moduleId))
            ..orderBy([(row) => OrderingTerm.desc(row.installedAt)]))
          .get();

  Future<ModuleInstallProvenance> versionProvenance(
    String moduleId,
    String version,
  ) async {
    final row = await (db.select(db.moduleVersions)
          ..where((item) =>
              item.moduleId.equals(moduleId) &
              item.version.equals(version)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Unknown module version: $moduleId@$version');
    }
    return _versionProvenance(row);
  }

  Future<Map<String, Object?>> versionSource(
    String moduleId,
    String version,
  ) async {
    final row = await (db.select(db.moduleVersions)
          ..where((item) =>
              item.moduleId.equals(moduleId) &
              item.version.equals(version)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Unknown module version: $moduleId@$version');
    }
    final decoded = jsonDecode(row.sourceJson);
    if (decoded is! Map) {
      throw StateError('Stored module version is invalid');
    }
    return decoded.map((key, value) => MapEntry('$key', value));
  }

  Future<void> setEnabled(String moduleId, bool enabled) async {
    final current = await getInstalled(moduleId);
    if (current == null || !current.installed) {
      throw StateError('Module not installed: $moduleId');
    }
    await db.transaction(() async {
      await (db.update(db.moduleInstallations)
            ..where((row) => row.id.equals(moduleId)))
          .write(
        ModuleInstallationsCompanion(
          enabled: Value(enabled),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (!enabled) {
        await (db.update(db.fieldDefinitions)
              ..where((row) => row.moduleId.equals(moduleId)))
            .write(
          const FieldDefinitionsCompanion(active: Value(false)),
        );
      }
    });
  }

  Future<void> uninstall(
    String moduleId, {
    bool deleteData = false,
  }) async {
    final current = await getInstalled(moduleId);
    if (current == null) return;

    await db.transaction(() async {
      if (!deleteData) {
        await (db.update(db.moduleInstallations)
              ..where((row) => row.id.equals(moduleId)))
            .write(
          ModuleInstallationsCompanion(
            installed: const Value(false),
            enabled: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await (db.update(db.fieldDefinitions)
              ..where((row) => row.moduleId.equals(moduleId)))
            .write(
          const FieldDefinitionsCompanion(active: Value(false)),
        );
        return;
      }

      final definitions = await (db.select(db.fieldDefinitions)
            ..where((row) => row.moduleId.equals(moduleId)))
          .get();
      final keys = definitions.map((item) => item.key).toList();
      if (keys.isNotEmpty) {
        await (db.delete(db.fieldValues)
              ..where((row) => row.fieldKey.isIn(keys)))
            .go();
      }
      await (db.delete(db.fieldDefinitions)
            ..where((row) => row.moduleId.equals(moduleId)))
          .go();
      await (db.delete(db.moduleVersions)
            ..where((row) => row.moduleId.equals(moduleId)))
          .go();
      await (db.delete(db.ruleExecutions)
            ..where((row) => row.moduleId.equals(moduleId)))
          .go();
      await (db.delete(db.moduleInstallations)
            ..where((row) => row.id.equals(moduleId)))
          .go();
    });
  }

  ModuleInstallProvenance _versionProvenance(
    ModuleVersion version,
  ) {
    return ModuleInstallProvenance(
      origin: version.origin,
      publisherId: version.publisherId,
      packageDigest: version.packageDigest,
      reviewId: version.reviewId,
      signatureKeyId: version.signatureKeyId,
    );
  }

  bool _sameProvenance(
    ModuleInstallProvenance a,
    ModuleInstallProvenance b,
  ) {
    return a.origin == b.origin &&
        a.publisherId == b.publisherId &&
        a.packageDigest == b.packageDigest &&
        a.reviewId == b.reviewId &&
        a.signatureKeyId == b.signatureKeyId;
  }

  String _canonicalEncode(Object? value) =>
      jsonEncode(_normalize(value));

  Object? _normalize(Object? value) {
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry('${entry.key}', entry.value))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return {
        for (final entry in entries)
          entry.key: _normalize(entry.value),
      };
    }
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }

  Future<ModuleInstallation?> getInstalled(String moduleId) =>
      (db.select(db.moduleInstallations)
            ..where((row) => row.id.equals(moduleId)))
          .getSingleOrNull();

  Future<List<ModuleInstallation>> listInstalled() =>
      db.select(db.moduleInstallations).get();
}
