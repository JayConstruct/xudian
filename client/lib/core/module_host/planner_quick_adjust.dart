import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../contracts/json_values.dart';
import 'plan_confirmation.dart';

/// One native gesture can approve one exact time-only planner transaction.
/// The script cannot manufacture this capability or request a broader scope.
class PlannerQuickAdjustment {
  PlannerQuickAdjustment.move(
    Map<String, Object?> event, {
    required this.moduleId,
    required this.taskModuleId,
    required this.applyServiceId,
    required this.undoServiceId,
  }) : _event = _map(freezeJson(event));

  PlannerQuickAdjustment._undo(
    this._batch,
    this._taskWrite,
    this._occurrence, {
    required this.moduleId,
    required this.taskModuleId,
    required this.applyServiceId,
    required this.undoServiceId,
  }) : _event = null;

  final String moduleId, taskModuleId, applyServiceId, undoServiceId;

  final Map<String, Object?>? _event;
  Map<String, Object?>? _batch, _taskWrite, _occurrence;
  PlannerQuickAdjustment? _undo;
  bool _used = false;

  String? get batchId => _batch?['id'] as String?;
  PlannerQuickAdjustment? get undoAdjustment => _undo;

  /// Describe only the immutable task snapshot accepted for this gesture.
  String? get successMessage {
    if (!_used || _event == null || _batch == null) return null;
    try {
      final change = _map(_list(_batch!['changes']).single);
      final before = _map(change['before']), after = _map(change['after']);
      final zone = tz.getLocation(after['plannedTimezone'] as String);
      final start = tz.TZDateTime.from(
        DateTime.parse(after['plannedStartAt'] as String),
        zone,
      );
      final end = tz.TZDateTime.from(
        DateTime.parse(after['plannedEndAt'] as String),
        zone,
      );
      final rawTitle = after['title'] as String? ?? '';
      final title = rawTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
      final verb = _event['intent'] == 'resize'
          ? '已调整为'
          : before['plannedStartAt'] == null
          ? '已安排至'
          : '已移至';
      String day(DateTime value) =>
          '${value.month}/${value.day} 周${'一二三四五六日'[value.weekday - 1]}';
      String time(DateTime value) =>
          '${value.hour.toString().padLeft(2, '0')}:'
          '${value.minute.toString().padLeft(2, '0')}';
      final sameDay =
          start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      final finish = sameDay ? time(end) : '${day(end)} ${time(end)}';
      return '${title.isEmpty ? '任务' : title}$verb${day(start)} ${time(start)}–$finish';
    } catch (_) {
      // Feedback must never turn an accepted save into an error.
      return '已调整';
    }
  }

  bool allows({
    required String moduleId,
    required String serviceId,
    required Object? input,
    required List<Object?> writes,
    required Object? result,
    required PlanConfirmation? confirmation,
  }) {
    if (_used ||
        moduleId != this.moduleId ||
        confirmation?.acknowledgement != null) {
      return false;
    }
    try {
      final request = _map(input), response = _map(result);
      final records = writes.map(_map).toList();
      final identities = <String>{};
      final spaces = <String, String>{};
      for (final write in records) {
        if (!_keys(write, {
              'moduleId',
              'space',
              'collection',
              'id',
              'before',
              'value',
            }) ||
            write.length != 6 ||
            !_string(write['id']) ||
            !_string(write['space']) ||
            !{taskModuleId, moduleId}.contains(write['moduleId'])) {
          return false;
        }
        final module = write['moduleId'] as String;
        if (spaces.containsKey(module) && spaces[module] != write['space']) {
          return false;
        }
        spaces[module] = write['space'] as String;
        if (!identities.add(
          canonicalJson([
            module,
            write['space'],
            write['collection'],
            write['id'],
          ]),
        )) {
          return false;
        }
        for (final field in ['before', 'value']) {
          if (write[field] != null && _map(write[field])['id'] != write['id']) {
            return false;
          }
        }
      }
      final approved = _event == null
          ? serviceId == undoServiceId &&
                _allowsUndo(request, records, response)
          : serviceId == applyServiceId &&
                _allowsMove(request, records, response);
      if (!approved) return false;
      _used = true;
      return true;
    } catch (_) {
      // A malformed or unfamiliar transaction always falls back to review.
      return false;
    }
  }

  bool _allowsMove(
    Map<String, Object?> input,
    List<Map<String, Object?>> writes,
    Map<String, Object?> result,
  ) {
    final event = _event!;
    final kind = event['intent'] ?? 'move';
    final id = event['taskId'] ?? event['id'];
    if (!{'move', 'resize'}.contains(kind) ||
        !_string(id) ||
        !_keys(input, {'operationKey', 'preview', 'allowOverdue'}) ||
        input['allowOverdue'] != null && input['allowOverdue'] != false ||
        !_string(input['operationKey'])) {
      return false;
    }
    final preview = _map(input['preview']);
    final proposal = _map(preview['input']);
    if (preview['schemaVersion'] != 1 ||
        preview['kind'] != kind ||
        preview['confirmable'] != true ||
        !_empty(preview['overdue']) ||
        !_empty(preview['conflicts']) ||
        proposal['taskId'] != id ||
        (proposal['kind'] ?? 'move') != kind ||
        proposal['targetTaskId'] != null) {
      return false;
    }
    final changes = _list(preview['changes']),
        blocks = _list(preview['previewBlocks']);
    if (changes.length != 1 || blocks.length != 1) return false;
    final change = _map(changes.single), block = _map(blocks.single);
    if (change['taskId'] != id ||
        block['id'] != id ||
        !_sameWallTime(block['start'], event['start']) ||
        !_sameWallTime(block['end'], event['end'])) {
      return false;
    }
    final taskWrites = writes
        .where((w) => w['moduleId'] == taskModuleId)
        .toList();
    if (taskWrites.length != 1) return false;
    final taskWrite = taskWrites.single;
    final before = _map(taskWrite['before']), after = _map(taskWrite['value']);
    final fields = _map(change['fields']);
    const temporal = {
      'plannedDate',
      'plannedStartAt',
      'plannedEndAt',
      'plannedTimezone',
      'estimatedMinutes',
      'updatedAt',
    };
    if (taskWrite['collection'] != 'tasks' ||
        taskWrite['id'] != id ||
        !_equal(change['before'], before) ||
        before['locked'] == true ||
        [
          'completedAt',
          'deletedAt',
          'archivedAt',
        ].any((k) => before[k] != null) ||
        !_onlyChanges(before, after, temporal) ||
        !_keys(fields, {
          'plannedStartAt',
          'plannedEndAt',
          'plannedTimezone',
          'estimatedMinutes',
        }) ||
        fields.length != 4 ||
        fields.entries.any((e) => !_equal(e.value, after[e.key])) ||
        !_matchesInstant(
          after['plannedStartAt'],
          after['plannedTimezone'],
          event['start'],
        ) ||
        !_matchesInstant(
          after['plannedEndAt'],
          after['plannedTimezone'],
          event['end'],
        ) ||
        after['plannedDate'] != (event['start'] as String).substring(0, 10)) {
      return false;
    }
    final begin = DateTime.parse(after['plannedStartAt'] as String);
    final finish = DateTime.parse(after['plannedEndAt'] as String);
    final minutes =
        finish.difference(begin).inMicroseconds /
        Duration.microsecondsPerMinute;
    if (minutes < 1 ||
        minutes != minutes.roundToDouble() ||
        after['estimatedMinutes'] != minutes ||
        kind == 'resize' &&
            !_equal(before['plannedStartAt'], after['plannedStartAt'])) {
      return false;
    }
    final key = input['operationKey'];
    if (!_equal(result, {'id': key, 'applied': 1})) return false;
    final newBatches = writes
        .where(
          (w) =>
              w['moduleId'] == moduleId &&
              w['collection'] == 'batches' &&
              w['id'] == key,
        )
        .toList();
    if (newBatches.length != 1 || newBatches.single['before'] != null) {
      return false;
    }
    final batch = _map(newBatches.single['value']);
    if (!_keys(batch, {
          'id',
          'kind',
          'createdAt',
          'request',
          'changes',
          'undone',
          'sequence',
          'undoOccupancy',
        }) ||
        batch.length != (batch.containsKey('undoOccupancy') ? 8 : 7) ||
        batch.containsKey('undoOccupancy') !=
            preview.containsKey('undoOccupancy') ||
        batch.containsKey('undoOccupancy') &&
            (!_equal(batch['undoOccupancy'], preview['undoOccupancy']) ||
                !_validUndoOccupancy(batch['undoOccupancy'], before)) ||
        batch['kind'] != kind ||
        batch['undone'] != false ||
        !_string(batch['createdAt']) ||
        batch['sequence'] is! int ||
        (batch['sequence'] as int) < 1 ||
        batch['request'] != _operationRequest(preview)) {
      return false;
    }
    final deltas = _list(batch['changes']);
    if (deltas.length != 1) return false;
    final delta = _map(deltas.single);
    if (!_keys(delta, {
          'taskId',
          'before',
          'after',
          'occurrenceId',
          'beforeOccurrence',
          'afterOccurrence',
        }) ||
        delta['taskId'] != id ||
        !_equal(delta['before'], before) ||
        !_equal(delta['after'], after)) {
      return false;
    }
    Map<String, Object?>? occurrence;
    final occurrenceWrites = writes
        .where(
          (w) => w['moduleId'] == moduleId && w['collection'] == 'occurrences',
        )
        .toList();
    if (delta['occurrenceId'] != null) {
      if (occurrenceWrites.length != 1) return false;
      occurrence = occurrenceWrites.single;
      final old = _map(occurrence['before']), value = _map(occurrence['value']);
      if (occurrence['id'] != delta['occurrenceId'] ||
          old['taskId'] != id ||
          !_equal(old, delta['beforeOccurrence']) ||
          !_equal(value, delta['afterOccurrence']) ||
          !_onlyChanges(old, value, {
            'date',
            'estimatedMinutes',
            'locked',
            'status',
          }) ||
          value['date'] != after['plannedDate'] ||
          value['estimatedMinutes'] != after['estimatedMinutes'] ||
          value['locked'] != after['locked'] ||
          value['status'] != 'confirmed') {
        return false;
      }
    } else if (delta.length != 3 || occurrenceWrites.isNotEmpty) {
      return false;
    }
    if (!_allowsHistory(
      writes,
      batch,
      newBatches.single,
      occurrence,
      taskWrite,
    )) {
      return false;
    }
    _batch = _map(freezeJson(batch));
    _taskWrite = _map(freezeJson(taskWrite));
    _occurrence = occurrence == null ? null : _map(freezeJson(occurrence));
    _undo = PlannerQuickAdjustment._undo(
      _batch,
      _taskWrite,
      _occurrence,
      moduleId: moduleId,
      taskModuleId: taskModuleId,
      applyServiceId: applyServiceId,
      undoServiceId: undoServiceId,
    );
    return true;
  }

  bool _allowsHistory(
    List<Map<String, Object?>> writes,
    Map<String, Object?> batch,
    Map<String, Object?> currentBatch,
    Map<String, Object?>? occurrence,
    Map<String, Object?> task,
  ) {
    final deleted = <Object?, Map<String, Object?>>{};
    final receipts = <Object?, Map<String, Object?>>{};
    for (final write in writes) {
      if (identical(write, task) ||
          identical(write, currentBatch) ||
          identical(write, occurrence)) {
        continue;
      }
      if (write['moduleId'] != moduleId) return false;
      if (write['collection'] == 'batches' && write['value'] == null) {
        final old = _map(write['before']);
        if (old['changes'] is! List ||
            old['createdAt'] is! String ||
            (old['sequence'] ?? 0) is! int ||
            (old['sequence'] as int? ?? 0) > (batch['sequence'] as int) - 50) {
          return false;
        }
        deleted[write['id']] = old;
      } else if (write['collection'] == 'receipts') {
        receipts[write['id']] = write;
      } else {
        return false;
      }
    }
    if (!receipts.containsKey(batch['id'])) return false;
    for (final entry in receipts.entries) {
      final old = entry.key == batch['id'] ? batch : deleted[entry.key];
      if (old == null || old['request'] == null) return false;
      final expected = {
        'id': old['id'],
        'kind': old['kind'] ?? 'plan',
        'request': _oldRequest(old),
        'createdAt': old['createdAt'],
      };
      if (!_equal(entry.value['value'], expected) ||
          entry.value['before'] != null &&
              !_equal(entry.value['before'], expected)) {
        return false;
      }
    }
    // Identical existing receipts are omitted by CollectionStore.stage.
    return true;
  }

  bool _allowsUndo(
    Map<String, Object?> input,
    List<Map<String, Object?>> writes,
    Map<String, Object?> result,
  ) {
    final batch = _batch!, task = _taskWrite!;
    if (!_equal(input, {'id': batch['id']}) ||
        !_equal(result, {'id': batch['id'], 'restored': 1}) ||
        writes.length != (_occurrence == null ? 2 : 3)) {
      return false;
    }
    bool inverse(Map<String, Object?> write, Map<String, Object?> original) =>
        write['moduleId'] == original['moduleId'] &&
        write['space'] == original['space'] &&
        write['collection'] == original['collection'] &&
        write['id'] == original['id'] &&
        _equal(write['before'], original['value']) &&
        _equal(write['value'], original['before']);
    if (writes.where((w) => inverse(w, task)).length != 1) return false;
    if (_occurrence != null &&
        writes.where((w) => inverse(w, _occurrence!)).length != 1) {
      return false;
    }
    final history = writes
        .where(
          (w) =>
              w['moduleId'] == moduleId &&
              w['collection'] == 'batches' &&
              w['id'] == batch['id'],
        )
        .toList();
    if (history.length != 1 || !_equal(history.single['before'], batch)) {
      return false;
    }
    final after = _map(history.single['value']);
    return _onlyChanges(batch, after, {'undone', 'undoneAt'}) &&
        after['undone'] == true &&
        _string(after['undoneAt']);
  }

  static Map<String, Object?> _map(Object? value) =>
      Map<String, Object?>.from(value as Map);
  static List _list(Object? value) => value as List;
  static bool _empty(Object? value) => value is List && value.isEmpty;
  static bool _string(Object? value) => value is String && value.isNotEmpty;
  static bool _keys(Map<String, Object?> map, Set<String> keys) =>
      map.keys.every(keys.contains);
  static bool _equal(Object? a, Object? b) =>
      canonicalJson(a) == canonicalJson(b);
  static bool _onlyChanges(
    Map<String, Object?> before,
    Map<String, Object?> after,
    Set<String> allowed,
  ) => {...before.keys, ...after.keys}.every(
    (key) =>
        allowed.contains(key) ||
        before.containsKey(key) == after.containsKey(key) &&
            _equal(before[key], after[key]),
  );
  static bool _sameWallTime(Object? a, Object? b) =>
      a is String &&
      b is String &&
      DateTime.tryParse(a) != null &&
      DateTime.tryParse(a) == DateTime.tryParse(b);
  static bool _validUndoOccupancy(Object? raw, Map<String, Object?> task) {
    if (raw is! Map) return false;
    final value = _map(raw);
    if (value.length != 2 ||
        !_keys(value, {'version', 'overlaps'}) ||
        value['version'] != 1 ||
        value['overlaps'] is! List) {
      return false;
    }
    final spans = value['overlaps'] as List;
    final start = _utc(task['plannedStartAt']),
        end = _utc(task['plannedEndAt']);
    if (start == null || end == null) return spans.isEmpty;
    final seen = <String>{};
    for (final raw in spans) {
      if (raw is! Map) return false;
      final span = _map(raw);
      if (span.length != 5 ||
          !_keys(span, {'taskId', 'kind', 'id', 'startAt', 'endAt'}) ||
          span['taskId'] != task['id'] ||
          !_string(span['id']) ||
          !{'task', 'course', 'busy'}.contains(span['kind']) ||
          span['kind'] == 'task' && span['id'] == task['id'] ||
          !seen.add(canonicalJson(span))) {
        return false;
      }
      final from = _utc(span['startAt']), to = _utc(span['endAt']);
      if (from == null ||
          to == null ||
          !to.isAfter(from) ||
          !from.isBefore(end) ||
          !to.isAfter(start)) {
        return false;
      }
    }
    return true;
  }

  static DateTime? _utc(Object? value) {
    if (value is! String || !value.endsWith('Z')) return null;
    return DateTime.tryParse(value);
  }

  static bool _matchesInstant(Object? instant, Object? zone, Object? wall) {
    if (instant is! String || zone is! String || wall is! String) return false;
    final local = tz.TZDateTime.from(
      DateTime.parse(instant),
      tz.getLocation(zone),
    );
    final date = DateTime.parse(wall);
    return [
          local.year,
          local.month,
          local.day,
          local.hour,
          local.minute,
          local.second,
          local.millisecond,
          local.microsecond,
        ].join(':') ==
        [
          date.year,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
          date.millisecond,
          date.microsecond,
        ].join(':');
  }

  static String _operationRequest(Map<String, Object?> preview) {
    final input = _map(preview['input'])..remove('expectedTasks');
    return canonicalJson({
      'input': input,
      'changes': _list(preview['changes']).map((raw) {
        final change = _map(raw);
        return {'taskId': change['taskId'], 'fields': change['fields']};
      }).toList(),
      'allowOverdue': false,
    });
  }

  static String _oldRequest(Map<String, Object?> batch) {
    final value = jsonDecode(batch['request'] as String);
    if (value is Map && value['changes'] is List) {
      final input = _map(value['input'])..remove('expectedTasks');
      return canonicalJson({..._map(value), 'input': input});
    }
    // Current plan receipts already contain planRequest's normalized fields.
    return batch['request'] as String;
  }
}
