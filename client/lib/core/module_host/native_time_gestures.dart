import 'module_host.dart';
import 'module_package.dart';
import 'planner_quick_adjust.dart';
import 'record_contract.dart';

/// Authority belongs to native event identity and the provider instances that
/// declared the bindings. No serializable page value can manufacture it.
class NativeTimeGestures {
  final _approvals = Expando<PlannerQuickAdjustment>('native time gesture');
  PlannerQuickAdjustment? lookup(Object event) => _approvals[event];
  void attachUndo(Object event, PlannerQuickAdjustment approval) =>
      _approvals[event] = approval;

  Map<String, Object?>? configuration(
    ModuleHost host,
    String moduleId,
    Object? raw,
  ) {
    try {
      if (raw is! Map ||
          raw['contract'] != PlannerQuickAdjustment.contract ||
          raw.keys.toSet().difference({
            'contract',
            'records',
            'taskModuleId',
            'applyServiceId',
            'undoServiceId',
          }).isNotEmpty ||
          !['taskModuleId', 'applyServiceId', 'undoServiceId'].every(
            (key) => raw[key] is String && (raw[key] as String).isNotEmpty,
          )) {
        return null;
      }
      final config = object(raw);
      _resolve(host, moduleId, config);
      return config;
    } catch (_) {
      return null;
    }
  }

  TimeAdjustmentRecords _resolve(
    ModuleHost host,
    String moduleId,
    Map<String, Object?> config,
  ) {
    final owner = host.instances[moduleId]!,
        source = host.instances[config['taskModuleId']]!;
    final refs = object(config['records']);
    if (refs.length != 4 ||
        !{
          'subject',
          'journal',
          'receipt',
          'occurrence',
        }.every(refs.containsKey)) {
      throw const FormatException('Invalid time record references');
    }
    return TimeAdjustmentRecords(
      subjectModuleId: source.package.id,
      ownerModuleId: owner.package.id,
      subject: source.package.recordContracts[refs['subject']]!,
      journal: owner.package.recordContracts[refs['journal']]!,
      receipt: owner.package.recordContracts[refs['receipt']]!,
      occurrence: owner.package.recordContracts[refs['occurrence']]!,
    );
  }

  void begin(
    Object event,
    ModuleHost host,
    String moduleId,
    Map<String, Object?> config,
  ) {
    final records = _resolve(host, moduleId, config);
    final owner = host.instances[moduleId],
        source = host.instances[records.subjectModuleId];
    _approvals[event] = PlannerQuickAdjustment.move(
      object(event),
      records: records,
      isCurrent: () =>
          identical(owner, host.instances[moduleId]) &&
          identical(source, host.instances[records.subjectModuleId]),
      moduleId: moduleId,
      taskModuleId: records.subjectModuleId,
      applyServiceId: config['applyServiceId'] as String,
      undoServiceId: config['undoServiceId'] as String,
    );
  }
}
