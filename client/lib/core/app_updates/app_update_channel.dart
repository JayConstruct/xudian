import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/providers.dart';
import 'github_app_updates.dart';

final appUpdateChannelProvider =
    AsyncNotifierProvider<AppUpdateChannelController, AppUpdateChannel>(
      AppUpdateChannelController.new,
    );

class AppUpdateChannelController extends AsyncNotifier<AppUpdateChannel> {
  static const storageKey = 'app.updateChannel';

  @override
  Future<AppUpdateChannel> build() async {
    final db = await ref.watch(databaseProvider.future);
    final row = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals(storageKey))).getSingleOrNull();
    return AppUpdateChannel.values.firstWhere(
      (channel) => channel.name == row?.value,
      orElse: () => AppUpdateChannel.stable,
    );
  }

  Future<void> save(AppUpdateChannel channel) async {
    final db = await ref.read(databaseProvider.future);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: storageKey, value: channel.name),
        );
    state = AsyncData(channel);
  }
}
