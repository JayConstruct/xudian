import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:task_app/app/app_icons.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/responsive_content_grid.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> _source(String id) async {
  final folder = Directory('../packages/modules/$id');
  final files = <String, String>{};
  await for (final entry in folder.list(recursive: true)) {
    if (entry is File && entry.path.endsWith('.js')) {
      files[entry.path.substring(folder.path.length + 1)] = await entry
          .readAsString();
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

Iterable<Map<String, Object?>> _nodes(Object? value) sync* {
  if (value is Map) {
    yield object(value);
    for (final child in value.values) {
      yield* _nodes(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* _nodes(child);
    }
  }
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
    directory = await Directory.systemTemp.createTemp('module-pages-style-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 10, 10, 6);
    await host.initialize();
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Map<String, Object?>> render(
    String module, {
    String? page,
    Object? state,
    Object? event,
    Map<String, Object?> forms = const {},
    Map<String, Object?> context = const {},
  }) async => object(
    await host.invokePage(module, 'render', {
      'state': state ?? {},
      'event': event,
      'formValues': forms,
      'context': {...context, if (page != null) 'pageId': '$module.$page'},
    }),
  );

  testWidgets('public vector icon gallery renders at 320px with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(
      () async => host.install(await _source('app.ui.examples')),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: ScriptPage(
            host: host,
            moduleId: 'app.ui.examples',
            handler: 'render',
            pageContext: const {'pageId': 'app.ui.examples.demo.content'},
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(ResponsiveContentGrid), findsNWidgets(3));
    expect(find.byType(AppSymbolIcon), findsNWidgets(38));
    expect(find.text('today'), findsOneWidget);
    expect(find.text('calendar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('schedule settings and management use natural sections without losing course actions or grid', () async {
    await host.install(await _source('app.schedule'));
    final actor = host.instances['app.schedule']!.actor;
    final plan = await host.prepare(
      actor,
      const ServiceRef('app.schedule', 'schedule.demo.create', 1),
      {},
    );
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
    final before = await store.sql(
      'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
    );
    for (final page in [
      'settings',
      'semester',
      'periods',
      'courses',
      'changes',
      'imports',
      'timetables',
      'today',
    ]) {
      final result = await render('app.schedule', page: page);
      final nodes = _nodes(result['tree']).toList();
      expect(
        nodes.where((node) => node['type'] == 'card'),
        isEmpty,
        reason: page,
      );
      expect(
        nodes.where((node) => node['type'] == 'sectionHeader'),
        isNotEmpty,
        reason: page,
      );
      expect(
        nodes
            .where((node) => node['type'] == 'listTile')
            .every((node) => !node.containsKey('icon')),
        true,
        reason: page,
      );
    }
    final courses = _nodes(
      (await render('app.schedule', page: 'courses'))['tree'],
    ).toList();
    expect(courses.where((node) => node['type'] == 'disclosure'), isNotEmpty);
    final edit = courses.firstWhere((node) => node['title'] == '编辑安排');
    final calls = <Map<String, Object?>>[];
    host.interaction = (_, method, args) async {
      calls.add({'method': method, ...args});
      return null;
    };
    await render('app.schedule', page: 'courses', event: edit['event']);
    expect(calls.single['method'], 'ui.dialog');
    expect(
      (calls.single['fields'] as List).map((field) => object(field)['key']),
      containsAll([
        'name',
        'weekday',
        'startPeriod',
        'endPeriod',
        'weeks',
        'location',
        'teacher',
      ]),
    );
    final grid = _nodes((await render('app.schedule', page: 'home'))['tree'])
        .singleWhere((node) => node['type'] == 'timeGrid');
    expect(grid['blocks'], isNotEmpty);
    final today = _nodes((await render('app.schedule', page: 'today'))['tree']);
    final agenda = today.firstWhere((node) => node['type'] == 'agendaItem');
    expect(agenda['startTime'], '08:00');
    await render('app.schedule', page: 'today', event: agenda['event']);
    expect(calls.last['method'], 'ui.panel');
    expect(calls.last['page'], 'app.schedule.occurrence');
    final detail = _nodes(
      (await render(
        'app.schedule',
        page: 'occurrence',
        context: object(calls.last['context']),
      ))['tree'],
    );
    expect(detail.any((node) => node['title'] == '单次调课'), true);
    expect(
      await store.sql(
        'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
      ),
      before,
    );
  });

  test('importer internal navigation retains search, paging and script metadata in simple sections', () async {
    for (final id in ['app.schedule', 'app.import.shiguang']) {
      await host.install(await _source(id));
    }
    final before = await store.sql('SELECT * FROM host_records');
    var page = await render('app.import.shiguang');
    expect(
      _nodes(page['tree']).where((node) => node['type'] == 'card'),
      isEmpty,
    );
    final entry = _nodes(page['tree'])
        .firstWhere((node) => node['title'] == '按学校导入');
    page = await render(
      'app.import.shiguang',
      state: page['state'],
      event: entry['event'],
    );
    final first = _nodes(page['tree'])
        .firstWhere((node) => node['type'] == 'sectionHeader');
    expect(first['title'], '搜索结果');
    expect(first['count'], greaterThan(30));
    page = await render(
      'app.import.shiguang',
      state: page['state'],
      event: {'type': 'schoolPage', 'page': 1},
    );
    expect(
      _nodes(page['tree'])
          .any((node) => '${node['subtitle']}'.startsWith('第 2/')),
      true,
    );
    page = await render(
      'app.import.shiguang',
      state: page['state'],
      event: {'type': 'searchSchool'},
      forms: {'schoolSearch': '安徽财经大学'},
    );
    final schools = _nodes(page['tree'])
        .where(
          (node) =>
              node['type'] == 'listTile' &&
              object(node['event'])['type'] == 'selectSchool',
        )
        .toList();
    expect(schools, hasLength(1));
    expect(schools.single.containsKey('icon'), false);
    page = await render(
      'app.import.shiguang',
      state: page['state'],
      event: schools.single['event'],
    );
    final details = _nodes(page['tree']).toList();
    expect(details.where((node) => node['type'] == 'card'), isEmpty);
    expect(details.any((node) => node['title'] == '脚本来源'), true);
    expect(
      details.any(
        (node) =>
            node['type'] == 'richText' &&
            '${node['text']}'.contains('github.com/'),
      ),
      true,
    );
    page = await render(
      'app.import.shiguang',
      state: page['state'],
      event: {'type': 'back'},
    );
    expect(object(page['state'])['schoolSearch'], '安徽财经大学');
    expect(await store.sql('SELECT * FROM host_records'), before);
  });

  test('AI transcript and gallery preserve public controls and local task completion without nested cards', () async {
    await host.install(await _source('app.ai'));
    await host.install(await _source('app.ui.examples'));
    final before = await store.sql('SELECT * FROM host_records');
    final ai = await render(
      'app.ai',
      state: {
        'messages': [
          {'role': 'user', 'content': '本地会话'},
          {'role': 'assistant', 'content': '本地回复'},
        ],
      },
    );
    final transcript = _nodes(ai['tree']).toList();
    expect(transcript.where((node) => node['type'] == 'card'), isEmpty);
    expect(
      transcript
          .where((node) => node['type'] == 'richText')
          .map((node) => node['text']),
      ['本地会话', '本地回复'],
    );
    final cancel = transcript.singleWhere((node) => node['text'] == '取消当前操作');
    expect(cancel['interrupt'], 'cancel');
    expect(
      transcript.singleWhere((node) => node['text'] == '发送')['variant'],
      'filled',
    );
    final home = await render('app.ui.examples', page: 'page');
    expect(
      _nodes(home['tree']).where((node) => node['type'] == 'card'),
      isEmpty,
    );
    expect(
      _nodes(home['tree']).where((node) => node['type'] == 'sectionHeader'),
      isNotEmpty,
    );
    final card = await render('app.ui.examples', page: 'demo.card');
    expect(
      _nodes(card['tree']).where((node) => node['ref'] == 'ui.card@1'),
      isNotEmpty,
    );
    var taskPage = await render('app.ui.examples', page: 'demo.tasks');
    var task = _nodes(taskPage['tree']).firstWhere(
      (node) =>
          node['ref'] == 'ui.taskItem@1' &&
          object(node['props'])['completed'] == false,
    );
    final key = object(object(task['events'])['change'])['id'];
    taskPage = await render(
      'app.ui.examples',
      page: 'demo.tasks',
      state: taskPage['state'],
      event: {...object(object(task['events'])['change']), 'value': true},
    );
    task = _nodes(taskPage['tree'])
        .singleWhere((node) => node['key'] == 'demo-task:$key');
    expect(object(task['props'])['completed'], true);
    expect(await store.sql('SELECT * FROM host_records'), before);
  });
}
