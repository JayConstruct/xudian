import 'dart:convert';

import '../../../core/declarative/declarative_module.dart';
import '../../../core/declarative/declarative_module_parser.dart';
import '../../../core/declarative/runtime/declarative_module_store.dart';
import '../../../core/declarative/package/module_install_provenance.dart';
import '../../../core/modules/app_module.dart';
import '../../../core/modules/module_registry.dart';
import '../../declarative_runtime/declarative_runtime_controller.dart';
import 'module_proposal.dart';

class ModuleProposalService {
  ModuleProposalService({
    required this.store,
    required this.registry,
    required this.runtime,
  });

  final DeclarativeModuleStore store;
  final ModuleRegistry registry;
  final DeclarativeRuntimeController runtime;
  final DeclarativeModuleParser _parser = const DeclarativeModuleParser();

  Future<ModuleProposal> prepare(
    Map<String, Object?> source, {
    ModuleInstallProvenance provenance = const ModuleInstallProvenance(),
  }) async {
    final module = _parser.parse(source);
    _validatePermissions(module);

    final current = await store.getInstalled(module.manifest.id);
    final existingRuntime = registry.modules.where(
      (item) => item.manifest.id == module.manifest.id,
    );
    if (registry.isBuiltin(module.manifest.id) ||
        (current == null && existingRuntime.isNotEmpty)) {
      throw StateError(
        'Built-in module IDs cannot be replaced by AI proposals',
      );
    }

    final runtimeModule = runtime.validate(module);
    _validateCandidate(runtimeModule);
    if (current != null) {
      final order = _compareSemver(module.manifest.version, current.version);
      if (order <= 0) {
        throw StateError(
          'Module updates must increase version; use rollback for downgrade',
        );
      }
    }
    final previous = current == null
        ? null
        : _parser.parse(_decode(current.sourceJson));

    return ModuleProposal(
      source: source,
      module: module,
      expectedCurrentVersion: current?.version,
      provenance: provenance,
      diff: _diff(previous, module),
    );
  }

  Future<void> apply(ModuleProposal proposal) async {
    final current = await store.getInstalled(proposal.module.manifest.id);
    if (current?.version != proposal.expectedCurrentVersion) {
      throw StateError(
        'Module changed after proposal was prepared; regenerate diff',
      );
    }
    await runtime.install(proposal.source, provenance: proposal.provenance);
  }

  void _validatePermissions(DeclarativeModule module) {
    const allowed = {
      'tasks.read',
      'tasks.write',
      'fields.write',
      'ui.register',
    };
    for (final permission in module.manifest.permissions) {
      if (!allowed.contains(permission)) {
        throw StateError('Unsupported permission: $permission');
      }
    }
  }

  void _validateCandidate(AppModule module) {
    registry.validateAddition(module);
    final candidates = List<AppModule>.of(registry.modules);
    final index = candidates.indexWhere(
      (item) => item.manifest.id == module.manifest.id,
    );
    if (index >= 0) {
      candidates[index] = module;
    } else {
      candidates.add(module);
    }
    ModuleRegistry(candidates, capabilities: registry.capabilities).dispose();
  }

  ModuleProposalDiff _diff(DeclarativeModule? before, DeclarativeModule after) {
    final beforePermissions =
        before?.manifest.permissions.toSet() ?? <String>{};
    final afterPermissions = after.manifest.permissions.toSet();

    final resources = <ModuleResourceChange>[
      _resourceDiff('page', before?.pages ?? const [], after.pages),
      _resourceDiff('view', before?.views ?? const [], after.views),
      _resourceDiff('field', before?.fields ?? const [], after.fields),
      _resourceDiff('template', before?.templates ?? const [], after.templates),
      _resourceDiff('rule', before?.rules ?? const [], after.rules),
      _resourceDiff('layout', before?.layouts ?? const [], after.layouts),
    ].where((change) => !change.isEmpty).toList();

    return ModuleProposalDiff(
      moduleId: after.manifest.id,
      fromVersion: before?.manifest.version,
      toVersion: after.manifest.version,
      permissionsAdded: (afterPermissions.difference(beforePermissions).toList()
        ..sort()),
      permissionsRemoved:
          (beforePermissions.difference(afterPermissions).toList()..sort()),
      resources: resources,
    );
  }

  ModuleResourceChange _resourceDiff(
    String kind,
    List<Map<String, Object?>> before,
    List<Map<String, Object?>> after,
  ) {
    final beforeMap = {
      for (final item in before) item['id'] as String: _canonical(item),
    };
    final afterMap = {
      for (final item in after) item['id'] as String: _canonical(item),
    };
    final beforeIds = beforeMap.keys.toSet();
    final afterIds = afterMap.keys.toSet();

    final changed =
        beforeIds
            .intersection(afterIds)
            .where((id) => beforeMap[id] != afterMap[id])
            .toList()
          ..sort();

    return ModuleResourceChange(
      kind: kind,
      added: (afterIds.difference(beforeIds).toList()..sort()),
      removed: (beforeIds.difference(afterIds).toList()..sort()),
      changed: changed,
    );
  }

  String _canonical(Object? value) => jsonEncode(_normalize(value));

  Object? _normalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: _normalize(value[key])};
    }
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }

  int _compareSemver(String a, String b) {
    final left = a.split('.').map(int.parse).toList();
    final right = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final result = left[i].compareTo(right[i]);
      if (result != 0) return result;
    }
    return 0;
  }

  Map<String, Object?> _decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Stored module source must be an object');
    }
    return decoded.map((key, value) => MapEntry('$key', value));
  }
}
