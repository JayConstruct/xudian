import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../data/app_database.dart';

class ChangeJournal {
  ChangeJournal(this.db);

  final AppDatabase db;
  final Uuid _uuid = const Uuid();

  Future<void> append({
    required String entityType,
    required String entityId,
    required String action,
    Map<String, Object?> payload = const {},
  }) async {
    final deviceRow = await (db.select(db.appSettings)
          ..where((s) => s.key.equals('device_id')))
        .getSingleOrNull();
    final deviceId = deviceRow?.value ?? _uuid.v7();
    if (deviceRow == null) {
      await db.into(db.appSettings).insert(
            AppSetting(key: 'device_id', value: deviceId),
          );
    }
    final counterRow = await (db.select(db.appSettings)
          ..where((s) => s.key.equals('operation_counter')))
        .getSingleOrNull();
    final counter = (int.tryParse(counterRow?.value ?? '') ?? 0) + 1;
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSetting(key: 'operation_counter', value: '$counter'),
        );

    await db.into(db.changeOperations).insert(
          ChangeOperation(
            id: _uuid.v7(),
            deviceId: deviceId,
            counter: counter,
            entityType: entityType,
            entityId: entityId,
            action: action,
            payload: jsonEncode(payload),
            createdAt: DateTime.now(),
            synced: false,
          ),
        );
  }
}
