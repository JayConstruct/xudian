import 'package:flutter/material.dart';

import '../../../core/declarative/package/module_install_provenance.dart';
import 'module_proposal_review.dart';
import 'module_proposal_service.dart';

class ModuleProposalCoordinator {
  ModuleProposalCoordinator(this.service);

  final ModuleProposalService service;

  Future<bool> reviewAndApply(
    BuildContext context,
    Map<String, Object?> source, {
    ModuleInstallProvenance provenance = const ModuleInstallProvenance(),
    bool Function()? canApply,
  }) async {
    final proposal = await service.prepare(source, provenance: provenance);
    if (!context.mounted || !(canApply?.call() ?? true)) return false;

    final confirmed = await showModuleProposalReview(
      context: context,
      proposal: proposal,
    );
    if (!confirmed || !context.mounted || !(canApply?.call() ?? true)) {
      return false;
    }

    await service.apply(proposal);
    return true;
  }
}
