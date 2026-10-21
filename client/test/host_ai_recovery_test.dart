import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

import 'planner_task_schedule_test.dart' show sourcePackage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late Map<String, Object?> created;
  late Future<Object?> Function(int, Map<String, Object?>) respond;
  late Future<bool> Function(Map<String, Object?>) review;
  late bool approveGrant;
  late int requests;
  late int grantRequests;
  late int taskReviews;
  late int historyReviews;

  Future<Map<String, Object?>> command(
    String moduleId,
    String serviceId,
    Map<String, Object?> input,
  ) async {
    final actor = host.instances[moduleId]!.actor;
    final plan = await host.prepare(
      actor,
      ServiceRef(moduleId, serviceId, 1),
      input,
    );
    host.review(plan.id, actor);
    return object(await host.commit(actor, plan.id));
  }

  Future<Map<String, Object?>> task() async => object(
    await store.get(
      host.instances['app.tasks']!.actor,
      'tasks',
      created['id'] as String,
    ),
  );

  Future<Map<String, Object?>> history() async => object(
    await store.get(host.instances['app.ai']!.actor, 'history', 'conversation'),
  );

  Future<Map<String, Object?>> render(
    String type, {
    Map<String, Object?> state = const {},
  }) async => object(
    await host.invokePage('app.ai', 'render', {
      'state': state,
      'event': {'type': type},
      'formValues': {'message': '仅修改任务标题'},
    }),
  );

  Map<String, Object?> response(Map<String, Object?> message) => {
    'status': 200,
    'body': jsonEncode({
      'choices': [
        {'message': message},
      ],
    }),
  };

  Map<String, Object?> tool(String title, {String callId = 'edit'}) {
    final toolIndex = host
        .directoryServices()
        .map(object)
        .where(
          (service) =>
              service['tool'] != null && service['moduleId'] != 'app.ai',
        )
        .toList()
        .indexWhere((service) => service['id'] == 'task.updateFields');
    return {
      'id': callId,
      'type': 'function',
      'function': {
        'name': 'service_$toolIndex',
        'arguments': jsonEncode({
          'id': created['id'],
          'changes': {'title': title},
        }),
      },
    };
  }

  Map<String, Object?> tools(List<Map<String, Object?>> calls) =>
      response({'role': 'assistant', 'content': null, 'tool_calls': calls});

  bool isHistory(Map<String, Object?> arguments) =>
      (arguments['writes'] as List)
          .map(object)
          .every((write) => write['collection'] == 'history');

  Future<void> expectPartial(Map<String, Object?> page) async {
    final state = object(page['state']);
    expect((await task())['title'], 'after AI');
    expect(state['lastUndo'], isNotNull);
    expect(state['receipts'], hasLength(1));
    expect(jsonEncode(page['tree']), contains('部分完成'));
    expect(jsonEncode(page['tree']), contains('已提交 1 项操作'));
    expect(jsonEncode(page['tree']), contains('撤销上次操作'));
    expect(jsonEncode(page['tree']), contains('未自动重试'));
    expect((await history())['lastUndo'], state['lastUndo']);
    expect(taskReviews, 1);
  }

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(database);
    directory = await Directory.systemTemp.createTemp('ai-recovery-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    for (final moduleId in ['app.tasks', 'app.ai']) {
      await host.install(await sourcePackage(moduleId));
    }
    created = await command('app.tasks', 'task.create', {'title': 'before AI'});
    await command('app.ai', 'ai.connection.save', {
      'connection': {
        'endpoint': 'https://model.invalid/v1',
        'model': 'mock-only',
        'credential': 'mock-opaque',
      },
    });
    requests = 0;
    grantRequests = 0;
    taskReviews = 0;
    historyReviews = 0;
    approveGrant = true;
    review = (arguments) async => true;
    respond = (requestNumber, arguments) async => requestNumber == 1
        ? tools([tool('after AI')])
        : response({'role': 'assistant', 'content': 'done'});
    host.interaction = (actor, method, arguments) async {
      if (method == 'grants.request') {
        grantRequests++;
        return approveGrant;
      }
      if (method == 'ui.review') {
        if (isHistory(arguments)) {
          historyReviews++;
        } else {
          taskReviews++;
        }
        return review(arguments);
      }
      if (method == 'http.request') {
        requests++;
        expect(arguments['url'], 'https://model.invalid/v1/chat/completions');
        return respond(requests, arguments);
      }
      if (method == 'http.cancel') return null;
      throw StateError('Unexpected bridge; real network forbidden: $method');
    };
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'F04 cancelled undo retains receipt and can be reviewed again',
    () async {
      final edited = await render('send');
      final editedState = object(edited['state']);
      review = (arguments) async => isHistory(arguments);
      final cancelled = await render('undo', state: editedState);
      expect(object(cancelled['state'])['lastUndo'], editedState['lastUndo']);
      expect((await task())['title'], 'after AI');
      expect(jsonEncode(cancelled['tree']), contains('撤销审核已取消'));
      review = (arguments) async => true;
      final undone = await render('undo', state: object(cancelled['state']));
      expect((await task())['title'], 'before AI');
      expect(object(undone['state']).containsKey('lastUndo'), false);
      expect((await history())['lastUndo'], isNull);
      final refreshed = await render('refresh', state: editedState);
      expect(object(refreshed['state']).containsKey('lastUndo'), false);
      expect(taskReviews, 3);
    },
  );

  test(
    'F04 undo conflict does not lose the saved undo or overwrite data',
    () async {
      final edited = await render('send');
      final savedUndo = (await history())['lastUndo'];
      await command('app.tasks', 'task.updateFields', {
        'id': created['id'],
        'changes': {'title': 'user changed later'},
      });
      await expectLater(
        render('undo', state: object(edited['state'])),
        throwsStateError,
      );
      expect((await history())['lastUndo'], savedUndo);
      expect((await task())['title'], 'user changed later');
      expect(object((await render('refresh'))['state'])['lastUndo'], savedUndo);
    },
  );

  test('F04 commit conflict after review retains the undo receipt', () async {
    final edited = await render('send');
    final savedUndo = (await history())['lastUndo'];
    review = (arguments) async {
      if (!isHistory(arguments)) {
        await command('app.tasks', 'task.updateFields', {
          'id': created['id'],
          'changes': {'title': 'changed during review'},
        });
      }
      return true;
    };
    await expectLater(
      render('undo', state: object(edited['state'])),
      throwsStateError,
    );
    expect((await history())['lastUndo'], savedUndo);
    expect((await task())['title'], 'changed during review');
  });

  for (final failure in ['http', 'network', 'malformed']) {
    test(
      'F02 $failure after commit returns durable partial success and undo',
      () async {
        respond = (requestNumber, arguments) async {
          if (requestNumber == 1) return tools([tool('after AI')]);
          final saved = await history();
          expect(saved['lastUndo'], isNotNull);
          expect(saved['receipts'], hasLength(1));
          if (failure == 'network') throw StateError('mock network failure');
          if (failure == 'malformed') {
            return {'status': 200, 'body': 'not json'};
          }
          return {'status': 503, 'body': 'mock unavailable'};
        };
        final page = await render('send');
        await expectPartial(page);
        expect(requests, 2);
        final reopened = await render('refresh');
        expect(object(reopened['state'])['lastUndo'], isNotNull);
        await render('undo', state: object(reopened['state']));
        expect((await task())['title'], 'before AI');
      },
    );
  }

  test(
    'F02 partial receipt survives host restart without page state',
    () async {
      respond = (requestNumber, arguments) async => requestNumber == 1
          ? tools([tool('after AI')])
          : {'status': 503, 'body': 'mock unavailable'};
      await render('send');
      final saved = await history();
      await host.close();
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      host.interaction = (actor, method, arguments) async => throw StateError(
        'Refresh must not request a grant or network: $method',
      );
      final reopened = await render('refresh');
      expect(object(reopened['state'])['lastUndo'], saved['lastUndo']);
      expect(object(reopened['state'])['receipts'], saved['receipts']);
      expect(jsonEncode(reopened['tree']), contains('部分完成'));
      expect(jsonEncode(reopened['tree']), contains('撤销上次操作'));
      expect((await task())['title'], 'after AI');
    },
  );

  test('F02 cancellation after commit retains results and never replays on authorization', () async {
    final waiting = Completer<void>();
    final release = Completer<void>();
    respond = (requestNumber, arguments) async {
      if (requestNumber == 1) return tools([tool('after AI')]);
      expect((await history())['lastUndo'], isNotNull);
      waiting.complete();
      await release.future;
      return response({'role': 'assistant', 'content': 'late response'});
    };
    final running = render('send');
    await waiting.future;
    await host.invokeInterrupt('app.ai', 'cancel');
    release.complete();
    final page = await running;
    await expectPartial(page);
    expect(jsonEncode(page['tree']), contains('已取消'));
    expect(jsonEncode(page['tree']), contains('重新申请工具授权'));
    await render('authorize', state: object(page['state']));
    expect(requests, 2);
    expect(taskReviews, 1);
    expect(grantRequests, 2);
    await render('undo');
    expect((await task())['title'], 'before AI');
  });

  test(
    'F02 round limit retains committed results without duplicate writes',
    () async {
      respond = (requestNumber, arguments) async => tools([tool('after AI')]);
      final page = await render('send');
      await expectPartial(page);
      expect(requests, 8);
      expect(jsonEncode(page['tree']), contains('8轮'));
      expect(taskReviews, 1);
    },
  );

  test('F02 tool call limit preserves committed results', () async {
    respond = (requestNumber, arguments) async => tools(
      List.generate(25, (index) => tool('after AI', callId: 'edit-$index')),
    );
    final page = await render('send');
    await expectPartial(page);
    expect(requests, 1);
    expect(jsonEncode(page['tree']), contains('24次'));
  });

  test('F02 failed second tool keeps the first receipt and excludes uncommitted work', () async {
    final invalid = tool('not committed', callId: 'invalid');
    invalid['function'] = {...object(invalid['function']), 'arguments': '{}'};
    respond = (requestNumber, arguments) async =>
        tools([tool('after AI'), invalid]);
    final page = await render('send');
    await expectPartial(page);
    expect(requests, 1);
    expect(taskReviews, 1);
  });

  for (final failure in ['declined', 'failed']) {
    test(
      'F02 $failure history review preserves in-session receipt and stops tools',
      () async {
        review = (arguments) async {
          if (!isHistory(arguments)) return true;
          if (failure == 'failed') {
            throw StateError('mock history review failed');
          }
          return false;
        };
        final page = await render('send');
        final state = object(page['state']);
        expect((await task())['title'], 'after AI');
        expect(state['lastUndo'], isNotNull);
        expect(state['receipts'], hasLength(1));
        expect(jsonEncode(page['tree']), contains('部分完成'));
        expect(jsonEncode(page['tree']), contains('仅保留在当前会话'));
        expect(requests, 1);
        expect(taskReviews, 1);
        final reopened = await render('refresh');
        expect(object(reopened['state'])['lastUndo'], state['lastUndo']);
        expect(jsonEncode(reopened['tree']), contains('仅保留在当前会话'));
        review = (arguments) async => true;
        await render('undo');
        expect((await task())['title'], 'before AI');
      },
    );
  }

  test(
    'F05 host grant expiration requires explicit authorization without replay',
    () async {
      await render('send');
      final expired = host.grants.values.single;
      host.grants[expired.id] = HostGrant(
        expired.id,
        expired.caller,
        expired.scopes,
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      respond = (requestNumber, arguments) async =>
          tools([tool('must not run', callId: 'after-expiration')]);
      final failed = await render('send');
      expect(jsonEncode(failed['tree']), contains('重新申请工具授权'));
      expect(jsonEncode(failed['tree']), contains('本轮未提交业务写入'));
      expect((await task())['title'], 'after AI');
      expect(grantRequests, 1);
      final requestCount = requests;
      await render('send');
      expect(requests, requestCount + 1);
      approveGrant = false;
      final declined = await render('authorize');
      expect(jsonEncode(declined['tree']), contains('重新申请工具授权'));
      approveGrant = true;
      await render('authorize');
      expect(requests, requestCount + 1);
      expect(taskReviews, 1);
      respond = (requestNumber, arguments) async =>
          requestNumber == requestCount + 2
          ? tools([tool('new explicit instruction', callId: 'new-edit')])
          : response({'role': 'assistant', 'content': 'done'});
      await render('send');
      expect((await task())['title'], 'new explicit instruction');
      expect(taskReviews, 2);
    },
  );

  test(
    'F05 grant revoked during tool review does not commit or auto-renew',
    () async {
      review = (arguments) async {
        if (!isHistory(arguments)) host.grants.values.single.revoked = true;
        return true;
      };
      final page = await render('send');
      expect((await task())['title'], 'before AI');
      expect(jsonEncode(page['tree']), contains('本轮未提交业务写入'));
      expect(jsonEncode(page['tree']), contains('重新申请工具授权'));
      expect(grantRequests, 1);
      expect(requests, 1);
    },
  );

  for (final invalidGrant in ['expired', 'revoked']) {
    test(
      'F05 $invalidGrant tool grant does not block ordinary no-tool chat',
      () async {
        await render('send');
        final previousGrant = host.grants.values.single;
        if (invalidGrant == 'revoked') {
          previousGrant.revoked = true;
        } else {
          host.grants[previousGrant.id] = HostGrant(
            previousGrant.id,
            previousGrant.caller,
            previousGrant.scopes,
            DateTime.now().subtract(const Duration(minutes: 1)),
          );
        }
        respond = (requestNumber, arguments) async =>
            tools([tool('must not run', callId: 'invalid-grant-edit')]);
        final denied = await render('send');
        expect(jsonEncode(denied['tree']), contains('重新申请工具授权'));
        final previousRequests = requests;
        respond = (requestNumber, arguments) async =>
            response({'role': 'assistant', 'content': '普通聊天不需要工具授权'});
        final chat = await render('send', state: object(denied['state']));
        final messages = object(chat['state'])['messages'] as List;
        expect(object(messages.last)['content'], '普通聊天不需要工具授权');
        expect(requests, previousRequests + 1);
        expect(grantRequests, 1);
        expect(taskReviews, 1);
        expect((await task())['title'], 'after AI');
        expect(jsonEncode(chat['tree']), contains('重新申请工具授权'));
      },
    );
  }

  test('history save accepts the original messages-only input', () async {
    await command('app.ai', 'ai.history.save', {
      'messages': [
        {'role': 'assistant', 'content': 'legacy message'},
      ],
    });
    final reopened = await render('refresh');
    expect(jsonEncode(reopened['tree']), contains('legacy message'));
    expect(object(reopened['state']).containsKey('lastUndo'), false);
    expect((await history())['receipts'], isEmpty);
  });

  test(
    'F05 invalid tool authorization does not block advanced module generation',
    () async {
      await render('send');
      host.grants.values.single.revoked = true;
      respond = (requestNumber, arguments) async =>
          tools([tool('must not run')]);
      await render('send');
      final previousRequests = requests;
      final previousInteraction = host.interaction!;
      host.interaction = (actor, method, arguments) async {
        if (method == 'packages.review') return true;
        return previousInteraction(actor, method, arguments);
      };
      respond = (requestNumber, arguments) async {
        expect(object(arguments['body'])['tools'], isNull);
        return response({
          'role': 'assistant',
          'content': jsonEncode({
            'definition': {
              'formatVersion': 3,
              'manifest': {
                'id': 'private.ai.recovery',
                'name': 'Mock generated module',
                'version': '1.0.0',
                'hostApi': '^1.0.0',
                'dataVersion': 1,
                'permissions': ['ui'],
                'dependencies': [],
              },
              'entryPoint': 'main.js',
              'collections': [],
              'pages': [
                {
                  'id': 'private.ai.recovery.page',
                  'title': 'Mock',
                  'handler': 'render',
                },
              ],
              'services': [],
            },
            'files': {
              'main.js': "export function render() { return {state:{},tree:{type:'text',text:'mock'}}; }",
            },
          }),
        });
      };
      await render('send', state: {'advanced': true});
      expect(host.instances['private.ai.recovery']!.package.version, '1.0.0');
      expect(requests, previousRequests + 1);
      expect(grantRequests, 1);
      expect(taskReviews, 1);
      expect((await task())['title'], 'after AI');
    },
  );

  test(
    'F05 20-write quota persists across turns and renewal never replays',
    () async {
      respond = (requestNumber, arguments) async => requestNumber.isOdd
          ? tools([tool('edit-$requestNumber', callId: 'edit-$requestNumber')])
          : response({'role': 'assistant', 'content': 'done'});
      for (var turn = 0; turn < 20; turn++) {
        await render('send');
      }
      expect(host.grants.values.single.remainingWrites, 0);
      expect(grantRequests, 1);
      expect(taskReviews, 20);
      final exhausted = await render('send');
      expect(jsonEncode(exhausted['tree']), contains('重新申请工具授权'));
      expect(requests, 41);
      await render('authorize');
      expect(requests, 41);
      expect(taskReviews, 20);
      expect(grantRequests, 2);
      respond = (requestNumber, arguments) async => requestNumber == 42
          ? tools([tool('edit-42', callId: 'edit-42')])
          : response({'role': 'assistant', 'content': 'done'});
      await render('send');
      expect(taskReviews, 21);
      expect((await task())['title'], 'edit-42');
    },
  );

  test(
    'F05 initial denied grant leaves task unchanged and offers reauthorization',
    () async {
      approveGrant = false;
      final page = await render('send');
      expect((await task())['title'], 'before AI');
      expect(jsonEncode(page['tree']), contains('本轮未提交业务写入'));
      expect(jsonEncode(page['tree']), contains('重新申请工具授权'));
      expect(taskReviews, 0);
      expect(grantRequests, 1);
      expect(historyReviews, 1);
    },
  );
}
