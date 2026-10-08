import '../contracts/json_values.dart';
import 'module_package.dart';

/// Small explicit JSON Schema subset. Unsupported constraints fail closed.
void validateSchema(
  Object? value,
  Map<String, Object?> schema, [
  String path = r'$',
]) {
  const supported = {
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
  for (final key in schema.keys) {
    if (!supported.contains(key)) {
      throw FormatException('Unsupported schema keyword: $key');
    }
  }
  final type = schema['type'];
  final types = type is List ? type : [type];
  bool matches(Object? t) => switch (t) {
    null => true,
    'null' => value == null,
    'object' => value is Map,
    'array' => value is List,
    'string' => value is String,
    'boolean' => value is bool,
    'integer' => value is int,
    'number' => value is num && value.isFinite,
    _ => false,
  };
  if (!types.any(matches)) throw FormatException('$path: expected $type');
  if (schema['enum'] is List &&
      !(schema['enum'] as List).any(
        (v) => canonicalJson(v) == canonicalJson(value),
      )) {
    throw FormatException('$path: not in enum');
  }
  if (value is Map) {
    final properties = object(schema['properties'] ?? {});
    for (final key in schema['required'] as List? ?? []) {
      if (!value.containsKey(key)) {
        throw FormatException('$path.$key: required');
      }
    }
    for (final key in value.keys) {
      if (properties.containsKey(key)) {
        validateSchema(value[key], object(properties[key]), '$path.$key');
      } else if (schema['additionalProperties'] == false) {
        throw FormatException('$path.$key: unknown property');
      }
    }
  }
  if (value is List) {
    if (schema['minItems'] is int &&
            value.length < (schema['minItems'] as int) ||
        schema['maxItems'] is int &&
            value.length > (schema['maxItems'] as int)) {
      throw FormatException('$path: array length');
    }
    if (schema['items'] != null) {
      for (var i = 0; i < value.length; i++) {
        validateSchema(value[i], object(schema['items']), '$path[$i]');
      }
    }
  }
  if (value is String &&
      (schema['minLength'] is int &&
              value.length < (schema['minLength'] as int) ||
          schema['maxLength'] is int &&
              value.length > (schema['maxLength'] as int))) {
    throw FormatException('$path: string length');
  }
  if (value is num &&
      (schema['minimum'] is num && value < (schema['minimum'] as num) ||
          schema['maximum'] is num && value > (schema['maximum'] as num))) {
    throw FormatException('$path: numeric range');
  }
}
