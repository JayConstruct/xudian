import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/platform/json_file_saver.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/settings/configuration_export.dart';
import 'package:task_app/features/settings/configuration_export_page.dart';

class _Secrets extends FlutterSecureStorage {
  int reads = 0;
  bool fail = false;

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    if (fail) throw StateError('private secret storage error');
    return {
      'xudian.ai.apiKey': 'legacy-secret',
      'xudian.module.app.ai.test': 'module-secret',
      'unrelated': 'other-secret',
    };
  }
}

class _Saver extends JsonFileSaver {
  bool saved = false;
  bool fail = false;
  String? text;
  Completer<bool>? pending;

  @override
  Future<bool> save({required String name, required String text}) async {
    expect(name, startsWith('xudian-config-'));
    expect(name, endsWith('.json'));
    this.text = text;
    if (fail) throw StateError('private file path');
    return pending?.future ?? saved;
  }
}

void main() {
  late AppDatabase db;
  late _Secrets secrets;
  late ConfigurationExporter exporter;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    secrets = _Secrets();
    exporter = ConfigurationExporter(db, secureStorage: secrets);
  });
  tearDown(() => db.close());

  Future<void> setting(String key, String value) => db.customStatement(
    'INSERT INTO app_settings(key,value) VALUES(?,?)',
    [key, value],
  );

  Future<void> record(
    String module,
    String collection,
    String id, {
    String space = 'current',
    bool deleted = false,
    bool configuration = false,
  }) async {
    await db.customStatement(
      'INSERT OR IGNORE INTO host_collections(module_id,space,name,definition) VALUES(?,?,?,?)',
      [
        module,
        space,
        collection,
        jsonEncode({'id': collection, 'configuration': configuration}),
      ],
    );
    await db.customStatement('INSERT INTO host_records VALUES(?,?,?,?,?,1,?)', [
      module,
      space,
      collection,
      id,
      jsonEncode({'id': id}),
      deleted ? 1 : 0,
    ]);
  }

  test(
    'snapshot includes defaults without reading or writing secure storage',
    () async {
      secrets.fail = true;
      final result = await exporter.capture(now: DateTime.utc(2026, 10, 18));
      expect(result['format'], 'xudian.configuration');
      expect(result['exportedAt'], '2026-10-18T00:00:00.000Z');
      expect(result['includesSecrets'], false);
      expect(result.containsKey('secrets'), false);
      expect((result['appSettings'] as Map)['ui.preferences'], {
        'theme': 'system',
        'reduceMotion': false,
        'haptics': true,
      });
      expect(secrets.reads, 0);
      expect(await db.select(db.appSettings).get(), isEmpty);
    },
  );

  test('captures saved preferences, disabled modules and current configuration only', () async {
    await setting('ui.preferences', '{"theme":"dark","haptics":false}');
    await setting('ai.model', '123');
    await setting('device_id', 'private-device');
    await setting('operation_counter', '7');
    await setting('ai.assistant.history', 'private-history');
    for (final module in [
      'app.ai',
      'app.planner',
      'app.schedule',
      'app.tasks',
      'third.party',
    ]) {
      await db.customStatement(
        'INSERT INTO host_installations VALUES(?,?,?,1,1,0,1,NULL)',
        [module, '1.0.0', 'current'],
      );
    }
    await db.customStatement(
      'INSERT INTO host_packages VALUES(?,?,?,?,?,?,?)',
      [
        'app.ai',
        '1.0.0',
        'abc123',
        'local',
        '{}',
        '{"manifest":{"id":"app.ai","permissions":["secrets"]}}',
        '2026-10-18',
      ],
    );
    await db.customStatement('INSERT INTO host_ui_preferences VALUES(?,?,?)', [
      'third.party',
      'display',
      '{"expanded":true}',
    ]);
    for (final pair in [
      ['module-catalog-repository', 'author/catalog'],
      ['module-repository:app.ai', 'author/modules'],
      ['credential:handle', '{"alias":"xudian.ai.apiKey","moduleId":"app.ai"}'],
      ['defaults-v3', 'private-migration-marker'],
    ]) {
      await db.customStatement('INSERT INTO host_meta VALUES(?,?)', pair);
    }
    await record('app.ai', 'connections', 'connection', configuration: true);
    await record('app.ai', 'history', 'private-chat');
    await record('app.ai', 'connections', 'old', space: 'snapshot');
    await record('app.ai', 'connections', 'deleted', deleted: true);
    await record('app.planner', 'settings', 'planner', configuration: true);
    await record('app.planner', 'rules', 'rule', configuration: true);
    await record('app.planner', 'occurrences', 'private-occurrence');
    await record('app.schedule', 'timetables', 'semester', configuration: true);
    await record('app.schedule', 'courses', 'private-course');
    await record('app.tasks', 'tasks', 'private-task');
    await record('third.party', 'customOptions', 'custom', configuration: true);
    final before = await db
        .customSelect('SELECT count(*) AS n FROM host_records')
        .getSingle();
    final result = await exporter.capture(annotationEnabled: true);
    final settings = result['appSettings'] as Map;
    expect(settings['ui.preferences'], {'theme': 'dark', 'haptics': false});
    expect(settings['ai.model'], '123');
    expect(settings.containsKey('device_id'), false);
    expect(settings.containsKey('operation_counter'), false);
    final modules = result['modules'] as List;
    expect(modules.first['enabled'], false);
    expect(modules.first['sha256'], 'abc123');
    expect(modules.first['manifest']['permissions'], ['secrets']);
    expect(
      (result['hostSettings'] as Map).keys,
      contains('module-repository:app.ai'),
    );
    expect((result['moduleConfiguration'] as List).map((v) => v['id']), [
      'connection',
      'rule',
      'planner',
      'semester',
      'custom',
    ]);
    expect((result['moduleUiPreferences'] as List).single['value'], {
      'expanded': true,
    });
    expect(result['session'], {'uiAnnotationEnabled': true});
    final encoded = jsonEncode(result);
    for (final excluded in [
      'private-history',
      'private-chat',
      'private-task',
      'private-course',
      'private-device',
      'private-migration-marker',
      'private-occurrence',
    ]) {
      expect(encoded, isNot(contains(excluded)));
    }
    final after = await db
        .customSelect('SELECT count(*) AS n FROM host_records')
        .getSingle();
    expect(after.data, before.data);
    expect(secrets.reads, 0);
  });

  test(
    'keys are opt in and secure-storage failures abort the export',
    () async {
      final result = await exporter.capture(includeSecrets: true);
      expect(result['secrets'], {
        'xudian.ai.apiKey': 'legacy-secret',
        'xudian.module.app.ai.test': 'module-secret',
      });
      secrets.fail = true;
      await expectLater(
        exporter.capture(includeSecrets: true),
        throwsStateError,
      );
    },
  );

  for (final wide in [false, true]) {
    testWidgets(
      'export cancellation, failure and retry at ${wide ? 'desktop' : 'narrow large text'}',
      (tester) async {
        tester.view.physicalSize = wide
            ? const Size(1200, 900)
            : const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = wide ? 1 : 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final saver = _Saver();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              configurationExporterProvider.overrideWith((_) async => exporter),
              configurationFileSaverProvider.overrideWith((_) => saver),
            ],
            child: const MaterialApp(home: ConfigurationExportPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          false,
        );
        Future<void> tapExport() async {
          await tester.scrollUntilVisible(
            find.text('选择位置并导出'),
            180,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.ensureVisible(find.text('选择位置并导出'));
          await tester.tap(find.text('选择位置并导出'));
          await tester.pumpAndSettle();
        }

        await tapExport();
        expect(find.text('已取消导出'), findsOneWidget);
        expect((jsonDecode(saver.text!) as Map).containsKey('secrets'), false);
        saver.fail = true;
        await tapExport();
        expect(find.text('配置导出失败，请重试'), findsWidgets);
        expect(find.textContaining('private file path'), findsNothing);
        saver.fail = false;
        saver.saved = true;
        await tapExport();
        expect(find.text('配置已导出到所选位置'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'oversized UTF-8 configuration is rejected before opening a picker',
    () async {
      await expectLater(
        JsonFileSaver().save(name: 'large.json', text: '中' * 700000),
        throwsFormatException,
      );
    },
  );
}
