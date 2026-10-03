import '../../../data/app_database.dart';

class AiSettings {
  const AiSettings({required this.endpoint, required this.model});

  final String endpoint;
  final String model;
}

abstract interface class AiSettingsStore {
  Future<AiSettings> load();
  Future<void> save({required String endpoint, required String model});
}

class DriftAiSettingsStore implements AiSettingsStore {
  DriftAiSettingsStore(this.db);

  final AppDatabase db;

  static const _endpointKey = 'ai.endpoint';
  static const _modelKey = 'ai.model';

  @override
  Future<AiSettings> load() async {
    final rows = await db.select(db.appSettings).get();
    final values = {for (final row in rows) row.key: row.value};
    return AiSettings(
      endpoint: values[_endpointKey] ?? '',
      model: values[_modelKey] ?? '',
    );
  }

  @override
  Future<void> save({required String endpoint, required String model}) async {
    await db.transaction(() async {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: _endpointKey, value: endpoint),
          );
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: _modelKey, value: model),
          );
    });
  }
}
