import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:task_app/features/ai/provider/assistant_model.dart';
import 'package:task_app/features/ai/provider/openai_compatible_provider.dart';

class _DirectHttpOverrides extends HttpOverrides {}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _exercise(String scenario) async {
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  ).timeout(const Duration(seconds: 2));
  final received = Completer<HttpRequest>();
  server.listen(received.complete, onError: received.completeError);
  final cancellation = AiRequestCancellation();
  final provider = OpenAiCompatibleProvider(
    httpClientFactory: () =>
        _DirectHttpOverrides().createHttpClient(null)
          ..findProxy = (_) => 'DIRECT',
    totalTimeout: const Duration(seconds: 2),
    connectTimeout: const Duration(seconds: 1),
    bodyTimeout: const Duration(milliseconds: 100),
    maxResponseBytes: 4096,
  );
  final result = provider
      .generateModule(
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}/v1/chat/completions',
        ),
        model: 'test-model',
        apiKey: 'secret',
        request: '增加考试管理',
        installedModules: const ['app.old@1.0.0'],
        cancellation: cancellation,
      )
      .then<Object>((module) => module, onError: (Object error) => error);
  try {
    final incoming = await received.future.timeout(const Duration(seconds: 2));
    final body = await utf8.decoder
        .bind(incoming)
        .join()
        .timeout(const Duration(seconds: 2));
    final payload = jsonDecode(body) as Map;
    _check(payload['model'] == 'test-model', 'Incorrect model');
    _check(
      incoming.headers.value(HttpHeaders.authorizationHeader) ==
          'Bearer secret',
      'Incorrect authorization',
    );
    _check(
      (payload['messages'] as List).last['content'] == '增加考试管理',
      'Incorrect UTF-8 request body',
    );
    incoming.response.done.ignore();
    if (scenario == 'cancel headers') {
      cancellation.cancel();
    } else if (scenario == 'total timeout') {
      final outcome = await result.timeout(const Duration(seconds: 3));
      _check(
        outcome is TimeoutException && outcome.message!.contains('total'),
        'Headers must honor the total deadline',
      );
      return;
    } else {
      incoming.response.headers.contentType = ContentType.json;
      if (scenario == 'HTTP error') {
        incoming.response.statusCode = 500;
        incoming.response.write('upstream failed');
        await incoming.response.close();
      } else if (scenario == 'byte limit') {
        incoming.response.bufferOutput = false;
        incoming.response.write('过' * 2048);
        await incoming.response.flush();
      } else if (scenario == 'body timeout' || scenario == 'cancel body') {
        incoming.response.bufferOutput = false;
        incoming.response.write('{');
        await incoming.response.flush();
        if (scenario == 'cancel body') cancellation.cancel();
      } else {
        incoming.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '生成结果：{"formatVersion":1,"manifest":'
                      '{"id":"app.ai.generated","version":"1.0.0","coreApi":"1"}}',
                },
              },
            ],
          }),
        );
        await incoming.response.close();
      }
    }
    final outcome = await result.timeout(const Duration(seconds: 3));
    switch (scenario) {
      case 'success':
        _check(
          outcome is Map &&
              outcome['formatVersion'] == 1 &&
              (outcome['manifest'] as Map)['id'] == 'app.ai.generated',
          'Module extraction failed: $outcome',
        );
      case 'HTTP error':
        _check(
          outcome is StateError &&
              outcome.message.contains('HTTP 500: upstream failed'),
          'HTTP error was not preserved: $outcome',
        );
      case 'byte limit':
        _check(
          outcome is StateError && outcome.message.contains('字节限制'),
          'Byte limit was not enforced: $outcome',
        );
      case 'body timeout':
        _check(
          outcome is TimeoutException && outcome.message!.contains('body'),
          'Body deadline was not enforced: $outcome',
        );
      case 'cancel headers':
      case 'cancel body':
        _check(
          outcome is StateError && outcome.message.contains('cancelled'),
          'Cancellation did not settle the request: $outcome',
        );
    }
  } finally {
    cancellation.cancel();
    await server.close(force: true).timeout(const Duration(seconds: 2));
  }
}

Future<void> _exerciseConversation(String scenario) async {
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  ).timeout(const Duration(seconds: 2));
  final received = Completer<HttpRequest>();
  var requestCount = 0;
  server.listen((incoming) {
    requestCount++;
    if (!received.isCompleted) {
      received.complete(incoming);
    } else {
      incoming.response.statusCode = 500;
      incoming.response.done.ignore();
      unawaited(incoming.response.close());
    }
  }, onError: received.completeError);
  final cancellation = AiRequestCancellation();
  final fallback = scenario == 'JSON fallback';
  final noTools = scenario == 'no tools';
  final provider = OpenAiCompatibleProvider(
    httpClientFactory: () =>
        _DirectHttpOverrides().createHttpClient(null)
          ..findProxy = (_) => 'DIRECT',
    totalTimeout: const Duration(seconds: 2),
    connectTimeout: const Duration(seconds: 1),
    bodyTimeout: const Duration(milliseconds: 100),
    maxResponseBytes: 4096,
  );
  final conversation = OpenAiAssistantModel(
    provider: provider,
    jsonCompatibilityFallback: fallback,
    maxToolCalls: 1,
    maxToolArgumentsBytes: 64,
  );
  final result = conversation
      .complete(
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}/v1/chat/completions',
        ),
        model: 'test-model',
        apiKey: 'secret',
        messages: [
          AssistantMessage(role: 'user', content: '查找考试'),
          if (scenario == 'tool history' || fallback) ...[
            AssistantMessage(
              role: 'assistant',
              content: '',
              toolCalls: [
                AssistantToolCall(
                  id: 'old-call',
                  name: 'task.list',
                  arguments: {},
                ),
              ],
            ),
            AssistantMessage(
              role: 'tool',
              content: '[]',
              toolCallId: 'old-call',
            ),
          ],
        ],
        tools: [
          if (!noTools)
            AssistantToolSchema(
              name: 'task.list',
              description: 'List tasks',
              parameters: {'type': 'object'},
            ),
        ],
        cancellation: cancellation,
      )
      .then<Object>((reply) => reply, onError: (Object error) => error);
  try {
    final incoming = await received.future.timeout(const Duration(seconds: 2));
    final body = await utf8.decoder
        .bind(incoming)
        .join()
        .timeout(const Duration(seconds: 2));
    final payload = jsonDecode(body) as Map;
    _check(payload['model'] == 'test-model', 'Incorrect conversation model');
    _check(
      incoming.headers.value(HttpHeaders.authorizationHeader) ==
          'Bearer secret',
      'Incorrect conversation authorization',
    );
    _check(!body.contains('secret'), 'Credentials leaked into message data');
    _check(
      !body.contains('声明式功能设计器'),
      'Module prompt leaked into conversation',
    );
    _check(
      payload.containsKey('tools') == (!fallback && !noTools),
      'Incorrect native schema mode',
    );
    _check(
      payload['tool_choice'] == (!fallback && !noTools ? 'auto' : null),
      'Incorrect native tool choice',
    );
    if (scenario == 'tool history') {
      _check(
        payload['messages'].last['tool_call_id'] == 'old-call',
        'Tool result history lost its call id',
      );
    }
    if (fallback) {
      _check(
        payload['messages'].first['content'].contains('task.list') &&
            jsonDecode(payload['messages'].last['content'])['toolCallId'] ==
                'old-call',
        'JSON compatibility schemas or tool history missing',
      );
    }
    incoming.response.done.ignore();
    incoming.response.headers.contentType = ContentType.json;
    if (scenario == 'cancel headers') {
      cancellation.cancel();
    } else if (scenario == 'body timeout' || scenario == 'cancel body') {
      incoming.response.bufferOutput = false;
      incoming.response.write('{');
      await incoming.response.flush();
      if (scenario == 'cancel body') cancellation.cancel();
    } else if (scenario == 'byte limit') {
      incoming.response.bufferOutput = false;
      incoming.response.write('过' * 2048);
      await incoming.response.flush();
    } else if (scenario == 'unsupported tools') {
      incoming.response.statusCode = 400;
      incoming.response.write('tools unsupported');
      await incoming.response.close();
    } else {
      final arguments = scenario == 'malformed arguments'
          ? '[]'
          : scenario == 'argument limit'
          ? jsonEncode({'title': '过' * 30})
          : jsonEncode({'title': '考试'});
      final call = {
        'id': 'call-1',
        'type': 'function',
        'function': {'name': 'task.list', 'arguments': arguments},
      };
      incoming.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': noTools
                    ? '你好'
                    : fallback
                    ? jsonEncode({
                        'text': '查找中',
                        'calls': [
                          {
                            'id': 'call-1',
                            'name': 'task.list',
                            'arguments': {'title': '考试'},
                          },
                        ],
                      })
                    : null,
                if (!noTools && !fallback)
                  'tool_calls': [
                    call,
                    if (scenario == 'call limit') {...call, 'id': 'call-2'},
                  ],
              },
            },
          ],
        }),
      );
      await incoming.response.close();
    }
    final outcome = await result.timeout(const Duration(seconds: 3));
    if (scenario == 'no tools') {
      _check(
        outcome is AssistantModelReply &&
            outcome.text == '你好' &&
            outcome.calls.isEmpty,
        'Conversational reply failed: $outcome',
      );
    } else if (scenario == 'native calls' ||
        scenario == 'tool history' ||
        fallback) {
      _check(
        outcome is AssistantModelReply &&
            outcome.calls.single.id == 'call-1' &&
            outcome.calls.single.name == 'task.list' &&
            outcome.calls.single.arguments['title'] == '考试',
        'Tool reply failed: $outcome',
      );
    } else if (scenario == 'body timeout') {
      _check(outcome is TimeoutException, 'Conversation body deadline failed');
    } else if (scenario == 'cancel headers' || scenario == 'cancel body') {
      _check(
        outcome is StateError && outcome.message.contains('cancelled'),
        'Conversation cancellation failed',
      );
    } else if (scenario == 'byte limit' || scenario == 'unsupported tools') {
      _check(outcome is StateError, 'Conversation transport rejection failed');
    } else {
      _check(outcome is FormatException, 'Invalid calls accepted: $outcome');
    }
    _check(
      requestCount == 1,
      'Conversation request was automatically replayed',
    );
  } finally {
    cancellation.cancel();
    await server.close(force: true).timeout(const Duration(seconds: 2));
  }
}

Future<void> main() async {
  for (final scenario in [
    'success',
    'HTTP error',
    'byte limit',
    'body timeout',
    'cancel headers',
    'cancel body',
    'total timeout',
  ]) {
    await _exercise(scenario);
    stdout.writeln('PASS: $scenario');
  }
  for (final scenario in [
    'no tools',
    'native calls',
    'tool history',
    'JSON fallback',
    'malformed arguments',
    'call limit',
    'argument limit',
    'unsupported tools',
    'byte limit',
    'body timeout',
    'cancel headers',
    'cancel body',
  ]) {
    await _exerciseConversation(scenario);
    stdout.writeln('PASS: conversation $scenario');
  }
}
