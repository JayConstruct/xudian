import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

Future<ScriptPackage> timezoneSourcePackage(String id) async {
  final directory = Directory('../packages/modules/$id');
  final files = <String, String>{};
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.js')) {
      files[entity.path.substring(directory.path.length + 1)] = await entity
          .readAsString();
    }
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${directory.path}/module.json').readAsString()),
      ),
      files,
    ),
    allowUnsignedLocal: true,
  );
}

Iterable<Map<String, Object?>> timezoneNodes(Object? value) sync* {
  if (value is Map) {
    yield object(value);
    for (final child in value.values) {
      yield* timezoneNodes(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* timezoneNodes(child);
    }
  }
}

Map<String, Object?> timezoneTable({String zone = 'Asia/Shanghai'}) => {
  'id': 'table',
  'name': '原课表',
  'firstMonday': '2026-03-02',
  'totalWeeks': 20,
  'timezone': zone,
  'displayWeekStart': 1,
  'periods': [
    {'number': 1, 'start': '01:30', 'end': '03:30'},
  ],
};

Map<String, Object?> timezonePayload({String? zone}) => {
  'config': {'semesterStartDate': '2026-03-02', 'timezone': ?zone},
  'courses': [
    {
      'name': '数学',
      'day': 1,
      'startSection': 1,
      'endSection': 1,
      'weeks': [1],
    },
  ],
  'timeSlots': [
    {'number': 1, 'startTime': '08:00', 'endTime': '08:45'},
  ],
};

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late ModuleActor schedule, importer;
  String? systemZone;
  final dialogs = <Map<String, Object?>>[];
  var reviews = 0;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('schedule-zone-');
    systemZone = 'America/New_York';
    host = ModuleHost(
      store: store,
      directory: directory,
      systemTimezoneResolver: () async => systemZone,
    );
    host.clockNow = () => DateTime.utc(2026, 3, 9, 1);
    await host.initialize();
    for (final id in ['app.schedule', 'app.import.shiguang']) {
      await host.install(await timezoneSourcePackage(id));
    }
    schedule = host.instances['app.schedule']!.actor;
    importer = host.instances['app.import.shiguang']!.actor;
    dialogs.clear();
    reviews = 0;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<Object?> command(String id, Map<String, Object?> input) async {
    final plan = await host.prepare(
      schedule,
      ServiceRef('app.schedule', id, 1),
      input,
    );
    host.review(plan.id, schedule);
    return host.commit(schedule, plan.id);
  }

  Future<Map<String, Object?>> renderSchedule(
    String page, {
    Object? state,
    Object? event,
    Map<String, Object?> context = const {},
  }) async => object(
    await host.invokePage('app.schedule', 'render', {
      'context': {'pageId': 'app.schedule.$page', ...context},
      'state': state ?? {},
      'event': event,
    }),
  );
  void mockDialogs({String target = 'new', String? backup}) {
    host.interaction = (actor, method, args) async {
      if (method == 'ui.review') {
        reviews++;
        return true;
      }
      if (method == 'ui.navigate') return true;
      if (method == 'files.readText') return backup;
      expect(method, 'ui.dialog');
      dialogs.add(args);
      if (args['title'] == '选择导入目标') return {'target': target};
      return {
        for (final raw in args['fields'] as List)
          object(raw)['key'] as String: object(raw)['key'] == 'scope'
              ? 'school/student/2026-spring'
              : object(raw)['value'],
      };
    };
  }

  Future<Map<String, Object?>> configureImport({String? sourceZone}) async {
    final rendered = object(
      await host.invokePage(importer.moduleId, 'render', {
        'context': {
          'shiguangImport': {
            'version': 1,
            'payload': timezonePayload(zone: sourceZone),
          },
        },
      }),
    );
    expect(object(rendered['state'])['error'], isNull);
    return object(rendered['state']);
  }

  Future<String> saveImporterInput(Object? input) async {
    final plan = await host.prepare(
      importer,
      const ServiceRef('app.schedule', 'schedule.import.prepare', 1),
      input,
    );
    final preview = await renderSchedule(
      'imports',
      context: {'importPlanId': plan.id},
    );
    expect(await store.query(schedule, 'courses', {}), isEmpty);
    final saved = await renderSchedule(
      'imports',
      context: {'importPlanId': plan.id},
      state: preview['state'],
      event: {'type': 'confirmAdapter'},
    );
    return object(saved['state'])['timetableId'] as String;
  }

  test('new timetable has no timezone form field and stores the current device zone', () async {
    mockDialogs();
    await renderSchedule('timetables', event: {'type': 'newTimetable'});
    expect(dialogs.single['title'], '新建课表');
    expect(
      (dialogs.single['fields'] as List).map((f) => object(f)['key']),
      isNot(contains('timezone')),
    );
    final created = object(
      (await store.query(schedule, 'timetables', {})).single,
    );
    expect(created['timezone'], 'America/New_York');
    expect(
      created['firstMonday'],
      '2026-03-02',
      reason: 'Defaults use the Sunday in New York, not Monday in UTC.',
    );
    systemZone = 'Asia/Tokyo';
    await renderSchedule('semester', context: {'timetableId': created['id']});
    await renderSchedule(
      'timetables',
      context: {'timetableId': created['id']},
      event: {'type': 'settings'},
    );
    expect(
      object(
        await store.get(schedule, 'timetables', created['id'] as String),
      )['timezone'],
      'America/New_York',
    );
    expect(
      (dialogs.last['fields'] as List).map((f) => object(f)['key']),
      isNot(contains('timezone')),
    );
    final withoutZone = {...created, 'name': '改名'}..remove('timezone');
    await command('schedule.timetable.save', {
      'timetable': withoutZone,
      'expectedTimetable': created,
    });
    expect(
      object(
        await store.get(schedule, 'timetables', created['id'] as String),
      )['timezone'],
      'America/New_York',
    );
    await command('schedule.timetable.save', {
      'timetable': {...withoutZone, 'id': 'new-api'},
    });
    expect(
      object(await store.get(schedule, 'timetables', 'new-api'))['timezone'],
      'Asia/Tokyo',
    );
  });

  test(
    'demo uses device zone once and remains unchanged after travel',
    () async {
      final saved = object(await command('schedule.demo.create', {}));
      expect(saved['timezone'], 'America/New_York');
      final before = await store.query(schedule, 'timetables', {});
      systemZone = 'Australia/Sydney';
      final repeated = object(await command('schedule.demo.create', {}));
      expect(repeated['alreadyExists'], true);
      expect(await store.query(schedule, 'timetables', {}), before);
    },
  );

  test(
    'advanced timezone remains a reviewed draft and busy periods honor DST',
    () async {
      await command('schedule.timetable.save', {'timetable': timezoneTable()});
      mockDialogs();
      var page = await renderSchedule(
        'semester',
        context: {'timetableId': 'table'},
      );
      expect(
        timezoneNodes(page['tree'])
            .where((node) => node['key'] == 'semester.table.timezone'),
        isEmpty,
      );
      page = await renderSchedule(
        'semester',
        state: page['state'],
        event: {'type': 'toggleTimezone'},
      );
      expect(
        timezoneNodes(page['tree']).singleWhere(
          (node) => node['key'] == 'semester.table.timezone',
        )['value'],
        'Asia/Shanghai',
      );
      page = await renderSchedule(
        'semester',
        state: page['state'],
        event: {
          'type': 'semesterField',
          'field': 'timezone',
          'value': 'America/New_York',
        },
      );
      expect(
        object(await store.get(schedule, 'timetables', 'table'))['timezone'],
        'Asia/Shanghai',
      );
      expect(reviews, 0);
      systemZone = 'Europe/Paris';
      page = await renderSchedule(
        'semester',
        state: page['state'],
        event: {'type': 'toggleTimezone'},
      );
      expect(
        object(
          object(object(page['state'])['semesterDraft'])['values'],
        )['timezone'],
        'America/New_York',
      );
      await renderSchedule(
        'semester',
        state: page['state'],
        event: {'type': 'saveSemester'},
      );
      expect(reviews, 1);
      expect(
        object(await store.get(schedule, 'timetables', 'table'))['timezone'],
        'America/New_York',
      );
      await command('schedule.course.save', {
        'course': {'id': 'course', 'timetableId': 'table', 'name': '跨夏令时课程'},
        'meeting': {
          'id': 'meeting',
          'timetableId': 'table',
          'weekday': 7,
          'startPeriod': 1,
          'endPeriod': 1,
          'weeks': [1],
        },
      });
      final busy = object(
        await host.query(
          schedule,
          const ServiceRef('app.schedule', 'schedule.query.busy', 1),
          {'startDate': '2026-03-08', 'endDate': '2026-03-08'},
        ),
      );
      final item = object((busy['items'] as List).single);
      expect(item['timezone'], 'America/New_York');
      expect(
        DateTime.parse(item['startAt'] as String),
        DateTime.utc(2026, 3, 8, 6, 30),
      );
      expect(
        DateTime.parse(item['endAt'] as String),
        DateTime.utc(2026, 3, 8, 7, 30),
      );
    },
  );

  test('advanced timezone validation and concurrent edits retain the draft without saving', () async {
    await command('schedule.timetable.save', {'timetable': timezoneTable()});
    mockDialogs();
    var page = await renderSchedule(
      'semester',
      context: {'timetableId': 'table'},
    );
    page = await renderSchedule(
      'semester',
      state: page['state'],
      event: {
        'type': 'semesterField',
        'field': 'timezone',
        'value': 'Mars/Invalid',
      },
    );
    page = await renderSchedule(
      'semester',
      state: page['state'],
      event: {'type': 'saveSemester'},
    );
    expect(object(object(page['state'])['semesterDraft'])['error'], isNotNull);
    expect(reviews, 0);
    expect(
      object(await store.get(schedule, 'timetables', 'table'))['timezone'],
      'Asia/Shanghai',
    );
    page = await renderSchedule(
      'semester',
      state: page['state'],
      event: {
        'type': 'semesterField',
        'field': 'timezone',
        'value': 'America/New_York',
      },
    );
    final original = object(await store.get(schedule, 'timetables', 'table'));
    await command('schedule.timetable.save', {
      'timetable': {...original, 'name': '其他页面改名'},
      'expectedTimetable': original,
    });
    page = await renderSchedule(
      'semester',
      state: page['state'],
      event: {'type': 'saveSemester'},
    );
    expect(
      object(object(page['state'])['semesterDraft'])['error'],
      contains('其他页面修改'),
    );
    expect(reviews, 0);
    expect(
      object(
        object(object(page['state'])['semesterDraft'])['values'],
      )['timezone'],
      'America/New_York',
    );
    expect(
      object(await store.get(schedule, 'timetables', 'table'))['timezone'],
      'Asia/Shanghai',
    );
  });

  test('Shiguang new import hides timezone and stores the device zone after review', () async {
    mockDialogs();
    final state = await configureImport();
    expect(dialogs, hasLength(1));
    expect(dialogs.single['title'], '确认学期配置');
    expect(
      (dialogs.last['fields'] as List).map((f) => object(f)['key']),
      isNot(contains('timezone')),
    );
    expect(
      object(object(object(state['input'])['draft'])['timetable'])['timezone'],
      'America/New_York',
    );
    expect(await store.query(schedule, 'timetables', {}), isEmpty);
    final tid = await saveImporterInput(state['input']);
    expect(reviews, 1);
    expect(
      object(await store.get(schedule, 'timetables', tid))['timezone'],
      'America/New_York',
    );
    systemZone = 'Asia/Tokyo';
    mockDialogs(target: tid);
    final existing = await configureImport(sourceZone: 'Europe/Paris');
    expect(
      dialogs.skip(1).map((dialog) => dialog['title']),
      ['选择导入目标', '确认学期配置'],
    );
    final input = object(existing['input']);
    expect(input['mode'], 'merge');
    expect(
      object(object(input['draft'])['timetable'])['timezone'],
      'America/New_York',
    );
    await command('schedule.import.prepare', input);
    expect(
      object(await store.get(schedule, 'timetables', tid))['timezone'],
      'America/New_York',
    );
  });

  test(
    'source timezone survives Shiguang conversion and configuration',
    () async {
      mockDialogs();
      final state = await configureImport(sourceZone: 'Europe/Paris');
      expect(
        object(
          object(object(state['input'])['draft'])['timetable'],
        )['timezone'],
        'Europe/Paris',
      );
      final tid = await saveImporterInput(state['input']);
      expect(
        object(await store.get(schedule, 'timetables', tid))['timezone'],
        'Europe/Paris',
      );
      final converted = object(
        await host.query(
          importer,
          const ServiceRef('app.import.shiguang', 'shiguang.convert', 1),
          {
            'payload': timezonePayload(zone: 'Asia/Tokyo'),
            'options': {
              'name': '备份来源',
              'scope': 'source/config',
              'firstMonday': '2026-03-02',
            },
          },
        ),
      );
      expect(object(converted['timetable'])['timezone'], 'Asia/Tokyo');
    },
  );

  test(
    'busy periods reject nonexistent and ambiguous local DST boundaries',
    () async {
      for (final (id, monday, date, start, end) in [
        ('gap', '2026-03-02', '2026-03-08', '02:15', '03:45'),
        ('fold', '2026-10-26', '2026-11-01', '01:15', '01:45'),
      ]) {
        await command('schedule.timetable.save', {
          'timetable': {
            ...timezoneTable(zone: 'America/New_York'),
            'id': id,
            'firstMonday': monday,
            'periods': [
              {'number': 1, 'start': start, 'end': end},
            ],
          },
        });
        await command('schedule.course.save', {
          'course': {'id': '$id-course', 'timetableId': id, 'name': '夏令时课程'},
          'meeting': {
            'id': '$id-meeting',
            'timetableId': id,
            'weekday': 7,
            'startPeriod': 1,
            'endPeriod': 1,
            'weeks': [1],
          },
        });
        await expectLater(
          host.query(
            schedule,
            const ServiceRef('app.schedule', 'schedule.query.busy', 1),
            {'startDate': date, 'endDate': date},
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains('夏令时'),
            ),
          ),
        );
      }
    },
  );

  test(
    'JSON backup export and import preserve an explicit zone after travel',
    () async {
      await command('schedule.timetable.save', {
        'timetable': timezoneTable(zone: 'Europe/Paris'),
      });
      final backup = object(
        await host.query(
          schedule,
          const ServiceRef('app.schedule', 'schedule.backup.export', 1),
          {'timetableId': 'table'},
        ),
      );
      expect(object(backup['timetable'])['timezone'], 'Europe/Paris');
      systemZone = 'Asia/Tokyo';
      mockDialogs(backup: jsonEncode(backup));
      var page = await renderSchedule('imports', event: {'type': 'import'});
      expect(
        object(
          object(object(page['state'])['importDraft'])['timetable'],
        )['timezone'],
        'Europe/Paris',
      );
      host.interaction = (_, method, args) async =>
          method == 'ui.dialog' ? {'mode': 'new'} : true;
      page = await renderSchedule(
        'imports',
        state: page['state'],
        event: {'type': 'previewImport'},
      );
      await renderSchedule(
        'imports',
        state: page['state'],
        event: {'type': 'confirmImport'},
      );
      final tables = await store.query(schedule, 'timetables', {});
      expect(tables, hasLength(2));
      expect(tables.map((table) => object(table)['timezone']).toSet(), {
        'Europe/Paris',
      });
    },
  );

  test(
    'fallback is visible for created timetables and Shiguang import drafts',
    () async {
      systemZone = null;
      mockDialogs();
      final page = await renderSchedule(
        'timetables',
        event: {'type': 'newTimetable'},
      );
      expect(object(page['state'])['notice'], contains('设备时区未能获取'));
      expect(
        object(
          (await store.query(schedule, 'timetables', {})).single,
        )['timezone'],
        'Asia/Shanghai',
      );
      final state = await configureImport();
      expect(state['timezoneNotice'], contains('当前使用 Asia/Shanghai'));
      expect(
        object(object(state['input'])['draft'])['warnings'],
        contains('设备时区未能获取，当前使用 Asia/Shanghai'),
      );
    },
  );
}
