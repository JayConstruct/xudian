import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_network.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

class _LocalHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late HostNetwork network;
  late Directory directory;
  late ModuleActor actor;
  late Future<Object?> Function(String, Map<String, Object?>) interact;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    network = HostNetwork(store);
    directory = await Directory.systemTemp.createTemp('ai-connection-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    final source = Directory('../packages/modules/app.ai');
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          object(
            jsonDecode(await File('${source.path}/module.json').readAsString()),
          ),
          {
            for (final file in source.listSync().whereType<File>())
              if (file.path.endsWith('.js'))
                file.uri.pathSegments.last: await file.readAsString(),
          },
        ),
        allowUnsignedLocal: true,
      ),
    );
    actor = host.instances['app.ai']!.actor;
    interact = (method, args) async => throw StateError('Unexpected $method');
    host.interaction = (caller, method, args) async {
      if (method == 'ui.review') return true;
      if (method == 'secrets.delete') {
        await network.delete(caller, args['handle'] as String);
        return null;
      }
      return interact(method, args);
    };
  });
  tearDown(() async {
    network.close();
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> render(
    String type, {
    Object? state,
    Map<String, Object?>? forms,
  }) async => object(
    await host.invokePage('app.ai', 'render', {
      'event': {'type': type},
      'state': state ?? {},
      'formValues': forms ?? {},
    }),
  );
  Future<Map<String, Object?>> connection() async =>
      object(await store.get(actor, 'connections', 'default'));

  test(
    'conversation gear opens the same registered settings destination',
    () async {
      interact = (method, args) async {
        expect(method, 'ui.navigate');
        expect(args['page'], 'app.ai.settings');
        return true;
      };
      final result = await render('settings');
      expect(object(result['tree'])['footer'], isA<Map>());
      final settings = object(
        await host.invokePage('app.ai', 'renderSettings', {}),
      );
      expect(object(settings['header'])['title'], 'AI 设置');
      final connectionPage = object(
        await host.invokePage('app.ai', 'renderSettings', {
          'event': {'type': 'configure'},
        }),
      );
      expect(object(connectionPage['header'])['title'], '模型连接');
      expect(object(connectionPage['header'])['backEvent'], {
        'type': 'connectionBack',
      });
      final back = object(
        await host.invokePage('app.ai', 'renderSettings', {
          'state': connectionPage['state'],
          'event': {'type': 'connectionBack'},
        }),
      );
      expect(object(back['header'])['title'], 'AI 设置');
    },
  );

  test(
    'work mode persists across settings and conversation instances',
    () async {
      interact = (method, args) async {
        expect(method, 'ui.dialog');
        return {'mode': 'advanced'};
      };
      await host.invokePage('app.ai', 'renderSettings', {
        'event': {'type': 'advanced'},
      });
      final chat = await render('refresh');
      expect(object(chat['state'])['advanced'], true);
      expect(
        object(await store.get(actor, 'preferences', 'default'))['advanced'],
        true,
      );
    },
  );

  test(
    'declining history clear preserves messages across page instances',
    () async {
      final originalConnection = await connection();
      final plan = await host.prepare(
        actor,
        const ServiceRef('app.ai', 'ai.history.save', 1),
        {
          'messages': [
            {'role': 'user', 'content': '保留我的消息'},
          ],
        },
      );
      host.review(plan.id, actor);
      await host.commit(actor, plan.id);
      host.interaction = (_, method, args) async {
        expect(method, 'ui.review');
        return false;
      };
      await host.invokePage('app.ai', 'renderSettings', {
        'event': {'type': 'clear'},
      });
      final chat = await render('refresh');
      expect(jsonEncode(chat['tree']), contains('保留我的消息'));
      host.interaction = (_, method, args) async => true;
      await host.invokePage('app.ai', 'renderSettings', {
        'event': {'type': 'clear'},
      });
      final cleared = await render(
        'refresh',
        state: {
          'messages': [
            {'role': 'user', 'content': '保留我的消息'},
          ],
        },
      );
      expect(jsonEncode(cleared['tree']), isNot(contains('保留我的消息')));
      expect(await connection(), originalConnection);
    },
  );
  Future<void> configure({
    String endpoint = 'http://127.0.0.1:8317',
    String model = '',
    String keyMode = 'replace',
  }) async {
    interact = (method, args) async {
      if (method == 'ui.dialog') {
        return {'endpoint': endpoint, 'model': model, 'keyMode': keyMode};
      }
      if (method == 'secrets.configure') {
        expect(args['endpoint'], isNot(contains('/chat/completions')));
        return network.configure(
          actor,
          args['endpoint'] as String,
          'fixture-client-key',
        );
      }
      throw StateError('Unexpected $method');
    };
    final result = await render('configureCliProxy');
    expect(object(result['state'])['connectionStatus'], contains('连接已保存'));
  }

  for (final endpoint in [
    ' http://127.0.0.1:8317/ ',
    'http://127.0.0.1:8317/v1/',
    'http://127.0.0.1:8317/v1/chat/completions',
    'http://127.0.0.1:8317/v1/models',
  ]) {
    test(
      'CLIProxyAPI normalizes $endpoint and stores only a credential handle',
      () async {
        await configure(endpoint: endpoint);
        final saved = await connection();
        expect(saved['provider'], 'cliproxyapi');
        expect(saved['endpoint'], 'http://127.0.0.1:8317/v1');
        expect(saved['model'], '');
        expect(jsonEncode(saved), isNot(contains('fixture-client-key')));
        expect(await const FlutterSecureStorage().readAll(), hasLength(1));
      },
    );
  }

  for (final endpoint in [
    'http://remote.example:8317',
    'https://user:key@remote.example/v1',
    'https://remote.example/v1?api_key=secret',
    'https://remote.example/v1#fragment',
    'http://127.0.0.1:99999',
  ]) {
    test(
      'invalid address $endpoint is rejected before asking for a secret',
      () async {
        final original = await connection();
        interact = (method, args) async {
          expect(method, 'ui.dialog');
          return {'endpoint': endpoint, 'model': '', 'keyMode': 'replace'};
        };
        final result = await render('configureCliProxy');
        expect(
          object(result['state'])['connectionStatus'],
          isNot(contains('连接已保存')),
        );
        expect(await connection(), original);
        expect(await const FlutterSecureStorage().readAll(), isEmpty);
      },
    );
  }

  test(
    'editing the model retains the key; changing address requires a new key',
    () async {
      await configure(model: 'first');
      final original = await connection();
      await configure(model: 'second', keyMode: 'keep');
      expect((await connection())['credential'], original['credential']);
      expect((await connection())['model'], 'second');
      interact = (method, args) async {
        expect(method, 'ui.dialog');
        return {
          'endpoint': 'https://other.example/v1',
          'model': 'third',
          'keyMode': 'keep',
        };
      };
      final result = await render('configureCliProxy');
      expect(object(result['state'])['connectionStatus'], contains('地址已变化'));
      expect((await connection())['endpoint'], original['endpoint']);
      expect(await const FlutterSecureStorage().readAll(), hasLength(1));
    },
  );

  test('replacement deletes only the old key after approval', () async {
    await configure();
    final first = await connection();
    await configure(model: 'new');
    expect((await connection())['credential'], isNot(first['credential']));
    expect(await const FlutterSecureStorage().readAll(), hasLength(1));
    await expectLater(
      network.metadata(actor, first['credential'] as String),
      throwsStateError,
    );
  });

  test('declining the connection review deletes the new key and preserves the old connection', () async {
    await configure(model: 'old');
    final original = await connection();
    host.interaction = (caller, method, args) async {
      if (method == 'ui.review') return false;
      if (method == 'ui.dialog') {
        return {
          'endpoint': 'https://new.example',
          'model': 'new',
          'keyMode': 'replace',
        };
      }
      if (method == 'secrets.configure') {
        return network.configure(
          caller,
          args['endpoint'] as String,
          'discarded-key',
        );
      }
      if (method == 'secrets.delete') {
        await network.delete(caller, args['handle'] as String);
        return null;
      }
      throw StateError('Unexpected $method');
    };
    await render('configureCliProxy');
    expect(await connection(), original);
    expect((await const FlutterSecureStorage().readAll()).values, [
      'fixture-client-key',
    ]);
  });

  test('real local HTTP discovers models, tests chat, and sends without losing history', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];
    final bodies = <Map<String, Object?>>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      expect(
        request.headers.value('Authorization'),
        'Bearer fixture-client-key',
      );
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(
          jsonEncode({
            'data': [
              {'id': 'second'},
              {'id': 'first'},
              {'id': 'first'},
              {'id': ''},
              null,
            ],
          }),
        );
      } else {
        final body = object(
          jsonDecode(await utf8.decoder.bind(request).join()),
        );
        bodies.add(body);
        expect(body['model'], 'first');
        expect(body['stream'], false);
        expect(body.containsKey('temperature'), false);
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'OK'},
              },
            ],
          }),
        );
      }
      await request.response.close();
    });
    await configure(endpoint: 'http://127.0.0.1:${server.port}');
    interact = (method, args) async {
      if (method == 'http.request') {
        return HttpOverrides.runWithHttpOverrides(
          () => network.request(actor, args),
          _LocalHttp(),
        );
      }
      if (method == 'ui.dialog') {
        final field = object((args['fields'] as List).single);
        expect(field['options'], [
          {'value': 'first', 'label': 'first'},
          {'value': 'second', 'label': 'second'},
        ]);
        return {'model': 'first'};
      }
      throw StateError('Unexpected $method');
    };
    await render('chooseModel');
    expect((await connection())['model'], 'first');
    final tested = await render('testConnection');
    expect(object(tested['state'])['connectionStatus'], contains('连接成功'));
    expect(await store.get(actor, 'history', 'conversation'), isNull);
    final sent = await render('send', forms: {'message': '你好'});
    expect(object(sent['state'])['messages'], [
      {'role': 'user', 'content': '你好'},
      {'role': 'assistant', 'content': 'OK'},
    ]);
    expect(requests, [
      '/v1/models',
      '/v1/chat/completions',
      '/v1/chat/completions',
    ]);
    expect(bodies.first.containsKey('tools'), false);
  });

  test('HTTP authentication failures are actionable and never echo the server body', () async {
    await configure(model: 'test');
    interact = (method, args) async => {
      'status': 401,
      'body': 'fixture-client-key private-upstream-token',
    };
    final result = await render('testConnection');
    final status = object(result['state'])['connectionStatus'] as String;
    expect(status, contains('HTTP 401'));
    expect(status, contains('客户端 API Key'));
    expect(status, isNot(contains('fixture-client-key')));
  });

  for (final body in ['not json', '{"data":{}}', '{"data":[]}', 'null']) {
    test(
      'invalid or empty model list $body preserves the selected model',
      () async {
        await configure(model: 'existing');
        interact = (method, args) async {
          expect(method, 'http.request');
          return {'status': 200, 'body': body};
        };
        final result = await render('chooseModel');
        expect(
          object(result['state'])['connectionStatus'],
          isNot(contains('模型已保存')),
        );
        expect((await connection())['model'], 'existing');
      },
    );
  }

  test(
    'cancel interrupts model discovery and later connections can be tested',
    () async {
      await configure(model: 'test');
      final started = Completer<void>(), response = Completer<Object?>();
      String? requestId;
      interact = (method, args) async {
        if (method == 'http.request') {
          requestId = args['id'] as String;
          started.complete();
          return response.future;
        }
        expect(method, 'http.cancel');
        expect(args['id'], requestId);
        response.complete({'status': 200, 'body': '{"data":[{"id":"late"}]}'});
        return null;
      };
      final work = render('chooseModel');
      await started.future;
      await host.invokeInterrupt('app.ai', 'cancel');
      expect(object((await work)['state'])['connectionStatus'], '已取消连接操作');
      expect((await connection())['model'], 'test');
      interact = (method, args) async => {
        'status': 200,
        'body': '{"choices":[{"message":{"content":"OK"}}]}',
      };
      expect(
        object((await render('testConnection'))['state'])['connectionStatus'],
        contains('连接成功'),
      );
    },
  );
}
