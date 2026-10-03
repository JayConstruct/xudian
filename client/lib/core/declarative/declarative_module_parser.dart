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
    if (json['formatVersion'] != 1) {
      throw const FormatException('Unsupported formatVersion');
    }
    final manifestJson = _object(json['manifest'], 'manifest');
    const manifestKeys = {
      'id',
      'version',
      'coreApi',
      'dependencies',
      'requiresCapabilities',
      'permissions',
    };
    for (final key in manifestJson.keys) {
      if (!manifestKeys.contains(key)) {
        throw FormatException('Unknown manifest key: $key');
      }
    }

    final manifest = ModuleManifest(
      id: _string(manifestJson['id'], 'manifest.id'),
      version: _string(manifestJson['version'], 'manifest.version'),
      coreApi: _string(manifestJson['coreApi'], 'manifest.coreApi'),
      dependencies: _stringList(manifestJson['dependencies']),
      requiresCapabilities:
          _stringList(manifestJson['requiresCapabilities']),
      permissions: _stringList(manifestJson['permissions']),
    );
    manifest.validate();

    final module = DeclarativeModule(
      formatVersion: 1,
      manifest: manifest,
      pages: _resources(json['pages'], 'pages'),
      views: _resources(json['views'], 'views'),
      fields: _resources(json['fields'], 'fields'),
      templates: _resources(json['templates'], 'templates'),
      rules: _resources(json['rules'], 'rules'),
      layouts: _resources(json['layouts'], 'layouts'),
    );
    _validateResources(module);
    return module;
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
          throw FormatException(
            'Duplicate ${entry.key} resource id: $id',
          );
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
    return List.unmodifiable(
      value.map((item) => _object(item, name)),
    );
  }
}
