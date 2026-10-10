import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/providers.dart';
import '../contracts/json_values.dart';
import '../module_host/host_providers.dart';
import 'ui_pack.dart';

/// One immutable snapshot per host publication, with no per-widget compilation.
final uiPackRegistryProvider = StreamProvider<Map<String, UiPackDefinition>>((
  ref,
) async* {
  final host = await ref.watch(moduleHostProvider.future);
  final changes = StreamController<Map<String, UiPackDefinition>>();
  Map<String, UiPackDefinition> snapshot() => Map.unmodifiable({
    for (final instance in host.instances.values)
      if (instance.package.isUiPack)
        instance.package.id: instance.package.uiPack!,
  });
  // Subscribe first: an activation between snapshot and subscription must not
  // leave the renderer using an obsolete pack until the next host publication.
  final subscription = host.registryChanges.stream.listen(
    (_) => changes.add(snapshot()),
    onError: changes.addError,
  );
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    subscription.cancel();
    changes.close();
  });
  changes.add(snapshot());
  try {
    yield* changes.stream;
  } finally {
    if (!disposed) {
      await subscription.cancel();
      await changes.close();
    }
  }
});

final uiSelectionProvider =
    AsyncNotifierProvider<UiSelectionController, UiSelection>(
      UiSelectionController.new,
    );

class UiSelectionController extends AsyncNotifier<UiSelection> {
  static const storageKey = 'ui.selection';

  static UiSelection _decode(String? value) {
    if (value == null) return UiSelection();
    try {
      return UiSelection.fromJson(
        (jsonDecode(value) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      return UiSelection();
    } on TypeError {
      return UiSelection();
    }
  }

  @override
  Future<UiSelection> build() async {
    final database = await ref.watch(databaseProvider.future);
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(storageKey))).getSingleOrNull();
    // Missing packs remain in the selection, so re-enabling restores them.
    return _decode(row?.value);
  }

  Future<void> save(UiSelection selection) async {
    final database = await ref.read(databaseProvider.future);
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: storageKey,
            value: jsonEncode(selection.toJson()),
          ),
        );
    state = AsyncData(selection);
  }

  Future<void> saveIfUnchanged(
    UiSelection selection, {
    required UiSelection expected,
  }) async {
    final database = await ref.read(databaseProvider.future);
    await database.transaction(() async {
      final row = await (database.select(
        database.appSettings,
      )..where((row) => row.key.equals(storageKey))).getSingleOrNull();
      if (canonicalJson(_decode(row?.value).toJson()) !=
          canonicalJson(expected.toJson())) {
        throw StateError('界面风格已被其他操作修改，请重新读取');
      }
      await database
          .into(database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: storageKey,
              value: jsonEncode(selection.toJson()),
            ),
          );
    });
    state = AsyncData(selection);
  }

  /// Only the UI selection is reset; module data and installations stay intact.
  Future<void> restoreDefaults() => save(UiSelection());
}
