import '../module_host/json_schema.dart';

const defaultUiPackId = 'app.ui.default';

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$label must be an object');
  }
  return value.cast<String, Object?>();
}

/// A public component contract is independent of its selected implementation.
class UiContract {
  const UiContract(
    this.ref, {
    this.propsSchema = uiCommonPropsSchema,
    this.requiredSlots = const [],
    this.events = const [],
  });
  final String ref;
  final Map<String, Object?> propsSchema;
  final List<String> requiredSlots, events;
  Map<String, Object?> toJson() => {
    'ref': ref,
    'propsSchema': propsSchema,
    'requiredSlots': requiredSlots,
    'events': events,
  };
}

const Map<String, Object?> uiCommonPropsSchema = {
  'type': 'object',
  'properties': {
    'label': {
      'type': ['string', 'null'],
    },
    'title': {
      'type': ['string', 'null'],
    },
    'text': {
      'type': ['string', 'null'],
    },
    'disabled': {'type': 'boolean'},
    'key': {'type': 'string'},
    'selectedIndex': {'type': 'integer'},
    'empty': {'type': 'boolean'},
    'destinations': {'type': 'array'},
  },
};

final Map<String, UiContract> uiContracts = Map.unmodifiable({
  for (final name in [
    'text',
    'icon',
    'section',
    'divider',
    'tag',
    'tabs',
    'filters',
    'loading',
    'empty',
    'error',
    'progress',
    'listTile',
    'entityRow',
  ])
    'ui.$name@1': UiContract('ui.$name@1'),
  'ui.button@1': const UiContract('ui.button@1', events: ['press']),
  'ui.card@1': const UiContract('ui.card@1', requiredSlots: ['content']),
  'ui.list@1': const UiContract('ui.list@1', requiredSlots: ['items']),
  for (final name in [
    'input',
    'numberInput',
    'checkbox',
    'toggle',
    'select',
    'multiSelect',
    'dateInput',
    'timeInput',
    'dateTimeInput',
    'dateRangeInput',
    'slider',
    'timeGrid',
  ])
    'ui.$name@1': UiContract('ui.$name@1', requiredSlots: const ['control']),
  for (final name in ['dialog', 'panel', 'floatingPanel'])
    'ui.$name@1': UiContract('ui.$name@1', requiredSlots: const ['content']),
  'ui.page.list@1': const UiContract(
    'ui.page.list@1',
    requiredSlots: ['items'],
  ),
  'ui.page.form@1': const UiContract(
    'ui.page.form@1',
    requiredSlots: ['fields', 'actions'],
  ),
  'ui.page.settings@1': const UiContract(
    'ui.page.settings@1',
    requiredSlots: ['sections'],
  ),
  'ui.page.detail@1': const UiContract(
    'ui.page.detail@1',
    requiredSlots: ['content', 'actions'],
  ),
  'ui.page.timeGrid@1': const UiContract(
    'ui.page.timeGrid@1',
    requiredSlots: ['grid'],
  ),
  'ui.chrome.bottomNav@1': const UiContract(
    'ui.chrome.bottomNav@1',
    requiredSlots: ['navigation', 'input'],
  ),
  'ui.chrome.sidebar@1': const UiContract(
    'ui.chrome.sidebar@1',
    requiredSlots: ['navigation'],
  ),
  'ui.chrome.header@1': const UiContract(
    'ui.chrome.header@1',
    requiredSlots: ['title', 'actions'],
  ),
});

class UiSelection {
  UiSelection({
    this.globalPackId = defaultUiPackId,
    Map<String, String> modulePackIds = const {},
  }) : modulePackIds = Map.unmodifiable(modulePackIds);
  final String globalPackId;
  final Map<String, String> modulePackIds;
  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'globalPackId': globalPackId,
    'modulePackIds': modulePackIds,
  };
  factory UiSelection.fromJson(Map<String, Object?> json) {
    if (json['formatVersion'] != 1 || json['globalPackId'] is! String) {
      throw const FormatException('Unsupported UI selection');
    }
    return UiSelection(
      globalPackId: json['globalPackId'] as String,
      modulePackIds: _map(
        json['modulePackIds'] ?? {},
        'module UI choices',
      ).cast<String, String>(),
    );
  }
  UiSelection copyWith({
    String? globalPackId,
    Map<String, String>? modulePackIds,
  }) => UiSelection(
    globalPackId: globalPackId ?? this.globalPackId,
    modulePackIds: modulePackIds ?? this.modulePackIds,
  );
}

/// Bindings and recipes are parsed once at package verification, never per frame.
class UiBinding {
  UiBinding(this.path);
  final List<Object> path;
  Object? read(Map<String, Object?> scope) {
    Object? value = scope;
    for (final part in path) {
      if (value is Map && part is String) {
        value = value[part];
      } else if (value is List &&
          part is int &&
          part >= 0 &&
          part < value.length) {
        value = value[part];
      } else {
        return null;
      }
    }
    return value;
  }
}

Object? _compileValue(Object? raw, [int depth = 0]) {
  if (depth > 32) throw const FormatException('UI value exceeds 32 levels');
  if (raw is Map) {
    if (raw.containsKey('bind')) {
      final path = raw['bind'];
      if (raw.length != 1 ||
          path is! List ||
          path.isEmpty ||
          !['props', 'item', 'index', 'environment'].contains(path.first) ||
          path.any((p) => p is! String && (p is! int || p < 0))) {
        throw const FormatException('Invalid UI binding');
      }
      return UiBinding(List<Object>.unmodifiable(path.cast<Object>()));
    }
    return Map<String, Object?>.unmodifiable(
      _map(
        raw,
        'UI value',
      ).map((k, v) => MapEntry(k, _compileValue(v, depth + 1))),
    );
  }
  if (raw is List) {
    return List<Object?>.unmodifiable(
      raw.map((v) => _compileValue(v, depth + 1)),
    );
  }
  if (raw is num && !raw.isFinite) {
    throw const FormatException('Non-finite UI value');
  }
  return raw;
}

Object? evaluateUiValue(Object? raw, Map<String, Object?> scope) {
  if (raw is UiBinding) return raw.read(scope);
  if (raw is Map<String, Object?>) {
    return raw.map((k, v) => MapEntry(k, evaluateUiValue(v, scope)));
  }
  if (raw is List) return raw.map((v) => evaluateUiValue(v, scope)).toList();
  return raw;
}

class UiRecipeNode {
  UiRecipeNode._(
    this.type,
    this.values,
    this.children,
    this.branches,
    this.slots,
  );
  final String type;
  final Map<String, Object?> values;
  final List<UiRecipeNode> children;
  final Map<String, UiRecipeNode> branches, slots;
  static const primitiveNames = {
    'column',
    'row',
    'wrap',
    'card',
    'text',
    'button',
    'icon',
    'divider',
    'spacer',
    'padding',
    'expanded',
    'scroll',
    'list',
  };
  factory UiRecipeNode.parse(Object? raw, [int depth = 0]) {
    if (depth > 32) throw const FormatException('UI recipe exceeds 32 levels');
    final spec = _map(raw, 'UI recipe');
    final type = spec['type'];
    final allowed = switch (type) {
      'base' => {'type'},
      'slot' => {'type', 'name'},
      'primitive' => {'type', 'name', 'props', 'children', 'event'},
      'component' => {'type', 'ref', 'props', 'slots', 'events'},
      'if' => {'type', 'condition', 'then', 'else'},
      'repeat' => {'type', 'items', 'child', 'key'},
      'responsive' => {'type', 'narrow', 'wide'},
      _ => throw FormatException('Unknown UI recipe node: $type'),
    };
    if (spec.keys.any((k) => !allowed.contains(k))) {
      throw FormatException('Unknown $type UI field');
    }
    if (type == 'slot' &&
        (spec['name'] is! String || (spec['name'] as String).isEmpty)) {
      throw const FormatException('UI slot requires a name');
    }
    if (type == 'primitive' && !primitiveNames.contains(spec['name'])) {
      throw FormatException('Unknown UI primitive: ${spec['name']}');
    }
    if (type == 'component' && !_validRef(spec['ref'])) {
      throw const FormatException('Invalid component reference');
    }
    if (spec['event'] != null && spec['event'] is! String) {
      throw const FormatException('Invalid event port');
    }
    if (spec.containsKey('event') &&
        (type != 'primitive' || spec['name'] != 'button')) {
      throw const FormatException(
        'Only an interactive primitive can forward an event',
      );
    }
    if (type == 'primitive' && spec.containsKey('children')) {
      final children = spec['children'];
      if (children is! List ||
          (!{
                'column',
                'row',
                'wrap',
                'card',
                'padding',
                'expanded',
                'scroll',
                'list',
              }.contains(spec['name']) &&
              children.isNotEmpty) ||
          {'padding', 'expanded', 'scroll'}.contains(spec['name']) &&
              children.length > 1) {
        throw const FormatException('Primitive cannot render these children');
      }
    }
    final children = <UiRecipeNode>[],
        branches = <String, UiRecipeNode>{},
        slots = <String, UiRecipeNode>{};
    final values = <String, Object?>{};
    for (final entry in spec.entries) {
      if (entry.key == 'type') continue;
      if (['then', 'else', 'child', 'narrow', 'wide'].contains(entry.key)) {
        branches[entry.key] = UiRecipeNode.parse(entry.value, depth + 1);
      } else if (entry.key == 'children') {
        if (entry.value is! List) {
          throw const FormatException('UI children must be an array');
        }
        children.addAll(
          (entry.value as List).map((v) => UiRecipeNode.parse(v, depth + 1)),
        );
      } else if (entry.key == 'slots') {
        slots.addAll(
          _map(
            entry.value,
            'slots',
          ).map((k, v) => MapEntry(k, UiRecipeNode.parse(v, depth + 1))),
        );
      } else {
        values[entry.key] = _compileValue(entry.value);
      }
    }
    if (type == 'if' &&
            (!spec.containsKey('condition') ||
                !branches.containsKey('then') ||
                !branches.containsKey('else')) ||
        type == 'repeat' &&
            (!spec.containsKey('items') || !branches.containsKey('child')) ||
        type == 'responsive' &&
            (!branches.containsKey('narrow') ||
                !branches.containsKey('wide'))) {
      throw const FormatException('Incomplete UI branch');
    }
    if (values.containsKey('props') && values['props'] is! Map) {
      throw const FormatException('UI props must be an object');
    }
    if (values.containsKey('events')) {
      final events = _map(values['events'], 'event forwarding');
      if (events.values.any((v) => v is! String)) {
        throw const FormatException('UI events only forward named ports');
      }
    }
    return UiRecipeNode._(
      type as String,
      Map.unmodifiable(values),
      List.unmodifiable(children),
      Map.unmodifiable(branches),
      Map.unmodifiable(slots),
    );
  }
  Iterable<UiRecipeNode> get descendants sync* {
    yield this;
    for (final child in [...children, ...branches.values, ...slots.values]) {
      yield* child.descendants;
    }
  }

  bool guarantees(String name, {bool event = false}) {
    if (type == 'base') return true;
    if (event
        ? values['event'] == name
        : type == 'slot' && values['name'] == name) {
      return true;
    }
    if (type == 'if' || type == 'responsive') {
      return branches.values.every((v) => v.guarantees(name, event: event));
    }
    if (type == 'repeat') return false;
    return children.any((v) => v.guarantees(name, event: event));
  }
}

bool _validRef(Object? ref) =>
    ref is String &&
    RegExp(r'^[a-z][a-zA-Z0-9_.-]*@[1-9][0-9]*$').hasMatch(ref);

class UiRecipe {
  UiRecipe(this.contract, this.tree);
  final UiContract contract;
  final UiRecipeNode tree;
}

class UiPackDefinition {
  UiPackDefinition._(
    this.moduleId,
    this.version,
    this.digest,
    this.components,
    this.tokens,
    this.contracts,
  );
  final String moduleId, version, digest;
  final Map<String, UiRecipe> components;
  final Map<String, Map<String, Object?>> tokens;
  final Map<String, UiContract> contracts;
  factory UiPackDefinition.parse({
    required String moduleId,
    required String version,
    required String digest,
    required Map<String, Object?> source,
  }) {
    if (source['contractVersion'] != 1 ||
        source.keys.any(
          (k) => !{
            'contractVersion',
            'tokens',
            'components',
            'templates',
            'chrome',
          }.contains(k),
        )) {
      throw const FormatException('Unsupported UI pack contract');
    }
    final tokens = <String, Map<String, Object?>>{};
    for (final mode in _map(source['tokens'] ?? {}, 'UI tokens').entries) {
      if (!['light', 'dark'].contains(mode.key)) {
        throw const FormatException('Unknown UI token mode');
      }
      final values = _map(mode.value, 'UI tokens');
      for (final e in values.entries) {
        if ([
          'primary',
          'surface',
          'canvas',
          'onSurface',
          'outline',
        ].contains(e.key)) {
          if (e.value is! String ||
              !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$')
                  .hasMatch(e.value as String)) {
            throw FormatException('Invalid UI color: ${e.key}');
          }
        } else if (['radius', 'spacing', 'fontScale'].contains(e.key)) {
          if (e.value is! num ||
              !(e.value as num).isFinite ||
              (e.value as num) < (e.key == 'fontScale' ? .8 : 0) ||
              (e.value as num) > (e.key == 'fontScale' ? 1.6 : 48)) {
            throw FormatException('Invalid UI dimension: ${e.key}');
          }
        } else {
          throw FormatException('Unknown UI token: ${e.key}');
        }
      }
      tokens[mode.key] = Map.unmodifiable(values);
    }
    final components = <String, UiRecipe>{}, contracts = <String, UiContract>{};
    for (final group in ['components', 'templates', 'chrome']) {
      for (final entry in _map(source[group] ?? {}, 'UI $group').entries) {
        if (!_validRef(entry.key) || components.containsKey(entry.key)) {
          throw const FormatException('Invalid or duplicate UI component');
        }
        final definition = _map(entry.value, 'UI component');
        if (definition.keys.any(
          (k) =>
              !{'tree', 'propsSchema', 'requiredSlots', 'events'}.contains(k),
        )) {
          throw const FormatException('Unknown UI component definition field');
        }
        final system = uiContracts[entry.key];
        if (system == null && !entry.key.startsWith('$moduleId.')) {
          throw const FormatException(
            'UI exports must use their package namespace',
          );
        }
        if (system != null && definition.keys.any((k) => k != 'tree')) {
          throw const FormatException(
            'System UI contracts cannot be redefined',
          );
        }
        final schema = _map(
          definition['propsSchema'] ?? {'type': 'object'},
          'component props schema',
        );
        _validateSchemaDefinition(schema);
        final contract =
            system ??
            UiContract(
              entry.key,
              propsSchema: Map.unmodifiable(schema),
              requiredSlots: List<String>.unmodifiable(
                (definition['requiredSlots'] as List? ?? []).cast<String>(),
              ),
              events: List<String>.unmodifiable(
                (definition['events'] as List? ?? []).cast<String>(),
              ),
            );
        final tree = UiRecipeNode.parse(definition['tree']);
        _validateNativePlacement(tree, contract);
        for (final slot in contract.requiredSlots) {
          if (!tree.guarantees(slot)) {
            throw FormatException(
              '${entry.key} must retain slot $slot in every branch',
            );
          }
        }
        for (final event in contract.events) {
          if (!tree.guarantees(event, event: true)) {
            throw FormatException('${entry.key} must retain event $event');
          }
        }
        final recipe = UiRecipe(contract, tree);
        components[entry.key] = recipe;
        contracts[entry.key] = contract;
      }
    }
    if (components.isEmpty && tokens.isEmpty) {
      throw const FormatException('Empty UI pack');
    }
    final pack = UiPackDefinition._(
      moduleId,
      version,
      digest,
      Map.unmodifiable(components),
      Map.unmodifiable(tokens),
      Map.unmodifiable(contracts),
    );
    pack._validateCycles();
    return pack;
  }
  void _validateCycles() {
    final visiting = <String>{}, visited = <String>{};
    void visit(String ref) {
      if (!visiting.add(ref)) throw const FormatException('Circular UI recipe');
      if (visiting.length > 33) {
        throw const FormatException('UI component chain exceeds 32 levels');
      }
      for (final node in components[ref]!.tree.descendants) {
        final target = node.values['ref'];
        if (node.type == 'component' &&
            components.containsKey(target) &&
            !visited.contains(target)) {
          visit(target as String);
        }
      }
      visiting.remove(ref);
      visited.add(ref);
    }

    for (final ref in components.keys) {
      if (!visited.contains(ref)) visit(ref);
    }
    final expandedDepth = <String, int>{};
    int referenceDepth(String ref) {
      if (expandedDepth.containsKey(ref)) return expandedDepth[ref]!;
      int nodeDepth(UiRecipeNode node) {
        var deepest = 0;
        for (final child in [
          ...node.children,
          ...node.branches.values,
          ...node.slots.values,
        ]) {
          final childDepth = nodeDepth(child);
          if (childDepth > deepest) deepest = childDepth;
        }
        if (node.type == 'component' &&
            components.containsKey(node.values['ref'])) {
          final targetDepth = referenceDepth(node.values['ref'] as String);
          if (targetDepth > deepest) deepest = targetDepth;
        }
        return deepest + 1;
      }

      final depth = nodeDepth(components[ref]!.tree);
      if (depth > 33) {
        throw const FormatException('Expanded UI recipe exceeds 32 levels');
      }
      expandedDepth[ref] = depth;
      return depth;
    }

    for (final ref in components.keys) {
      referenceDepth(ref);
    }
  }

  void validateDependencies(
    Map<String, UiPackDefinition> available,
    List<String> declaredDependencies,
  ) {
    for (final recipe in components.values) {
      for (final node in recipe.tree.descendants.where(
        (n) => n.type == 'component',
      )) {
        final ref = node.values['ref'] as String;
        if (uiContracts.containsKey(ref) || contracts.containsKey(ref)) {
          continue;
        }
        if (!declaredDependencies.any(
          (id) => available[id]?.contracts.containsKey(ref) == true,
        )) {
          throw FormatException(
            'Undeclared or missing UI component dependency: $ref',
          );
        }
      }
    }
  }

  void validateProps(String ref, Map<String, Object?> props) =>
      validateSchema(props, contracts[ref]!.propsSchema);
}

void _validateNativePlacement(UiRecipeNode tree, UiContract contract) {
  Map<String, int> usage(UiRecipeNode node) {
    if (node.type == 'base') return {'base': 1};
    if (node.type == 'slot') return {'slot:${node.values['name']}': 1};
    if (node.type == 'if' || node.type == 'responsive') {
      final result = <String, int>{};
      for (final branch in node.branches.values) {
        for (final entry in usage(branch).entries) {
          if ((result[entry.key] ?? 0) < entry.value) {
            result[entry.key] = entry.value;
          }
        }
      }
      return result;
    }
    final result = <String, int>{};
    for (final child in [...node.children, ...node.slots.values]) {
      for (final entry in usage(child).entries) {
        result[entry.key] = (result[entry.key] ?? 0) + entry.value;
      }
    }
    if (result.values.any((count) => count > 1)) {
      throw const FormatException('A native UI slot may only appear once');
    }
    if ((result['base'] ?? 0) > 0 &&
        result.keys.any((k) => k.startsWith('slot:'))) {
      throw const FormatException(
        'Base cannot be duplicated by explicit native slots',
      );
    }
    if (node.type == 'repeat' && usage(node.branches['child']!).isNotEmpty) {
      throw const FormatException(
        'Repeated UI may not duplicate a native control',
      );
    }
    final bounded =
        contract.ref == 'ui.page.list@1' ||
        contract.ref == 'ui.page.timeGrid@1' ||
        contract.ref == 'ui.chrome.sidebar@1';
    if (bounded &&
        node.type == 'primitive' &&
        {'scroll', 'list', 'wrap', 'row'}.contains(node.values['name']) &&
        result.keys.any(
          (k) =>
              k == 'base' ||
              {'slot:items', 'slot:grid', 'slot:navigation'}.contains(k),
        )) {
      throw const FormatException(
        'Scrollable native slots need a bounded vertical layout',
      );
    }
    return result;
  }

  usage(tree);
}

void _validateSchemaDefinition(Map<String, Object?> schema, [int depth = 0]) {
  if (depth > 32) throw const FormatException('UI schema exceeds 32 levels');
  // Exercise the same supported subset as business DTO schemas, recursively.
  const keys = {
    'type',
    'properties',
    'required',
    'additionalProperties',
    'items',
    'enum',
    'minimum',
    'maximum',
    'minLength',
    'maxLength',
    'minItems',
    'maxItems',
    'description',
    'title',
  };
  if (schema.keys.any((k) => !keys.contains(k))) {
    throw const FormatException('Unsupported UI props schema keyword');
  }
  const types = {
    'null',
    'object',
    'array',
    'string',
    'boolean',
    'integer',
    'number',
  };
  final rawType = schema['type'];
  if (rawType != null &&
      (rawType is List
          ? rawType.isEmpty || rawType.any((t) => !types.contains(t))
          : !types.contains(rawType))) {
    throw const FormatException('Invalid UI schema type');
  }
  if (schema.containsKey('required') &&
          (schema['required'] is! List ||
              (schema['required'] as List).any((v) => v is! String)) ||
      schema.containsKey('additionalProperties') &&
          schema['additionalProperties'] is! bool ||
      schema.containsKey('enum') && schema['enum'] is! List) {
    throw const FormatException('Invalid UI schema constraint');
  }
  for (final key in ['minimum', 'maximum']) {
    if (schema.containsKey(key) &&
        (schema[key] is! num || !(schema[key] as num).isFinite)) {
      throw const FormatException('Invalid UI schema numeric bound');
    }
  }
  for (final key in ['minLength', 'maxLength', 'minItems', 'maxItems']) {
    if (schema.containsKey(key) &&
        (schema[key] is! int || (schema[key] as int) < 0)) {
      throw const FormatException('Invalid UI schema length bound');
    }
  }
  if (schema['enum'] != null) _compileValue(schema['enum']);
  for (final child in _map(
    schema['properties'] ?? {},
    'schema properties',
  ).values) {
    _validateSchemaDefinition(_map(child, 'property schema'), depth + 1);
  }
  if (schema['items'] != null) {
    _validateSchemaDefinition(_map(schema['items'], 'items schema'), depth + 1);
  }
}
