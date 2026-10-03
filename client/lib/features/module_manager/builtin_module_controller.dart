import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/module_registry.dart';
import '../../data/app_database.dart';
import '../tasks/application/providers.dart';

final builtinModuleControllerProvider =
    FutureProvider.family<BuiltinModuleController, ModuleRegistry>(
      (ref, registry) async => BuiltinModuleController(
        db: await ref.watch(databaseProvider.future),
        registry: registry,
      ),
    );

class BuiltinModuleController {
  BuiltinModuleController({required this.db, required this.registry});

  final AppDatabase db;
  final ModuleRegistry registry;
  bool _changing = false;
  static const keyPrefix = 'modules.builtin.';

  Future<void> restore() async {
    final rows = await db.select(db.appSettings).get();
    registry.restoreBuiltinStates({
      for (final row in rows)
        if (row.key.startsWith(keyPrefix) &&
            (row.value == 'true' || row.value == 'false'))
          row.key.substring(keyPrefix.length): row.value == 'true',
    });
  }

  Future<void> setEnabled(String moduleId, bool enabled) async {
    if (_changing) throw StateError('模块状态正在保存，请稍后重试');
    registry.validateBuiltinState(moduleId, enabled);
    if (registry.isEnabled(moduleId) == enabled) return;
    _changing = true;
    final previous = registry.isEnabled(moduleId);
    try {
      await db.transaction(() async {
        await db
            .into(db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: '$keyPrefix$moduleId',
                value: '$enabled',
              ),
            );
        // Revalidate after the database await in case a dependency changed.
        registry.setBuiltinEnabled(moduleId, enabled);
      });
    } catch (_) {
      if (registry.isEnabled(moduleId) != previous) {
        registry.setBuiltinEnabled(moduleId, previous);
      }
      rethrow;
    } finally {
      _changing = false;
    }
  }
}
