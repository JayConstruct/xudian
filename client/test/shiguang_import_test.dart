import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/data/app_database.dart';

List<Map<String, Object?>> objects(Object? value) =>
    (value as List).map(object).toList();

Iterable<Map<String, Object?>> nodes(Object? value) sync* {
  if (value is Map) {
    final node = object(value);
    yield node;
    for (final child in node.values) {
      yield* nodes(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* nodes(child);
    }
  }
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory dir;
  late ModuleActor adapter, schedule;
  const options = {
    'name': '正方导入',
    'scope': 'school/student/2026-autumn',
    'firstMonday': '2026-09-07',
    'totalWeeks': 20,
  };
  Map<String, Object?> payload({List<int> weeks = const [1, 3, 5]}) => {
    'courses': [
      {
        'name': '数学',
        'teacher': '老师',
        'position': 'A101',
        'day': 1,
        'startSection': 1,
        'endSection': 2,
        'weeks': weeks,
      },
    ],
    'timeSlots': [
      {'number': 1, 'startTime': '08:00', 'endTime': '08:45'},
      {'number': 2, 'startTime': '08:50', 'endTime': '09:35'},
    ],
  };
  const importRef = ServiceRef('app.schedule', 'schedule.import.prepare', 1);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    dir = await Directory.systemTemp.createTemp('shiguang-import-');
    host = ModuleHost(store: store, directory: dir);
    await host.initialize();
    for (final id in ['app.schedule', 'app.import.shiguang']) {
      await host.install(
        await ScriptPackage.verify(
          await File('../dist/modules/$id.xmodule').readAsBytes(),
          allowUnsignedLocal: true,
        ),
      );
    }
    adapter = host.instances['app.import.shiguang']!.actor;
    schedule = host.instances['app.schedule']!.actor;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<Map<String, Object?>> convert(Map<String, Object?> input) async =>
      object(
        await host.query(
          adapter,
          const ServiceRef('app.import.shiguang', 'shiguang.convert', 1),
          {'payload': input, 'options': options},
        ),
      );
  Future<Map<String, Object?>> schools({
    String search = '',
    int page = 0,
  }) async => object(
    await host.query(
      adapter,
      const ServiceRef('app.import.shiguang', 'shiguang.adapters.list', 1),
      {'search': search, 'page': page},
    ),
  );
  Future<Object?> providerSave(ChangePlan plan) async {
    host.interaction = (actor, method, args) async {
      expect(actor, same(schedule));
      expect(method, 'ui.review');
      return true;
    };
    final result = object(
      await host.invokePage('app.schedule', 'render', {
        'context': {'pageId': 'app.schedule.imports', 'importPlanId': plan.id},
      }),
    );
    final state = object(result['state']);
    expect(state['adapterPlan'], isNotNull);
    final saved = object(
      await host.invokePage('app.schedule', 'render', {
        'context': {'pageId': 'app.schedule.imports', 'importPlanId': plan.id},
        'state': state,
        'event': {'type': 'confirmAdapter'},
      }),
    );
    return object(saved['state'])['timetableId'];
  }

  test('independent package mounts in settings and the importer slot', () {
    final registry = ModuleRegistry([
      for (final instance in host.instances.values)
        ScriptAppModule(host, instance.package),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
    expect(registry.ui.page('app.import.shiguang.home'), isNotNull);
    registry.dispose();
  });
  test(
    'warehouse search and pagination retain all adapters and school variants',
    () async {
      final first = await schools();
      expect(object(first['snapshot'])['schools'], 247);
      expect(first['total'], 269);
      expect(objects(first['items']), hasLength(30));
      final all = <Map<String, Object?>>[];
      for (var page = 0; page < (first['pages'] as int); page++) {
        final result = await schools(page: page);
        expect(result['page'], page);
        all.addAll(objects(result['items']));
      }
      expect(all, hasLength(first['total'] as int));
      expect(all.map((item) => item['id']).toSet(), hasLength(all.length));
      expect((await schools(page: 999))['page'], (first['pages'] as int) - 1);
      final named = objects((await schools(search: '安徽财经'))['items']);
      expect(named.map((item) => item['id']), ['AUFE_01', 'AUFE_02']);
      expect(
        objects((await schools(search: 'aufe webvpn'))['items']).single['id'],
        'AUFE_02',
      );
      expect((await schools(search: '不存在的学校xyz'))['total'], 0);
      expect(await store.query(schedule, 'timetables', {}), isEmpty);
    },
  );
  test('school selection replaces stale URL and real QuickJS loads every lazy bundle', () async {
    final representatives = <int, Map<String, Object?>>{};
    for (var page = 0; page < ((await schools())['pages'] as int); page++) {
      for (final item in objects((await schools(page: page))['items'])) {
        representatives.putIfAbsent(item['bundle'] as int, () => item);
      }
    }
    expect(representatives.keys.toSet(), {0, 1, 2, 3, 4});
    var captures = 0;
    for (final item in representatives.values) {
      final bundle = await File(
        '../packages/modules/app.import.shiguang/warehouse/scripts-${item['bundle']}.js',
      ).readAsString();
      final sources = object(
        jsonDecode(
          bundle
              .substring(bundle.indexOf('export default ') + 15)
              .trim()
              .replaceFirst(RegExp(r';$'), ''),
        ),
      );
      host.interaction = (actor, method, args) async {
        expect(actor, same(adapter));
        expect(method, 'browser.capture');
        expect(args['url'], item['url']);
        expect(args['script'], contains(sources[item['id']] as String));
        expect(args['script'], contains('installBridge'));
        captures++;
        return null;
      };
      final chosen = object(
        await host.invokePage(adapter.moduleId, 'render', {
          'state': {
            'url': 'https://old.example',
            'script': 'throw new Error("old script");',
            'input': {
              'draft': {'scope': 'old-school'},
            },
            'plan': {'planId': 'stale-preview'},
            'options': {'scope': 'old-school'},
          },
          'event': {'type': 'selectSchool', 'id': item['id']},
          'formValues': {'url': 'https://old.example'},
        }),
      );
      expect(object(chosen['state'])['script'], isNull);
      expect(object(chosen['state'])['input'], isNull);
      expect(object(chosen['state'])['plan'], isNull);
      expect(object(chosen['state'])['options'], isNull);
      expect(object(chosen['state'])['adapterId'], item['id']);
      expect(object(chosen['replaceForms'])['url'], item['url']);
      final captured = object(
        await host.invokePage(adapter.moduleId, 'render', {
          'state': chosen['state'],
          'event': {'type': 'browser'},
          'formValues': chosen['replaceForms'],
        }),
      );
      expect(object(captured['state'])['error'], isNull);
      expect(object(captured['state'])['input'], isNull);
    }
    expect(captures, 5);
    expect(await store.query(schedule, 'timetables', {}), isEmpty);
    expect(await store.query(schedule, 'courses', {}), isEmpty);
  });
  test(
    'school picker searches, selects and cancels without altering course data',
    () async {
      Future<Map<String, Object?>> render(Map<String, Object?> args) async =>
          object(await host.invokePage(adapter.moduleId, 'render', args));
      final opened = await render({
        'event': {'type': 'chooseSchool'},
        'formValues': {'url': 'https://kept.example'},
      });
      expect(object(opened['state'])['choosingSchool'], isTrue);
      final next = await render({
        'state': opened['state'],
        'event': {'type': 'schoolPage', 'page': 1},
      });
      expect(object(next['state'])['schoolPage'], 1);
      final searched = await render({
        'state': next['state'],
        'event': {'type': 'searchSchool'},
        'formValues': {'schoolSearch': 'AUFE WebVPN'},
      });
      expect(object(searched['state'])['schoolPage'], 0);
      final rows = objects(object(searched['tree'])['children']).where(
        (node) =>
            node['type'] == 'listTile' &&
            object(node['event'])['type'] == 'selectSchool',
      );
      expect(rows, hasLength(1));
      expect(object(rows.single['event'])['id'], 'AUFE_02');
      final closed = await render({
        'state': searched['state'],
        'event': {'type': 'closeSchools'},
      });
      expect(object(closed['state'])['choosingSchool'], isFalse);
      expect(object(closed['state'])['url'], 'https://kept.example');
      final invalid = await render({
        'event': {'type': 'selectSchool', 'id': 'missing-adapter'},
      });
      expect(object(invalid['state'])['error'], contains('学校脚本不存在'));
      expect(await store.query(schedule, 'courses', {}), isEmpty);
    },
  );
  test('import homepage groups entries and school search lists schools without instructions', () async {
    Future<Map<String, Object?>> render(Map<String, Object?> args) async =>
        object(await host.invokePage(adapter.moduleId, 'render', args));
    final home = await render({});
    final entries = nodes(home['tree'])
        .where((node) => node['type'] == 'listTile')
        .toList();
    expect(entries.map((node) => object(node['event'])['type']), [
      'chooseSchool',
      'chooseGeneral',
      'customScript',
      'json',
      'openAbout',
    ]);
    expect(
      nodes(home['tree']).where((node) => node['type'] == 'input'),
      isEmpty,
    );
    final chosen = await render({
      'event': {'type': 'chooseSchool'},
    });
    expect(object(chosen['state'])['view'], 'schools');
    final searched = await render({
      'state': chosen['state'],
      'event': {'type': 'searchSchool'},
      'formValues': {'schoolSearch': 'AUFE'},
    });
    final rows = nodes(searched['tree'])
        .where(
          (node) =>
              node['type'] == 'listTile' &&
              object(node['event'])['type'] == 'selectSchool',
        )
        .toList();
    expect(rows, hasLength(1));
    expect(rows.single['title'], '安徽财经大学');
    expect(rows.single['subtitle'], contains('2'));
    expect(rows.single['subtitle'], isNot(contains('进入教务系统')));
    expect(rows.single['subtitle'], isNot(contains('非本校开发者')));
    final detailed = await render({
      'state': searched['state'],
      'event': rows.single['event'],
    });
    final state = object(detailed['state']);
    expect(state['view'], 'detail');
    final detailNodes = nodes(detailed['tree']).toList();
    final variants = detailNodes
        .where(
          (node) =>
              node['type'] == 'listTile' &&
              object(node['event'])['type'] == 'selectSchool',
        )
        .toList();
    expect(variants.map((node) => object(node['event'])['id']).toSet(), {
      'AUFE_01',
      'AUFE_02',
    });
    expect(
      detailNodes
          .where((node) => node['type'] == 'richText')
          .map((node) => node['text'])
          .join('\n'),
      contains('resources/AUFE/aufe_01.js'),
    );
    expect(
      detailNodes.map((node) => node['text']).whereType<String>().join('\n'),
      contains('星河欲转'),
    );
    final switched = await render({
      'state': state,
      'event': {'type': 'selectSchool', 'id': 'AUFE_02'},
    });
    expect(object(switched['replaceForms'])['url'], 'http://vpn.aufe.edu.cn');
    final retained = {
      'draft': await convert(payload()),
      'mode': 'new',
      'choices': <String, Object?>{},
    };
    final returned = await render({
      'state': {...object(switched['state']), 'input': retained},
      'event': {'type': 'goHome'},
    });
    expect(object(returned['state'])['view'], 'home');
    expect(object(returned['state'])['input'], retained);
    expect(await store.query(schedule, 'courses', {}), isEmpty);
  });
  test('generic systems are separate from school search and about preserves upstream attribution', () async {
    Future<Map<String, Object?>> render(Map<String, Object?> args) async =>
        object(await host.invokePage(adapter.moduleId, 'render', args));
    final generic = await render({
      'event': {'type': 'chooseGeneral'},
    });
    expect(object(generic['state'])['view'], 'general');
    final genericRows = nodes(generic['tree'])
        .where(
          (node) =>
              node['type'] == 'listTile' &&
              object(node['event'])['type'] == 'selectSchool',
        )
        .toList();
    expect(genericRows, hasLength(4));
    final genericIds = genericRows
        .map((node) => object(node['event'])['id'])
        .toSet();
    final metadata = <Map<String, Object?>>[];
    for (var page = 0; page < ((await schools())['pages'] as int); page++) {
      metadata.addAll(objects((await schools(page: page))['items']));
    }
    expect(
      genericIds,
      metadata
          .where((item) => item['category'] == 'GENERAL_TOOL')
          .map((item) => item['id'])
          .toSet(),
    );
    final schoolsPage = await render({
      'event': {'type': 'chooseSchool'},
    });
    expect(
      nodes(schoolsPage['tree'])
          .where((node) => node['type'] == 'listTile' && node['event'] is Map)
          .map((node) => object(node['event'])['id']),
      isNot(anyElement(isIn(genericIds))),
    );
    final none = await render({
      'state': schoolsPage['state'],
      'event': {'type': 'searchSchool'},
      'formValues': {'schoolSearch': 'school-does-not-exist-xyz'},
    });
    expect(
      nodes(none['tree']).where(
        (node) =>
            node['event'] is Map &&
            object(node['event'])['type'] == 'chooseGeneral',
      ),
      isNotEmpty,
    );
    final about = await render({
      'event': {'type': 'openAbout'},
    });
    expect(object(about['state'])['view'], 'about');
    final selectable = nodes(about['tree'])
        .where((node) => node['type'] == 'richText')
        .map((node) => '${node['text']}')
        .join('\n');
    expect(
      selectable,
      contains('https://github.com/ShiGuangSchedule/shiguang_warehouse'),
    );
    expect(
      selectable,
      contains('https://github.com/ShiGuangSchedule/shiguangschedule'),
    );
    expect(selectable, contains('Permission is hereby granted'));
    expect(selectable, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
    expect(await store.query(schedule, 'timetables', {}), isEmpty);
  });
  test('selected school browser capture requires configuration and source changes discard old drafts', () async {
    final school = objects((await schools(search: 'AUFE WebVPN'))['items'])
        .single;
    final selected = object(
      await host.invokePage(adapter.moduleId, 'render', {
        'event': {'type': 'selectSchool', 'id': school['id']},
      }),
    );
    host.interaction = (_, method, args) async {
      if (method == 'browser.capture') {
        expect(args['url'], school['url']);
        return payload();
      }
      expect(method, 'ui.dialog');
      return args['title'] == '选择导入目标' ? {'target': 'new'} : null;
    };
    final canceled = object(
      await host.invokePage(adapter.moduleId, 'render', {
        'state': selected['state'],
        'event': {'type': 'browser'},
      }),
    );
    expect(object(canceled['state'])['input'], isNull);
    expect(await store.query(schedule, 'timetables', {}), isEmpty);
    host.interaction = (_, method, args) async {
      if (method == 'browser.capture') return payload();
      expect(method, 'ui.dialog');
      return args['title'] == '选择导入目标'
          ? {'target': 'new'}
          : {
              ...options,
              'timezone': 'Asia/Shanghai',
              'displayWeekStart': '1',
              'complete': false,
            };
    };
    final configured = object(
      await host.invokePage(adapter.moduleId, 'render', {
        'state': selected['state'],
        'event': {'type': 'browser'},
      }),
    );
    expect(
      object(object(object(configured['state'])['input'])['draft'])['courses'],
      hasLength(1),
    );
    expect(await store.query(schedule, 'courses', {}), isEmpty);
    final stale = {
      ...object(configured['state']),
      'plan': {'planId': 'old-preview'},
    };
    final reset = object(
      await host.invokePage(adapter.moduleId, 'render', {
        'state': stale,
        'event': {'type': 'defaultScript'},
      }),
    );
    final resetState = object(reset['state']);
    for (final field in ['adapterId', 'input', 'plan', 'options']) {
      expect(resetState[field], isNull);
    }
    host.interaction = (_, method, _) async {
      expect(method, 'ui.dialog');
      return {'script': 'window.shiguangBridge.notifyTaskCompletion();'};
    };
    final custom = object(
      await host.invokePage(adapter.moduleId, 'render', {
        'state': stale,
        'event': {'type': 'customScript'},
      }),
    );
    final customState = object(custom['state']);
    expect(
      customState['script'],
      'window.shiguangBridge.notifyTaskCompletion();',
    );
    for (final field in ['adapterId', 'input', 'plan', 'options']) {
      expect(customState[field], isNull);
    }
    expect(await store.query(schedule, 'courses', {}), isEmpty);
  });
  test('conversion normalizes numeric strings and exact custom times without shifting courses', () async {
    final converted = await convert({
      'courses': [
        {
          'name': '时间匹配课程',
          'day': '7',
          'startSection': '1',
          'endSection': '2',
          'weeks': ['3', '1', '3'],
          'isCustomTime': true,
          'customStartTime': '8:00:00',
          'customEndTime': '09:35',
        },
      ],
      'timeSlots': [
        {'number': '1', 'startTime': '8:00:00', 'endTime': '08:45'},
        {'number': '2', 'startTime': '8:50', 'endTime': '9:35:00'},
      ],
    });
    expect(objects(object(converted['timetable'])['periods']), [
      {'number': 1, 'start': '08:00', 'end': '08:45'},
      {'number': 2, 'start': '08:50', 'end': '09:35'},
    ]);
    final meeting = objects(converted['meetings']).single;
    expect(meeting['weekday'], 7);
    expect(meeting['startPeriod'], 1);
    expect(meeting['endPeriod'], 2);
    expect(meeting['weeks'], [1, 3]);
    expect(converted['warnings'], contains(contains('自定义上课时刻')));
    final strings = payload();
    strings['courses'] = [
      {
        ...objects(strings['courses']).single,
        'day': '2',
        'startSection': '1',
        'endSection': '2',
        'weeks': ['1', '3'],
      },
    ];
    expect(objects((await convert(strings))['meetings']).single['weekday'], 2);
    final unmatched = {
      'courses': [
        {
          'name': '无法映射',
          'day': 1,
          'weeks': [1],
          'isCustomTime': true,
          'customStartTime': '08:01',
          'customEndTime': '09:35',
        },
      ],
      'timeSlots': payload()['timeSlots'],
    };
    await expectLater(
      convert(unmatched),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'error',
          contains('无法准确对应'),
        ),
      ),
    );
    final invalid = payload();
    invalid['timeSlots'] = [
      {'number': 1, 'startTime': '8:00:01', 'endTime': '08:45'},
      objects(payload()['timeSlots'])[1],
    ];
    await expectLater(convert(invalid), throwsStateError);
    expect(await store.query(schedule, 'courses', {}), isEmpty);
  });
  test('real QuickJS conversion stages a provider-confirmed import, preserves source identity', () async {
    final draft = await convert(payload());
    final plan = await host.prepare(adapter, importRef, {
      'draft': draft,
      'mode': 'new',
    });
    expect(await store.query(schedule, 'courses', {}), isEmpty);
    host.review(plan.id, adapter);
    await expectLater(host.commit(adapter, plan.id), throwsStateError);
    final tid = await providerSave(plan);
    expect(tid, isA<String>());
    final courses = await store.query(schedule, 'courses', {});
    expect(object(courses.single)['name'], '数学');
    final sources = await store.query(schedule, 'importSources', {});
    expect(object(sources.single)['callerModuleId'], adapter.moduleId);
    final update = await host.prepare(adapter, importRef, {
      'draft': await convert(payload(weeks: [1, 3, 7])),
      'mode': 'merge',
      'targetTimetableId': tid,
    });
    await providerSave(update);
    expect(await store.query(schedule, 'courses', {}), courses);
    expect(
      object((await store.query(schedule, 'meetings', {})).single)['weeks'],
      [1, 3, 7],
    );
  });
  test(
    'JSON workflow reaches provider preview; cancellation writes nothing',
    () async {
      Map<String, Object?>? navigation;
      host.interaction = (actor, method, args) async {
        if (method == 'files.readText') return jsonEncode(payload());
        if (method == 'ui.dialog') {
          return args['title'] == '选择导入目标'
              ? {'target': 'new'}
              : {
                  ...options,
                  'timezone': 'Asia/Shanghai',
                  'displayWeekStart': '1',
                  'complete': false,
                };
        }
        if (method == 'ui.navigate') {
          navigation = args;
          return true;
        }
        throw StateError(method);
      };
      final loaded = object(
        await host.invokePage(adapter.moduleId, 'render', {
          'event': {'type': 'json'},
        }),
      );
      expect(object(loaded['state'])['error'], isNull);
      final preview = object(
        await host.invokePage(adapter.moduleId, 'render', {
          'state': loaded['state'],
          'event': {'type': 'preview'},
        }),
      );
      expect(object(preview['state'])['error'], isNull);
      expect(navigation?['page'], 'app.schedule.home');
      expect(object(navigation?['context'])['importPlanId'], isA<String>());
      expect(await store.query(schedule, 'courses', {}), isEmpty);
      host.interaction = (_, method, _) async {
        expect(method, 'browser.capture');
        return null;
      };
      final canceled = object(
        await host.invokePage(adapter.moduleId, 'render', {
          'event': {'type': 'browser'},
          'formValues': {'url': 'https://school.example'},
        }),
      );
      expect(object(canceled['state'])['input'], isNull);
      expect(await store.query(schedule, 'timetables', {}), isEmpty);
    },
  );
  test(
    'malformed or unsupported source does not create an import plan',
    () async {
      final unsupported = payload();
      unsupported['comboSchedule'] = {
        'publicSchedules': [{}],
      };
      await expectLater(convert(unsupported), throwsStateError);
      expect(await store.query(schedule, 'courses', {}), isEmpty);
    },
  );
  test('temporary school adapter reuses bridge and hands JSON to reviewed import workflow', () async {
    const fixtureId = 'test.school.adapter';
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': fixtureId,
              'version': '1.0.0',
              'hostApi': '^1.8.0',
              'dataVersion': 1,
              'dependencies': ['app.import.shiguang'],
              'permissions': [
                'ui',
                'browser.capture',
                'services.query:app.import.shiguang/shiguang.bridge.compile@1',
              ],
            },
            'entryPoint': 'main.js',
            'collections': [],
            'services': [],
            'pages': [],
          },
          {
            'main.js': '''
import {services, browser, ui} from '@xudian/sdk';
export async function render({event, formValues={}}) {
  if (event?.type === 'browser') {
    const compiled = await services.query({moduleId:'app.import.shiguang', serviceId:'shiguang.bridge.compile', majorVersion:1}, {script:'/* temporary-school-parser */'});
    const payload = await browser.capture({url:formValues.url, script:compiled.script});
    if (payload) await ui.navigate('app.import.shiguang.home', {shiguangImport:{version:1,payload}});
  }
  return {state:{}, tree:{type:'text',text:'Temporary school adapter'}};
}
''',
          },
        ),
        allowUnsignedLocal: true,
      ),
    );
    final school = host.instances[fixtureId]!.actor;
    Map<String, Object?>? navigation;
    host.interaction = (actor, method, args) async {
      expect(actor, same(school));
      if (method == 'browser.capture') {
        expect(args['url'], 'https://school.example');
        final script = args['script'] as String;
        expect(script, contains('installBridge'));
        expect(script, contains('temporary-school-parser'));
        return payload();
      }
      if (method == 'ui.navigate') {
        navigation = args;
        return true;
      }
      throw StateError(method);
    };
    final captured = object(
      await host.invokePage(school.moduleId, 'render', {
        'event': {'type': 'browser'},
        'formValues': {'url': 'https://school.example'},
      }),
    );
    expect(object(captured['state'])['error'], isNull);
    expect(navigation?['page'], 'app.import.shiguang.home');
    expect(await store.query(schedule, 'courses', {}), isEmpty);
    final context = object(navigation?['context']);
    var dialogs = 0;
    host.interaction = (actor, method, args) async {
      expect(actor, same(adapter));
      if (method == 'ui.dialog') {
        dialogs++;
        return args['title'] == '选择导入目标'
            ? {'target': 'new'}
            : {
                ...options,
                'timezone': 'Asia/Shanghai',
                'displayWeekStart': '1',
                'complete': false,
              };
      }
      if (method == 'ui.navigate') {
        navigation = args;
        return true;
      }
      throw StateError(method);
    };
    final configured = object(
      await host.invokePage(adapter.moduleId, 'render', {'context': context}),
    );
    final state = object(configured['state']);
    expect(state['error'], isNull);
    expect(object(object(state['input'])['draft'])['courses'], hasLength(1));
    await host.invokePage(adapter.moduleId, 'render', {
      'context': context,
      'state': state,
    });
    expect(dialogs, 2, reason: 'Handoff is consumed once even on a rerender');
    final preview = object(
      await host.invokePage(adapter.moduleId, 'render', {
        'context': context,
        'state': state,
        'event': {'type': 'preview'},
      }),
    );
    expect(object(preview['state'])['error'], isNull);
    expect(navigation?['page'], 'app.schedule.home');
    expect(await store.query(schedule, 'courses', {}), isEmpty);
    final planId = object(navigation?['context'])['importPlanId'] as String;
    await providerSave(store.plan(planId, adapter));
    expect(
      object((await store.query(schedule, 'courses', {})).single)['name'],
      '数学',
    );
    // The school parser has no direct conversion/write permission.
    await expectLater(
      host.query(
        school,
        const ServiceRef('app.import.shiguang', 'shiguang.convert', 1),
        {'payload': payload(), 'options': options},
      ),
      throwsStateError,
    );
    await expectLater(host.prepare(school, importRef, {}), throwsStateError);
  });

  test(
    'cancelled or invalid school handoff never stages or saves courses',
    () async {
      var dialogs = 0;
      host.interaction = (_, method, _) async {
        expect(method, 'ui.dialog');
        dialogs++;
        return null;
      };
      final context = {
        'shiguangImport': {'version': 1, 'payload': payload()},
      };
      final canceled = object(
        await host.invokePage(adapter.moduleId, 'render', {'context': context}),
      );
      final state = object(canceled['state']);
      expect(state['input'], isNull);
      await host.invokePage(adapter.moduleId, 'render', {
        'context': context,
        'state': state,
      });
      expect(dialogs, 1);
      final invalid = object(
        await host.invokePage(adapter.moduleId, 'render', {
          'context': {
            'shiguangImport': {'version': 2, 'payload': payload()},
          },
        }),
      );
      expect(object(invalid['state'])['error'], contains('接口无效'));
      expect(await store.query(schedule, 'timetables', {}), isEmpty);
    },
  );
}
