import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/app_updates/app_update_channel.dart';
import 'package:task_app/core/app_updates/github_app_updates.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

void main() {
  test('defaults to stable and persists channel across fresh scopes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    ProviderContainer scope() => ProviderContainer(
      overrides: [databaseProvider.overrideWith((_) async => db)],
    );
    var container = scope();
    try {
      expect(
        await container.read(appUpdateChannelProvider.future),
        AppUpdateChannel.stable,
      );
      await container
          .read(appUpdateChannelProvider.notifier)
          .save(AppUpdateChannel.testing);
      container.dispose();
      container = scope();
      expect(
        await container.read(appUpdateChannelProvider.future),
        AppUpdateChannel.testing,
      );
      await container
          .read(appUpdateChannelProvider.notifier)
          .save(AppUpdateChannel.stable);
      container.dispose();
      container = scope();
      expect(
        await container.read(appUpdateChannelProvider.future),
        AppUpdateChannel.stable,
      );
    } finally {
      container.dispose();
    }
  });

  test('unknown stored channel falls back to stable', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppUpdateChannelController.storageKey,
            value: 'unknown',
          ),
        );
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((_) async => db)],
    );
    addTearDown(container.dispose);
    expect(
      await container.read(appUpdateChannelProvider.future),
      AppUpdateChannel.stable,
    );
  });
}
