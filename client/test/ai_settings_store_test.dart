import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/settings/ai_settings_store.dart';

void main() {
  test('AI endpoint and model persist in app settings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final store = DriftAiSettingsStore(db);

    expect((await store.load()).endpoint, isEmpty);
    expect((await store.load()).model, isEmpty);

    await store.save(
      endpoint: 'https://example.com/v1/chat/completions',
      model: 'test-model',
    );

    final loaded = await store.load();
    expect(
      loaded.endpoint,
      'https://example.com/v1/chat/completions',
    );
    expect(loaded.model, 'test-model');

    await store.save(
      endpoint: 'https://other.example/v1/chat/completions',
      model: 'new-model',
    );
    final updated = await store.load();
    expect(
      updated.endpoint,
      'https://other.example/v1/chat/completions',
    );
    expect(updated.model, 'new-model');

    await db.close();
  });
}
