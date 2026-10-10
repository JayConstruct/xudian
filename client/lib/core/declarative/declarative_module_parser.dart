import '../modules/module_manifest.dart';
import 'declarative_module.dart';

class DeclarativeModuleParser {
  const DeclarativeModuleParser();

  DeclarativeModule parse(Map<String, Object?> json) {
    const allowedTop = {
      'formatVersion',
      'manifest',
      'pages',
      'views',
      'fields',
      'templates',
      'rules',
      'layouts',
    };
    for (final key in json.keys) {
      if (!allowedTop.contains(key)) {
        throw FormatException('Unknown top-level key: $key');
      }
    }
    final formatVersion = json['formatVersion'];
    if (formatVersion is! int || (formatVersion != 1 && formatVersion != 2)) {
      throw const FormatException('Unsupported formatVersion');
    }
    final manifestJson = _object(json['manifest'], 'manifest');
    const manifestKeys = {
      'id',
      'version',
      'coreApi',
      'description',
      'author',
      'dependencies',
      'requiresCapabilities',
      'permissions',
    };
    for (final key in manifestJson.keys) {
      if (!manifestKeys.contains(key)) {
        throw FormatException('Unknown manifest key: $key');
      }
    }

    for (final key in ['description', 'author']) {
      if (manifestJson[key] != null && manifestJson[key] is! String) {
        throw FormatException('manifest.$key must be a string');
      }
    }

    final manifest = ModuleManifest(
      id: _string(manifestJson['id'], 'manifest.id'),
      version: _string(manifestJson['version'], 'manifest.version'),
      coreApi: _string(manifestJson['coreApi'], 'manifest.coreApi'),
      description: manifestJson['description'] as String?,
      author: manifestJson['author'] as String?,
      dependencies: _stringList(manifestJson['dependencies']),
      requiresCapabilities: _stringList(manifestJson['requiresCapabilities']),
      permissions: _stringList(manifestJson['permissions']),
    );
    manifest.validate();

    final module = DeclarativeModule(
      formatVersion: formatVersion,
      manifest: manifest,
      pages: _resources(json['pages'], 'pages'),
      views: _resources(json['views'], 'views'),
      fields: _resources(json['fields'], 'fields'),
      templates: _resources(json['templates'], 'templates'),
      rules: _resources(json['rules'], 'rules'),
      layouts: _resources(json['layouts'], 'layouts'),
    );
    _validateResources(module);
    if (module.formatVersion == 2) validateComposition(module);
    return module;
  }

  void validateComposition(DeclarativeModule module) {
    if (!module.manifest.requiresCapabilities.contains('ui.composition') ||
        !module.manifest.requiresCapabilities.contains('ui.registry') ||
        !module.manifest.permissions.contains('ui.register')) {
      throw const FormatException(
        'Format v2 requires ui.composition, ui.registry and ui.register',
      );
    }
    final entryIds = <String>{};
    for (final page in module.pages) {
      _keys(page, const {
        'id',
        'title',
        'kind',
        'view',
        'icon',
        'selectedIcon',
        'quickAdd',
        'quickAddDefaults',
        'slots',
        'requiredContext',
        'retainPosition',
        'entry',
      }, 'page');
      _string(page['title'], 'page.title');
      _choice(page['kind'] ?? 'view', const {'view', 'container'}, 'page.kind');
      if ((page['kind'] ?? 'view') == 'view') {
        final viewId = _string(page['view'], 'page.view');
        if (!module.views.any((view) => view['id'] == viewId)) {
          throw FormatException('Page references unknown view: $viewId');
        }
      } else if (page.containsKey('view')) {
        throw const FormatException('Container page cannot declare view');
      }
      _context(page['requiredContext'], 'page.requiredContext');
      _boolean(page, 'retainPosition');
      _boolean(page, 'quickAdd');
      for (final name in ['icon', 'selectedIcon']) {
        if (page.containsKey(name)) _string(page[name], 'page.$name');
      }
      if (page.containsKey('quickAddDefaults')) {
        _object(page['quickAddDefaults'], 'page.quickAddDefaults');
      }
      final slotIds = <String>{};
      for (final slot in _resources(page['slots'], 'page.slots')) {
        _keys(slot, const {
          'id',
          'label',
          'kind',
          'public',
          'editable',
          'capacity',
          'requiredContext',
        }, 'slot');
        final id = _localId(slot['id'], 'slot.id');
        if (!slotIds.add(id)) throw FormatException('Duplicate slot id: $id');
        _string(slot['label'], 'slot.label');
        _choice(slot['kind'] ?? 'entries', const {
          'entries',
          'tabs',
          'sections',
        }, 'slot.kind');
        _boolean(slot, 'public');
        _boolean(slot, 'editable');
        if (slot.containsKey('capacity') &&
            (slot['capacity'] is! int || (slot['capacity'] as int) < 1)) {
          throw const FormatException(
            'slot.capacity must be a positive integer',
          );
        }
        _context(slot['requiredContext'], 'slot.requiredContext');
      }
      final entryValue = page['entry'];
      if (entryValue == null || entryValue == false) {
        continue;
      }
      final entry = _object(entryValue, 'page.entry');
      _keys(entry, const {
        'id',
        'label',
        'opening',
        'placement',
        'content',
        'targetPageId',
        'slotId',
        'order',
      }, 'entry');
      final id = _localId(entry['id'] ?? page['id'], 'entry.id');
      if (!entryIds.add(id)) throw FormatException('Duplicate entry id: $id');
      if (entry.containsKey('label')) _string(entry['label'], 'entry.label');
      _mount(module, entry, hostKey: 'targetPageId');
    }
    for (final layout in module.layouts) {
      _keys(layout, const {
        'id',
        'pageId',
        'label',
        'content',
        'opening',
        'placement',
        'hostPageId',
        'slotId',
        'order',
      }, 'layout');
      final id = _localId(layout['id'], 'layout.id');
      if (!entryIds.add(id)) throw FormatException('Duplicate entry id: $id');
      _reference(module, layout['pageId'], 'layout.pageId');
      _string(layout['label'], 'layout.label');
      _mount(module, layout, hostKey: 'hostPageId');
    }
  }

  void _mount(
    DeclarativeModule module,
    Map<String, Object?> value, {
    required String hostKey,
  }) {
    _choice(value['opening'] ?? 'workspace', const {
      'workspace',
      'detail',
      'adaptivePanel',
    }, 'opening');
    final placement = value['placement'] ?? 'main';
    _choice(placement, const {
      'main',
      'header',
      'more',
      'settings',
      'hidden',
      'page',
    }, 'placement');
    _boolean(value, 'content');
    if (value.containsKey('order') && value['order'] is! int) {
      throw const FormatException('order must be an integer');
    }
    if (placement == 'page') {
      _reference(module, value[hostKey], hostKey);
      final slotId = _localId(value['slotId'], 'slotId');
      final hostId = value[hostKey] as String;
      final localId = hostId.startsWith('${module.manifest.id}.')
          ? hostId.substring(module.manifest.id.length + 1)
          : hostId;
      final localHosts = module.pages.where((page) => page['id'] == localId);
      if (localHosts.isNotEmpty) {
        final slots = _resources(localHosts.single['slots'], 'page.slots');
        final targets = slots.where((slot) => slot['id'] == slotId);
        if (targets.isEmpty) {
          throw FormatException('Unknown local slot: $slotId');
        }
        final kind = targets.single['kind'] ?? 'entries';
        if ((value['content'] == true) == (kind == 'entries')) {
          throw const FormatException('Mount content does not match slot kind');
        }
      }
    } else if (value.containsKey(hostKey) ||
        value.containsKey('slotId') ||
        value['content'] == true) {
      throw const FormatException(
        'Host, slot and content require page placement',
      );
    }
  }

  void _reference(DeclarativeModule module, Object? value, String name) {
    final reference = _string(value, name);
    if (!RegExp(r'^[a-z][a-zA-Z0-9_-]*(\.[a-z][a-zA-Z0-9_-]*)*$')
        .hasMatch(reference)) {
      throw FormatException('Invalid page reference: $reference');
    }
    final localId = reference.startsWith('${module.manifest.id}.')
        ? reference.substring(module.manifest.id.length + 1)
        : reference;
    final local =
        !reference.contains('.') ||
        (reference.startsWith('${module.manifest.id}.') &&
            !localId.contains('.'));
    if (local && !module.pages.any((page) => page['id'] == localId)) {
      throw FormatException('Unknown local page: $reference');
    }
  }

  String _localId(Object? value, String name) {
    final id = _string(value, name);
    if (!RegExp(r'^[a-z][a-zA-Z0-9_-]*$').hasMatch(id)) {
      throw FormatException('Invalid $name: $id');
    }
    return id;
  }

  void _keys(Map<String, Object?> value, Set<String> allowed, String name) {
    for (final key in value.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('Unknown $name key: $key');
      }
    }
  }

  void _boolean(Map<String, Object?> value, String name) {
    if (value.containsKey(name) && value[name] is! bool) {
      throw FormatException('$name must be a boolean');
    }
  }

  void _choice(Object? value, Set<String> allowed, String name) {
    if (value is! String || !allowed.contains(value)) {
      throw FormatException('Unsupported $name: $value');
    }
  }

  void _context(Object? value, String name) {
    final required = _stringList(value);
    if (required.any((item) => item != 'taskId' && item != 'projectId')) {
      throw FormatException('$name only supports taskId and projectId');
    }
  }

  void _validateResources(DeclarativeModule module) {
    final groups = <String, List<Map<String, Object?>>>{
      'page': module.pages,
      'view': module.views,
      'field': module.fields,
      'template': module.templates,
      'rule': module.rules,
      'layout': module.layouts,
    };

    for (final entry in groups.entries) {
      final ids = <String>{};
      for (final resource in entry.value) {
        final id = _string(resource['id'], '${entry.key}.id');
        if (!RegExp(r'^[a-z][a-zA-Z0-9_-]*$').hasMatch(id)) {
          throw FormatException('Invalid resource id: $id');
        }
        if (!ids.add(id)) {
          throw FormatException('Duplicate ${entry.key} resource id: $id');
        }
      }
    }
  }

  Map<String, Object?> _object(Object? value, String name) {
    if (value is! Map) {
      throw FormatException('$name must be an object');
    }
    return value.map((key, item) => MapEntry('$key', item));
  }

  String _string(Object? value, String name) {
    if (value is! String || value.isEmpty) {
      throw FormatException('$name must be a non-empty string');
    }
    return value;
  }

  List<String> _stringList(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw const FormatException('Expected a string array');
    }
    final result = value.cast<String>();
    if (result.toSet().length != result.length) {
      throw const FormatException('Array values must be unique');
    }
    return List.unmodifiable(result);
  }

  List<Map<String, Object?>> _resources(Object? value, String name) {
    if (value == null) return const [];
    if (value is! List) {
      throw FormatException('$name must be an array');
    }
    return List.unmodifiable(value.map((item) => _object(item, name)));
  }
}
