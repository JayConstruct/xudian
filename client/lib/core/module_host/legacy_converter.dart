import 'dart:convert';

import 'package:flutter/services.dart';

import '../contracts/json_values.dart';
import '../declarative/declarative_module_parser.dart';
import 'module_package.dart';

/// Deterministic derived artifacts. The legacy source is a registered file and
/// its provenance stays in the legacy version table; no derived signature claim.
Future<ScriptPackage> convertLegacyModule(Map<String, Object?> source) async {
  final legacy = const DeclarativeModuleParser().parse(source);
  final id = legacy.manifest.id;
  final script = await rootBundle.loadString('assets/module-sdk/legacy.js');
  String pageId(String value) => value.contains('.') ? value : '$id.$value';
  final services = <Map<String, Object?>>[
    if (legacy.fields.isNotEmpty)
      for (final name in ['fields.set', 'fields.clear', 'fields.setMany'])
        {
          'id': name,
          'major': 1,
          'kind': 'command',
          'handler': name == 'fields.clear'
              ? 'fieldClear'
              : name == 'fields.setMany'
              ? 'fieldSetMany'
              : 'fieldSet',
          'input': {'type': 'object'},
          'output': {'type': 'object'},
        },
    if (legacy.fields.isNotEmpty)
      {
        'id': 'fields.query.entity',
        'major': 1,
        'kind': 'query',
        'handler': 'fieldQuery',
        'supportsBatch': true,
        'extensionFor': {
          'moduleId': 'app.tasks',
          'collection': 'tasks',
          'commands': {
            'set': 'fields.set',
            'clear': 'fields.clear',
            'setMany': 'fields.setMany',
          },
        },
        'input': {'type': 'object'},
        'output': {'type': 'object'},
      },
    for (final template in legacy.templates)
      {
        'id': 'template.${template['id']}',
        'major': 1,
        'kind': 'command',
        'handler': 'applyTemplate',
        'input': {'type': 'object'},
        'output': {'type': 'object'},
      },
    for (final rule in legacy.rules)
      {
        'id': 'rule.${rule['id']}',
        'major': 1,
        'kind': 'command',
        'handler': 'applyRule',
        'input': {'type': 'object'},
        'output': {'type': 'object'},
      },
  ];
  final permissions = [
    'ui',
    'clock.today',
    'events.subscribe',
    if (legacy.rules.isNotEmpty) 'automation.execute',
  ];
  if (legacy.manifest.permissions.contains('tasks.read') ||
      legacy.fields.isNotEmpty) {
    for (final s in ['task.list', 'task.get', 'project.list']) {
      permissions.add('services.query:app.tasks/$s@1');
    }
  }
  if (legacy.manifest.permissions.contains('tasks.write')) {
    for (final s in [
      'task.create',
      'task.updateFields',
      'task.setCompleted',
      'project.create',
    ]) {
      permissions.add('services.command:app.tasks/$s@1');
    }
  }
  final definition = <String, Object?>{
    'formatVersion': 3,
    'manifest': {
      'id': id,
      'name': id,
      if (legacy.manifest.description != null)
        'description': legacy.manifest.description,
      if (legacy.manifest.author != null) 'author': legacy.manifest.author,
      'version': legacy.manifest.version,
      'hostApi': '^1.0.0',
      'dataVersion': 1,
      'permissions': permissions,
      'dependencies': {
        ...legacy.manifest.dependencies,
        if (legacy.views.isNotEmpty ||
            legacy.templates.isNotEmpty ||
            legacy.rules.isNotEmpty ||
            legacy.fields.isNotEmpty)
          'app.tasks',
      }.toList(),
    },
    'entryPoint': 'main.js',
    'legacyExecutionCollection': 'ruleExecutions',
    'legacyEventProvider': 'app.tasks',
    'collections': [
      for (final name in ['fieldDefinitions', 'fieldValues', 'ruleExecutions'])
        {
          'id': name,
          'schema': {
            'type': 'object',
            'required': ['id'],
            'properties': {
              'id': {'type': 'string'},
            },
          },
        },
    ],
    'services': services,
    'rules': [
      for (final rule in legacy.rules)
        {
          'id': rule['id'],
          'event': rule['event'],
          'publishers': ['app.tasks', id],
          'serviceId': 'rule.${rule['id']}',
        },
    ],
    'pages': [
      for (final page in legacy.pages)
        {
          ...page,
          'id': pageId(page['id'] as String),
          'legacyPageId': page['id'],
          'handler': 'render',
          'entry': legacy.formatVersion == 1
              ? {
                  'id': pageId(page['id'] as String),
                  'opening': 'workspace',
                  'placement': 'main',
                }
              : page['entry'] is Map
              ? {
                  ...object(page['entry']),
                  'id': pageId(
                    object(page['entry'])['id'] as String? ??
                        page['id'] as String,
                  ),
                }
              : null,
        },
      if (legacy.templates.isNotEmpty)
        {
          'id': '$id.templates',
          'title': '模板',
          'handler': 'renderTemplates',
          'entry': {
            'id': '$id.templates',
            'opening': 'detail',
            'placement': 'more',
          },
        },
    ],
    'derivedFrom': {
      'formatVersion': legacy.formatVersion,
      'sourceDigest': await digest(utf8.encode(canonicalJson(source))),
      'converter': 'legacy-v3.3',
    },
  };
  final layouts = legacy.layouts;
  for (final layout in layouts) {
    final target = definition['pages'] as List<Map<String, Object?>>;
    final original = target.firstWhere(
      (p) => p['id'] == pageId(layout['pageId'] as String),
    );
    target.add({
      ...original,
      'id': '${pageId(layout['id'] as String)}.page',
      'entry': {
        'id': pageId(layout['id'] as String),
        'label': layout['label'],
        'opening': layout['opening'] ?? 'workspace',
        'placement': layout['placement'] ?? 'main',
        'content': layout['content'] == true,
        'targetPageId': layout['hostPageId'] == null
            ? null
            : pageId(layout['hostPageId'] as String),
        'slotId': layout['slotId'],
        'order': layout['order'] ?? 0,
      },
    });
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(definition, {
      'legacy.json': canonicalJson(source),
      'main.js':
          'const definition = ${canonicalJson({
            ...source,
            for (final key in ['fields', 'rules', 'templates', 'views', 'pages']) key: source[key] ?? [],
          })};\n$script',
    }),
    allowUnsignedLocal: true,
  );
}
