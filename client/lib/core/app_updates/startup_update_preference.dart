import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/providers.dart';

final startupUpdateEnabledProvider =
    AsyncNotifierProvider<StartupUpdatePreference, bool>(
      StartupUpdatePreference.new,
    );

class StartupUpdatePreference extends AsyncNotifier<bool> {
  static const storageKey = 'app.checkUpdatesOnStartup';

  @override
  Future<bool> build() async {
    final db = await ref.watch(databaseProvider.future);
    final row = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals(storageKey))).getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> save(bool enabled) async {
    final db = await ref.read(databaseProvider.future);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: storageKey, value: '$enabled'),
        );
    state = AsyncData(enabled);
  }
}
