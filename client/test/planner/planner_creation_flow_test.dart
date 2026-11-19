import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/ui_preferences.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  Map<String, Object?> obj(Object? value) =>
      Map<String, Object?>.from(value as Map);
  Iterable<Map<String, Object?>> nodes(Object? value) sync* {
    if (value is Map) {
      yield obj(value);
      for (final child in value.values) {
        yield* nodes(child);
      }
    } else if (value is List) {
      for (final child in value) {
        yield* nodes(child);
      }
    }
  }

  Future<Map<String, Object?>> page({
    String pageId = 'app.planner.quickAdd',
    Map<String, Object?> context = const {},
    Map<String, Object?> state = const {},
    Map<String, Object?>? event,
    Map<String, Object?> forms = const {},
  }) async => obj(
    await host.invokePage('app.planner', 'render', {
      'context': {'pageId': pageId, ...context},
      'state': state,
      'event': event,
      'formValues': forms,
    }),
  );
  Future<void> install(String id) async {
    final directory = Directory('../packages/modules/$id');
    final scripts = <String, String>{};
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.js')) {
        scripts[file.path.substring(directory.path.length + 1)] = file
            .readAsStringSync();
      }
    }
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          obj(
            jsonDecode(
              File('${directory.path}/module.json').readAsStringSync(),
            ),
          ),
          scripts,
        ),
        allowUnsignedLocal: true,
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('planner-creation-test-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 10, 21, 0);
    await install('app.tasks');
    await install('app.planner');
    host.interaction = (_, method, args) async => method == 'ui.review';
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> rawTasks() async => (await host.query(
    host.instances['app.tasks']!.actor,
    const ServiceRef('app.tasks', 'task.list', 1),
    {'view': 'raw'},
  ) as List).map(obj).toList();

  Future<Object?> savedDraft() =>
      ModuleUiPreferences(store)
          .get(host.instances['app.planner']!.actor, 'creation.draft.v1');

  Future<void> cacheTitle(String title) async {
    await ModuleUiPreferences(store).set(
      host.instances['app.planner']!.actor,
      'creation.input.v1',
      {'title': title},
    );
  }

  Future<Object?> cachedInput() =>
      ModuleUiPreferences(store)
          .get(host.instances['app.planner']!.actor, 'creation.input.v1');

  Future<Map<String, Object?>> editContent(
    Map<String, Object?> p,
    String key,
    Map<String, Object?> values,
  ) async {
    p = await page(state: obj(p['state']), event: {'type': 'openAdd'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'editContent', 'key': key},
    );
    return page(
      state: obj(p['state']),
      forms: values,
      event: {'type': 'applyContent'},
    );
  }

  test('nested multiple rules preserve priority through apply and preview while back discards later changes', () async {
    var p = await page(forms: {'title': '多次优先级'});
    p = await page(state: obj(p['state']), event: {'type': 'openAdd'});
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'rules'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'addRule', 'id': 'priority'},
    );
    p = await page(
      state: obj(p['state']),
      forms: {'priority': 2},
      event: {'type': 'applyRules'},
    );
    expect(obj(p['state'])['step'], 'multiple');
    p = await page(state: obj(p['state']), event: {'type': 'rules'});
    p = await page(
      state: obj(p['state']),
      forms: {'priority': 3},
      event: {'type': 'back'},
    );
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    expect(obj(p['state'])['error'], isNull);
    expect(obj(obj(p['state'])['draft'])['priorityEnabled'], true);
    expect(obj(obj(p['state'])['draft'])['priority'], 2);
    p = await page(state: obj(p['state']), event: {'type': 'preview'});
    expect(obj(p['state'])['error'], isNull);
    expect(obj(obj(obj(p['state'])['preview'])['input'])['priority'], 2);
  });

  test('title-only single creation has one add entry and does not invent time settings', () async {
    var p = await page(forms: {'title': '只记录名称'});
    expect(obj(obj(p['state'])['draft'])['mode'], 'once');
    final visible = nodes(p['tree']).toList();
    expect(
      visible.where(
        (n) => n['type'] == 'segmented' && n['key'] == 'creationMode',
      ),
      isEmpty,
    );
    expect(
      visible.where((n) => obj(n['event'] ?? {})['type'] == 'openAdd'),
      hasLength(1),
    );
    expect(
      visible.where(
        (n) => [
          'dueDate',
          'dueTime',
          'start',
          'end',
          'estimatedMinutes',
        ].contains(n['key']),
      ),
      isEmpty,
    );
    expect(visible.any((n) => n['text'] == '创建任务'), true);
    p = await page(state: obj(p['state']), event: {'type': 'save'});
    expect(obj(p['state'])['error'], isNull);
    final saved = (await rawTasks()).single;
    expect(saved['title'], '只记录名称');
    for (final key in [
      'estimatedMinutes',
      'plannedStartAt',
      'plannedEndAt',
      'plannedDate',
      'dueDate',
      'dueAt',
    ]) {
      expect(saved[key], isNull, reason: '$key must remain optional');
    }
    expect(saved['locked'], false);
  });

  test('unified editor cancels unsaved location and retains title and applied notes through nested back', () async {
    var p = await page(forms: {'title': '保留主草稿'}, event: {'type': 'openAdd'});
    expect(obj(p['header'])['title'], '添加内容或规则');
    p = await page(
      state: obj(p['state']),
      event: {'type': 'editContent', 'key': 'location'},
    );
    p = await page(
      state: obj(p['state']),
      forms: {'location': '不保存的地点'},
      event: {'type': 'back'},
    );
    expect(obj(p['state'])['step'], 'addContent');
    expect(obj(obj(p['state'])['draft'])['location'] ?? '', isEmpty);
    p = await page(state: obj(p['state']), event: {'type': 'back'});
    expect(obj(p['state'])['step'], 'create');
    expect(obj(obj(p['state'])['draft'])['title'], '保留主草稿');
    p = await editContent(p, 'notes', {'notes': '已保存的描述\n第二行'});
    expect(obj(p['state'])['step'], 'create');
    p = await editContent(p, 'location', {'location': '图书馆302'});
    expect(obj(p['state'])['error'], isNull);
    expect(nodes(p['tree']).any((n) => n['title'] == '地点'), true);
    p = await page(
      state: obj(p['state']),
      event: {'type': 'removeContent', 'key': 'location'},
    );
    expect(nodes(p['tree']).any((n) => n['title'] == '地点'), false);
    p = await page(state: obj(p['state']), event: {'type': 'save'});
    expect(obj(p['state'])['error'], isNull);
    final saved = (await rawTasks()).single;
    expect(saved['notes'], '已保存的描述\n第二行');
    final content = obj(
      await host.query(
        host.instances['app.planner']!.actor,
        const ServiceRef('app.planner', 'planner.task.content', 1),
        {'id': saved['id']},
      ),
    );
    expect(content['location'], isNull);
  });

  test('fixed schedule derives duration and combines with independent deadline and location', () async {
    var p = await page(forms: {'title': '固定阅读时间'});
    p = await editContent(p, 'schedule', {
      'startDate': '2026-10-22',
      'start': '09:00',
      'endDate': '2026-10-22',
      'end': '10:00',
      'locked': true,
    });
    expect(obj(p['state'])['error'], isNull);
    expect(obj(obj(p['state'])['draft'])['estimatedMinutes'], 60);
    p = await editContent(p, 'deadline', {
      'dueDate': '2026-10-22',
      'dueTime': '18:00',
    });
    p = await editContent(p, 'location', {'location': '图书馆302'});
    expect(obj(p['state'])['error'], isNull);
    expect(
      nodes(p['tree']).where((n) => n['title'] == '预计耗时'),
      isEmpty,
      reason: 'A scheduled range already derives its elapsed duration.',
    );
    p = await page(state: obj(p['state']), event: {'type': 'save'});
    expect(obj(p['state'])['error'], isNull);
    final saved = (await rawTasks()).single;
    expect(saved['plannedStartAt'], '2026-10-22T01:00:00.000Z');
    expect(saved['plannedEndAt'], '2026-10-22T02:00:00.000Z');
    expect(saved['dueAt'], '2026-10-22T10:00:00.000Z');
    expect(saved['locked'], true);
    expect(saved['estimatedMinutes'], 60);
    final home = await page(
      pageId: 'app.planner.home',
      state: {'startDate': '2026-10-22', 'days': 1},
    );
    final board = nodes(home['tree'])
        .singleWhere((n) => n['type'] == 'plannerBoard');
    final block = obj((board['blocks'] as List).single);
    expect(block['location'], '图书馆302');
    expect(block['fixed'], true);
    expect(block['moveEvent'], isNull);
  });

  test('duration and scheduled range replace each other while deadline survives time removal', () async {
    var p = await page(forms: {'title': '可选时间'});
    p = await editContent(p, 'duration', {'estimatedMinutes': '45'});
    expect(obj(obj(p['state'])['draft'])['durationEnabled'], true);
    p = await editContent(p, 'schedule', {
      'startDate': '2026-10-22',
      'start': '09:00',
      'endDate': '2026-10-22',
      'end': '10:00',
      'locked': true,
    });
    expect(obj(obj(p['state'])['draft'])['durationEnabled'], false);
    p = await editContent(p, 'deadline', {
      'dueDate': '2026-10-23',
      'dueTime': null,
    });
    p = await page(
      state: obj(p['state']),
      event: {'type': 'removeContent', 'key': 'schedule'},
    );
    expect(obj(obj(p['state'])['draft'])['locked'], false);
    p = await page(state: obj(p['state']), event: {'type': 'save'});
    expect(obj(p['state'])['error'], isNull);
    final saved = (await rawTasks()).single;
    expect(saved['estimatedMinutes'], isNull);
    expect(saved['plannedStartAt'], isNull);
    expect(saved['locked'], false);
    expect(saved['dueDate'], '2026-10-23');
    expect(saved['dueAt'], isNull);
  });

  test('invalid schedule stays editable and back does not apply it or create a task', () async {
    var p = await page(forms: {'title': '等待有效时间'}, event: {'type': 'openAdd'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'editContent', 'key': 'schedule'},
    );
    p = await page(
      state: obj(p['state']),
      event: {'type': 'applyContent'},
      forms: {
        'startDate': '2026-10-22',
        'start': '10:00',
        'endDate': '2026-10-22',
        'end': '09:00',
        'locked': true,
      },
    );
    expect(obj(p['state'])['step'], 'contentEditor');
    expect(obj(p['state'])['error'], isNotNull);
    expect(await rawTasks(), isEmpty);
    p = await page(state: obj(p['state']), event: {'type': 'back'});
    expect(obj(obj(p['state'])['draft'])['scheduleEnabled'], false);
    expect(obj(obj(p['state'])['draft'])['title'], '等待有效时间');
  });

  test('deeper multiple setup can be cancelled or removed without losing the original fixed single range and deadline', () async {
    var p = await page(forms: {'title': '单次转多次'});
    p = await editContent(p, 'schedule', {
      'startDate': '2026-10-22',
      'start': '09:00',
      'endDate': '2026-10-22',
      'end': '10:00',
      'locked': true,
    });
    p = await editContent(p, 'deadline', {
      'dueDate': '2026-10-23',
      'dueTime': '18:00',
    });
    final single = obj(obj(p['state'])['draft']);
    p = await page(state: obj(p['state']), event: {'type': 'openAdd'});
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    p = await page(
      state: obj(p['state']),
      forms: {'minDays': '5'},
      event: {'type': 'back'},
    );
    expect(obj(p['state'])['step'], 'addContent');
    expect(obj(obj(p['state'])['draft']), single);
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    expect(obj(obj(p['state'])['draft'])['mode'], 'batch');
    expect(obj(obj(p['state'])['draft'])['locked'], false);
    expect(obj(obj(p['state'])['draft'])['dueDate'], isNull);
    p = await page(
      state: obj(p['state']),
      event: {'type': 'removeContent', 'key': 'multiple'},
    );
    final restored = obj(obj(p['state'])['draft']);
    for (final key in [
      'mode',
      'scheduleEnabled',
      'durationEnabled',
      'deadlineEnabled',
      'startDate',
      'start',
      'endDate',
      'end',
      'locked',
      'estimatedMinutes',
      'dueDate',
      'dueTime',
    ]) {
      expect(
        restored[key],
        single[key],
        reason: '$key should survive entering the deeper repeat flow.',
      );
    }
    expect(await rawTasks(), isEmpty);
  });

  test('a scheduled template clears dates and fixed state but keeps reusable location and description', () async {
    var p = await page(forms: {'title': '阅读模板'});
    p = await editContent(p, 'schedule', {
      'startDate': '2026-10-22',
      'start': '09:00',
      'endDate': '2026-10-22',
      'end': '10:00',
      'locked': true,
    });
    p = await editContent(p, 'deadline', {
      'dueDate': '2026-10-23',
      'dueTime': '18:00',
    });
    p = await editContent(p, 'location', {'location': '图书馆302'});
    p = await editContent(p, 'notes', {'notes': '模板里的说明'});
    host.interaction = (_, method, args) async =>
        method == 'ui.dialog' ? {'name': '阅读模板', 'replace': true} : true;
    p = await page(state: obj(p['state']), event: {'type': 'saveTemplate'});
    expect(obj(p['state'])['error'], isNull);
    p = await page(event: {'type': 'templates'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'templateTab', 'index': 1},
    );
    final entry = nodes(p['tree'])
        .singleWhere((n) => n['type'] == 'listTile' && n['title'] == '阅读模板');
    p = await page(state: obj(p['state']), event: obj(entry['event']));
    final restored = obj(obj(p['state'])['draft']);
    expect(restored['notes'], '模板里的说明');
    expect(restored['location'], '图书馆302');
    expect(restored['durationEnabled'], true);
    expect(restored['estimatedMinutes'], 60);
    expect(
      nodes(p['tree']).any((n) => n['title'] == '预计耗时'),
      true,
      reason: 'A reusable template keeps its derived duration when absolute times are cleared.',
    );
    expect(restored['scheduleEnabled'], false);
    expect(restored['locked'], false);
    for (final key in [
      'startDate',
      'start',
      'endDate',
      'end',
      'dueDate',
      'dueTime',
    ]) {
      expect(
        restored[key],
        isNull,
        reason: '$key must not reuse a historical timestamp.',
      );
    }
    p = await page(state: obj(p['state']), event: {'type': 'save'});
    final saved = (await rawTasks()).single;
    expect(saved['plannedStartAt'], isNull);
    expect(saved['dueDate'], isNull);
    expect(saved['locked'], false);
    expect(saved['estimatedMinutes'], 60);
  });

  test('replacing a multiple draft with a template cannot restore the previous single task timestamps', () async {
    var p = await page(forms: {'title': '旧的固定单次草稿'});
    p = await editContent(p, 'schedule', {
      'startDate': '2026-10-22',
      'start': '09:00',
      'endDate': '2026-10-22',
      'end': '10:00',
      'locked': true,
    });
    p = await editContent(p, 'deadline', {
      'dueDate': '2026-10-23',
      'dueTime': '18:00',
    });
    p = await page(state: obj(p['state']), event: {'type': 'openAdd'});
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    expect(
      obj(p['state'])['singleTime'],
      isNotNull,
      reason: 'The draft currently remembers the replaced single-task times.',
    );
    host.interaction = (_, method, args) async =>
        method == 'ui.dialog' ? {'replace': true} : true;
    p = await page(state: obj(p['state']), event: {'type': 'templates'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'useTemplate', 'id': 'read-paper'},
    );
    expect(obj(obj(p['state'])['draft'])['title'], '阅读论文');
    p = await page(
      state: obj(p['state']),
      event: {'type': 'removeContent', 'key': 'multiple'},
    );
    final restored = obj(obj(p['state'])['draft']);
    expect(restored['mode'], 'once');
    expect(restored['scheduleEnabled'], false);
    expect(restored['locked'], false);
    expect(restored['durationEnabled'], true);
    expect(restored['estimatedMinutes'], 30);
    for (final key in [
      'startDate',
      'start',
      'endDate',
      'end',
      'dueDate',
      'dueTime',
    ]) {
      expect(
        restored[key],
        isNull,
        reason:
            '$key belongs to the old draft and must not leak through template replacement.',
      );
    }
    p = await page(state: obj(p['state']), event: {'type': 'save'});
    expect(obj(p['state'])['error'], isNull);
    final saved = (await rawTasks()).single;
    expect(saved['title'], '阅读论文');
    expect(saved['plannedStartAt'], isNull);
    expect(saved['dueDate'], isNull);
    expect(saved['locked'], false);
    expect(saved['estimatedMinutes'], 30);
  });

  test('batch preview creates nothing until confirmed and manual adjustment preserves task count', () async {
    var p = await page(event: {'type': 'openAdd'}, forms: {'title': '阅读论文'});
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'preview'});
    var state = obj(p['state']);
    expect(state['error'], isNull);
    expect(state['step'], 'preview');
    final preview = obj(state['preview']);
    expect(preview['startDate'], '2026-10-21');
    expect(preview['endDate'], '2026-11-19');
    expect((preview['assigned'] as List).length, greaterThan(1));
    expect(
      await host.query(
        host.instances['app.tasks']!.actor,
        const ServiceRef('app.tasks', 'task.list', 1),
        {'view': 'raw'},
      ),
      isEmpty,
    );
    final first = obj((preview['assigned'] as List).first);
    p = await page(state: state, event: {'type': 'adjust', 'id': first['id']});
    p = await page(state: obj(p['state']), event: {'type': 'applyAdjustment'});
    state = obj(p['state']);
    expect(state['error'], isNull);
    expect(state['step'], 'preview');
    final count = (obj(state['preview'])['assigned'] as List).length;
    p = await page(state: state, event: {'type': 'confirmCreation'});
    expect(obj(p['state'])['error'], isNull);
    final tasks = await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.list', 1),
      {'view': 'raw'},
    ) as List;
    expect(tasks.length, count);
  });

  test(
    'rule editing is applied explicitly and cancel preserves draft',
    () async {
      var p = await page(
        event: {'type': 'mode', 'index': 1},
        forms: {'title': '草稿', 'notes': '描述'},
      );
      p = await page(state: obj(p['state']), event: {'type': 'rules'});
      p = await page(
        state: obj(p['state']),
        event: {'type': 'field', 'key': 'minDays', 'value': '5'},
      );
      expect(obj(obj(p['state'])['draft'])['minDays'], 4);
      p = await page(state: obj(p['state']), event: {'type': 'back'});
      expect(obj(obj(p['state'])['draft'])['minDays'], 4);
      expect(obj(obj(p['state'])['draft'])['notes'], '描述');
      p = await page(state: obj(p['state']), event: {'type': 'rules'});
      p = await page(
        state: obj(p['state']),
        event: {'type': 'applyRules'},
        forms: {'minDays': '5', 'maxDays': '6'},
      );
      expect(obj(obj(p['state'])['draft'])['minDays'], '5');
      expect(obj(p['state'])['step'], 'create');
    },
  );

  test('templates are text-only subpage and require approval before replacing an edited draft', () async {
    var p = await page(forms: {'title': '保留原任务'}, event: {'type': 'templates'});
    expect(obj(p['header'])['title'], '选择模板');
    final templates = nodes(p['tree'])
        .where((n) => n['type'] == 'listTile')
        .toList();
    expect(templates.length, 4);
    expect(templates.every((n) => n['icon'] == null), isTrue);
    host.interaction = (_, method, args) async => null;
    p = await page(
      state: obj(p['state']),
      event: {'type': 'useTemplate', 'id': 'read-paper'},
    );
    expect(obj(obj(p['state'])['draft'])['title'], '保留原任务');
    host.interaction = (_, method, args) async =>
        method == 'ui.dialog' ? {'replace': true} : true;
    p = await page(
      state: obj(p['state']),
      event: {'type': 'useTemplate', 'id': 'read-paper'},
    );
    expect(obj(obj(p['state'])['draft'])['title'], '阅读论文');
    expect(obj(p['state'])['step'], 'create');
    expect(obj(p['replaceForms'])['title'], '阅读论文');
  });

  test('template replacement protects every applied content item and batch rules without a title', () async {
    final cases = <String, Map<String, Object?>>{
      'location': {'location': '图书馆302'},
      'duration': {'estimatedMinutes': '45'},
      'deadline': {'dueDate': '2026-10-23'},
      'priority': {'priority': 2},
      'schedule': {
        'startDate': '2026-10-22',
        'start': '09:00',
        'endDate': '2026-10-22',
        'end': '10:00',
      },
    };
    var replacementReviews = 0;
    host.interaction = (_, method, args) async {
      if (method == 'ui.dialog') {
        replacementReviews++;
        expect(args['title'], '套用模板');
      }
      return null;
    };
    for (final entry in cases.entries) {
      await ModuleUiPreferences(store)
          .set(host.instances['app.planner']!.actor, 'creation.draft.v1', null);
      var p = await page();
      p = await editContent(p, entry.key, entry.value);
      final original = obj(obj(p['state'])['draft']);
      p = await page(state: obj(p['state']), event: {'type': 'templates'});
      p = await page(
        state: obj(p['state']),
        event: {'type': 'useTemplate', 'id': 'notes'},
      );
      expect(obj(obj(p['state'])['draft']), original, reason: entry.key);
      expect(obj(p['state'])['step'], 'templates');
    }
    await ModuleUiPreferences(store)
        .set(host.instances['app.planner']!.actor, 'creation.draft.v1', null);
    var p = await page(event: {'type': 'openMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    final original = obj(obj(p['state'])['draft']);
    p = await page(state: obj(p['state']), event: {'type': 'templates'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'useTemplate', 'id': 'notes'},
    );
    expect(obj(obj(p['state'])['draft']), original);
    expect(replacementReviews, cases.length + 1);
  });

  test('daily repetition ignores hidden invalid interval values and new drafts allow every day', () async {
    host.interaction = (_, method, args) async =>
        method == 'ui.dialog' ? {'replace': true} : true;
    var p = await page(
      forms: {'title': '每日任务'},
      event: {'type': 'openMultiple'},
    );
    expect(obj(obj(p['state'])['multiDraft'])['weekdays'], [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ]);
    p = await page(state: obj(p['state']), event: {'type': 'rules'});
    p = await page(
      state: obj(p['state']),
      forms: {'minDays': '7', 'maxDays': '4'},
      event: {'type': 'addRule', 'id': 'daily'},
    );
    expect(nodes(p['tree']).where((n) => n['key'] == 'minDays'), isEmpty);
    p = await page(state: obj(p['state']), event: {'type': 'applyRules'});
    expect(obj(p['state'])['error'], isNull);
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'preview'});
    final preview = obj(obj(p['state'])['preview']);
    expect(preview['confirmable'], true);
    expect(preview['assigned'], hasLength(30));
    expect(preview['unassigned'], isEmpty);
    expect(await rawTasks(), isEmpty);
  });

  test('daily repetition explains an explicit weekday restriction and preserves it', () async {
    var p = await page(
      forms: {'title': '保留工作日限制'},
      event: {'type': 'openMultiple'},
    );
    p = await page(
      state: obj(p['state']),
      forms: {
        'repeatKind': 'daily',
        'weekdays': [1, 2, 3, 4, 5],
      },
    );
    expect(
      nodes(p['tree']).any((n) => '${n['text']}'.contains('当前限制了允许星期')),
      true,
    );
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    expect(obj(obj(p['state'])['draft'])['weekdays'], [1, 2, 3, 4, 5]);
    p = await page(state: obj(p['state']), event: {'type': 'preview'});
    expect(obj(obj(p['state'])['preview'])['confirmable'], false);
    expect(obj(obj(p['state'])['draft'])['weekdays'], [1, 2, 3, 4, 5]);
  });

  test('required repetition is explained and cannot be silently removed or restored', () async {
    var p = await page(event: {'type': 'openMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'rules'});
    expect(
      nodes(p['tree']).where(
        (n) =>
            obj(n['event'] ?? {})['type'] == 'removeRule' &&
            obj(n['event'] ?? {})['id'] == 'interval',
      ),
      isEmpty,
    );
    p = await page(
      state: obj(p['state']),
      event: {'type': 'removeRule', 'id': 'interval'},
    );
    expect(obj(p['state'])['error'], contains('必须保留一种重复方式'));
    expect(obj(obj(p['state'])['ruleDraft'])['intervalEnabled'], true);
    expect(obj(obj(p['tree'])['footerMessage'])['tone'], 'warning');
    p = await page(state: obj(p['state']), event: {'type': 'back'});
    p = await page(
      state: obj(p['state']),
      forms: {'intervalEnabled': false},
      event: {'type': 'applyMultiple'},
    );
    expect(obj(p['state'])['step'], 'multiple');
    expect(obj(p['state'])['error'], contains('需要一种重复方式'));
    expect(obj(obj(p['state'])['multiDraft'])['intervalEnabled'], false);
  });

  test('title-only template summary does not invent a duration', () async {
    host.interaction = (_, method, args) async =>
        method == 'ui.dialog' ? {'name': '无时间模板'} : true;
    var p = await page(
      forms: {'title': '仅名称'},
      event: {'type': 'saveTemplate'},
    );
    p = await page(state: obj(p['state']), event: {'type': 'templates'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'templateTab', 'index': 1},
    );
    final row = nodes(p['tree'])
        .singleWhere((n) => n['type'] == 'listTile' && n['title'] == '无时间模板');
    expect(row['subtitle'], '未设置时间 · 无重复规则');
  });

  test('validation message stays in fixed footer while the form retains its page identity', () async {
    var p = await page();
    final key = obj(p['tree'])['key'];
    p = await page(state: obj(p['state']), event: {'type': 'save'});
    final tree = obj(p['tree']);
    expect(tree['key'], key);
    expect(obj(tree['footerMessage'])['text'], contains('请填写任务名称'));
    expect(
      nodes(tree['children']).where((n) => '${n['text']}'.contains('请填写任务名称')),
      isEmpty,
    );
    expect(nodes(tree['footer']).any((n) => n['text'] == '创建任务'), true);
  });

  test('subpage transitions follow navigation direction and same-page edits keep their identity', () async {
    var p = await page(forms: {'title': '动画草稿'});
    p = await page(state: obj(p['state']), event: {'type': 'openAdd'});
    expect(obj(obj(p['tree'])['pageTransition'])['direction'], 'forward');
    expect(obj(obj(p['tree'])['pageTransition'])['duration'], 260);
    p = await page(
      state: obj(p['state']),
      event: {'type': 'editContent', 'key': 'location'},
    );
    final editorKey = obj(p['tree'])['key'];
    final editorScroll = obj(p['tree'])['scrollKey'];
    p = await page(state: obj(p['state']), forms: {'location': '图书馆'});
    expect(obj(p['tree'])['key'], editorKey);
    expect(obj(p['tree'])['scrollKey'], editorScroll);
    p = await page(state: obj(p['state']), event: {'type': 'applyContent'});
    expect(obj(obj(p['tree'])['pageTransition'])['direction'], 'back');
    final mainKey = obj(p['tree'])['key'];
    p = await page(
      state: obj(p['state']),
      event: {'type': 'removeContent', 'key': 'location'},
    );
    expect(obj(p['tree'])['key'], mainKey);
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'rules'});
    expect(obj(obj(p['tree'])['pageTransition'])['direction'], 'forward');
    p = await page(state: obj(p['state']), event: {'type': 'back'});
    expect(obj(obj(p['tree'])['pageTransition'])['direction'], 'back');
    expect(obj(p['state'])['step'], 'multiple');
  });

  test('reopening restores only the main draft, excluding staged edits, previews and old plans', () async {
    var p = await page(forms: {'title': '下次继续'});
    p = await editContent(p, 'location', {'location': '已保存地点'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'editContent', 'key': 'notes'},
    );
    p = await page(state: obj(p['state']), forms: {'notes': '未应用的描述'});
    var reopened = await page();
    expect(obj(reopened['state'])['step'], 'create');
    expect(obj(obj(reopened['state'])['draft'])['title'], '下次继续');
    expect(obj(obj(reopened['state'])['draft'])['location'], '已保存地点');
    expect(obj(obj(reopened['state'])['draft'])['notes'], '');
    expect(
      nodes(reopened['tree']).any((n) => n['text'] == '已恢复上次未完成的草稿'),
      true,
    );
    reopened = await page(
      state: obj(reopened['state']),
      event: {'type': 'openMultiple'},
    );
    reopened = await page(
      state: obj(reopened['state']),
      event: {'type': 'applyMultiple'},
    );
    reopened = await page(
      state: obj(reopened['state']),
      event: {'type': 'preview'},
    );
    expect(obj(reopened['state'])['creationPlanId'], isNotNull);
    final persisted = obj(await savedDraft());
    expect(persisted.keys, ['draft', 'singleTime']);
    host.clockNow = () => DateTime.utc(2026, 10, 23);
    reopened = await page();
    final state = obj(reopened['state']);
    expect(state['step'], 'create');
    expect(state['preview'], isNull);
    expect(state['creationPlanId'], isNull);
    expect(state['adjustments'], isEmpty);
    expect(obj(state['draft'])['firstDate'], '2026-10-23');
    expect(obj(state['draft'])['mode'], 'batch');
    expect(await rawTasks(), isEmpty);
  });

  test('clear draft requires confirmation and successful creation removes its saved draft', () async {
    var p = await page(forms: {'title': '保留到确认'});
    host.interaction = (_, method, args) async => null;
    p = await page(state: obj(p['state']), event: {'type': 'clearDraft'});
    expect(obj(obj(p['state'])['draft'])['title'], '保留到确认');
    expect(await savedDraft(), isNotNull);
    host.interaction = (_, method, args) async =>
        method == 'ui.dialog' ? {'clear': true} : true;
    p = await page(state: obj(p['state']), event: {'type': 'clearDraft'});
    expect(obj(obj(p['state'])['draft'])['title'], '');
    expect(await savedDraft(), isNull);
    p = await page();
    expect(nodes(p['tree']).any((n) => n['text'] == '已恢复上次未完成的草稿'), false);
    p = await page(
      state: obj(p['state']),
      forms: {'title': '创建后无草稿'},
      event: {'type': 'save'},
    );
    expect(await savedDraft(), isNull);
    expect(await rawTasks(), hasLength(1));
    p = await page();
    expect(obj(obj(p['state'])['draft'])['title'], '');
  });

  test('reopened multiple draft retains the single schedule and deadline it temporarily replaced', () async {
    var p = await page(forms: {'title': '恢复原单次安排'});
    p = await editContent(p, 'schedule', {
      'startDate': '2026-10-22',
      'start': '09:00',
      'endDate': '2026-10-22',
      'end': '10:00',
      'locked': true,
    });
    p = await editContent(p, 'deadline', {'dueDate': '2026-10-23'});
    final original = obj(obj(p['state'])['draft']);
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    p = await page();
    expect(obj(obj(p['state'])['draft'])['mode'], 'batch');
    p = await page(
      state: obj(p['state']),
      event: {'type': 'removeContent', 'key': 'multiple'},
    );
    final restored = obj(obj(p['state'])['draft']);
    for (final key in [
      'scheduleEnabled',
      'startDate',
      'start',
      'endDate',
      'end',
      'locked',
      'dueDate',
      'dueTime',
      'estimatedMinutes',
    ]) {
      expect(restored[key], original[key], reason: key);
    }
  });

  test('preference quota failure leaves the prior saved draft intact and explains unsaved changes', () async {
    var p = await page(forms: {'title': '容量受限仍可编辑'});
    final priorSaved = await savedDraft();
    for (var i = 0; i < 7; i++) {
      await ModuleUiPreferences(
        store,
      ).set(host.instances['app.planner']!.actor, 'quotaFixture$i', 'a' * 4096);
    }
    p = await editContent(p, 'notes', {'notes': 'a' * 4096});
    expect(obj(p['state'])['error'], isNull);
    expect(obj(p['state'])['draftSaveFailed'], true);
    expect(obj(obj(p['tree'])['footerMessage'])['text'], contains('草稿暂未自动保存'));
    expect(await savedDraft(), priorSaved);
    p = await page(
      state: obj(p['state']),
      event: {'type': 'removeContent', 'key': 'notes'},
    );
    expect(obj(p['state'])['draftSaveFailed'], isNull);
  });

  test('native title cache overrides an older draft, including an explicitly empty title', () async {
    var p = await page(forms: {'title': '旧标题'});
    expect(obj(obj(p['tree'])['formCache']), {
      'preferenceKey': 'creation.input.v1',
      'fields': ['title'],
    });
    await cacheTitle('关闭前最后输入');
    p = await page();
    expect(obj(obj(p['state'])['draft'])['title'], '关闭前最后输入');
    expect(obj(obj(await savedDraft())['draft'])['title'], '关闭前最后输入');
    p = await page(state: obj(p['state']), event: {'type': 'openAdd'});
    expect(obj(p['tree'])['formCache'], isNull);
    await cacheTitle('');
    p = await page();
    expect(obj(obj(p['state'])['draft'])['title'], '');
    expect(await savedDraft(), isNull);
    expect(nodes(p['tree']).any((n) => n['text'] == '已恢复上次未完成的草稿'), false);
  });

  test('title cache restores a draft before its first module input render has completed', () async {
    await cacheTitle('仅原生缓存里的标题');
    expect(await savedDraft(), isNull);
    final p = await page();
    expect(obj(obj(p['state'])['draft'])['title'], '仅原生缓存里的标题');
    expect(obj(p['state'])['step'], 'create');
    expect(nodes(p['tree']).any((n) => n['text'] == '已恢复上次未完成的草稿'), true);
  });

  test('confirmed clearing removes the native title cache while cancelled clearing preserves it', () async {
    await cacheTitle('保留的即时标题');
    var p = await page();
    host.interaction = (_, method, args) async => null;
    p = await page(state: obj(p['state']), event: {'type': 'clearDraft'});
    expect(obj(await cachedInput())['title'], '保留的即时标题');
    expect(await savedDraft(), isNotNull);
    host.interaction = (_, method, args) async =>
        method == 'ui.dialog' ? {'clear': true} : true;
    p = await page(state: obj(p['state']), event: {'type': 'clearDraft'});
    expect(await cachedInput(), isNull);
    expect(await savedDraft(), isNull);
    p = await page();
    expect(obj(obj(p['state'])['draft'])['title'], '');
  });

  test('single and multiple creation both clear the native input cache before returning home', () async {
    for (final batch in [false, true]) {
      await cacheTitle(batch ? '多次缓存任务' : '单次缓存任务');
      var p = await page();
      if (batch) {
        p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
        p = await page(
          state: obj(p['state']),
          event: {'type': 'applyMultiple'},
        );
        p = await page(state: obj(p['state']), event: {'type': 'preview'});
      }
      p = await page(
        state: obj(p['state']),
        event: {'type': batch ? 'confirmCreation' : 'save'},
      );
      expect(obj(p['state'])['error'], isNull);
      expect(await cachedInput(), isNull);
      expect(await savedDraft(), isNull);
      p = await page();
      expect(obj(obj(p['state'])['draft'])['title'], '');
    }
  });

  test('a confirmed template cannot be overwritten by the preceding native title cache on reopen', () async {
    await cacheTitle('套用前缓存标题');
    var p = await page(event: {'type': 'templates'});
    host.interaction = (_, method, args) async =>
        method == 'ui.dialog' ? {'replace': true} : true;
    p = await page(
      state: obj(p['state']),
      event: {'type': 'useTemplate', 'id': 'notes'},
    );
    expect(obj(obj(p['state'])['draft'])['title'], '整理笔记');
    expect(await cachedInput(), isNull);
    p = await page();
    expect(obj(obj(p['state'])['draft'])['title'], '整理笔记');
  });

  test('a draft that exceeds preference limits stays editable and can still be created', () async {
    var p = await page(forms: {'title': '长描述任务'});
    final notes = '字' * 5000;
    p = await editContent(p, 'notes', {'notes': notes});
    expect(obj(obj(p['state'])['draft'])['notes'], notes);
    expect(obj(p['state'])['error'], isNull);
    expect(obj(p['state'])['draftSaveFailed'], true);
    expect(obj(obj(p['tree'])['footerMessage'])['text'], contains('草稿暂未自动保存'));
    p = await page(state: obj(p['state']), event: {'type': 'save'});
    expect(obj(p['state'])['error'], isNull);
    expect((await rawTasks()).single['notes'], notes);
    expect(await savedDraft(), isNull);
  });

  test(
    'invalid interval and manual duration remain reviewable errors',
    () async {
      var p = await page(
        event: {'type': 'mode', 'index': 1},
        forms: {'title': '任务'},
      );
      p = await page(state: obj(p['state']), event: {'type': 'rules'});
      p = await page(
        state: obj(p['state']),
        event: {'type': 'applyRules'},
        forms: {'minDays': '7', 'maxDays': '4'},
      );
      expect(obj(p['state'])['step'], 'rules');
      expect(obj(p['state'])['error'], contains('最大间隔'));
      p = await page(state: obj(p['state']), event: {'type': 'back'});
      p = await page(state: obj(p['state']), event: {'type': 'preview'});
      final first = obj(
        (obj(obj(p['state'])['preview'])['assigned'] as List).first,
      );
      p = await page(
        state: obj(p['state']),
        event: {'type': 'adjust', 'id': first['id']},
      );
      p = await page(
        state: obj(p['state']),
        event: {'type': 'applyAdjustment'},
        forms: {'adjustEnd': '18:01'},
      );
      expect(obj(p['state'])['step'], 'adjust');
      expect(obj(p['state'])['error'], isNotNull);
    },
  );
  test('generated task editor exposes scope and interval checks while ordinary tasks do not', () async {
    var p = await page(
      event: {'type': 'mode', 'index': 1},
      forms: {'title': '可改期批量'},
    );
    p = await page(state: obj(p['state']), event: {'type': 'preview'});
    p = await page(state: obj(p['state']), event: {'type': 'confirmCreation'});
    expect(obj(p['state'])['error'], isNull);
    final tasks = await host.query(
      host.instances['app.tasks']!.actor,
      const ServiceRef('app.tasks', 'task.list', 1),
      {'view': 'raw'},
    ) as List;
    final taskId = obj(tasks.first)['id'];
    p = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': taskId, 'step': 'time'},
    );
    final choices = nodes(p['tree']).where((n) => n['type'] == 'choiceCard');
    expect(choices.map((n) => n['title']), ['仅本次', '本次及以后']);
    expect(nodes(p['tree']).any((n) => n['title'] == '间隔检查'), isTrue);
    p = await page(
      pageId: 'app.planner.taskDetail',
      context: {'taskId': taskId, 'step': 'time'},
      state: obj(p['state']),
      event: {'type': 'field', 'key': 'scheduleScope', 'value': 'following'},
    );
    expect(obj(obj(p['state'])['draft'])['scheduleScope'], 'following');
  });

  test(
    'my templates persist configuration and never retain an absolute deadline',
    () async {
      host.interaction = (_, method, args) async =>
          method == 'ui.dialog' ? {'name': '我的阅读', 'replace': true} : true;
      var p = await page(
        forms: {'title': '阅读草稿', 'dueDate': '2026-11-01'},
        event: {'type': 'saveTemplate'},
      );
      expect(obj(p['state'])['error'], isNull);
      p = await page(event: {'type': 'templates'});
      p = await page(
        state: obj(p['state']),
        event: {'type': 'templateTab', 'index': 1},
      );
      final templates = nodes(p['tree'])
          .where((n) => n['type'] == 'listTile')
          .toList();
      expect(templates.single['title'], '我的阅读');
      final event = obj(templates.single['event']);
      p = await page(state: obj(p['state']), event: event);
      expect(obj(obj(p['state'])['draft'])['title'], '阅读草稿');
      expect(obj(obj(p['state'])['draft'])['dueDate'], isNull);
    },
  );
}
