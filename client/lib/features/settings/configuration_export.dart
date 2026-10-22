import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/module_host/host_providers.dart';
import '../../core/platform/json_file_saver.dart';
import '../../core/ui/ui_pack.dart';
import '../../data/app_database.dart';
import 'app_preferences.dart';
import 'ui_layout.dart';

final configurationExporterProvider = FutureProvider<ConfigurationExporter>((
  ref,
) async {
  final host = await ref.watch(moduleHostProvider.future);
  return ConfigurationExporter(host.store.db);
});

final configurationFileSaverProvider = Provider((_) => JsonFileSaver());

/// Reads one database snapshot without changing settings or module lifecycle.
class ConfigurationExporter {
  ConfigurationExporter(this.db, {FlutterSecureStorage? secureStorage})
    : secureStorage = secureStorage ?? const FlutterSecureStorage();

  final AppDatabase db;
  final FlutterSecureStorage secureStorage;

  Future<Map<String, Object?>> capture({
    bool includeSecrets = false,
    bool annotationEnabled = false,
    DateTime? now,
  }) async {
    final result = await db.transaction(() async {
      final settings = <String, Object?>{
        'ui.preferences': const AppPreferences().toJson(),
        'ui.layout': UiLayout().toJson(),
        'ui.selection': UiSelection().toJson(),
        'app.updateChannel': 'stable',
        'app.checkUpdatesOnStartup': 'false',
      };
      for (final row in await db.select(db.appSettings).get()) {
        if (const {
          'device_id',
          'operation_counter',
          'ai.assistant.history',
        }.contains(row.key)) {
          continue;
        }
        settings[row.key] = _settingValue(row.key, row.value);
      }
      final installations = await db.customSelect('''
        SELECT i.module_id, i.version, i.space, i.data_version,
          i.installed, i.enabled, p.digest, p.origin, p.definition
        FROM host_installations i LEFT JOIN host_packages p
          ON p.module_id=i.module_id AND p.version=i.version
        ORDER BY i.module_id
      ''').get();
      final metadata = await db.customSelect('''
        SELECT key,value FROM host_meta
        WHERE key='module-catalog-repository'
          OR substr(key,1,18)='module-repository:'
          OR substr(key,1,11)='credential:' ORDER BY key
      ''').get();
      final preferences = await db.customSelect('''
        SELECT module_id,key,value FROM host_ui_preferences
        ORDER BY module_id,key
      ''').get();
      final declarations = await db.customSelect('''
        SELECT c.module_id,c.space,c.name,c.definition
        FROM host_collections c JOIN host_installations i
          ON c.module_id=i.module_id AND c.space=i.space
        ORDER BY c.module_id,c.name
      ''').get();
      final configurationCollections = <String, List<String>>{};
      final records = <Map<String, Object?>>[];
      for (final declaration in declarations) {
        final definition =
            jsonDecode(declaration.read<String>('definition')) as Map;
        if (definition['configuration'] != true) continue;
        final moduleId = declaration.read<String>('module_id');
        final collection = declaration.read<String>('name');
        configurationCollections
            .putIfAbsent(moduleId, () => [])
            .add(collection);
        final rows = await db
            .customSelect(
              'SELECT id,value FROM host_records '
              'WHERE module_id=? AND space=? AND collection=? '
              'AND deleted=0 AND value IS NOT NULL ORDER BY id',
              variables: [
                Variable(moduleId),
                Variable(declaration.read<String>('space')),
                Variable(collection),
              ],
            )
            .get();
        for (final row in rows) {
          records.add({
            'moduleId': moduleId,
            'space': declaration.read<String>('space'),
            'collection': collection,
            'id': row.read<String>('id'),
            'value': jsonDecode(row.read<String>('value')),
          });
        }
      }
      return <String, Object?>{
        'format': 'xudian.configuration',
        'formatVersion': 1,
        'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'includesSecrets': includeSecrets,
        'appSettings': settings,
        'session': {'uiAnnotationEnabled': annotationEnabled},
        'modules': [
          for (final row in installations)
            {
              'moduleId': row.data['module_id'],
              'version': row.data['version'],
              'space': row.data['space'],
              'dataVersion': row.data['data_version'],
              'installed': row.data['installed'] == 1,
              'enabled': row.data['enabled'] == 1,
              'sha256': row.data['digest'],
              'origin': row.data['origin'],
              if (row.data['definition'] != null)
                'manifest': (jsonDecode(
                  row.data['definition'] as String,
                ) as Map)['manifest'],
            },
        ],
        'hostSettings': {
          for (final row in metadata)
            row.read<String>('key'): _decode(row.read<String>('value')),
        },
        'moduleUiPreferences': [
          for (final row in preferences)
            {
              'moduleId': row.read<String>('module_id'),
              'key': row.read<String>('key'),
              'value': jsonDecode(row.read<String>('value')),
            },
        ],
        'moduleConfiguration': records,
        'scope': {
          'moduleCollections': configurationCollections,
          'excluded': ['businessRecords', 'history', 'modulePackages'],
        },
      };
    });
    // Secure storage is read only when the user explicitly enables this option.
    // Failure propagates so a partial export is never reported as complete.
    if (includeSecrets) {
      final values = await secureStorage.readAll();
      result['secrets'] = {
        for (final entry in values.entries)
          if (entry.key == 'xudian.ai.apiKey' ||
              entry.key.startsWith('xudian.module.'))
            entry.key: entry.value,
      };
    }
    return result;
  }

  Object? _settingValue(String key, String value) =>
      const {'ui.preferences', 'ui.layout', 'ui.selection'}.contains(key)
      ? _decode(value)
      : value;

  Object? _decode(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return value;
    }
  }
}
