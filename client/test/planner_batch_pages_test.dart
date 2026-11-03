import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/ui_preferences.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show sourcePackage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    Map<String, Object?> state = const {},
    Map<String, Object?>? event,
    Map<String, Object?> forms = const {},
    String pageId = 'app.planner.batches',
  }) async => obj(
    await host.invokePage('app.planner', 'render', {
      'context': {'pageId': pageId},
      'state': state,
      'event': event,
      'formValues': forms,
    }),
  );
  Future<Map<String, Object?>> query(
    String id, [
    Map<String, Object?> input = const {},
  ]) async => obj(
    await host.query(
      host.instances['app.planner']!.actor,
      ServiceRef('app.planner', 'planner.$id', 1),
      input,
    ),
  );
  Future<Map<String, Object?>> run(
    String id,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances['app.planner']!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef('app.planner', 'planner.$id', 1),
      input,
    );
    host.review(plan.id, actor);
    return obj(await host.commit(actor, plan.id));
  }

  Future<void> fixture() async {
    final preview = await query('creation.preview', {
      'title': '阅读论文',
      'estimatedMinutes': 30,
      'timezone': 'UTC',
      'firstDate': '2026-11-03',
      'days': 30,
      'rules': {
        'interval': {'minDays': 2, 'maxDays': 3},
        'weekdays': [1, 2, 3, 4, 5, 6, 7],
        'timeWindow': {'start': '20:00', 'end': '22:00'},
      },
    });
    expect(preview['confirmable'], true);
    await run('creation.apply', {
      'creationKey': 'paper-series',
      'preview': preview,
    });
  }

  Future<Map<String, Object?>> openDetail() async =>
      page(event: {'type': 'openBatch', 'id': 'paper-series'});
  List<String> texts(Map<String, Object?> p) =>
      nodes(p['tree'])
          .where((n) => n['text'] is String)
          .map((n) => n['text'] as String)
          .toList();

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('planner-batch-pages-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    host.clockNow = () => DateTime.utc(2026, 11, 3, 0);
    await host.install(await sourcePackage('app.tasks'));
    await host.install(await sourcePackage('app.planner'));
    host.interaction = (_, method, args) async => method == 'ui.review';
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  test(
    'planner menu opens full-page batch management without replacing timeline',
    () async {
      final p = await page(pageId: 'app.planner.home');
      final actions = (obj(p['header'])['actions'] as List).map(obj);
      final entry = actions.singleWhere((a) => a['label'] == '批量任务');
      expect(entry['presentation'], 'menu');
      final calls = <Map<String, Object?>>[];
      host.interaction = (_, method, args) async {
        calls.add({'method': method, ...args});
        return true;
      };
      await page(
        pageId: 'app.planner.home',
        state: obj(p['state']),
        event: obj(entry['event']),
      );
      expect(
        calls.any(
          (call) =>
              call['method'] == 'ui.navigate' &&
              call['page'] == 'app.planner.batches',
        ),
        true,
      );
    },
  );

  test(
    'empty/search/filter views remain usable and return preserves list context',
    () async {
      var p = await page();
      expect(texts(p), contains('还没有批量任务'));
      expect(texts(p), contains('新建批量任务'));
      await fixture();
      p = await page(event: {'type': 'search', 'value': '论文'});
      expect(texts(p), contains('阅读论文'));
      p = await page(
        state: obj(p['state']),
        event: {'type': 'openBatch', 'id': 'paper-series'},
      );
      expect(obj(p['header'])['title'], '批次详情');
      expect(texts(p), contains('持续补齐未来30天'));
      expect(texts(p), contains('每2～3天 · 每次30分钟'));
      expect(texts(p).where((s) => s.startsWith('查看其余')), isNotEmpty);
      p = await page(state: obj(p['state']), event: {'type': 'backToList'});
      expect(obj(p['state'])['search'], '论文');
      p = await page(
        state: obj(p['state']),
        event: {'type': 'filter', 'status': 'paused'},
      );
      expect(texts(p), contains('没有找到匹配的批量任务'));
      p = await page(
        state: obj(p['state']),
        event: {'type': 'search', 'value': ''},
      );
      expect(texts(p), contains('此状态下暂无批量任务'));
    },
  );

  test('batch creation is initialized in batch mode and returns to list after commit', () async {
    final preferences = ModuleUiPreferences(store);
    final actor = host.instances['app.planner']!.actor;
    final ordinaryDraft = {
      'draft': {'title': '保留原有单次草稿', 'mode': 'once'},
    };
    await preferences.set(actor, 'creation.draft.v1', ordinaryDraft);
    var p = await page(event: {'type': 'newBatch'});
    expect(obj(p['header'])['backEvent'], {'type': 'creationBack'});
    expect(texts(p), contains('预览安排'));
    p = await page(
      state: obj(p['state']),
      event: {'type': 'field', 'key': 'title', 'value': '新批量练习'},
    );
    p = await page(state: obj(p['state']), event: {'type': 'preview'});
    expect(obj(p['header'])['title'], '预览安排');
    expect(nodes(p['tree']).any((n) => n['planReview'] != null), true);
    p = await page(state: obj(p['state']), event: {'type': 'confirmCreation'});
    expect(obj(p['header'])['title'], '批量任务');
    expect(texts(p), contains('新批量练习'));
    expect(obj(p['state'])['screen'], 'list');
    expect(await preferences.get(actor, 'creation.draft.v1'), ordinaryDraft);
  });

  test(
    'status, selection cancellation, and tab changes use live series state',
    () async {
      await fixture();
      var p = await openDetail();
      final original = await query('series.get', {'id': 'paper-series'});
      p = await page(state: obj(p['state']), event: {'type': 'status'});
      expect(texts(p), contains('恢复生成'));
      expect(obj(p['state'])['cachedDetail'], isA<Map>());
      expect(
        (await query('series.get', {'id': 'paper-series'}))['pendingCount'],
        original['pendingCount'],
      );
      p = await page(state: obj(p['state']), event: {'type': 'status'});
      expect(texts(p), contains('暂停生成'));
      p = await page(state: obj(p['state']), event: {'type': 'selectMode'});
      final first = obj((original['rows'] as List).first);
      p = await page(
        state: obj(p['state']),
        event: {'type': 'selectRow', 'taskId': first['taskId'], 'value': true},
      );
      expect(obj(p['state'])['selected'], [first['taskId']]);
      p = await page(state: obj(p['state']), event: {'type': 'cancelSelected'});
      expect(
        (await query('series.get', {'id': 'paper-series'}))['cancelledCount'],
        1,
      );
      p = await page(state: obj(p['state']), event: {'type': 'selectMode'});
      p = await page(
        state: obj(p['state']),
        event: {'type': 'tab', 'status': 'cancelled'},
      );
      expect(obj(p['state'])['selecting'], false);
      expect(obj(p['state'])['selected'], isEmpty);
      expect(texts(p), contains('已取消'));
    },
  );

  test(
    'rule edit preview saves future rules while preserving generated tasks',
    () async {
      await fixture();
      var p = await openDetail();
      final before = await query('series.get', {'id': 'paper-series'});
      p = await page(state: obj(p['state']), event: {'type': 'editRules'});
      expect(obj(p['header'])['title'], '编辑规则');
      p = await page(
        state: obj(p['state']),
        event: {'type': 'editField', 'key': 'editDuration', 'value': 45},
      );
      p = await page(state: obj(p['state']), event: {'type': 'previewRules'});
      expect(obj(p['header'])['title'], '规则变更预览');
      expect(texts(p), contains('修改已生成任务：0项'));
      p = await page(state: obj(p['state']), event: {'type': 'applyRules'});
      expect(obj(p['header'])['title'], '批次详情');
      final after = await query('series.get', {'id': 'paper-series'});
      expect(obj(after['draft'])['estimatedMinutes'], 45);
      expect(after['rows'], before['rows']);
      expect(obj(p['state'])['error'], isNull);
    },
  );

  test('completing an embedded task returns to its batch detail and keeps management context', () async {
    await fixture();
    var p = await page(event: {'type': 'search', 'value': '论文'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'openBatch', 'id': 'paper-series'},
    );
    p = await page(state: obj(p['state']), event: {'type': 'moreRows'});
    final before = await query('series.get', {'id': 'paper-series'});
    final task = obj((before['rows'] as List).first);
    final calls = <String>[];
    host.interaction = (_, method, args) async {
      calls.add(method);
      return method == 'ui.review';
    };
    p = await page(
      state: obj(p['state']),
      event: {'type': 'openTask', 'taskId': task['taskId']},
    );
    expect(obj(p['header'])['title'], '任务详情');
    p = await page(state: obj(p['state']), event: {'type': 'complete'});
    expect(obj(p['header'])['title'], '批次详情');
    final state = obj(p['state']);
    expect(state['screen'], 'detail');
    expect(state['id'], 'paper-series');
    expect(state['search'], '论文');
    expect(state['filter'], 'all');
    expect(state['visibleRows'], 24);
    expect(
      (await query('series.get', {'id': 'paper-series'}))['completedCount'],
      1,
    );
    expect(calls, isNot(contains('ui.navigate')));
    expect(calls, isNot(contains('ui.panel')));
  });

  test('opening another batch rule editor discards hidden inputs from the prior batch', () async {
    await fixture();
    final preview = await query('creation.preview', {
      'title': '每日复盘',
      'estimatedMinutes': 15,
      'timezone': 'UTC',
      'firstDate': '2026-11-03',
      'days': 30,
      'rules': {
        'interval': {'minDays': 1, 'maxDays': 1},
        'weekdays': [1, 2, 3, 4, 5, 6, 7],
        'timeWindow': {'start': '21:00', 'end': '22:00'},
      },
    });
    await run('creation.apply', {
      'creationKey': 'review-series',
      'preview': preview,
    });
    var p = await openDetail();
    p = await page(state: obj(p['state']), event: {'type': 'editRules'});
    final staleForms = obj(obj(p['state'])['edit']);
    p = await page(
      state: obj(p['state']),
      event: {'type': 'backToDetail'},
      forms: staleForms,
    );
    p = await page(
      state: obj(p['state']),
      event: {'type': 'backToList'},
      forms: staleForms,
    );
    p = await page(
      state: obj(p['state']),
      event: {'type': 'openBatch', 'id': 'review-series'},
      forms: staleForms,
    );
    p = await page(
      state: obj(p['state']),
      event: {'type': 'editRules'},
      forms: staleForms,
    );
    expect(obj(p['replaceForms'])['editTitle'], '每日复盘');
    expect(obj(p['replaceForms'])['editDuration'], 15);
    expect(obj(p['replaceForms'])['editMin'], 1);
    expect(obj(p['state'])['error'], isNull);
  });

  test(
    'batch-only entry preserves repeat rules when a one-time template is used',
    () async {
      var p = await page(event: {'type': 'newBatch'});
      p = await page(state: obj(p['state']), event: {'type': 'templates'});
      host.interaction = (_, method, args) async =>
          method == 'ui.dialog' ? {'replace': true} : method == 'ui.review';
      p = await page(
        state: obj(p['state']),
        event: {'type': 'useTemplate', 'id': 'notes'},
      );
      final creation = obj(obj(p['state'])['creation']);
      final draft = obj(creation['draft']);
      expect(draft['mode'], 'batch');
      expect(draft['title'], '整理笔记');
      expect(draft['minDays'], 4);
      expect(texts(p), contains('预览安排'));
      expect(nodes(p['tree']).any((n) => n['label'] == '移除多次任务'), false);
    },
  );

  test('preferred time survives new batch draft and preview, and can be edited and cleared', () async {
    var p = await page(event: {'type': 'newBatch'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'field', 'key': 'title', 'value': '优先时间阅读'},
    );
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    expect(
      nodes(p['tree'])
          .any((n) => n['key'] == 'preferredTime' && n['clearable'] == true),
      true,
    );
    p = await page(
      state: obj(p['state']),
      event: {'type': 'field', 'key': 'preferredTime', 'value': '20:03'},
    );
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    expect(
      obj(obj(obj(p['state'])['creation'])['draft'])['preferredTime'],
      '20:03',
    );
    p = await page(state: obj(p['state']), event: {'type': 'creationBack'});
    p = await page(state: obj(p['state']), event: {'type': 'newBatch'});
    expect(
      obj(obj(obj(p['state'])['creation'])['draft'])['preferredTime'],
      '20:03',
    );
    p = await page(state: obj(p['state']), event: {'type': 'preview'});
    final creation = obj(obj(p['state'])['creation']);
    expect(creation['error'], isNull);
    expect(texts(p), contains('优先时间点 20:03'));
    expect(
      (obj(creation['preview'])['assigned'] as List)
          .map(obj)
          .every((n) => n['start'] == '20:03'),
      true,
    );
    p = await page(state: obj(p['state']), event: {'type': 'confirmCreation'});
    final list = await query('series.list');
    final batch = obj((list['items'] as List).single);
    p = await page(
      state: obj(p['state']),
      event: {'type': 'openBatch', 'id': batch['id']},
    );
    final original = await query('series.get', {'id': batch['id']});
    expect(texts(p), contains('优先时间点 20:03'));
    p = await page(state: obj(p['state']), event: {'type': 'editRules'});
    expect(obj(p['replaceForms'])['editPreferredTime'], '20:03');
    p = await page(
      state: obj(p['state']),
      event: {
        'type': 'editField',
        'key': 'editPreferredTime',
        'value': '21:03',
      },
    );
    p = await page(state: obj(p['state']), event: {'type': 'previewRules'});
    expect(texts(p), contains('优先时间点：20:03 → 21:03'));
    p = await page(state: obj(p['state']), event: {'type': 'applyRules'});
    expect(texts(p), contains('优先时间点 21:03'));
    expect(
      (await query('series.get', {'id': batch['id']}))['rows'],
      original['rows'],
    );
    p = await page(state: obj(p['state']), event: {'type': 'editRules'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'editField', 'key': 'editPreferredTime', 'value': null},
    );
    p = await page(state: obj(p['state']), event: {'type': 'previewRules'});
    expect(texts(p), contains('优先时间点：21:03 → 未设置'));
    p = await page(state: obj(p['state']), event: {'type': 'applyRules'});
    expect(texts(p).where((t) => t.startsWith('优先时间点 ')), isEmpty);
    expect(
      (await query('series.get', {'id': batch['id']}))['rows'],
      original['rows'],
    );
  });

  test('new batch validates preferred time against allowed duration before applying settings', () async {
    var p = await page(event: {'type': 'newBatch'});
    p = await page(state: obj(p['state']), event: {'type': 'openMultiple'});
    p = await page(
      state: obj(p['state']),
      event: {'type': 'field', 'key': 'preferredTime', 'value': '21:45'},
    );
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    expect(obj(obj(p['state'])['creation'])['step'], 'multiple');
    expect(obj(obj(p['state'])['creation'])['error'], contains('完整放下'));
    p = await page(
      state: obj(p['state']),
      event: {'type': 'field', 'key': 'preferredTime', 'value': null},
    );
    p = await page(state: obj(p['state']), event: {'type': 'applyMultiple'});
    expect(obj(obj(p['state'])['creation'])['step'], 'create');
    expect(obj(obj(p['state'])['creation'])['error'], isNull);
  });
}
