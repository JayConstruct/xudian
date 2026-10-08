import 'package:flutter/material.dart';

import '../modules/app_module.dart';
import '../modules/module_manifest.dart';
import '../ui/ui_composition.dart';
import '../ui/ui_registration.dart';
import 'module_host.dart';
import 'module_package.dart';
import 'script_page.dart';
import 'script_launcher.dart';
import '../ui/ui_slot.dart';

class ScriptAppModule implements AppModule {
  ScriptAppModule(this.host, this.package);
  final ModuleHost host;
  final ScriptPackage package;
  @override
  ModuleManifest get manifest => ModuleManifest(
    id: package.id,
    version: package.version,
    coreApi: '1',
    dependencies: package.dependencies,
    requiresCapabilities: const ['ui.registry', 'ui.composition'],
    permissions: const ['ui.register'],
  );
  @override
  List<UiRegistration> get ui => [
    for (final raw in package.definition['pages'] as List? ?? [])
      ..._page(object(raw)),
    for (final raw in package.definition['contributions'] as List? ?? [])
      WidgetRegistration(
        UiSlot.values.byName(object(raw)['slot'] as String),
        object(raw)['id'] as String,
        (context) =>
            object(raw)['kind'] == 'content' &&
                object(raw)['slot'] != 'globalOverlay'
            ? ScriptPage(
                host: host,
                moduleId: package.id,
                handler: object(raw)['handler'] as String,
                pageContext: {'contributionId': object(raw)['id']},
                embedded: true,
              )
            : ScriptLauncher(
                host: host,
                moduleId: package.id,
                handler: object(raw)['handler'] as String,
                label: object(raw)['label'] as String,
                id: object(raw)['id'] as String,
                floating: object(raw)['slot'] == 'globalOverlay',
              ),
      ),
  ];
  List<UiRegistration> _page(Map<String, Object?> page) {
    final id = string(page['id'], 'page id');
    final entries = [
      if (page['entry'] != null) object(page['entry']),
      for (final raw in page['entries'] as List? ?? []) object(raw),
    ];
    return [
      UiPageRegistration(
        id: id,
        moduleId: package.id,
        title: page['title'] as String? ?? package.title,
        container: page['kind'] == 'container',
        retainPosition: page['retainPosition'] == true,
        headerMode: page['headerMode'] as String? ?? 'standard',
        requiredContext: (page['requiredContext'] as List? ?? [])
            .cast<String>(),
        slots: [
          for (final raw in page['slots'] as List? ?? [])
            PageSlotDefinition(
              id: object(raw)['id'] as String,
              label: object(raw)['label'] as String,
              kind: PageSlotKind.values.byName(
                object(raw)['kind'] as String? ?? 'entries',
              ),
              isPublic: object(raw)['public'] == true,
              editable: object(raw)['editable'] != false,
              capacity: object(raw)['capacity'] as int?,
              requiredContext: (object(raw)['requiredContext'] as List? ?? [])
                  .cast<String>(),
            ),
        ],
        builder: (_, context) => ScriptPage(
          key: ValueKey('$id:${context.identity}'),
          host: host,
          moduleId: package.id,
          handler: page['handler'] as String,
          pageContext: {
            if (package.definition['derivedFrom'] != null)
              'legacyPageId':
                  page['legacyPageId'] ?? id.substring(package.id.length + 1),
            ...context.values,
            'pageId': id,
            if (context.taskId != null) 'taskId': context.taskId,
            if (context.projectId != null) 'projectId': context.projectId,
          },
        ),
      ),
      for (final entry in entries)
        UiEntryRegistration(
          id: entry['id'] as String,
          moduleId: package.id,
          pageId: id,
          label:
              entry['label'] as String? ??
              page['title'] as String? ??
              package.title,
          icon: _icon(page['icon']),
          opening: UiOpening.values.byName(
            entry['opening'] as String? ?? 'workspace',
          ),
          content: entry['content'] == true,
          defaultMount: UiMount(
            placement: UiPlacement.values.byName(
              entry['placement'] as String? ?? 'main',
            ),
            pageId: entry['targetPageId'] as String?,
            slotId: entry['slotId'] as String?,
            order: entry['order'] as int? ?? 0,
            context: PageContext(
              taskId: entry['taskId'] as String?,
              projectId: entry['projectId'] as String?,
              values: object(entry['values'] ?? {}),
            ),
          ),
        ),
    ];
  }

  IconData _icon(Object? name) => switch (name) {
    'calendar' => Icons.calendar_month_outlined,
    'ai' => Icons.auto_awesome_outlined,
    'today' => Icons.today_outlined,
    'inbox' => Icons.inbox_outlined,
    'projects' => Icons.folder_outlined,
    _ => Icons.extension_outlined,
  };
}
