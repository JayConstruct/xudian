import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final database = await AppDatabase.open();
  ref.onDispose(database.close);
  return database;
});
