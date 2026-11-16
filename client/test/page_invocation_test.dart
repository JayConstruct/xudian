import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/data/app_database.dart';

import 'host_batch_install_test.dart' as fixtures;

void main() {
  test(
    'a late dialog response cannot lend its approval to the next page call',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final folder = await Directory.systemTemp.createTemp(
        'invocation-authority-',
      );
      final host = ModuleHost(store: CollectionStore(db), directory: folder);
      addTearDown(() async {
        await host.close();
        await host.store.close();
        await db.close();
        await folder.delete(recursive: true);
      });
      await host.initialize();
      final oldStarted = Completer<void>(), newStarted = Completer<void>();
      final oldResult = Completer<Object?>(), newResult = Completer<Object?>();
      host.interaction = (_, method, args) async {
        expect(method, 'ui.dialog');
        if (args['title'] == 'old') {
          oldStarted.complete();
          return oldResult.future;
        }
        newStarted.complete();
        return newResult.future;
      };
      await host.install(
        await fixtures.candidate(
          'test.invocation',
          permissions: ['ui'],
          script: '''
import {ui} from '@xudian/sdk';
let pending;
const form=title=>({title,command:{ref:{moduleId:'test.invocation',serviceId:'save',majorVersion:1},input:{title}}});
export function first(){pending=ui.dialog(form('old'));return {};}
export async function second(){await ui.dialog(form('new'));return {};}
export async function settled(){return await pending;}
''',
        ),
      );
      await host.invokePage(
        'test.invocation',
        'first',
        {},
        commandIsCurrent: () => true,
      );
      await oldStarted.future;
      final instance = host.instances['test.invocation']!;
      expect(instance.page, isNull);
      final second = host.invokePage(
        'test.invocation',
        'second',
        {},
        commandIsCurrent: () => true,
      );
      await newStarted.future;
      final current = instance.page!;
      oldResult.complete({'title': 'old'});
      await instance.workflow.invoke('settled', {});
      expect(instance.page, same(current));
      expect(current.active, isTrue);
      expect(
        current.commandApproval,
        isNull,
        reason: 'A different invocation owns this response',
      );
      newResult.complete({'title': 'new'});
      await second;
      expect(current.active, isFalse);
      expect(current.commandApproval, isNull);
      expect(instance.page, isNull);
    },
  );
}
