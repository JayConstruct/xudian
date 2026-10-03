import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../tasks/application/providers.dart';

class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.reduceMotion = false,
    this.haptics = true,
  });

  final ThemeMode themeMode;
  final bool reduceMotion;
  final bool haptics;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    bool? reduceMotion,
    bool? haptics,
  }) => AppPreferences(
    themeMode: themeMode ?? this.themeMode,
    reduceMotion: reduceMotion ?? this.reduceMotion,
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
      final values = jsonDecode(row.value) as Map<String, dynamic>;
      return AppPreferences(
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == values['theme'],
          orElse: () => ThemeMode.system,
        ),
        reduceMotion: values['reduceMotion'] == true,
        haptics: values['haptics'] != false,
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
            value: jsonEncode({
              'theme': preferences.themeMode.name,
              'reduceMotion': preferences.reduceMotion,
              'haptics': preferences.haptics,
            }),
          ),
        );
    state = AsyncData(preferences);
  }
}
