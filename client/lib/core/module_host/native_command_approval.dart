import '../contracts/json_values.dart';
import 'plan_confirmation.dart';

/// Created by a native click or submitted host form, never by script execution.
/// A declaration describes intent; it becomes authority only at that boundary.
class NativeCommandApproval {
  NativeCommandApproval._(this._reference, this._input);

  final String _reference, _input;
  bool _used = false;

  static NativeCommandApproval? fromInteraction(
    Object? declaration, {
    Map<String, Object?>? submittedValues,
  }) {
    if (declaration is! Map ||
        declaration.keys.any(
          (key) => !{'ref', 'input', 'fields'}.contains(key),
        ) ||
        declaration['ref'] is! Map ||
        declaration['input'] is! Map) {
      return null;
    }
    final reference = declaration['ref'] as Map;
    if (reference.keys.toSet().difference({
          'moduleId',
          'serviceId',
          'majorVersion',
        }).isNotEmpty ||
        reference['moduleId'] is! String ||
        (reference['moduleId'] as String).isEmpty ||
        reference['serviceId'] is! String ||
        (reference['serviceId'] as String).isEmpty ||
        reference['majorVersion'] is! int ||
        (reference['majorVersion'] as int) < 1) {
      return null;
    }
    final input = <String, Object?>{};
    for (final entry in (declaration['input'] as Map).entries) {
      if (entry.key is! String) return null;
      input[entry.key as String] = entry.value;
    }
    if (declaration.containsKey('fields')) {
      final fields = declaration['fields'];
      if (fields is! Map || submittedValues == null) return null;
      for (final entry in fields.entries) {
        if (entry.key is! String ||
            (entry.key as String).isEmpty ||
            entry.value is! String ||
            !submittedValues.containsKey(entry.value)) {
          return null;
        }
        input[entry.key as String] = submittedValues[entry.value];
      }
    }
    return NativeCommandApproval._(
      canonicalJson(reference),
      canonicalJson(input),
    );
  }

  bool allows({
    required Object? reference,
    required Object? input,
    required List<Object?> writes,
    required PlanConfirmation? confirmation,
  }) {
    if (_used) return false;
    _used = true;
    if (confirmation?.acknowledgement != null ||
        canonicalJson(reference) != _reference ||
        canonicalJson(input) != _input ||
        writes.length != 1) {
      return false;
    }
    final write = writes.single;
    if (write is! Map || write['value'] is! Map) return false;
    final after = write['value'] as Map;
    // Soft deletion is still deletion even though storage represents it as an
    // upsert. It must continue through the visible review flow.
    if (after['deletedAt'] != null || after['deleted'] == true) return false;
    return true;
  }
}
