import '../../../contracts/command_bus.dart';
import '../../../events/event_bus.dart';
import '../../../modules/module_context.dart';
import '../../../../data/app_database.dart';
import '../../declarative_module.dart';

class TemplateEngine {
  TemplateEngine({
    required this.commands,
    required this.db,
    required this.events,
  });

  final CommandBus commands;
  final AppDatabase db;
  final EventBus events;
  final Map<String, _TemplateModule> _modules = {};

  void installModule(DeclarativeModule module) {
    validateModule(module);
    if (module.templates.isEmpty) {
      _modules.remove(module.manifest.id);
      return;
    }
    _modules[module.manifest.id] = _TemplateModule(
      context: ModuleContext(
        moduleId: module.manifest.id,
        permissions: module.manifest.permissions,
      ),
      templates: module.templates,
    );
  }

  void removeModule(String moduleId) {
    _modules.remove(moduleId);
  }

  List<Map<String, Object?>> templatesFor(String moduleId) =>
      List.unmodifiable(_modules[moduleId]?.templates ?? const []);

  void validateModule(DeclarativeModule module) {
    if (module.templates.isNotEmpty &&
        !module.manifest.requiresCapabilities.contains('tasks.command')) {
      throw const FormatException('Templates require tasks.command capability');
    }
    for (final template in module.templates) {
      final id = template['id'];
      final title = template['title'];
      final tasks = template['tasks'];
      if (id is! String || title is! String || tasks is! List) {
        throw const FormatException('Template requires id, title and tasks');
      }
      if (tasks.isEmpty) {
        throw FormatException('Template $id requires at least one task');
      }
      if (!module.manifest.permissions.contains('tasks.write')) {
        throw FormatException('Template $id requires tasks.write permission');
      }
      final parameterIds = <String>{};
      final parameters = template['parameters'];
      if (parameters != null) {
        if (parameters is! List) {
          throw FormatException('Template $id parameters must be an array');
        }
        for (final raw in parameters) {
          if (raw is! Map) {
            throw FormatException('Template $id parameter must be object');
          }
          final paramId = raw['id'];
          final label = raw['label'];
          final type = raw['type'];
          if (paramId is! String || label is! String || type is! String) {
            throw FormatException(
              'Template $id parameter requires id, label and type',
            );
          }
          if (!parameterIds.add(paramId)) {
            throw FormatException('Template $id duplicate parameter: $paramId');
          }
          if (!const {
            'text',
            'number',
            'boolean',
            'date',
            'datetime',
            'select',
            'multiSelect',
          }.contains(type)) {
            throw FormatException(
              'Template $id unsupported parameter type: $type',
            );
          }
          if (type == 'select' || type == 'multiSelect') {
            final options = raw['options'];
            if (options is! List ||
                options.isEmpty ||
                options.any((item) => item is! String) ||
                options.toSet().length != options.length) {
              throw FormatException(
                'Template $id select parameter requires unique options',
              );
            }
          }
          if (raw.containsKey('default') && raw['default'] != null) {
            _validateParameterValue(paramId, type, raw['default'], raw);
          }
        }
      }

      final project = template['project'];
      if (project != null) {
        if (project is! Map ||
            project['name'] is! String ||
            (project['name'] as String).trim().isEmpty) {
          throw FormatException('Template $id project requires non-empty name');
        }
      }

      final seen = <String>{};
      for (final raw in tasks) {
        if (raw is! Map) {
          throw FormatException('Template $id task must be object');
        }
        final key = raw['key'];
        final taskTitle = raw['title'];
        if (key is! String || taskTitle is! String) {
          throw FormatException('Template $id task requires key and title');
        }
        if (!seen.add(key)) {
          throw FormatException('Template $id duplicate task key: $key');
        }
        final parentKey = raw['parentKey'];
        if (parentKey != null &&
            (parentKey is! String || !seen.contains(parentKey))) {
          throw FormatException(
            'Template $id parentKey must reference an earlier task',
          );
        }
        final fields = raw['fields'];
        if (fields != null &&
            (fields is! Map ||
                !module.manifest.permissions.contains('fields.write'))) {
          throw FormatException(
            'Template $id task fields require fields.write permission',
          );
        }
      }

      _validateParameterRefs(project, parameterIds, id);
      _validateParameterRefs(tasks, parameterIds, id);
    }
  }

  Future<TemplateApplyResult> apply(
    String moduleId,
    String templateId, {
    Map<String, Object?> parameters = const {},
  }) async {
    final module = _modules[moduleId];
    if (module == null) {
      throw StateError('Module templates not active: $moduleId');
    }
    final template = module.templates
        .where((item) => item['id'] == templateId)
        .singleOrNull;
    if (template == null) {
      throw StateError('Unknown template: $moduleId:$templateId');
    }
    final resolvedParameters = _resolveParameters(template, parameters);

    return events.afterCommit(
      () => db.transaction(
        () async =>
            _applyResolved(moduleId, module, template, resolvedParameters),
      ),
    );
  }

  Future<TemplateApplyResult> _applyResolved(
    String moduleId,
    _TemplateModule module,
    Map<String, Object?> template,
    Map<String, Object?> resolvedParameters,
  ) async {
    String? projectId;
    final project = template['project'];
    if (project is Map) {
      final result = await commands.execute(module.context, 'project.create', {
        'name': _resolveValue(project['name'], resolvedParameters),
      });
      projectId = (result as Map)['id'] as String;
    }

    final ids = <String, String>{};
    var created = 0;
    for (final raw in (template['tasks'] as List).cast<Map>()) {
      final key = raw['key'] as String;
      final parentKey = raw['parentKey'] as String?;
      final payload = <String, Object?>{
        'title': _resolveValue(raw['title'], resolvedParameters),
        'projectId': projectId,
        'parentTaskId': parentKey == null ? null : ids[parentKey],
        'priority': _resolveValue(raw['priority'] ?? 0, resolvedParameters),
        if (raw.containsKey('dueDate'))
          'dueDate': _resolveDate(
            _resolveValue(raw['dueDate'], resolvedParameters),
          ),
        if (raw.containsKey('plannedDate'))
          'plannedDate': _resolveDate(
            _resolveValue(raw['plannedDate'], resolvedParameters),
          ),
      };
      final result = await commands.execute(
        module.context,
        'task.create',
        payload,
      );
      final taskId = (result as Map)['id'] as String;
      ids[key] = taskId;
      created++;

      final fields = raw['fields'];
      if (fields is Map) {
        for (final entry in fields.entries) {
          await commands.execute(module.context, 'field.set', {
            'taskId': taskId,
            'fieldKey': '$moduleId:${entry.key}',
            'value': _resolveValue(entry.value, resolvedParameters),
          });
        }
      }
    }

    return TemplateApplyResult(
      projectId: projectId,
      taskIds: Map.unmodifiable(ids),
      createdTasks: created,
    );
  }

  Map<String, Object?> _resolveParameters(
    Map<String, Object?> template,
    Map<String, Object?> provided,
  ) {
    final definitions =
        (template['parameters'] as List?)?.cast<Map>() ?? const <Map>[];
    final known = definitions.map((item) => item['id'] as String).toSet();
    for (final key in provided.keys) {
      if (!known.contains(key)) {
        throw ArgumentError('Unknown template parameter: $key');
      }
    }

    final result = <String, Object?>{};
    for (final raw in definitions) {
      final id = raw['id'] as String;
      final type = raw['type'] as String;
      final hasProvided = provided.containsKey(id);
      final hasDefault = raw.containsKey('default');
      final value = hasProvided
          ? provided[id]
          : hasDefault
          ? raw['default']
          : null;
      if (value == null && raw['required'] == true) {
        throw ArgumentError('Missing required template parameter: $id');
      }
      if (value != null) {
        _validateParameterValue(id, type, value, raw);
      }
      result[id] = value;
    }
    return result;
  }

  void _validateParameterValue(
    String id,
    String type,
    Object value,
    Map definition,
  ) {
    final valid = switch (type) {
      'text' => value is String,
      'number' => value is num,
      'boolean' => value is bool,
      'date' => value is String && _isDate(value),
      'datetime' => value is String && DateTime.tryParse(value) != null,
      'select' =>
        value is String && (definition['options'] as List).contains(value),
      'multiSelect' =>
        value is List &&
            value.every(
              (item) =>
                  item is String &&
                  (definition['options'] as List).contains(item),
            ),
      _ => false,
    };
    if (!valid) {
      throw ArgumentError('Invalid value for template parameter $id ($type)');
    }
  }

  void _validateParameterRefs(
    Object? value,
    Set<String> parameterIds,
    String templateId,
  ) {
    if (value is Map) {
      for (final item in value.values) {
        _validateParameterRefs(item, parameterIds, templateId);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        _validateParameterRefs(item, parameterIds, templateId);
      }
      return;
    }
    if (value is! String) return;

    final matches = RegExp(r'\$param\.([a-z][a-zA-Z0-9_-]*)').allMatches(value);
    for (final match in matches) {
      final id = match.group(1)!;
      if (!parameterIds.contains(id)) {
        throw FormatException(
          'Template $templateId references unknown parameter: $id',
        );
      }
    }
  }

  Object? _resolveValue(Object? value, Map<String, Object?> parameters) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': _resolveValue(entry.value, parameters),
      };
    }
    if (value is List) {
      return value
          .map((item) => _resolveValue(item, parameters))
          .toList(growable: false);
    }
    if (value is! String) return value;

    final exact = RegExp(r'^\$param\.([a-z][a-zA-Z0-9_-]*)$').firstMatch(value);
    if (exact != null) {
      return parameters[exact.group(1)!];
    }

    return value.replaceAllMapped(
      RegExp(r'\$param\.([a-z][a-zA-Z0-9_-]*)'),
      (match) => parameters[match.group(1)!]?.toString() ?? '',
    );
  }

  bool _isDate(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
  }

  Object? _resolveDate(Object? value) {
    if (value is! String || !value.startsWith(r'$today')) return value;
    final match = RegExp(r'^\$today(?:(\+|-)\s*(\d+)d)?$').firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid relative date: $value');
    }
    var date = DateTime.now();
    final amount = int.tryParse(match.group(2) ?? '') ?? 0;
    if (amount != 0) {
      date = date.add(Duration(days: match.group(1) == '-' ? -amount : amount));
    }
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

class _TemplateModule {
  const _TemplateModule({required this.context, required this.templates});

  final ModuleContext context;
  final List<Map<String, Object?>> templates;
}

class TemplateApplyResult {
  const TemplateApplyResult({
    required this.projectId,
    required this.taskIds,
    required this.createdTasks,
  });

  final String? projectId;
  final Map<String, String> taskIds;
  final int createdTasks;
}
