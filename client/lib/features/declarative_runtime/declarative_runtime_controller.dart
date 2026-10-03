import 'dart:convert';

import '../../core/declarative/declarative_module_parser.dart';
import '../../core/declarative/runtime/declarative_module_store.dart';
import '../../core/declarative/runtime/rules/rule_engine.dart';
import '../../core/declarative/runtime/templates/template_engine.dart';
import '../../core/declarative/declarative_module.dart';
import '../../core/declarative/package/module_install_provenance.dart';
import '../../core/modules/app_module.dart';
import '../../core/modules/module_registry.dart';
import 'declarative_app_module.dart';

class ModuleRestoreFailure {
  const ModuleRestoreFailure(this.moduleId, this.reason);

  final String moduleId;
  final String reason;
}

class DeclarativeRuntimeController {
  DeclarativeRuntimeController({
    required this.store,
    required this.registry,
    this.ruleEngine,
    this.templateEngine,
  });

  final DeclarativeModuleStore store;
  final ModuleRegistry registry;
  final RuleEngine? ruleEngine;
  final TemplateEngine? templateEngine;
  final DeclarativeModuleParser _parser = const DeclarativeModuleParser();

  AppModule validate(DeclarativeModule module) {
    final runtimeModule = DeclarativeAppModule(module);
    if (module.rules.isNotEmpty) {
      final engine = ruleEngine;
      if (engine == null) {
        throw const FormatException('Rule engine is unavailable');
      }
      engine.validateModule(module);
    }
    if (module.templates.isNotEmpty) {
      final engine = templateEngine;
      if (engine == null) {
        throw const FormatException('Template engine is unavailable');
      }
      engine.validateModule(module);
    }
    return runtimeModule;
  }

  void _activate(DeclarativeModule module) {
    ruleEngine?.installModule(module);
    templateEngine?.installModule(module);
  }

  void _deactivate(String moduleId) {
    ruleEngine?.removeModule(moduleId);
    templateEngine?.removeModule(moduleId);
  }

  Future<List<ModuleRestoreFailure>> restoreEnabled() async {
    final failures = <String, ModuleRestoreFailure>{};
    final modules = <String, DeclarativeModule>{};
    final installed = await store.listInstalled();
    for (final row in installed.where(
      (item) => item.installed && item.enabled,
    )) {
      try {
        final module = _parser.parse(_decode(row.sourceJson));
        if (module.manifest.id != row.id) {
          throw const FormatException('模块标识与安装记录不一致');
        }
        modules[row.id] = module;
      } catch (error) {
        failures[row.id] = ModuleRestoreFailure(row.id, '$error');
      }
    }

    final visiting = <String>[];
    final restored = <String>{};
    // Visit dependencies first, independently of database row order. A failed
    // branch must not prevent unrelated modules from restoring.
    bool restore(String id) {
      if (failures.containsKey(id)) return false;
      if (restored.contains(id)) return true;
      final cycleStart = visiting.indexOf(id);
      if (cycleStart >= 0) {
        final cycle = [...visiting.sublist(cycleStart), id].join(' → ');
        failures[id] = ModuleRestoreFailure(id, '模块依赖形成循环：$cycle');
        return false;
      }
      final module = modules[id]!;
      visiting.add(id);
      try {
        for (final dependency in module.manifest.dependencies) {
          if (failures.containsKey(dependency) ||
              (modules.containsKey(dependency) && !restore(dependency))) {
            throw StateError('依赖模块恢复失败：$dependency');
          }
          if (!registry.isEnabled(dependency)) {
            throw StateError('缺少或尚未启用依赖模块：$dependency');
          }
        }
        final runtimeModule = validate(module);
        registry.addOrReplace(runtimeModule);
        _activate(module);
        restored.add(id);
        return true;
      } catch (error) {
        failures.putIfAbsent(id, () => ModuleRestoreFailure(id, '$error'));
        return false;
      } finally {
        visiting.removeLast();
      }
    }

    for (final id in modules.keys) {
      restore(id);
    }
    for (final id in failures.keys) {
      await store.setEnabled(id, false);
    }
    return failures.values.toList(growable: false);
  }

  Future<void> install(
    Map<String, Object?> source, {
    ModuleInstallProvenance? provenance,
  }) async {
    final module = _parser.parse(source);
    final runtimeModule = validate(module);
    registry.validateAddition(runtimeModule);
    await store.install(module, source, provenance: provenance);
    registry.addOrReplace(runtimeModule);
    _activate(module);
  }

  Future<void> rollback(String moduleId, String version) async {
    final source = await store.versionSource(moduleId, version);
    final provenance = await store.versionProvenance(moduleId, version);
    final module = _parser.parse(source);
    final runtimeModule = validate(module);
    registry.validateAddition(runtimeModule);
    await store.install(module, source, provenance: provenance);
    registry.addOrReplace(runtimeModule);
    _activate(module);
  }

  Future<void> uninstall(String moduleId, {bool deleteData = false}) async {
    registry.validateRemoval(moduleId);
    await store.uninstall(moduleId, deleteData: deleteData);
    registry.remove(moduleId);
    _deactivate(moduleId);
  }

  Future<void> setEnabled(String moduleId, bool enabled) async {
    if (!enabled) {
      registry.validateRemoval(moduleId);
      await store.setEnabled(moduleId, false);
      registry.remove(moduleId);
      _deactivate(moduleId);
      return;
    }

    final matches = (await store.listInstalled())
        .where((item) => item.id == moduleId)
        .toList();
    if (matches.isEmpty) {
      throw StateError('Module not installed: $moduleId');
    }
    final source = _decode(matches.single.sourceJson);
    final module = _parser.parse(source);
    final runtimeModule = validate(module);
    registry.validateAddition(runtimeModule);
    await store.install(module, source);
    registry.addOrReplace(runtimeModule);
    _activate(module);
  }

  Map<String, Object?> _decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Stored module source must be an object');
    }
    return decoded.map((key, value) => MapEntry('$key', value));
  }
}
