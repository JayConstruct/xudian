import 'dart:convert';

import '../contracts/json_values.dart';
import 'collection_store.dart';

String uiPreferencesReadDependency(String moduleId) =>
    '@ui.preferences:$moduleId';

/// Small presentation preferences, isolated from business records and plans.
class ModuleUiPreferences {
  ModuleUiPreferences(this.store);
  final CollectionStore store;

  void _key(String key) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,63}$').hasMatch(key)) {
      throw const FormatException('Invalid UI preference key');
    }
  }

  void _value(Object? value, int depth, List<int> count) {
    if (depth > 8 || ++count[0] > 256) {
      throw const FormatException('UI preference exceeds JSON limits');
    }
    if (value == null || value is bool) return;
    if (value is num && value.isFinite) return;
    if (value is String && value.length <= 4096) return;
    if (value is List) {
      for (final item in value) {
        _value(item, depth + 1, count);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String || (entry.key as String).length > 64) {
          throw const FormatException('Invalid UI preference object key');
        }
        _value(entry.value, depth + 1, count);
      }
      return;
    }
    throw const FormatException('UI preferences require bounded JSON values');
  }

  Future<Object?> get(ModuleActor actor, String key) async {
    _key(key);
    store.requireActive(actor);
    final rows = await store.sql(
      'SELECT value FROM host_ui_preferences WHERE module_id=? AND key=?',
      [actor.moduleId, key],
    );
    store.requireActive(actor);
    return rows.isEmpty ? null : jsonDecode(rows.single['value'] as String);
  }

  Future<Object?> set(
    ModuleActor actor,
    String key,
    Object? value, {
    bool notify = true,
  }) async {
    _key(key);
    _value(value, 0, [0]);
    final encoded = jsonEncode(value);
    final bytes = utf8.encode(encoded).length;
    if (bytes > 8192) {
      throw const FormatException('UI preference exceeds 8 KiB');
    }
    var changed = false;
    await store.db.transaction(() async {
      store.requireActive(actor);
      final all = await store.sql(
        'SELECT key,value FROM host_ui_preferences WHERE module_id=?',
        [actor.moduleId],
      );
      final current = all.where((row) => row['key'] == key);
      if (value == null && current.isEmpty ||
          value != null &&
              current.isNotEmpty &&
              canonicalJson(jsonDecode(current.single['value'] as String)) ==
                  canonicalJson(value)) {
        return;
      }
      final rows = all.where((row) => row['key'] != key).toList();
      if (value != null &&
          (rows.length >= 64 ||
              rows.fold<int>(
                        0,
                        (size, row) =>
                            size + utf8.encode(row['value'] as String).length,
                      ) +
                      bytes >
                  32768)) {
        throw const FormatException('UI preference module quota exceeded');
      }
      store.requireActive(actor);
      if (value == null) {
        await store.db.customStatement(
          'DELETE FROM host_ui_preferences WHERE module_id=? AND key=?',
          [actor.moduleId, key],
        );
      } else {
        await store.db.customStatement(
          'INSERT INTO host_ui_preferences(module_id,key,value) VALUES(?,?,?) '
          'ON CONFLICT(module_id,key) DO UPDATE SET value=excluded.value',
          [actor.moduleId, key, encoded],
        );
      }
      changed = true;
    });
    final dependency = uiPreferencesReadDependency(actor.moduleId);
    if (changed) store.recordDataChange({dependency});
    store.requireActive(actor);
    // Preference invalidation refreshes only UI readers. It is not a business
    // mutation: do not publish a module-data change or an automation event.
    if (changed && notify) store.changes.add({dependency});
    return value;
  }
}
