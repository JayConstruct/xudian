import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app_icons.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> source(String id) async {
  final folder = Directory('../packages/modules/$id');
  final files = <String, String>{};
  for (final file in folder.listSync().whereType<File>()) {
    if (file.path.endsWith('.js')) {
      files[file.uri.pathSegments.last] = await file.readAsString();
    }
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${folder.path}/module.json').readAsString()),
      ),
      files,
    ),
    allowUnsignedLocal: true,
  );
}

List<Map<String, Object?>> descendants(Object? value) {
  if (value is Map) {
    return [
      object(value),
      for (final child in value.values) ...descendants(child),
    ];
  }
  if (value is List) {
    return [for (final child in value) ...descendants(child)];
  }
  return [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('ui-example-catalog-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
    await host.install(await source('app.ui.examples'));
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Map<String, Object?>> render(
    String page, {
    Object? state,
    Object? event,
    Map<String, Object?> forms = const {},
    Map<String, Object?> context = const {},
  }) async => object(
    await host.invokePage('app.ui.examples', 'render', {
      'context': {'pageId': 'app.ui.examples.$page', ...context},
      'state': state ?? {},
      'event': event,
      'formValues': forms,
    }),
  );

  test('content exposes callable vector icons and their real public component code', () async {
    final page = await render('demo.content');
    final nodes = descendants(page['tree']);
    final icons = nodes.where((node) => node['ref'] == 'ui.icon@1').toList();
    expect(icons, hasLength(38));
    final names = icons.map((node) => object(node['props'])['name']).toSet();
    expect(names, hasLength(38));
    expect(
      names,
      containsAll([
        'today',
        'calendar',
        'tasks',
        'modules',
        'projects',
        'inbox',
        'ai',
        'copy',
        'pin',
      ]),
    );
    for (final icon in icons) {
      final props = object(icon['props']);
      expect(appIconData(props['name']), isNotNull);
      expect(props['size'], 28);
      expect(props['semanticLabel'], isNotEmpty);
      expect(
        nodes.any(
          (node) => node['type'] == 'text' && node['text'] == props['name'],
        ),
        true,
      );
    }
    expect(nodes.where((node) => node['type'] == 'grid'), hasLength(3));
    final calls = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      calls.add({'method': method, ...args});
      return null;
    };
    await render('demo.content', event: {'type': 'showCode'});
    expect(calls.single['method'], 'ui.showCode');
    final code = (calls.single['sections'] as List)
        .map((section) => object(section)['code'])
        .join('\n');
    expect(code, contains("ui.component('ui.icon@1'"));
    expect(code, contains('semanticLabel'));
    expect(code, contains('AppSymbolIcon'));
    expect(code, contains('UI 包可覆盖'));
  });

  test('categorized home links to 38 demos with icon-free rows and code-dialog actions', () async {
    final home = await render('page');
    final links = descendants(home['tree'])
        .where((node) => node['type'] == 'listTile')
        .toList();
    expect(links, hasLength(38));
    expect(links.every((link) => !link.containsKey('icon')), true);
    expect(
      descendants(home['tree']).where((node) => node['type'] == 'grid'),
      isEmpty,
    );
    final calls = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      calls.add({'method': method, ...args});
      return null;
    };
    for (final link in links) {
      final id = object(link['event'])['id'] as String;
      final page = await render('demo.$id');
      final tree = object(page['tree']);
      expect(tree['footer'], isNull);
      expect(
        object(object((tree['children'] as List).last)['props'])['label'],
        '查看调用方式',
      );
      expect(
        descendants(tree).where((node) => node['type'] == 'richText'),
        isEmpty,
      );
      await render('demo.$id', event: {'type': 'showCode'});
      expect(calls.last['method'], 'ui.showCode');
      final code = (calls.last['sections'] as List)
          .map((section) => object(section)['code'])
          .join('\n');
      expect(code, isNot(contains('/* 当前值 */')));
      expect(code, isNot(contains('ui.panel@1')));
      await render('page', event: link['event']);
      expect(calls.last['page'], 'app.ui.examples.demo.$id');
    }
    final definition = host.instances['app.ui.examples']!.package.definition;
    final pageIds = (definition['pages'] as List)
        .map((value) => object(value)['id'])
        .toList();
    expect(
      pageIds,
      containsAll(['app.ui.examples.composition', 'app.ui.examples.local']),
    );
    expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
  });

  test('daily UI demonstrations use public refs and real local change/open actions', () async {
    final overview = await render('demo.dailyOverview');
    final overviewComponent = descendants(overview['tree'])
        .singleWhere((node) => node['ref'] == 'ui.dayOverview@1');
    final props = object(overviewComponent['props']);
    expect(props['date'], '2026-10-10');
    expect(props['selectedDate'], props['date']);
    expect(props['days'], hasLength(5));
    final calls = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      calls.add({'method': method, ...args});
      return method == 'ui.dialog' ? {'name': '演示已确认'} : null;
    };
    for (final id in ['dailyHeader', 'dailyAgenda']) {
      final page = await render('demo.$id');
      final component = descendants(page['tree']).singleWhere(
        (node) =>
            node['ref'] ==
            (id == 'dailyHeader' ? 'ui.sectionHeader@1' : 'ui.agendaItem@1'),
      );
      final changed = await render(
        'demo.$id',
        state: page['state'],
        event: object(component['events'])['press'],
      );
      expect(
        descendants(changed['tree'])
            .any((node) => '${node['text']}'.startsWith('已执行：')),
        true,
      );
    }
    var page = await render('demo.dailyTask');
    var task = descendants(page['tree'])
        .singleWhere((node) => node['ref'] == 'ui.taskItem@1');
    expect(object(task['props'])['completed'], false);
    page = await render(
      'demo.dailyTask',
      state: page['state'],
      event: {...object(object(task['events'])['change']), 'value': true},
    );
    task = descendants(page['tree'])
        .singleWhere((node) => node['ref'] == 'ui.taskItem@1');
    expect(object(task['props'])['completed'], true);
    await render(
      'demo.dailyTask',
      state: page['state'],
      event: object(task['events'])['open'],
    );
    expect(calls.last['method'], 'ui.dialog');
    expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
  });

  test(
    'pins save in one action without business review and survive restart',
    () async {
      final calls = <String>[];
      host.interaction = (_, method, _) async {
        calls.add(method);
        return null;
      };
      var demo = await render(
        'demo.date',
        event: {'type': 'pin', 'id': 'date', 'remove': false},
      );
      expect(
        descendants(demo['tree'])
            .any((node) => object(node['props'] ?? {})['label'] == '取消固定'),
        true,
      );
      await render(
        'demo.date',
        event: {'type': 'pin', 'id': 'date', 'remove': false},
      );
      expect(calls, isEmpty);
      expect(await store.sql('SELECT * FROM host_operations'), isEmpty);
      await host.close();
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      var home = await render('page');
      final pinned = descendants(home['tree']).where(
        (node) => node['type'] == 'sectionHeader' && node['title'] == '已固定',
      );
      expect(pinned, hasLength(1));
      expect(
        descendants(home['tree']).where((node) => node['title'] == '日期选择器'),
        hasLength(2),
      );
      demo = await render(
        'demo.date',
        event: {'type': 'pin', 'id': 'date', 'remove': true},
      );
      home = await render('page');
      expect(
        descendants(home['tree']).where(
          (node) => node['type'] == 'sectionHeader' && node['title'] == '已固定',
        ),
        isEmpty,
      );
    },
  );

  test(
    'real floating, errors, loading, animations and dialog events respond',
    () async {
      var page = await render(
        'demo.floating',
        event: {'type': 'floating', 'visible': true},
      );
      expect(object(object(page['tree'])['floatingPanel'])['title'], '悬浮窗示例');
      page = await render(
        'demo.floating',
        state: page['state'],
        event: {'type': 'floating', 'visible': false},
      );
      expect(object(page['tree'])['floatingPanel'], isNull);
      page = await render('demo.error');
      final error = descendants(page['tree'])
          .singleWhere((node) => node['ref'] == 'ui.error@1');
      page = await render(
        'demo.error',
        state: page['state'],
        event: object(error['events'])['retry'],
      );
      expect(
        descendants(page['tree']).any((node) => node['text'] == '重试成功，已恢复示例内容'),
        true,
      );
      page = await render(
        'demo.loading',
        event: {'type': 'changeDemo', 'id': 'loading', 'value': true},
      );
      expect(
        descendants(page['tree']).any((node) => node['ref'] == 'ui.loading@1'),
        true,
      );
      page = await render(
        'demo.loading',
        state: page['state'],
        event: {'type': 'changeDemo', 'id': 'loading', 'value': false},
      );
      expect(
        descendants(page['tree']).any((node) => node['ref'] == 'ui.loading@1'),
        false,
      );
      page = await render(
        'demo.animation',
        event: {'type': 'changeDemo', 'id': 'animation', 'value': 'slide'},
      );
      var transition = descendants(page['tree'])
          .singleWhere((node) => node['type'] == 'transition');
      expect(transition['effect'], 'slide');
      page = await render(
        'demo.animation',
        state: page['state'],
        event: {'type': 'replay'},
      );
      transition = descendants(page['tree'])
          .singleWhere((node) => node['type'] == 'transition');
      expect(transition['replayKey'], 1);
      final calls = <Map<String, Object?>>[];
      host.interaction = (_, method, args) async {
        calls.add({'method': method, ...args});
        return method == 'ui.dialog' ? {'name': '真实确认'} : null;
      };
      page = await render(
        'demo.confirm',
        event: {'type': 'confirm', 'id': 'confirm'},
      );
      expect(
        descendants(page['tree']).any((node) => node['text'] == '已确认 真实确认'),
        true,
      );
      await render(
        'demo.notification',
        event: {'type': 'notify', 'kind': 'success'},
      );
      expect(calls.last['method'], 'ui.notify');
      expect(calls.last['kind'], 'success');
      await render('demo.panel', event: {'type': 'panel'});
      expect(calls.last['method'], 'ui.panel');
      expect(object(calls.last['presentation'])['adaptive'], true);
    },
  );

  test('date samples use today and registered provider demos are callable and pinnable', () async {
    var date = await render(
      'demo.date',
      event: {'type': 'mode', 'id': 'date', 'mode': '已选'},
    );
    expect(object(date['replaceForms'])['demo.date'], '2026-10-10');
    await host.install(await source('example.ui.compact'));
    var home = await render('page');
    final link = descendants(home['tree'])
        .singleWhere((node) => node['title'] == '主要操作按钮');
    final id = object(link['event'])['id'] as String;
    final ref = id.split('|').last;
    final context = {'providerId': 'example.ui.compact', 'componentRef': ref};
    var page = await render('registered', context: context);
    final sample = descendants(page['tree'])
        .singleWhere((node) => node['type'] == 'componentExample');
    expect(sample['providerId'], 'example.ui.compact');
    expect(sample['ref'], ref);
    final calls = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      calls.add({'method': method, ...args});
      return null;
    };
    await render('registered', context: context, event: {'type': 'showCode'});
    expect(calls.last['method'], 'ui.showCode');
    final code = (calls.last['sections'] as List)
        .map((section) => object(section)['code'])
        .join('\n');
    expect(code, contains("ui.component('$ref'"));
    expect(code, contains('"dependencies"'));
    page = await render(
      'registered',
      context: context,
      event: {'type': 'registeredAction', 'port': 'press'},
    );
    expect(
      descendants(page['tree'])
          .any((node) => '${node['text']}'.startsWith('事件：press')),
      true,
    );
    await render(
      'registered',
      context: context,
      event: {'type': 'pin', 'id': id, 'remove': false},
    );
    home = await render('page');
    expect(
      descendants(home['tree']).where((node) => node['title'] == '主要操作按钮'),
      hasLength(2),
    );
    await render(
      'registered',
      context: {
        'providerId': 'example.ui.compact',
        'componentRef': 'ui.button@1',
      },
      event: {'type': 'showCode'},
    );
    expect(
      (calls.last['sections'] as List).any(
        (section) => '${object(section)['code']}'.contains('添加依赖不会切换风格'),
      ),
      true,
    );
  });
}
