import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/plan_confirmation.dart';
import 'package:task_app/core/module_host/planner_quick_adjust.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show sourcePackage, table;

Map<String, Object?> clone(Object? value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

PlannerQuickAdjustment moveGate(Map<String, Object?> event) =>
    PlannerQuickAdjustment.move(
      event,
      moduleId: 'app.planner',
      taskModuleId: 'app.tasks',
      applyServiceId: 'planner.operation.apply',
      undoServiceId: 'planner.batch.undo',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ModuleHost host;
  late Directory folder;
  late Map<String, Object?> task, event, input;
  late ChangePlan plan;
  Future<Object?> run(
    String module,
    String service,
    Map<String, Object?> data,
  ) async {
    final actor = host.instances[module]!.actor;
    final p = await host.prepare(actor, ServiceRef(module, service, 1), data);
    host.review(p.id, actor);
    return host.commit(actor, p.id);
  }

  bool allows(
    PlannerQuickAdjustment gate, {
    String module = 'app.planner',
    String service = 'planner.operation.apply',
    Map<String, Object?>? changedInput,
    List<Object?>? writes,
    Object? result,
    PlanConfirmation? confirmation,
  }) => gate.allows(
    moduleId: module,
    serviceId: service,
    input: changedInput ?? input,
    writes: writes ?? plan.writes,
    result: result ?? plan.content['result'],
    confirmation: confirmation,
  );
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    folder = await Directory.systemTemp.createTemp('planner-quick-');
    host = ModuleHost(store: CollectionStore(db), directory: folder);
    host.clockNow = () => DateTime.utc(2026, 10, 20);
    await host.initialize();
    await host.install(await sourcePackage('app.tasks'));
    await host.install(await sourcePackage('app.planner'));
    task = Map<String, Object?>.from(
      await run('app.tasks', 'task.create', {
        'title': '唯一任务',
        'notes': '保留描述',
        'dueDate': '2026-10-24',
        'plannedStartAt': '2026-10-21T01:00:00Z',
        'plannedEndAt': '2026-10-21T01:30:00Z',
        'plannedTimezone': 'Asia/Shanghai',
        'estimatedMinutes': 30,
      }) as Map,
    );
    event = {
      'intent': 'move',
      'taskId': task['id'],
      'id': task['id'],
      'start': '2026-10-21T10:00:00.000',
      'end': '2026-10-21T10:30:00.000',
    };
    final preview = await host.query(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.planner', 'planner.operation.preview', 1),
      {
        'kind': 'move',
        'taskId': task['id'],
        'date': '2026-10-21',
        'start': '10:00',
        'end': '10:30',
        'timezone': 'Asia/Shanghai',
        'preserveDuration': true,
      },
    );
    input = {
      'operationKey': 'native-gesture',
      'preview': preview,
      'allowOverdue': false,
    };
    plan = await host.prepare(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.planner', 'planner.operation.apply', 1),
      input,
    );
  });
  tearDown(() async {
    await host.close();
    await host.store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  test('real frozen move transaction and its exact undo receive one native authorization each', () async {
    final gate = moveGate(event);
    expect(allows(gate), isTrue);
    expect(gate.batchId, 'native-gesture');
    expect(gate.successMessage, '唯一任务已移至10/21 周三 10:00–10:30');
    expect(allows(gate), isFalse);
    final undo = gate.undoAdjustment!;
    expect(undo.successMessage, isNull);
    final actor = host.instances['app.planner']!.actor;
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
    final undoPlan = await host.prepare(
      actor,
      const ServiceRef('app.planner', 'planner.batch.undo', 1),
      {'id': 'native-gesture'},
    );
    expect(
      undo.allows(
        moduleId: 'app.planner',
        serviceId: 'planner.batch.undo',
        input: {'id': 'native-gesture'},
        writes: undoPlan.writes,
        result: undoPlan.content['result'],
        confirmation: null,
      ),
      isTrue,
    );
    expect(undo.successMessage, isNull);
    expect(
      undo.allows(
        moduleId: 'app.planner',
        serviceId: 'planner.batch.undo',
        input: {'id': 'native-gesture'},
        writes: undoPlan.writes,
        result: undoPlan.content['result'],
        confirmation: null,
      ),
      isFalse,
    );
  });

  test('success feedback exists only after an approved move and uses its frozen after snapshot', () {
    final gate = moveGate(event);
    expect(gate.successMessage, isNull);
    expect(allows(gate, service: 'other.service'), isFalse);
    expect(gate.successMessage, isNull);
    final writes = (jsonDecode(jsonEncode(plan.writes)) as List)
        .cast<Object?>();
    expect(allows(gate, writes: writes), isTrue);
    expect(gate.successMessage, '唯一任务已移至10/21 周三 10:00–10:30');
    expect(gate.undoAdjustment!.successMessage, isNull);
    final taskWrite = writes.cast<Map>().singleWhere(
      (w) => w['moduleId'] == 'app.tasks',
    );
    (taskWrite['value'] as Map)['title'] = '后来被修改的标题';
    (taskWrite['value'] as Map)['plannedStartAt'] = '2026-10-22T00:00:00Z';
    expect(gate.successMessage, '唯一任务已移至10/21 周三 10:00–10:30');
    expect(allows(gate), isFalse);
    expect(gate.successMessage, '唯一任务已移至10/21 周三 10:00–10:30');
  });

  test('success feedback uses the approved timezone across midnight and preserves a complete single-line title', () async {
    const title = '  整理资料\n\r\t和复习笔记以及完整保留的很长很长很长很长标题  ';
    final created = await run('app.tasks', 'task.create', {
      'title': title,
      'estimatedMinutes': 60,
      'plannedStartAt': '2026-10-22T12:00:00Z',
      'plannedEndAt': '2026-10-22T13:00:00Z',
      'plannedTimezone': 'Asia/Shanghai',
    }) as Map;
    // The native board and the saved task now use New York wall time.
    final availability = await host.query(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.planner', 'planner.availability.get', 1),
      {},
    ) as Map;
    await run('app.planner', 'planner.availability.save', {
      'availability': {...availability, 'timezone': 'America/New_York'},
    });
    final preview = await host.query(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.planner', 'planner.operation.preview', 1),
      {
        'kind': 'move',
        'taskId': created['id'],
        'date': '2026-10-21',
        'start': '23:35',
        'timezone': 'America/New_York',
        'preserveDuration': true,
      },
    );
    input = {'operationKey': 'message-crossday', 'preview': preview};
    plan = await host.prepare(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.planner', 'planner.operation.apply', 1),
      input,
    );
    final gate = moveGate({
      'intent': 'move',
      'taskId': created['id'],
      'start': '2026-10-21T23:35:00',
      'end': '2026-10-22T00:35:00',
    });
    expect(allows(gate), isTrue);
    expect(
      gate.successMessage,
      '整理资料 和复习笔记以及完整保留的很长很长很长很长标题已移至10/21 周三 23:35–10/22 周四 00:35',
    );
    expect(gate.successMessage, isNot(contains('\n')));
    expect(gate.successMessage, isNot(contains('…')));
  });

  test(
    'an unscheduled task success says arranged and uses the saved wall date',
    () async {
      final created = await run('app.tasks', 'task.create', {
        'title': '待安排任务',
        'estimatedMinutes': 30,
      }) as Map;
      final preview = await host.query(
        host.instances['app.planner']!.actor,
        const ServiceRef('app.planner', 'planner.operation.preview', 1),
        {
          'kind': 'move',
          'taskId': created['id'],
          'date': '2026-10-25',
          'start': '09:35',
          'timezone': 'Asia/Shanghai',
          'preserveDuration': true,
        },
      );
      input = {'operationKey': 'message-candidate', 'preview': preview};
      plan = await host.prepare(
        host.instances['app.planner']!.actor,
        const ServiceRef('app.planner', 'planner.operation.apply', 1),
        input,
      );
      final gate = moveGate({
        'taskId': created['id'],
        'start': '2026-10-25T09:35:00',
        'end': '2026-10-25T10:05:00',
      });
      expect(allows(gate), isTrue);
      expect(gate.successMessage, '待安排任务已安排至10/25 周日 09:35–10:05');
    },
  );

  test(
    'wrong module service gesture target and swap never gain authorization',
    () {
      expect(allows(moveGate(event), module: 'other.module'), isFalse);
      expect(allows(moveGate(event), service: 'planner.task.update'), isFalse);
      expect(allows(moveGate({...event, 'taskId': 'another'})), isFalse);
      expect(allows(moveGate({...event, 'intent': 'swap'})), isFalse);
      expect(allows(moveGate({...event, 'intent': 'insert'})), isFalse);
      expect(
        allows(moveGate({...event, 'start': '2026-10-21T11:00:00'})),
        isFalse,
      );
    },
  );

  test('deadline risk conflicts unconfirmable preview and acknowledgement require explicit review', () {
    for (final field in ['overdue', 'conflicts', 'confirmable']) {
      final changed = clone(input), preview = changed['preview'] as Map;
      preview[field] = field == 'confirmable'
          ? false
          : [
              {'taskId': task['id']},
            ];
      expect(allows(moveGate(event), changedInput: changed), isFalse);
    }
    expect(
      allows(moveGate(event), changedInput: {...input, 'allowOverdue': true}),
      isFalse,
    );
    expect(
      allows(
        moveGate(event),
        confirmation: PlanConfirmation.parse({
          'title': '风险',
          'message': '请确认',
          'confirmLabel': '确认',
          'acknowledgement': '我了解',
        }),
      ),
      isFalse,
    );
  });

  test('task non-time edits extra task writes and arbitrary planner records are refused', () {
    for (final field in [
      'title',
      'notes',
      'dueDate',
      'locked',
      'completedAt',
    ]) {
      final writes = (jsonDecode(jsonEncode(plan.writes)) as List)
          .cast<Object?>();
      final taskWrite = writes.cast<Map>().singleWhere(
        (w) => w['moduleId'] == 'app.tasks',
      );
      (taskWrite['value'] as Map)[field] = field == 'locked' ? true : 'changed';
      expect(allows(moveGate(event), writes: writes), isFalse);
    }
    final extra = clone(plan.writes.first);
    extra['id'] = 'another';
    extra['before'] = {...(extra['before'] as Map), 'id': 'another'};
    extra['value'] = {...(extra['value'] as Map), 'id': 'another'};
    expect(allows(moveGate(event), writes: [...plan.writes, extra]), isFalse);
    expect(
      allows(
        moveGate(event),
        writes: [
          ...plan.writes,
          {
            'moduleId': 'app.planner',
            'space': 's',
            'collection': 'settings',
            'id': 'availability',
            'before': null,
            'value': {'id': 'availability'},
          },
        ],
      ),
      isFalse,
    );
  });

  test('forged batch snapshots receipts and optimistic duplicate success are refused', () {
    final writes = (jsonDecode(jsonEncode(plan.writes)) as List)
        .cast<Object?>();
    final batch = writes.cast<Map>().singleWhere(
      (w) => w['collection'] == 'batches',
    );
    (((batch['value'] as Map)['changes'] as List).single as Map)['taskId'] =
        'another';
    expect(allows(moveGate(event), writes: writes), isFalse);
    final receipts = (jsonDecode(jsonEncode(plan.writes)) as List)
        .cast<Object?>();
    final receipt = receipts.cast<Map>().singleWhere(
      (w) => w['collection'] == 'receipts',
    );
    (receipt['value'] as Map)['request'] = 'different request';
    expect(allows(moveGate(event), writes: receipts), isFalse);
    expect(
      allows(
        moveGate(event),
        writes: [],
        result: {'id': 'native-gesture', 'alreadyApplied': true},
      ),
      isFalse,
    );
  });

  test(
    'resize authorizes exact ending change while preserving start',
    () async {
      event = {
        ...event,
        'intent': 'resize',
        'start': '2026-10-21T09:00:00',
        'end': '2026-10-21T09:45:00',
      };
      final preview = await host.query(
        host.instances['app.planner']!.actor,
        const ServiceRef('app.planner', 'planner.operation.preview', 1),
        {
          'kind': 'resize',
          'taskId': task['id'],
          'endDate': '2026-10-21',
          'end': '09:45',
          'timezone': 'Asia/Shanghai',
        },
      );
      input = {'operationKey': 'native-resize', 'preview': preview};
      plan = await host.prepare(
        host.instances['app.planner']!.actor,
        const ServiceRef('app.planner', 'planner.operation.apply', 1),
        input,
      );
      final gate = moveGate(event);
      expect(allows(gate), isTrue);
      expect(gate.successMessage, '唯一任务已调整为10/21 周三 09:00–09:45');
    },
  );

  test('history retention may delete eligible old batches without changing other business records', () {
    final writes = (jsonDecode(jsonEncode(plan.writes)) as List)
        .cast<Object?>();
    final batch = writes.cast<Map>().singleWhere(
      (w) => w['collection'] == 'batches',
    );
    (batch['value'] as Map)['sequence'] = 51;
    final old = {...(batch['value'] as Map), 'id': 'old', 'sequence': 1};
    writes.add({
      'moduleId': 'app.planner',
      'space': batch['space'],
      'collection': 'batches',
      'id': 'old',
      'before': old,
      'value': null,
    });
    expect(allows(moveGate(event), writes: writes), isTrue);
    old['sequence'] = 2;
    expect(allows(moveGate(event), writes: writes), isFalse);
  });

  test('undo is bound to approved snapshots and cannot restore another batch or edit extra fields', () async {
    final gate = moveGate(event);
    expect(allows(gate), isTrue);
    final actor = host.instances['app.planner']!.actor;
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
    final undoPlan = await host.prepare(
      actor,
      const ServiceRef('app.planner', 'planner.batch.undo', 1),
      {'id': 'native-gesture'},
    );
    final undo = gate.undoAdjustment!;
    expect(
      undo.allows(
        moduleId: 'app.planner',
        serviceId: 'planner.batch.undo',
        input: {'id': 'other'},
        writes: undoPlan.writes,
        result: undoPlan.content['result'],
        confirmation: null,
      ),
      isFalse,
    );
    final writes = (jsonDecode(jsonEncode(undoPlan.writes)) as List)
        .cast<Object?>();
    final taskWrite = writes.cast<Map>().singleWhere(
      (w) => w['moduleId'] == 'app.tasks',
    );
    (taskWrite['value'] as Map)['notes'] = 'unexpected';
    expect(
      undo.allows(
        moduleId: 'app.planner',
        serviceId: 'planner.batch.undo',
        input: {'id': 'native-gesture'},
        writes: writes,
        result: undoPlan.content['result'],
        confirmation: null,
      ),
      isFalse,
    );
  });
  test('real fifty-record retention keeps automatic moves valid and later task edits block undo', () async {
    final actor = host.instances['app.planner']!.actor;
    PlannerQuickAdjustment? finalGate;
    for (var index = 0; index < 51; index++) {
      final time = DateTime.utc(2026, 10, 21, 10, index);
      final finish = time.add(const Duration(minutes: 30));
      final startTime = time.toIso8601String().substring(11, 16);
      final endTime = finish.toIso8601String().substring(11, 16);
      final preview = await host.query(
        actor,
        const ServiceRef('app.planner', 'planner.operation.preview', 1),
        {
          'kind': 'move',
          'taskId': task['id'],
          'date': '2026-10-21',
          'start': startTime,
          'end': endTime,
          'timezone': 'Asia/Shanghai',
          'preserveDuration': true,
        },
      );
      final request = {'operationKey': 'retention-$index', 'preview': preview};
      final prepared = await host.prepare(
        actor,
        const ServiceRef('app.planner', 'planner.operation.apply', 1),
        request,
      );
      final gate = moveGate({
        ...event,
        'start': '2026-10-21T$startTime:00',
        'end': '2026-10-21T$endTime:00',
      });
      expect(
        gate.allows(
          moduleId: 'app.planner',
          serviceId: 'planner.operation.apply',
          input: request,
          writes: prepared.writes,
          result: prepared.content['result'],
          confirmation: null,
        ),
        isTrue,
        reason: 'retention move $index',
      );
      host.review(prepared.id, actor);
      await host.commit(actor, prepared.id);
      finalGate = gate;
    }
    final history = await host.query(
      actor,
      const ServiceRef('app.planner', 'planner.batch.list', 1),
      {},
    );
    expect(history, hasLength(50));
    final current = await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.get', 1),
      {'id': task['id']},
    ) as Map;
    await run('app.tasks', 'task.updateFields', {
      'id': task['id'],
      'expectedUpdatedAt': current['updatedAt'],
      'changes': {'notes': 'later edit'},
    });
    await expectLater(
      host.prepare(
        actor,
        const ServiceRef('app.planner', 'planner.batch.undo', 1),
        {'id': finalGate!.batchId},
      ),
      throwsA(anything),
    );
  });

  test('related occurrence writes and exact snapshot undo remain scoped to the moved task', () async {
    await run('app.planner', 'planner.occurrence.update', {
      'taskId': task['id'],
      'window': {
        'startDate': '2026-10-21',
        'endDate': '2026-10-24',
        'estimatedMinutes': 30,
        'times': [
          {'start': '09:00', 'end': '18:00'},
        ],
      },
    });
    plan = await host.prepare(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.planner', 'planner.operation.apply', 1),
      {
        ...input,
        'preview': await host.query(
          host.instances['app.planner']!.actor,
          const ServiceRef('app.planner', 'planner.operation.preview', 1),
          {
            'kind': 'move',
            'taskId': task['id'],
            'date': '2026-10-21',
            'start': '10:00',
            'end': '10:30',
            'timezone': 'Asia/Shanghai',
            'preserveDuration': true,
          },
        ),
      },
    );
    final previewInput = await host.query(
      host.instances['app.planner']!.actor,
      const ServiceRef('app.planner', 'planner.operation.preview', 1),
      {
        'kind': 'move',
        'taskId': task['id'],
        'date': '2026-10-21',
        'start': '10:00',
        'end': '10:30',
        'timezone': 'Asia/Shanghai',
        'preserveDuration': true,
      },
    );
    input = {...input, 'preview': previewInput};
    final gate = moveGate(event);
    expect(allows(gate), isTrue);
    final actor = host.instances['app.planner']!.actor;
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
    final prepared = await host.prepare(
      actor,
      const ServiceRef('app.planner', 'planner.batch.undo', 1),
      {'id': gate.batchId},
    );
    expect(
      gate.undoAdjustment!.allows(
        moduleId: 'app.planner',
        serviceId: 'planner.batch.undo',
        input: {'id': gate.batchId},
        writes: prepared.writes,
        result: prepared.content['result'],
        confirmation: null,
      ),
      isTrue,
    );
  });
  test('the same strict transaction contract supports explicitly bound alternative modules and services', () async {
    final writes = (jsonDecode(jsonEncode(plan.writes)) as List)
        .cast<Object?>();
    for (final write in writes.cast<Map>()) {
      write['moduleId'] = write['moduleId'] == 'app.planner'
          ? 'test.timeline'
          : 'test.items';
    }
    final gate = PlannerQuickAdjustment.move(
      event,
      moduleId: 'test.timeline',
      taskModuleId: 'test.items',
      applyServiceId: 'timeline.adjust',
      undoServiceId: 'timeline.undo',
    );
    expect(
      gate.allows(
        moduleId: 'app.planner',
        serviceId: 'timeline.adjust',
        input: input,
        writes: writes,
        result: plan.content['result'],
        confirmation: null,
      ),
      isFalse,
    );
    expect(
      gate.allows(
        moduleId: 'test.timeline',
        serviceId: 'planner.operation.apply',
        input: input,
        writes: writes,
        result: plan.content['result'],
        confirmation: null,
      ),
      isFalse,
    );
    expect(
      gate.allows(
        moduleId: 'test.timeline',
        serviceId: 'timeline.adjust',
        input: input,
        writes: writes,
        result: plan.content['result'],
        confirmation: null,
      ),
      isTrue,
    );
    final actor = host.instances['app.planner']!.actor;
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
    final undoPlan = await host.prepare(
      actor,
      const ServiceRef('app.planner', 'planner.batch.undo', 1),
      {'id': gate.batchId},
    );
    final undoWrites = (jsonDecode(jsonEncode(undoPlan.writes)) as List)
        .cast<Object?>();
    for (final write in undoWrites.cast<Map>()) {
      write['moduleId'] = write['moduleId'] == 'app.planner'
          ? 'test.timeline'
          : 'test.items';
    }
    expect(
      gate.undoAdjustment!.allows(
        moduleId: 'test.timeline',
        serviceId: 'timeline.undo',
        input: {'id': gate.batchId},
        writes: undoWrites,
        result: undoPlan.content['result'],
        confirmation: null,
      ),
      isTrue,
    );
  });
  test('undo occupancy metadata is narrow, preview-bound and cannot authorize unrelated fields', () {
    final original =
        (plan.writes.cast<Map>().singleWhere(
              (w) => w['collection'] == 'batches',
            )['value']
            as Map);
    final snapshot = {
      'version': 1,
      'overlaps': [
        {
          'taskId': task['id'],
          'kind': 'course',
          'id': 'existing-course',
          'startAt': '2026-10-21T00:00:00.000Z',
          'endAt': '2026-10-21T01:35:00.000Z',
        },
      ],
    };
    final request = clone(input);
    (request['preview'] as Map)['undoOccupancy'] = snapshot;
    List<Object?> changed(Object? occupancy, {bool extra = false}) {
      final writes = (jsonDecode(jsonEncode(plan.writes)) as List)
          .cast<Object?>();
      final batch = writes.cast<Map>().singleWhere(
        (w) => w['collection'] == 'batches',
      );
      batch['value'] = {
        ...original,
        'undoOccupancy': occupancy,
        if (extra) 'arbitrary': true,
      };
      return writes;
    }

    expect(
      allows(moveGate(event), changedInput: request, writes: changed(snapshot)),
      isTrue,
    );
    expect(
      allows(
        moveGate(event),
        changedInput: request,
        writes: changed({'version': 1, 'overlaps': []}),
      ),
      isFalse,
    );
    expect(
      allows(
        moveGate(event),
        changedInput: request,
        writes: changed(snapshot, extra: true),
      ),
      isFalse,
    );
    for (final patch in [
      {'taskId': 'different'},
      {'kind': 'unknown'},
      {'extra': true},
      {'startAt': '2026-10-22T00:00:00Z', 'endAt': '2026-10-22T01:00:00Z'},
      {'startAt': '2026-10-21T01:35:00Z', 'endAt': '2026-10-21T00:00:00Z'},
    ]) {
      final malformed = {
        'version': 1,
        'overlaps': [
          {...(snapshot['overlaps'] as List).single as Map, ...patch},
        ],
      };
      final badInput = clone(request);
      (badInput['preview'] as Map)['undoOccupancy'] = malformed;
      expect(
        allows(
          moveGate(event),
          changedInput: badInput,
          writes: changed(malformed),
        ),
        isFalse,
      );
    }
  });

  for (final laterChange in ['none', 'new-task', 'changed-course']) {
    test(
      'real preexisting course overlap quick undo protects $laterChange occupancy',
      () async {
        await host.install(await sourcePackage('app.schedule'));
        Map<String, Object?> timetable(String end) => table(
          'overlap-table',
          zone: 'Asia/Shanghai',
          monday: '2026-10-19',
          start: '08:00',
          end: end,
        );
        await run('app.schedule', 'schedule.timetable.save', {
          'timetable': timetable('09:35'),
        });
        await run('app.schedule', 'schedule.course.save', {
          'course': {
            'id': 'overlap-course',
            'timetableId': 'overlap-table',
            'name': '原有高数',
          },
          'meeting': {
            'id': 'overlap-meeting',
            'weekday': 3,
            'startPeriod': 1,
            'endPeriod': 1,
            'weeks': [1],
          },
        });
        final actor = host.instances['app.planner']!.actor;
        final preview = await host.query(
          actor,
          const ServiceRef('app.planner', 'planner.operation.preview', 1),
          {
            'kind': 'move',
            'taskId': task['id'],
            'date': '2026-10-21',
            'start': '10:00',
            'end': '10:30',
            'timezone': 'Asia/Shanghai',
            'preserveDuration': true,
          },
        );
        expect((preview as Map)['undoOccupancy'], isA<Map>());
        expect(
          ((preview['undoOccupancy'] as Map)['overlaps'] as List),
          hasLength(1),
        );
        input = {...input, 'preview': preview};
        plan = await host.prepare(
          actor,
          const ServiceRef('app.planner', 'planner.operation.apply', 1),
          input,
        );
        final gate = moveGate(event);
        expect(allows(gate), isTrue);
        host.review(plan.id, actor);
        await host.commit(actor, plan.id);
        if (laterChange == 'new-task') {
          await run('app.tasks', 'task.create', {
            'title': '新增原位占用',
            'plannedStartAt': '2026-10-21T01:15:00Z',
            'plannedEndAt': '2026-10-21T01:25:00Z',
            'plannedTimezone': 'Asia/Shanghai',
            'estimatedMinutes': 10,
          });
        } else if (laterChange == 'changed-course') {
          await run('app.schedule', 'schedule.timetable.save', {
            'timetable': timetable('09:40'),
          });
        }
        final before = await host.store.sql(
          'SELECT * FROM host_records ORDER BY module_id,collection,id',
        );
        final undoInput = {'id': gate.batchId};
        if (laterChange == 'none') {
          final undoPlan = await host.prepare(
            actor,
            const ServiceRef('app.planner', 'planner.batch.undo', 1),
            undoInput,
          );
          final undo = gate.undoAdjustment!;
          expect(
            undo.allows(
              moduleId: 'app.planner',
              serviceId: 'planner.batch.undo',
              input: undoInput,
              writes: undoPlan.writes,
              result: undoPlan.content['result'],
              confirmation: null,
            ),
            isTrue,
          );
          host.review(undoPlan.id, actor);
          await host.commit(actor, undoPlan.id);
          expect(
            await host.query(
              host.instances['app.tasks']!.actor,
              const ServiceRef('app.tasks', 'task.get', 1),
              {'id': task['id']},
            ),
            task,
          );
        } else {
          await expectLater(
            host.prepare(
              actor,
              const ServiceRef('app.planner', 'planner.batch.undo', 1),
              undoInput,
            ),
            throwsA(anything),
          );
          expect(
            await host.store.sql(
              'SELECT * FROM host_records ORDER BY module_id,collection,id',
            ),
            before,
          );
        }
      },
    );
  }
}
