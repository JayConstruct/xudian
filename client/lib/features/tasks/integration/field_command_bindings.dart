import '../../../core/contracts/command_bus.dart';
import '../../../core/declarative/runtime/field_value_store.dart';
import '../../../core/events/event_bus.dart';
import '../application/field_command_service.dart';

void registerFieldCommands(
  CommandBus bus,
  FieldValueStore store, {
  required EventBus events,
}) {
  final service = FieldCommandService(store: store, events: events);
  bus.registerScoped(
    'field.set',
    permission: 'fields.write',
    handler: (context, payload) async {
      final taskId = payload['taskId'];
      final fieldKey = payload['fieldKey'];
      if (taskId is! String || fieldKey is! String) {
        throw ArgumentError('field.set requires taskId and fieldKey');
      }
      _requireFieldOwner(context.moduleId, context.permissions, fieldKey);
      if (payload['value'] == null) {
        throw ArgumentError('field.set requires a non-null value');
      }
      await service.updateValues(taskId, {fieldKey: payload['value']});
      return null;
    },
  );

  bus.registerScoped(
    'field.clear',
    permission: 'fields.write',
    handler: (context, payload) async {
      final taskId = payload['taskId'];
      final fieldKey = payload['fieldKey'];
      if (taskId is! String || fieldKey is! String) {
        throw ArgumentError('field.clear requires taskId and fieldKey');
      }
      _requireFieldOwner(context.moduleId, context.permissions, fieldKey);
      await service.updateValues(taskId, {fieldKey: null});
      return null;
    },
  );
  bus.registerScoped(
    'field.setMany',
    permission: 'fields.write',
    handler: (context, payload) async {
      final taskId = payload['taskId'];
      final values = payload['values'];
      if (taskId is! String ||
          values is! Map ||
          values.keys.any((key) => key is! String)) {
        throw ArgumentError('field.setMany requires taskId and field values');
      }
      final changes = values.cast<String, Object?>();
      for (final key in changes.keys) {
        _requireFieldOwner(context.moduleId, context.permissions, key);
      }
      await service.updateValues(taskId, changes);
      return null;
    },
  );
}

void _requireFieldOwner(
  String moduleId,
  Set<String> permissions,
  String fieldKey,
) {
  if (permissions.contains('*') || fieldKey.startsWith('$moduleId:')) return;
  throw StateError('Module $moduleId cannot write field $fieldKey');
}
