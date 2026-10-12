import 'dart:convert';

import '../../data/app_database.dart';
import '../contracts/json_values.dart';
import 'collection_store.dart';
import 'module_package.dart';
import 'native_resource.dart';

/// Adapts reviewed host settings to the preference readers' existing table.
/// Baseline validation and the mirror write run inside the store transaction.
class HostSettingsResource implements NativeResource {
  HostSettingsResource(this.store);

  final CollectionStore store;

  @override
  String get id => 'host.settings';

  Future<Map<String, Object?>> read(
    String key,
    Map<String, Object?> fallback,
    SnapshotSession session,
  ) async {
    final rows = await store.sql('SELECT value FROM app_settings WHERE key=?', [
      key,
    ]);
    final raw = rows.isEmpty ? null : rows.single['value'] as String;
    final reads = session.nativeReads.putIfAbsent(
      id,
      () => <String, Object?>{},
    ) as Map<String, Object?>;
    if (reads.containsKey(key) && reads[key] != raw) {
      throw StateError('Host setting changed while preparing');
    }
    reads[key] = raw;
    final staged = session.writes[_key(key).key];
    if (staged != null) return object(object(staged['value'])['values']);
    return raw == null ? fallback : object(jsonDecode(raw));
  }

  void stage(
    String key,
    Map<String, Object?> before,
    Map<String, Object?> after,
    SnapshotSession session,
  ) {
    final record = _key(key);
    final existing = session.writes[record.key];
    session.writes[record.key] = {
      'moduleId': record.moduleId,
      'space': record.space,
      'collection': record.collection,
      'id': record.id,
      'before':
          existing?['before'] ?? freezeJson({'id': key, 'values': before}),
      'value': freezeJson({'id': key, 'values': after}),
    };
  }

  RecordKey _key(String key) =>
      RecordKey('app.host', 'host-controls', 'settings', key);

  @override
  Future<void> validateReads(
    AppDatabase db,
    Map<String, Object?> baselines,
  ) async {
    for (final baseline in baselines.entries) {
      final rows = await store.sql(
        'SELECT value FROM app_settings WHERE key=?',
        [baseline.key],
      );
      if ((rows.isEmpty ? null : rows.single['value']) != baseline.value) {
        throw StateError('Host setting conflict; prepare again');
      }
    }
  }

  @override
  bool ownsWrite(Map<String, Object?> write) =>
      write['moduleId'] == 'app.host' &&
      write['space'] == 'host-controls' &&
      write['collection'] == 'settings';

  @override
  Future<void> applyWrite(AppDatabase db, Map<String, Object?> write) async {
    final value = write['value'];
    if (value == null) throw StateError('Host settings cannot be deleted');
    await db.customStatement(
      'INSERT INTO app_settings VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
      [write['id'], canonicalJson(object(value)['values'])],
    );
  }
}
