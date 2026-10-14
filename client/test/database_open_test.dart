import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:task_app/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File file;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('database-open-');
    file = File('${directory.path}/xudian_v9.sqlite');
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(paths, null);
    await directory.delete(recursive: true);
  });

  Future<void> legacyFile() async {
    final seed = AppDatabase(NativeDatabase(file));
    await seed.customStatement(
      "INSERT INTO app_settings(key,value) VALUES('backup-probe','original')",
    );
    await seed.close();
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('PRAGMA user_version=1');
    raw.close();
  }

  test(
    'fresh and current files are ready without creating a legacy backup',
    () async {
      for (var i = 0; i < 2; i++) {
        final database = await AppDatabase.open();
        expect(
          (await database.customSelect('PRAGMA user_version').get())
              .single
              .data['user_version'],
          2,
        );
        expect(await database.select(database.projects).get(), isEmpty);
        await database.close();
        expect(
          await File('${file.path}.before-host-v2.sqlite').exists(),
          isFalse,
        );
      }
    },
  );

  test('isolate creates a consistent schema-one backup before migration and never overwrites it', () async {
    await legacyFile();
    final database = await AppDatabase.open();
    expect(
      (await database.customSelect('PRAGMA user_version').get())
          .single
          .data['user_version'],
      2,
    );
    expect(
      (await database
              .customSelect(
                "SELECT value FROM app_settings WHERE key='backup-probe'",
              )
              .get())
          .single
          .data['value'],
      'original',
    );
    await database.close();
    final snapshot = File('${file.path}.before-host-v2.sqlite');
    final bytes = await snapshot.readAsBytes();
    final backup = sqlite.sqlite3.open(snapshot.path);
    expect(backup.select('PRAGMA user_version').single.values.single, 1);
    expect(
      backup
          .select("SELECT value FROM app_settings WHERE key='backup-probe'")
          .single['value'],
      'original',
    );
    backup.close();
    final current = sqlite.sqlite3.open(file.path);
    current.execute(
      "UPDATE app_settings SET value='changed' WHERE key='backup-probe'",
    );
    current.execute('PRAGMA user_version=1');
    current.close();
    final reopened = await AppDatabase.open();
    expect(
      (await reopened
              .customSelect(
                "SELECT value FROM app_settings WHERE key='backup-probe'",
              )
              .get())
          .single
          .data['value'],
      'changed',
    );
    await reopened.close();
    expect(await snapshot.readAsBytes(), bytes);
  });

  test(
    'failed pre-migration backup does not upgrade or alter the original file',
    () async {
      await legacyFile();
      await Directory('${file.path}.before-host-v2.sqlite.candidate').create();
      await expectLater(AppDatabase.open(), throwsException);
      final raw = sqlite.sqlite3.open(file.path);
      expect(raw.select('PRAGMA user_version').single.values.single, 1);
      expect(
        raw
            .select("SELECT value FROM app_settings WHERE key='backup-probe'")
            .single['value'],
        'original',
      );
      raw.close();
      expect(
        await File('${file.path}.before-host-v2.sqlite').exists(),
        isFalse,
      );
    },
  );
}
