import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

List<Map<String, Object?>> records(Object? value) =>
    (value as List).map((v) => object(v)).toList();

void main() {
  test(
    'packaged task views paginate filtered records and preserve today rules',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = CollectionStore(db);
      final folder = await Directory.systemTemp.createTemp('task-view-pages-');
      final host = ModuleHost(store: store, directory: folder);
      host.clockNow = () => DateTime.utc(2026, 10, 8, 12);
      addTearDown(() async {
        await host.close();
        await store.close();
        await db.close();
        await folder.delete(recursive: true);
      });
      await host.initialize();
      for (final id in ['app.tasks', 'app.views.today']) {
        await host.install(
          await ScriptPackage.verify(
            await File('../dist/modules/$id.xmodule').readAsBytes(),
            allowUnsignedLocal: true,
          ),
        );
      }
      final actor = host.instances['app.tasks']!.actor;
      await db.transaction(() async {
        for (var i = 0; i < 67; i++) {
          final id = 'task-${i.toString().padLeft(3, '0')}';
          final value = {
            'id': id,
            'title': '任务 $i',
            'priority': 0,
            'createdAt': id,
            'dueDate': i < 65 && i != 1 ? '2026-10-07' : null,
            'plannedDate': i == 1
                ? '2026-10-08'
                : i == 66
                ? '2026-10-09'
                : null,
            'completedAt': i == 61 ? 'completed' : null,
            'archivedAt': i == 62 ? 'archived' : null,
            'deletedAt': i == 63 ? 'deleted' : null,
            'parentTaskId': i == 64 ? 'task-000' : null,
          };
          await db.customStatement(
            'INSERT INTO host_records(module_id,space,collection,id,value,revision,deleted) VALUES(?,?,?,?,?,1,0)',
            [actor.moduleId, actor.space, 'tasks', id, jsonEncode(value)],
          );
        }
      });
      final today = await host.query(
        actor,
        const ServiceRef('app.tasks', 'task.list', 1),
        {'view': 'today', 'today': '2026-10-08', 'limit': 50},
      );
      expect(records(today), hasLength(50));
      expect(records(today).take(2).map((v) => v['id']), [
        'task-000',
        'task-001',
      ], reason: 'Today includes overdue tasks and tasks planned for today');

      var page = object(
        await host.invokePage('app.views.today', 'render', {'state': {}}),
      );
      List<Map<String, Object?>> items() =>
          records(object(object(page['tree'])['slots'])['items']);
      final firstIds = items()
          .where((v) => v['type'] == 'card')
          .map((v) => v['key'])
          .toList();
      expect(firstIds, hasLength(50));
      expect(items().where((v) => v['text'] == '加载更多任务'), hasLength(1));
      page = object(
        await host.invokePage('app.views.today', 'render', {
          'state': page['state'],
          'event': {'type': 'moreTasks'},
        }),
      );
      final ids = items()
          .where((v) => v['type'] == 'card')
          .map((v) => v['key'])
          .toList();
      expect(ids, hasLength(61));
      expect(ids.toSet(), hasLength(61));
      expect(
        ids,
        isNot(
          anyElement(
            isIn([
              'task-061',
              'task-062',
              'task-063',
              'task-064',
              'task-065',
              'task-066',
            ]),
          ),
        ),
        reason: 'Today excludes completed, archived, deleted, child, unplanned and future tasks',
      );
      expect(ids.take(50), firstIds);
      expect(items().where((v) => v['text'] == '加载更多任务'), isEmpty);
    },
  );
}
