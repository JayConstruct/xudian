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
  test('independent parser module reuses bridge and hands JSON to reviewed import workflow', () async {
    await host.install(
      await ScriptPackage.verify(
        await File('../dist/modules/app.import.zhengfang.xmodule')
            .readAsBytes(),
        allowUnsignedLocal: true,
      ),
    );
    final school = host.instances['app.import.zhengfang']!.actor;
    Map<String, Object?>? navigation;
    host.interaction = (actor, method, args) async {
      expect(actor, same(school));
      if (method == 'browser.capture') {
        expect(args['url'], 'https://school.example');
        final script = args['script'] as String;
        expect(script, contains('installBridge'));
        expect(script, contains('kbgrid_table_0'));
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
