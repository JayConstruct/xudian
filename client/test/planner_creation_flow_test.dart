import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
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

  test('batch preview creates nothing until confirmed and manual adjustment preserves task count', () async {
    var p = await page(
      event: {'type': 'mode', 'index': 1},
      forms: {'title': '阅读论文'},
    );
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
          method == 'ui.dialog' ? {'name': '我的阅读'} : true;
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
