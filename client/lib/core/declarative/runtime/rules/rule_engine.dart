import 'dart:async';
import 'dart:convert';

import '../../../contracts/command_bus.dart';
import '../../../contracts/query_bus.dart';
import '../../../events/automation_execution.dart';
import '../../../events/domain_event.dart';
import '../../../events/event_bus.dart';
import '../../../modules/module_context.dart';
import '../../../../data/app_database.dart';
import '../../declarative_module.dart';
import '../filter_expression.dart';
import 'rule_execution_store.dart';

class RuleEngine {
  RuleEngine({
    required this._events,
    required this.commands,
    required this.queries,
    required this.executions,
    this.maxDepth = 8,
  }) {
    _subscription = _events.events.listen(_enqueue);
  }

  final EventBus _events;
  final CommandBus commands;
  final QueryBus queries;
  final RuleExecutionStore executions;
  final int maxDepth;

  final Map<String, _RuleModule> _modules = {};
  late final StreamSubscription<DomainEvent> _subscription;
  Future<void> _tail = Future<void>.value();

  Future<void> close() => _subscription.cancel();

  Future<void> drain() => _tail;

  void installModule(DeclarativeModule module) {
    validateModule(module);
    if (module.rules.isEmpty) {
      _modules.remove(module.manifest.id);
      return;
    }
    _modules[module.manifest.id] = _RuleModule(
      context: ModuleContext(
        moduleId: module.manifest.id,
        permissions: module.manifest.permissions,
      ),
      rules: module.rules,
    );
  }

  void removeModule(String moduleId) {
    _modules.remove(moduleId);
  }

  void validateModule(DeclarativeModule module) {
    if (module.rules.isNotEmpty &&
        !module.manifest.requiresCapabilities.contains('tasks.command')) {
      throw const FormatException('Rules require tasks.command capability');
    }
    const allowedEvents = {
      'task.created',
      'task.updated',
      'task.completed',
      'task.reopened',
      'project.created',
    };
    const allowedCommands = {
      'task.create',
      'task.updateFields',
      'task.setCompleted',
      'project.create',
      'field.set',
      'field.clear',
    };

    for (final rule in module.rules) {
      final id = rule['id'];
      final event = rule['event'];
      final actions = rule['actions'];
      if (id is! String || event is! String || actions is! List) {
        throw const FormatException('Rule requires id, event and actions');
      }
      if (!allowedEvents.contains(event)) {
        throw FormatException('Unsupported rule event: $event');
      }
      if (actions.isEmpty) {
        throw FormatException('Rule $id requires at least one action');
      }
      if (rule['condition'] != null) {
        if (!module.manifest.permissions.contains('tasks.read') ||
            !module.manifest.requiresCapabilities.contains('tasks.query')) {
          throw FormatException(
            'Rule $id with condition requires tasks.query and tasks.read',
          );
        }
      }

      for (final raw in actions) {
        if (raw is! Map) {
          throw FormatException('Rule $id action must be an object');
        }
        final command = raw['command'];
        final payload = raw['payload'];
        if (command is! String || !allowedCommands.contains(command)) {
          throw FormatException('Rule $id uses unsupported command: $command');
        }
        if (payload != null && payload is! Map) {
          throw FormatException('Rule $id action payload must be object');
        }
      }
    }
  }

  void _enqueue(DomainEvent event) {
    _tail = _tail.then((_) => _handle(event)).catchError((Object _) {});
  }

  Future<void> _handle(DomainEvent event) async {
    for (final entry in _modules.entries) {
      final moduleId = entry.key;
      final module = entry.value;
      for (final rule in module.rules) {
        if (rule['event'] != event.type) continue;
        await _executeRule(
          moduleId: moduleId,
          module: module,
          rule: rule,
          event: event,
        );
      }
    }
  }

  Future<void> retry(RuleExecution execution) async {
    if (execution.status != 'failure') {
      throw StateError('Only failed rule executions can be retried');
    }
    final module = _modules[execution.moduleId];
    if (module == null) {
      throw StateError('Rule module is not active: ${execution.moduleId}');
    }
    final matches = module.rules.where(
      (rule) => rule['id'] == execution.ruleId,
    );
    if (matches.isEmpty) {
      throw StateError('Rule no longer exists: ${execution.ruleId}');
    }
    final decoded = jsonDecode(execution.eventPayloadJson);
    final payload = decoded is Map
        ? decoded.map((key, value) => MapEntry('$key', value))
        : <String, Object?>{};
    final event = DomainEvent(
      type: execution.eventType,
      entityType: execution.entityType,
      entityId: execution.entityId,
      payload: payload,
    );
    await _executeRule(
      moduleId: execution.moduleId,
      module: module,
      rule: matches.first,
      event: event,
      sourceExecutionId: execution.id,
      ignoreTrace: true,
    );
  }

  Future<void> _executeRule({
    required String moduleId,
    required _RuleModule module,
    required Map<String, Object?> rule,
    required DomainEvent event,
    int? sourceExecutionId,
    bool ignoreTrace = false,
  }) async {
    final ruleId = rule['id'] as String;
    final ruleKey = '$moduleId:$ruleId';
    final actions = (rule['actions'] as List).cast<Map>();

    if (event.automationDepth >= maxDepth) {
      await _log(
        moduleId: moduleId,
        ruleId: ruleId,
        event: event,
        status: 'skipped',
        message: '达到最大自动化深度 $maxDepth',
        actionCount: 0,
        sourceExecutionId: sourceExecutionId,
      );
      return;
    }
    if (!ignoreTrace && event.automationTrace.contains(ruleKey)) {
      await _log(
        moduleId: moduleId,
        ruleId: ruleId,
        event: event,
        status: 'skipped',
        message: '规则已在当前自动化链执行',
        actionCount: 0,
        sourceExecutionId: sourceExecutionId,
      );
      return;
    }

    try {
      final row = await _contextRow(module.context, event, rule['condition']);
      if (!const FilterExpression().evaluate(
        row,
        rule['condition'],
        fieldNamespace: moduleId,
      )) {
        await _log(
          moduleId: moduleId,
          ruleId: ruleId,
          event: event,
          status: 'skipped',
          message: '条件不满足',
          actionCount: 0,
          sourceExecutionId: sourceExecutionId,
        );
        return;
      }

      await _log(
        moduleId: moduleId,
        ruleId: ruleId,
        event: event,
        status: 'triggered',
        actionCount: actions.length,
        sourceExecutionId: sourceExecutionId,
      );

      await runAutomationStep<void>(
        ruleKey: ruleKey,
        parentDepth: event.automationDepth,
        parentTrace: event.automationTrace,
        action: () async {
          for (final action in actions) {
            final command = action['command'] as String;
            final payload = _resolveObject(
              action['payload'] ?? const <String, Object?>{},
              row,
              moduleId,
            );
            await commands.execute(
              module.context,
              command,
              (payload as Map).cast<String, Object?>(),
            );
          }
        },
      );

      await _log(
        moduleId: moduleId,
        ruleId: ruleId,
        event: event,
        status: 'success',
        actionCount: actions.length,
        sourceExecutionId: sourceExecutionId,
      );
    } catch (error) {
      await _log(
        moduleId: moduleId,
        ruleId: ruleId,
        event: event,
        status: 'failure',
        message: '$error',
        actionCount: actions.length,
        sourceExecutionId: sourceExecutionId,
      );
    }
  }

  Future<void> _log({
    required String moduleId,
    required String ruleId,
    required DomainEvent event,
    required String status,
    String? message,
    required int actionCount,
    int? sourceExecutionId,
  }) {
    final safeMessage = message == null || message.length <= 1000
        ? message
        : message.substring(0, 1000);
    return executions.append(
      moduleId: moduleId,
      ruleId: ruleId,
      eventType: event.type,
      entityType: event.entityType,
      entityId: event.entityId,
      eventPayloadJson: jsonEncode(event.payload),
      sourceExecutionId: sourceExecutionId,
      status: status,
      message: safeMessage,
      automationDepth: event.automationDepth,
      actionCount: actionCount,
    );
  }

  Future<Map<String, Object?>> _contextRow(
    ModuleContext context,
    DomainEvent event,
    Object? condition,
  ) async {
    final row = <String, Object?>{
      'event': <String, Object?>{
        'type': event.type,
        'entityType': event.entityType,
        'entityId': event.entityId,
        'payload': event.payload,
      },
    };

    if (condition != null && event.entityType == 'task') {
      row['task'] = await queries.execute(context, 'task.get', {
        'id': event.entityId,
      });
    }
    return row;
  }

  Object? _resolveObject(
    Object? value,
    Map<String, Object?> row,
    String moduleId,
  ) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': _resolveObject(entry.value, row, moduleId),
      };
    }
    if (value is List) {
      return value
          .map((item) => _resolveObject(item, row, moduleId))
          .toList(growable: false);
    }
    if (value is! String || !value.startsWith(r'$')) return value;

    if (value == r'$today') {
      final now = DateTime.now();
      return '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
    }
    if (value.startsWith(r'$module.field.')) {
      return '$moduleId:${value.substring(r'$module.field.'.length)}';
    }
    return _readPath(row, value.substring(1));
  }

  Object? _readPath(Map<String, Object?> row, String path) {
    Object? current = row;
    for (final segment in path.split('.')) {
      if (current is! Map) return null;
      current = current[segment];
    }
    return current;
  }
}

class _RuleModule {
  const _RuleModule({required this.context, required this.rules});

  final ModuleContext context;
  final List<Map<String, Object?>> rules;
}
