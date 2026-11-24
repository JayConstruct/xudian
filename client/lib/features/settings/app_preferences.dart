import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../core/contracts/json_values.dart';
import '../../data/providers.dart';

class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.haptics = true,
  });

  final ThemeMode themeMode;
  final bool haptics;

  Map<String, Object?> toJson() => {
    'theme': themeMode.name,
    'haptics': haptics,
  };

  factory AppPreferences.fromJson(Map<String, Object?> values) =>
      AppPreferences(
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == values['theme'],
          orElse: () => ThemeMode.system,
        ),
        haptics: values['haptics'] != false,
      );

  AppPreferences copyWith({ThemeMode? themeMode, bool? haptics}) =>
      AppPreferences(
        themeMode: themeMode ?? this.themeMode,
        haptics: haptics ?? this.haptics,
      );
}

final appPreferencesProvider =
    AsyncNotifierProvider<AppPreferencesController, AppPreferences>(
      AppPreferencesController.new,
    );

class AppPreferencesController extends AsyncNotifier<AppPreferences> {
  static const storageKey = 'ui.preferences';

  @override
  Future<AppPreferences> build() async {
    final db = await ref.watch(databaseProvider.future);
    final row = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals(storageKey))).getSingleOrNull();
    if (row == null) return const AppPreferences();
    try {
      return AppPreferences.fromJson(
        jsonDecode(row.value) as Map<String, dynamic>,
      );
    } on FormatException {
      return const AppPreferences();
    } on TypeError {
      return const AppPreferences();
    }
  }

  /// Publish only persisted values, so a failed save keeps the current theme.
  Future<void> save(AppPreferences preferences) async {
    final db = await ref.read(databaseProvider.future);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: storageKey,
            value: jsonEncode(preferences.toJson()),
          ),
        );
    state = AsyncData(preferences);
  }

  Future<void> saveIfUnchanged(
    AppPreferences preferences, {
    required AppPreferences expected,
  }) async {
    final database = await ref.read(databaseProvider.future);
    await database.transaction(() async {
      final row = await (database.select(
        database.appSettings,
      )..where((row) => row.key.equals(storageKey))).getSingleOrNull();
      final current = row == null
          ? const AppPreferences()
          : AppPreferences.fromJson(
              (jsonDecode(row.value) as Map).cast<String, Object?>(),
            );
      if (canonicalJson(current.toJson()) != canonicalJson(expected.toJson())) {
        throw StateError('外观设置已被其他操作修改，请重新读取');
      }
      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: storageKey,
              value: jsonEncode(preferences.toJson()),
            ),
          );
    });
    state = AsyncData(preferences);
  }
}
