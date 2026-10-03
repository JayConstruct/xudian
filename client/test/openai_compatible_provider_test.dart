import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/features/ai/provider/openai_compatible_provider.dart';

void main() {
  test('cancelling an active request closes the client without waiting for response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<void>();
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      received.complete();
    });
    final cancellation = AiRequestCancellation();
    final request = const OpenAiCompatibleProvider().generateModule(
      endpoint: Uri.parse(
        'http://127.0.0.1:${server.port}/v1/chat/completions',
      ),
      model: 'model',
      apiKey: '',
      request: 'test',
      installedModules: const [],
      cancellation: cancellation,
    );
    final assertion = expectLater(request, throwsA(anything));
    await received.future.timeout(const Duration(seconds: 5));
    cancellation.cancel();
    await assertion.timeout(const Duration(seconds: 5));
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
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, Object?>? received;
    String? authorization;

    server.listen((request) async {
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      final body = await utf8.decoder.bind(request).join();
      received = (jsonDecode(body) as Map).cast<String, Object?>();

      request.response.headers.contentType = ContentType.json;
      request.response.write(
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
      );
      await request.response.close();
    });
    final endpoint = Uri.parse(
      'http://127.0.0.1:${server.port}/v1/chat/completions',
    );
    final module = await const OpenAiCompatibleProvider().generateModule(
      endpoint: endpoint,
      model: 'test-model',
      apiKey: 'secret',
      request: '增加考试管理',
      installedModules: const ['app.old@1.0.0'],
    );

    expect(module['formatVersion'], 1);
    expect((module['manifest'] as Map)['id'], 'app.ai.generated');
    expect(authorization, 'Bearer secret');
    expect(received?['model'], 'test-model');
    final messages = received?['messages'] as List;
    expect((messages.last as Map)['content'], '增加考试管理');

    await server.close(force: true);
  });

  test('provider surfaces non-success HTTP responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 500;
      request.response.write('upstream failed');
      await request.response.close();
    });
    final endpoint = Uri.parse(
      'http://127.0.0.1:${server.port}/v1/chat/completions',
    );

    await expectLater(
      const OpenAiCompatibleProvider().generateModule(
        endpoint: endpoint,
        model: 'test-model',
        apiKey: '',
        request: 'test',
        installedModules: const [],
      ),
      throwsStateError,
    );

    await server.close(force: true);
  });
}
