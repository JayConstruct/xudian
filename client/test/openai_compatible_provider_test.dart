import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/features/ai/provider/assistant_model.dart';
import 'package:task_app/features/ai/provider/openai_compatible_provider.dart';

final _validResponse = utf8.encode(
  jsonEncode({
    'choices': [
      {
        'message': {'content': '生成结果：{"formatVersion":1}'},
      },
    ],
  }),
);

class _TestClient implements HttpClient {
  _TestClient(this.request, {Future<HttpClientRequest>? connection})
    : connection = connection ?? Future.value(request);

  final _TestRequest request;
  final Future<HttpClientRequest> connection;
  int closeCount = 0;
  bool forceClosed = false;

  @override
  Future<HttpClientRequest> postUrl(Uri url) => connection;

  @override
  void close({bool force = false}) {
    closeCount++;
    forceClosed = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestRequest implements HttpClientRequest {
  _TestRequest({Future<HttpClientResponse>? response})
    : response =
          response ?? Future.value(_TestResponse(Stream.value(_validResponse)));

  final Future<HttpClientResponse> response;
  final body = StringBuffer();
  int abortCount = 0;

  @override
  final _TestHeaders headers = _TestHeaders();

  @override
  void write(Object? object) => body.write(object);

  @override
  Future<HttpClientResponse> close() => response;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => abortCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHeaders implements HttpHeaders {
  final values = <String, Object>{};

  @override
  set contentType(ContentType? value) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestResponse extends Stream<List<int>> implements HttpClientResponse {
  _TestResponse(this.body, {this.statusCode = 200});

  final Stream<List<int>> body;

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Map<String, Object?>> _generate(
  OpenAiCompatibleProvider provider, {
  AiRequestCancellation? cancellation,
}) => provider.generateModule(
  endpoint: Uri.parse('https://model.example/v1/chat/completions'),
  model: 'test-model',
  apiKey: '',
  request: 'test',
  installedModules: const [],
  cancellation: cancellation,
);

void _expectCleanedUp(_TestClient client, {bool aborted = true}) {
  expect(client.closeCount, 1);
  expect(client.forceClosed, isTrue);
  expect(client.request.abortCount, aborted ? 1 : 0);
}

void main() {
  test('default network bounds remain 60/10/30 seconds and 1 MiB', () {
    const provider = OpenAiCompatibleProvider();
    expect(provider.totalTimeout, const Duration(seconds: 60));
    expect(provider.connectTimeout, const Duration(seconds: 10));
    expect(provider.bodyTimeout, const Duration(seconds: 30));
    expect(provider.maxResponseBytes, 1024 * 1024);
  });

  Future<AssistantModelReply> converse(
    OpenAiCompatibleProvider provider, {
    AiRequestCancellation? cancellation,
  }) => OpenAiAssistantModel(provider: provider).complete(
    endpoint: Uri.parse('https://model.example/v1/chat/completions'),
    model: 'test-model',
    apiKey: 'secret',
    messages: [AssistantMessage(role: 'user', content: '你好')],
    tools: [],
    cancellation: cancellation,
  );

  test(
    'conversation uses bounded transport without module system prompt',
    () async {
      final client = _TestClient(_TestRequest());
      final reply = await converse(
        OpenAiCompatibleProvider(httpClientFactory: () => client),
      );
      expect(reply.text, '生成结果：{"formatVersion":1}');
      expect(reply.calls, isEmpty);
      final sent = jsonDecode(client.request.body.toString()) as Map;
      expect(sent, {
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': '你好'},
        ],
      });
      expect(
        client.request.headers.values[HttpHeaders.authorizationHeader],
        'Bearer secret',
      );
      _expectCleanedUp(client, aborted: false);
    },
  );

  test('conversation pre-cancellation does not create a client', () async {
    var created = false;
    await expectLater(
      converse(
        OpenAiCompatibleProvider(
          httpClientFactory: () {
            created = true;
            return _TestClient(_TestRequest());
          },
        ),
        cancellation: AiRequestCancellation()..cancel(),
      ),
      throwsStateError,
    );
    expect(created, isFalse);
  });

  for (final phase in ['connect', 'headers', 'body']) {
    test('conversation cancellation settles stalled $phase', () async {
      final connection = Completer<HttpClientRequest>();
      final response = Completer<HttpClientResponse>();
      final listening = Completer<void>();
      var bodyCancelled = false;
      final body = StreamController<List<int>>(
        onListen: listening.complete,
        onCancel: () => bodyCancelled = true,
      );
      addTearDown(body.close);
      final client = _TestClient(
        _TestRequest(response: response.future),
        connection: connection.future,
      );
      final cancellation = AiRequestCancellation();
      final assertion = expectLater(
        converse(
          OpenAiCompatibleProvider(httpClientFactory: () => client),
          cancellation: cancellation,
        ),
        throwsStateError,
      );
      if (phase != 'connect') {
        connection.complete(client.request);
        await Future<void>.delayed(Duration.zero);
      }
      if (phase == 'body') {
        response.complete(_TestResponse(body.stream));
        await listening.future;
      }
      cancellation.cancel();
      await assertion;
      if (phase == 'connect') {
        connection.complete(client.request);
        await Future<void>.delayed(Duration.zero);
      }
      _expectCleanedUp(client);
      expect(bodyCancelled, phase == 'body');
      if (phase != 'body') await body.stream.listen(null).cancel();
    });
  }

  for (final phase in ['connect', 'headers', 'body']) {
    test('conversation honors $phase deadline', () async {
      final connection = Completer<HttpClientRequest>();
      final response = Completer<HttpClientResponse>();
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final client = _TestClient(
        _TestRequest(response: response.future),
        connection: connection.future,
      );
      final assertion = expectLater(
        converse(
          OpenAiCompatibleProvider(
            httpClientFactory: () => client,
            connectTimeout: Duration(
              milliseconds: phase == 'connect' ? 30 : 1000,
            ),
            totalTimeout: Duration(
              milliseconds: phase == 'headers' ? 30 : 1000,
            ),
            bodyTimeout: const Duration(milliseconds: 30),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
      if (phase != 'connect') connection.complete(client.request);
      if (phase == 'body') response.complete(_TestResponse(body.stream));
      await assertion;
      if (phase == 'connect') {
        connection.complete(client.request);
        await Future<void>.delayed(Duration.zero);
      }
      _expectCleanedUp(client);
      if (phase != 'body') await body.stream.listen(null).cancel();
    });
  }

  test(
    'conversation rejects oversize and malformed replies with cleanup',
    () async {
      for (final oversize in [true, false]) {
        final bytes = oversize
            ? _validResponse
            : utf8.encode('{"choices":[{"message":{"tool_calls":[{}]}}]}');
        final client = _TestClient(
          _TestRequest(
            response: Future.value(_TestResponse(Stream.value(bytes))),
          ),
        );
        await expectLater(
          converse(
            OpenAiCompatibleProvider(
              httpClientFactory: () => client,
              maxResponseBytes: oversize ? bytes.length - 1 : 1024,
            ),
          ),
          oversize ? throwsStateError : throwsFormatException,
        );
        _expectCleanedUp(client);
      }
    },
  );

  test('cancelling an active request closes the client without waiting for response', () async {
    final response = Completer<HttpClientResponse>();
    final client = _TestClient(_TestRequest(response: response.future));
    final cancellation = AiRequestCancellation();
    final request = _generate(
      OpenAiCompatibleProvider(httpClientFactory: () => client),
      cancellation: cancellation,
    );
    final assertion = expectLater(request, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    await assertion;
    _expectCleanedUp(client);
  });
  test('provider rejects cleartext remote endpoint', () async {
    await expectLater(
      const OpenAiCompatibleProvider().generateModule(
        endpoint: Uri.parse('http://example.com/v1/chat/completions'),
        model: 'test-model',
        apiKey: 'secret',
        request: 'test',
        installedModules: const [],
      ),
      throwsArgumentError,
    );
  });

  test('provider sends compatible request and extracts module JSON', () async {
    final client = _TestClient(
      _TestRequest(
        response: Future.value(
          _TestResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'content':
                            '生成结果：'
                            '{"formatVersion":1,'
                            '"manifest":{"id":"app.ai.generated",'
                            '"version":"1.0.0","coreApi":"1"}}',
                      },
                    },
                  ],
                }),
              ),
            ),
          ),
        ),
      ),
    );
    final module =
        await OpenAiCompatibleProvider(httpClientFactory: () => client)
            .generateModule(
              endpoint: Uri.parse('https://model.example/v1/chat/completions'),
              model: 'test-model',
              apiKey: 'secret',
              request: '增加考试管理',
              installedModules: const ['app.old@1.0.0'],
            );

    expect(module['formatVersion'], 1);
    expect((module['manifest'] as Map)['id'], 'app.ai.generated');
    expect(
      client.request.headers.values[HttpHeaders.authorizationHeader],
      'Bearer secret',
    );
    final received = jsonDecode(client.request.body.toString()) as Map;
    expect(received['model'], 'test-model');
    final messages = received['messages'] as List;
    expect((messages.last as Map)['content'], '增加考试管理');
    expect(received['temperature'], 0.2);
    expect(received.containsKey('tools'), isFalse);
    expect(received.containsKey('tool_choice'), isFalse);
    final system = (messages.first as Map)['content'] as String;
    expect(system, startsWith('你是序点应用的声明式功能设计器。\n'));
    expect(system, contains('formatVersion 只支持 1 或 2'));
    expect(system, contains('已安装动态模块：app.old@1.0.0'));
    expect(system, contains('必须由用户确认后安装'));
  });

  test('provider surfaces non-success HTTP responses', () async {
    final client = _TestClient(
      _TestRequest(
        response: Future.value(
          _TestResponse(
            Stream.value(utf8.encode('upstream failed')),
            statusCode: 500,
          ),
        ),
      ),
    );
    await expectLater(
      _generate(OpenAiCompatibleProvider(httpClientFactory: () => client)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('HTTP 500: upstream failed'),
        ),
      ),
    );
  });

  test('pre-cancelled requests do not create a client', () async {
    final cancellation = AiRequestCancellation()..cancel();
    var created = false;
    await expectLater(
      _generate(
        OpenAiCompatibleProvider(
          httpClientFactory: () {
            created = true;
            return _TestClient(_TestRequest());
          },
        ),
        cancellation: cancellation,
      ),
      throwsStateError,
    );
    expect(created, isFalse);
  });

  test('network bounds reject non-positive values before connecting', () async {
    var created = false;
    HttpClient factory() {
      created = true;
      return _TestClient(_TestRequest());
    }

    for (final provider in [
      OpenAiCompatibleProvider(
        httpClientFactory: factory,
        totalTimeout: Duration.zero,
      ),
      OpenAiCompatibleProvider(
        httpClientFactory: factory,
        connectTimeout: const Duration(milliseconds: -1),
      ),
      OpenAiCompatibleProvider(
        httpClientFactory: factory,
        bodyTimeout: Duration.zero,
      ),
      OpenAiCompatibleProvider(httpClientFactory: factory, maxResponseBytes: 0),
    ]) {
      await expectLater(_generate(provider), throwsArgumentError);
    }
    expect(created, isFalse);
  });

  test('connect timeout aborts a request that arrives late', () async {
    final connection = Completer<HttpClientRequest>();
    final client = _TestClient(_TestRequest(), connection: connection.future);
    await expectLater(
      _generate(
        OpenAiCompatibleProvider(
          httpClientFactory: () => client,
          connectTimeout: const Duration(milliseconds: 30),
        ),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('connect'),
        ),
      ),
    );
    expect(client.closeCount, 1);
    connection.complete(client.request);
    await Future<void>.delayed(Duration.zero);
    _expectCleanedUp(client);
  });

  test('total timeout also bounds stalled connection setup', () async {
    final connection = Completer<HttpClientRequest>();
    final client = _TestClient(_TestRequest(), connection: connection.future);
    await expectLater(
      _generate(
        OpenAiCompatibleProvider(
          httpClientFactory: () => client,
          totalTimeout: const Duration(milliseconds: 30),
        ),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('total'),
        ),
      ),
    );
    connection.complete(client.request);
    await Future<void>.delayed(Duration.zero);
    _expectCleanedUp(client);
  });

  test(
    'total timeout bounds response headers even if close never resolves',
    () async {
      final response = Completer<HttpClientResponse>();
      final client = _TestClient(_TestRequest(response: response.future));
      await expectLater(
        _generate(
          OpenAiCompatibleProvider(
            httpClientFactory: () => client,
            totalTimeout: const Duration(milliseconds: 30),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
      _expectCleanedUp(client);
      response.completeError(const HttpException('late transport failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('total deadline spans headers and body without restarting', () async {
    final response = Completer<HttpClientResponse>();
    final listening = Completer<void>();
    final body = StreamController<List<int>>(onListen: listening.complete);
    addTearDown(body.close);
    final client = _TestClient(_TestRequest(response: response.future));
    final result = _generate(
      OpenAiCompatibleProvider(
        httpClientFactory: () => client,
        totalTimeout: const Duration(milliseconds: 100),
        bodyTimeout: const Duration(seconds: 1),
      ),
    );
    final assertion = expectLater(
      result,
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('total'),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    response.complete(_TestResponse(body.stream));
    await listening.future;
    body.add([32]);
    await assertion;
    _expectCleanedUp(client);
  });

  test(
    'a rejected concurrent token attachment preserves the active request',
    () async {
      final response = Completer<HttpClientResponse>();
      final activeClient = _TestClient(_TestRequest(response: response.future));
      final rejectedClient = _TestClient(_TestRequest());
      final cancellation = AiRequestCancellation();
      final active = _generate(
        OpenAiCompatibleProvider(httpClientFactory: () => activeClient),
        cancellation: cancellation,
      );
      final activeAssertion = expectLater(active, throwsStateError);
      await expectLater(
        _generate(
          OpenAiCompatibleProvider(httpClientFactory: () => rejectedClient),
          cancellation: cancellation,
        ),
        throwsStateError,
      );
      _expectCleanedUp(rejectedClient, aborted: false);
      expect(activeClient.closeCount, 0);
      cancellation.cancel();
      await activeAssertion;
      _expectCleanedUp(activeClient);
    },
  );

  for (final phase in ['connect', 'headers', 'body']) {
    test(
      'cancellation settles stalled $phase and cleans up exactly once',
      () async {
        final connection = Completer<HttpClientRequest>();
        final response = Completer<HttpClientResponse>();
        final listening = Completer<void>();
        var bodyCancelled = false;
        final body = StreamController<List<int>>(
          onListen: listening.complete,
          onCancel: () => bodyCancelled = true,
        );
        addTearDown(body.close);
        final httpRequest = _TestRequest(response: response.future);
        final client = _TestClient(httpRequest, connection: connection.future);
        final cancellation = AiRequestCancellation();
        final result = _generate(
          OpenAiCompatibleProvider(httpClientFactory: () => client),
          cancellation: cancellation,
        );
        final assertion = expectLater(result, throwsStateError);
        if (phase != 'connect') {
          connection.complete(httpRequest);
          await Future<void>.delayed(Duration.zero);
        }
        if (phase == 'body') {
          response.complete(_TestResponse(body.stream));
          await listening.future;
        }
        cancellation.cancel();
        cancellation.cancel();
        await assertion;
        expect(client.closeCount, 1);
        if (phase == 'connect') {
          connection.complete(httpRequest);
          await Future<void>.delayed(Duration.zero);
        }
        _expectCleanedUp(client);
        expect(bodyCancelled, phase == 'body');
        if (phase != 'body') {
          await body.stream.listen(null).cancel();
        }
      },
    );
  }

  for (final useTotalTimeout in [false, true]) {
    test(
      '${useTotalTimeout ? 'total' : 'body'} timeout cancels stalled response stream',
      () async {
        var bodyCancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => bodyCancelled = true,
        );
        addTearDown(body.close);
        final client = _TestClient(
          _TestRequest(response: Future.value(_TestResponse(body.stream))),
        );
        await expectLater(
          _generate(
            OpenAiCompatibleProvider(
              httpClientFactory: () => client,
              totalTimeout: Duration(milliseconds: useTotalTimeout ? 30 : 1000),
              bodyTimeout: Duration(milliseconds: useTotalTimeout ? 1000 : 30),
            ),
          ),
          throwsA(
            isA<TimeoutException>().having(
              (error) => error.message,
              'message',
              contains(useTotalTimeout ? 'total' : 'body'),
            ),
          ),
        );
        expect(bodyCancelled, isTrue);
        _expectCleanedUp(client);
      },
    );
  }

  test('body timeout is not reset by a trickle of bytes', () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final trickle = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => body.add([32]),
    );
    addTearDown(trickle.cancel);
    final client = _TestClient(
      _TestRequest(response: Future.value(_TestResponse(body.stream))),
    );
    await expectLater(
      _generate(
        OpenAiCompatibleProvider(
          httpClientFactory: () => client,
          bodyTimeout: const Duration(milliseconds: 40),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    _expectCleanedUp(client);
  });

  test(
    'response limit accepts exact UTF-8 bytes split across chunks',
    () async {
      final body = Stream.fromIterable(_validResponse.map((byte) => [byte]));
      final client = _TestClient(
        _TestRequest(response: Future.value(_TestResponse(body))),
      );
      final cancellation = AiRequestCancellation();
      final module = await _generate(
        OpenAiCompatibleProvider(
          httpClientFactory: () => client,
          maxResponseBytes: _validResponse.length,
        ),
        cancellation: cancellation,
      );
      expect(module['formatVersion'], 1);
      cancellation.cancel();
      _expectCleanedUp(client, aborted: false);
    },
  );

  for (final status in [200, 500]) {
    test(
      'byte limit rejects oversized HTTP $status bodies without EOF',
      () async {
        var bodyCancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => bodyCancelled = true,
        );
        addTearDown(body.close);
        final client = _TestClient(
          _TestRequest(
            response: Future.value(
              _TestResponse(body.stream, statusCode: status),
            ),
          ),
        );
        final result = _generate(
          OpenAiCompatibleProvider(
            httpClientFactory: () => client,
            maxResponseBytes: _validResponse.length - 1,
          ),
        );
        final assertion = expectLater(
          result,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('字节限制'),
            ),
          ),
        );
        body.add(_validResponse.sublist(0, _validResponse.length - 1));
        body.add(_validResponse.sublist(_validResponse.length - 1));
        await assertion;
        expect(bodyCancelled, isTrue);
        _expectCleanedUp(client);
      },
    );
  }

  test('malformed JSON and stream errors clean up the client', () async {
    for (final body in [
      Stream<List<int>>.value(utf8.encode('not JSON')),
      Stream<List<int>>.error(const HttpException('broken body')),
    ]) {
      final client = _TestClient(
        _TestRequest(response: Future.value(_TestResponse(body))),
      );
      await expectLater(
        _generate(OpenAiCompatibleProvider(httpClientFactory: () => client)),
        throwsA(anyOf(isA<FormatException>(), isA<HttpException>())),
      );
      _expectCleanedUp(client);
    }
  });
}
