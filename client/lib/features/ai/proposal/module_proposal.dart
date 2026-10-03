import '../../../core/declarative/declarative_module.dart';
import '../../../core/declarative/package/module_install_provenance.dart';

class ModuleResourceChange {
  const ModuleResourceChange({
    required this.kind,
    required this.added,
    required this.removed,
    required this.changed,
  });

  final String kind;
  final List<String> added;
  final List<String> removed;
  final List<String> changed;

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;
}

class ModuleProposalDiff {
  const ModuleProposalDiff({
    required this.moduleId,
    required this.fromVersion,
    required this.toVersion,
    required this.permissionsAdded,
    required this.permissionsRemoved,
    required this.resources,
  });

  final String moduleId;
  final String? fromVersion;
  final String toVersion;
  final List<String> permissionsAdded;
  final List<String> permissionsRemoved;
  final List<ModuleResourceChange> resources;
}

class ModuleProposal {
  const ModuleProposal({
    required this.source,
    required this.module,
    required this.diff,
    required this.expectedCurrentVersion,
    required this.provenance,
  });

  final Map<String, Object?> source;
  final DeclarativeModule module;
  final ModuleProposalDiff diff;
  final String? expectedCurrentVersion;
  final ModuleInstallProvenance provenance;
}
