import '../../app/app_icons.dart';

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
      _contribution(object(raw)),
  ];

  UiRegistration _contribution(Map<String, Object?> contribution) {
    final slot = UiSlot.values.byName(contribution['slot'] as String);
    final id = contribution['id'] as String;
    final handler = contribution['handler'] as String;
    final label = contribution['label'] as String? ?? package.title;
    if (slot == UiSlot.workspaceAssistant) {
      return WorkspaceAssistantRegistration(
        id: id,
        label: label,
        supports: (moduleIds) => host.directoryServices().any((raw) {
          final service = object(raw);
          return moduleIds.contains(service['moduleId']) &&
              service['tool'] is Map;
        }),
        onOpen: (context, pageContext) => openScriptLauncher(
          context,
          host: host,
          moduleId: package.id,
          handler: handler,
          label: label,
          pageContext: pageContext,
        ),
      );
    }
    return WidgetRegistration(
      slot,
      id,
      (context) =>
          contribution['kind'] == 'content' && slot != UiSlot.globalOverlay
          ? ScriptPage(
              host: host,
              moduleId: package.id,
              handler: handler,
              pageContext: {'contributionId': id},
              embedded: true,
            )
          : ScriptLauncher(
              host: host,
              moduleId: package.id,
              handler: handler,
              label: label,
              id: id,
              floating: slot == UiSlot.globalOverlay,
            ),
    );
  }

  List<UiRegistration> _page(Map<String, Object?> page) {
    final id = string(page['id'], 'page id');
    final headerMode = page['headerMode'] ?? 'standard';
    if (!{'standard', 'contributed', 'date'}.contains(headerMode)) {
      throw const FormatException('Invalid page headerMode');
    }
    if (page['initializesRuntimeContext'] != null &&
        page['initializesRuntimeContext'] is! bool) {
      throw const FormatException('Invalid page initializesRuntimeContext');
    }
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
        headerMode: headerMode as String,
        initializesRuntimeContext: page['initializesRuntimeContext'] == true,
        requiredContext: (page['requiredContext'] as List? ?? [])
            .cast<String>(),
        slots: [
          for (final raw in page['slots'] as List? ?? [])
            _pageSlot(object(raw)),
        ],
        builder: (buildContext, context) => ScriptPage(
          key: ValueKey('$id:${context.navigationIdentity}'),
          host: host,
          moduleId: package.id,
          handler: page['handler'] as String,
          embedded: UiPageContentScope.inlineOf(buildContext),
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

  PageSlotDefinition _pageSlot(Map<String, Object?> slot) {
    final kind = PageSlotKind.values.byName(
      slot['kind'] as String? ?? 'entries',
    );
    final inline = slot.containsKey('inline') ? slot['inline'] : false;
    if (inline is! bool || inline && kind != PageSlotKind.sections) {
      throw const FormatException('inline requires a boolean sections slot');
    }
    return PageSlotDefinition(
      id: slot['id'] as String,
      label: slot['label'] as String,
      kind: kind,
      isPublic: slot['public'] == true,
      editable: slot['editable'] != false,
      inline: inline,
      capacity: slot['capacity'] as int?,
      requiredContext: (slot['requiredContext'] as List? ?? []).cast<String>(),
    );
  }

  IconData _icon(Object? name) => appIconData(name) ?? Icons.grid_view_outlined;
}
