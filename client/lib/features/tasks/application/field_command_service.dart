import '../../../core/declarative/runtime/field_value_store.dart';
import '../../../core/events/domain_event.dart';
import '../../../core/events/event_bus.dart';
import '../data/change_journal.dart';

class FieldCommandService {
  FieldCommandService({required this.store, required this.events});

  final FieldValueStore store;
  final EventBus events;

  /// All values, including clears (null), commit with their journal entries.
  Future<void> updateValues(String taskId, Map<String, Object?> values) async {
    final changed = <String>[];
    await store.db.transaction(() async {
      final journal = ChangeJournal(store.db);
      for (final entry in values.entries) {
        final didChange = entry.value == null
            ? await store.clearValue(taskId: taskId, fieldKey: entry.key)
            : await store.setValue(
                taskId: taskId,
                fieldKey: entry.key,
                value: entry.value,
              );
        if (!didChange) continue;
        changed.add(entry.key);
        await journal.append(
          entityType: 'task',
          entityId: taskId,
          action: entry.value == null ? 'field.clear' : 'field.set',
          payload: {
            'fieldKey': entry.key,
            if (entry.value != null) 'value': entry.value,
          },
        );
      }
    });
    if (changed.isNotEmpty) {
      // EventBus also defers this event when a template owns the outer commit.
      events.publish(
        DomainEvent(
          type: 'task.updated',
          entityType: 'task',
          entityId: taskId,
          payload: {
            'fields': changed
                .map((key) => 'fields.$key')
                .toList(growable: false),
          },
        ),
      );
    }
  }
}
