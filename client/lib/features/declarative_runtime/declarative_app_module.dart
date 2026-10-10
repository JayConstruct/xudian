import 'package:flutter/material.dart';

import '../../core/declarative/declarative_module.dart';
import '../../core/declarative/declarative_module_parser.dart';
import '../../core/modules/app_module.dart';
import '../../core/modules/module_context.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/ui/app_destination.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_registration.dart';
import 'declarative_task_page.dart';

class DeclarativeAppModule implements AppModule {
  DeclarativeAppModule(this.module) {
    _validate();
  }

  final DeclarativeModule module;

  @override
  ModuleManifest get manifest => module.manifest;

  ModuleContext get _context =>
      ModuleContext(moduleId: manifest.id, permissions: manifest.permissions);

  @override
  List<UiRegistration> get ui => module.formatVersion == 2
      ? _compositionUi
      : [
          for (final page in module.pages)
            NavigationRegistration(
              AppDestination(
                id: '${manifest.id}.${page['id']}',
                label: page['title'] as String,
                icon: _icon(page['icon'] as String?),
                selectedIcon: _icon(
                  (page['selectedIcon'] ?? page['icon']) as String?,
                  selected: true,
                ),
                quickAdd: page['quickAdd'] == true,
                quickAddDefaults:
                    (page['quickAddDefaults'] as Map?)
                        ?.cast<String, Object?>() ??
                    const {},
                builder: (_) => DeclarativeTaskPage(
                  key: ValueKey('${manifest.id}:${page['id']}'),
                  module: module,
                  moduleContext: _context,
                  page: page,
                ),
              ),
            ),
        ];

  String _pageId(String reference) =>
      reference.contains('.') ? reference : '${manifest.id}.$reference';

  UiMount _mount(Map<String, Object?> value, String hostKey) => UiMount(
    placement: UiPlacement.values.byName(
      value['placement'] as String? ?? 'main',
    ),
    pageId: value[hostKey] == null ? null : _pageId(value[hostKey] as String),
    slotId: value['slotId'] as String?,
    order: value['order'] as int? ?? 0,
  );

  List<UiRegistration> get _compositionUi {
    final registrations = <UiRegistration>[];
    for (final page in module.pages) {
      final id = _pageId(page['id'] as String);
      final container = page['kind'] == 'container';
      registrations.add(
        UiPageRegistration(
          id: id,
          moduleId: manifest.id,
          title: page['title'] as String,
          container: container,
          requiredContext:
              (page['requiredContext'] as List?)?.cast<String>() ?? const [],
          retainPosition: page['retainPosition'] == true,
          quickAdd: page['quickAdd'] == true,
          quickAddDefaults:
              (page['quickAddDefaults'] as Map?)?.cast<String, Object?>() ??
              const {},
          slots: [
            for (final rawSlot in page['slots'] as List? ?? const [])
              PageSlotDefinition(
                id: (rawSlot as Map)['id'] as String,
                label: rawSlot['label'] as String,
                kind: PageSlotKind.values.byName(
                  rawSlot['kind'] as String? ?? 'entries',
                ),
                isPublic: rawSlot['public'] == true,
                editable: rawSlot['editable'] != false,
                capacity: rawSlot['capacity'] as int?,
                requiredContext:
                    (rawSlot['requiredContext'] as List?)?.cast<String>() ??
                    const [],
              ),
          ],
          builder: (_, pageContext) => container
              ? const SizedBox.shrink()
              : DeclarativeTaskPage(
                  key: ValueKey('$id:${pageContext.identity}'),
                  module: module,
                  moduleContext: _context,
                  page: page,
                  pageContext: pageContext,
                ),
        ),
      );
      if (page['entry'] == null || page['entry'] == false) {
        continue;
      }
      final entry =
          (page['entry'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      registrations.add(
        UiEntryRegistration(
          id: _pageId(entry['id'] as String? ?? page['id'] as String),
          moduleId: manifest.id,
          pageId: id,
          label: entry['label'] as String? ?? page['title'] as String,
          icon: _icon(page['icon'] as String?),
          selectedIcon: _icon(
            (page['selectedIcon'] ?? page['icon']) as String?,
            selected: true,
          ),
          opening: UiOpening.values.byName(
            entry['opening'] as String? ?? 'workspace',
          ),
          defaultMount: _mount(entry, 'targetPageId'),
          content: entry['content'] == true,
        ),
      );
    }
    for (final layout in module.layouts) {
      registrations.add(
        UiEntryRegistration(
          id: _pageId(layout['id'] as String),
          moduleId: manifest.id,
          pageId: _pageId(layout['pageId'] as String),
          label: layout['label'] as String,
          icon: _icon(null),
          opening: UiOpening.values.byName(
            layout['opening'] as String? ?? 'workspace',
          ),
          defaultMount: _mount(layout, 'hostPageId'),
          content: layout['content'] == true,
        ),
      );
    }
    return List.unmodifiable(registrations);
  }

  void _validate() {
    if (module.formatVersion != 1 && module.formatVersion != 2) {
      throw const FormatException('Unsupported formatVersion');
    }
    if (module.formatVersion == 2) {
      const DeclarativeModuleParser().validateComposition(module);
    }
    if (module.pages.isNotEmpty) {
      if (!module.manifest.requiresCapabilities.contains('ui.registry') ||
          !module.manifest.permissions.contains('ui.register')) {
        throw const FormatException(
          'Pages require ui.registry capability and ui.register permission',
        );
      }
    }
    if (module.views.isNotEmpty) {
      if (!module.manifest.requiresCapabilities.contains('tasks.query') ||
          !module.manifest.permissions.contains('tasks.read')) {
        throw const FormatException(
          'Views require tasks.query capability and tasks.read permission',
        );
      }
    }
    if (module.formatVersion == 1 && module.layouts.isNotEmpty) {
      throw const FormatException(
        'layouts are not executable in runtime v1 yet',
      );
    }

    final fieldIds = <String>{};
    for (final field in module.fields) {
      final id = field['id'];
      final label = field['label'];
      final type = field['type'];
      if (id is! String || label is! String || type is! String) {
        throw const FormatException('Field requires id, label and type');
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
        throw FormatException('Unsupported field type: $type');
      }
      fieldIds.add(id);

      if (type == 'select' || type == 'multiSelect') {
        final config = (field['config'] as Map?)?.cast<String, Object?>();
        final options = config?['options'];
        if (options is! List ||
            options.isEmpty ||
            options.any((item) => item is! String) ||
            options.toSet().length != options.length) {
          throw FormatException('Field $id requires unique string options');
        }
      }
    }

    for (final page in module.pages) {
      if (module.formatVersion == 2 && page['kind'] == 'container') continue;
      if (page['title'] is! String || page['view'] is! String) {
        throw FormatException('Page requires title and view');
      }
      final viewId = page['view'];
      if (!module.views.any((view) => view['id'] == viewId)) {
        throw FormatException('Page references unknown view: $viewId');
      }
    }
    for (final view in module.views) {
      if (view['source'] != 'task.list') {
        throw FormatException('Unsupported view source: ${view['source']}');
      }
      final filter = view['filter'];
      if (filter != null && filter is! Map) {
        throw const FormatException('View filter must be an object');
      }

      final showFields = view['showFields'];
      if (showFields != null) {
        if (showFields is! List || showFields.any((item) => item is! String)) {
          throw const FormatException('view.showFields must be a string array');
        }
        for (final value in showFields.cast<String>()) {
          if (value.contains(':')) continue;
          if (!fieldIds.contains(value)) {
            throw FormatException(
              'View references unknown local field: $value',
            );
          }
        }
      }
    }
  }

  static IconData _icon(String? name, {bool selected = false}) =>
      switch (name) {
        'today' => selected ? Icons.today : Icons.today_outlined,
        'inbox' => selected ? Icons.inbox : Icons.inbox_outlined,
        'folder' => selected ? Icons.folder : Icons.folder_outlined,
        _ => selected ? Icons.view_list : Icons.view_list_outlined,
      };
}
