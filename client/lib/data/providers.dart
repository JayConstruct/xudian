import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import '../core/performance/ui_load_trace.dart';

final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final database = await UiLoadTrace.run('database.open', AppDatabase.open);
  ref.onDispose(database.close);
  return database;
});
