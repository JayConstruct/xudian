import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/ui_composition.dart';
import '../../core/contracts/json_values.dart';
import '../../data/app_database.dart';
import '../../data/providers.dart';

class UiLayoutProfile {
  UiLayoutProfile({this.mainLimit, Map<String, UiMount> mounts = const {}})
    : mounts = Map.unmodifiable(mounts);

  final int? mainLimit;
  final Map<String, UiMount> mounts;

  UiMount mountFor(UiEntryRegistration entry) =>
      mounts[entry.id] ?? entry.defaultMount;

  UiLayoutProfile withMount(String id, UiMount mount) =>
      UiLayoutProfile(mainLimit: mainLimit, mounts: {...mounts, id: mount});

  UiLayoutProfile withoutMount(String id) => UiLayoutProfile(
    mainLimit: mainLimit,
    mounts: Map<String, UiMount>.of(mounts)..remove(id),
  );

  Map<String, Object?> toJson() => {
    'mainLimit': mainLimit,
    'mounts': mounts.map((id, mount) => MapEntry(id, mount.toJson())),
  };

  factory UiLayoutProfile.fromJson(Map<String, Object?> json) {
    final limit = json['mainLimit'];
    if (limit != null && (limit is! int || limit < 1)) {
      throw const FormatException('Invalid navigation limit');
    }
    final raw = json['mounts'] as Map;
    return UiLayoutProfile(
      mainLimit: limit as int?,
      mounts: raw.map(
        (id, mount) => MapEntry(
          id as String,
          UiMount.fromJson((mount as Map).cast<String, Object?>()),
        ),
      ),
    );
  }
}

class UiLayout {
  UiLayout({
    UiLayoutProfile? narrow,
    UiLayoutProfile? wide,
    this.warning,
    this.corruptSource,
  }) : narrow = narrow ?? UiLayoutProfile(mainLimit: 4),
       wide = wide ?? UiLayoutProfile();

  final UiLayoutProfile narrow;
  final UiLayoutProfile wide;
  final String? warning;
  final String? corruptSource;

  UiLayoutProfile profile(bool desktop) => desktop ? wide : narrow;

  Map<String, Object?> toJson() => {
    'version': 1,
    'narrow': narrow.toJson(),
    'wide': wide.toJson(),
  };

  factory UiLayout.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unknown layout version');
    }
    return UiLayout(
      narrow: UiLayoutProfile.fromJson(
        (json['narrow'] as Map).cast<String, Object?>(),
      ),
      wide: UiLayoutProfile.fromJson(
        (json['wide'] as Map).cast<String, Object?>(),
      ),
    );
  }
}

final uiLayoutProvider = AsyncNotifierProvider<UiLayoutController, UiLayout>(
  UiLayoutController.new,
);

class UiLayoutEditorSessions {
  final Map<Object, bool> _sessions = {};

  void open(Object token) => _sessions[token] = false;
  void markDirty(Object token, bool dirty) => _sessions[token] = dirty;
  void close(Object token) => _sessions.remove(token);
  bool get hasDirtyEditors => _sessions.values.any((dirty) => dirty);
}

final uiLayoutEditorSessionsProvider = Provider<UiLayoutEditorSessions>(
  (ref) => UiLayoutEditorSessions(),
);

class UiLayoutController extends AsyncNotifier<UiLayout> {
  static const storageKey = 'ui.layout';

  @override
  Future<UiLayout> build() async {
    final database = await ref.watch(databaseProvider.future);
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(storageKey))).getSingleOrNull();
    if (row == null) return UiLayout();
    try {
      return UiLayout.fromJson(
        (jsonDecode(row.value) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return UiLayout(
        warning: '入口布局配置损坏，已使用默认布局；可在设置中重新保存。',
        corruptSource: row.value,
      );
    }
  }

  Future<void> save(UiLayout layout) async {
    final database = await ref.read(databaseProvider.future);
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: storageKey,
            value: jsonEncode(layout.toJson()),
          ),
        );
    state = AsyncData(layout);
  }

  Future<void> saveIfUnchanged(
    UiLayout layout, {
    required UiLayout expected,
  }) async {
    final database = await ref.read(databaseProvider.future);
    await database.transaction(() async {
      final row = await (database.select(
        database.appSettings,
      )..where((row) => row.key.equals(storageKey))).getSingleOrNull();
      final recovering =
          expected.warning != null &&
          expected.corruptSource != null &&
          row?.value == expected.corruptSource;
      final current = recovering || row == null
          ? UiLayout()
          : UiLayout.fromJson(
              (jsonDecode(row.value) as Map).cast<String, Object?>(),
            );
      if (!recovering &&
          canonicalJson(current.toJson()) != canonicalJson(expected.toJson())) {
        throw StateError('布局已被其他操作修改，请重新读取后再保存');
      }
      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: storageKey,
              value: jsonEncode(layout.toJson()),
            ),
          );
    });
    state = AsyncData(layout);
  }
}
