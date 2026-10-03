import 'package:flutter/foundation.dart';

import '../security/capability_registry.dart';
import '../ui/ui_registry.dart';
import '../ui/ui_slot.dart';
import 'app_module.dart';
import 'builtin_module_registration.dart';

class ModuleRegistry extends ChangeNotifier {
  ModuleRegistry(Iterable<AppModule> modules, {required this.capabilities})
    : _modules = List.of(modules) {
    _apply(_modules, notify: false);
  }

  final List<AppModule> _modules;
  final Map<String, BuiltinModuleRegistration> _builtins = {};
  final CapabilityRegistry capabilities;
  final UiRegistry ui = UiRegistry();

  List<AppModule> get modules => List.unmodifiable(_modules);
  List<BuiltinModuleRegistration> get builtins =>
      List.unmodifiable(_builtins.values);

  bool isBuiltin(String moduleId) => _builtins.containsKey(moduleId);
  bool isEnabled(String moduleId) =>
      _modules.any((module) => module.manifest.id == moduleId);

  void registerBuiltin(BuiltinModuleRegistration registration) {
    if (isBuiltin(registration.id) || isEnabled(registration.id)) {
      throw StateError('Module is already registered: ${registration.id}');
    }
    _apply([..._modules, registration.module], notify: false);
    _builtins[registration.id] = registration;
    notifyListeners();
  }

  List<AppModule> _builtinCandidate(Map<String, bool> states) => [
    for (final registration in _builtins.values)
      if (!registration.canDisable ||
          (states[registration.id] ?? isEnabled(registration.id)))
        registration.module,
    ..._modules.where((module) => !isBuiltin(module.manifest.id)),
  ];

  void validateBuiltinState(String moduleId, bool enabled) {
    final registration = _builtins[moduleId];
    if (registration == null) {
      throw StateError('Unknown built-in module: $moduleId');
    }
    if (!enabled && !registration.canDisable) {
      throw StateError('${registration.title} 必须保持可用');
    }
    final dependents = _modules.where(
      (module) =>
          module.manifest.id != moduleId &&
          module.manifest.dependencies.contains(moduleId),
    );
    if (!enabled && dependents.isNotEmpty) {
      final titles = dependents
          .map(
            (module) =>
                _builtins[module.manifest.id]?.title ?? module.manifest.id,
          )
          .join('、');
      throw StateError('请先关闭依赖${registration.title}的模块：$titles');
    }
    final candidate = _builtinCandidate({moduleId: enabled});
    _validate(candidate);
    _buildUi(candidate);
  }

  void setBuiltinEnabled(String moduleId, bool enabled) {
    validateBuiltinState(moduleId, enabled);
    if (isEnabled(moduleId) == enabled) return;
    _apply(_builtinCandidate({moduleId: enabled}));
  }

  void restoreBuiltinStates(Map<String, bool> states) =>
      _apply(_builtinCandidate(states));

  void addOrReplace(AppModule module) {
    validateAddition(module);
    final next = List<AppModule>.of(_modules);
    final index = next.indexWhere(
      (candidate) => candidate.manifest.id == module.manifest.id,
    );
    if (index >= 0) {
      next[index] = module;
    } else {
      next.add(module);
    }
    _apply(next);
  }

  void validateAddition(AppModule module) {
    final builtin = _builtins[module.manifest.id];
    if (builtin != null && !identical(builtin.module, module)) {
      throw StateError('Built-in module IDs cannot be replaced: ${builtin.id}');
    }
    final candidate =
        _modules
            .where((item) => item.manifest.id != module.manifest.id)
            .toList()
          ..add(module);
    _validate(candidate);
    _buildUi(candidate);
  }

  void validateRemoval(String moduleId) {
    final registration = _builtins[moduleId];
    if (registration != null && !registration.canDisable) {
      throw StateError('${registration.title} 必须保持可用');
    }
    _validate(
      _modules.where((module) => module.manifest.id != moduleId).toList(),
    );
  }

  bool remove(String moduleId) {
    validateRemoval(moduleId);
    final next = List<AppModule>.of(_modules)
      ..removeWhere((candidate) => candidate.manifest.id == moduleId);
    if (next.length == _modules.length) return false;
    _apply(next);
    return true;
  }

  void _apply(List<AppModule> next, {bool notify = true}) {
    final candidate = List<AppModule>.of(next);
    _validate(candidate);
    final nextUi = _buildUi(candidate);

    _modules
      ..clear()
      ..addAll(candidate);
    ui.clear();
    for (final slot in UiSlot.values) {
      for (final registration in nextUi.forSlot(slot)) {
        ui.register(registration);
      }
    }
    if (notify) notifyListeners();
  }

  void _validate(List<AppModule> modules) {
    final ids = <String>{};
    for (final module in modules) {
      module.manifest.validate();
      if (!ids.add(module.manifest.id)) {
        throw StateError('Duplicate module id: ${module.manifest.id}');
      }
    }
    for (final module in modules) {
      for (final dependency in module.manifest.dependencies) {
        if (!ids.contains(dependency)) {
          throw StateError(
            'Module ${module.manifest.id} is missing dependency $dependency',
          );
        }
      }
      capabilities.requireAll(module.manifest.requiresCapabilities);
    }
    final byId = {for (final module in modules) module.manifest.id: module};
    final visited = <String>{};
    final visiting = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw StateError(
          'Module dependency cycle: ${[...visiting, id].join(' → ')}',
        );
      }
      for (final dependency in byId[id]!.manifest.dependencies) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in ids) {
      visit(id);
    }
  }

  UiRegistry _buildUi(List<AppModule> modules) {
    final result = UiRegistry();
    for (final module in modules) {
      if (module.ui.isNotEmpty &&
          !module.manifest.permissions.contains('ui.register')) {
        throw StateError(
          'Module ${module.manifest.id} cannot register UI without '
          'ui.register permission',
        );
      }
      for (final registration in module.ui) {
        result.register(registration);
      }
    }
    return result;
  }
}
