import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/features/ai/provider/assistant_model.dart';
import 'package:task_app/features/ai/provider/openai_compatible_provider.dart';

class _RecordingProvider extends OpenAiCompatibleProvider {
  _RecordingProvider(this.response);

  final Object? response;
  int requests = 0;
  List<Map<String, Object?>>? sentMessages;
  List<Map<String, Object?>>? sentTools;
  String? sentToolChoice;
  String? sentApiKey;
  AiRequestCancellation? sentCancellation;

  @override
  Future<Result> requestChatCompletion<Result>({
    required Uri endpoint,
    required String model,
    required String apiKey,
    required List<Map<String, Object?>> messages,
    required Result Function(String body) parseResponse,
    List<Map<String, Object?>>? tools,
    String? toolChoice,
    double? temperature,
    AiRequestCancellation? cancellation,
  }) async {
    requests++;
    sentMessages = messages;
    sentTools = tools;
    sentToolChoice = toolChoice;
    sentApiKey = apiKey;
    sentCancellation = cancellation;
    if (response is Exception) throw response!;
    return parseResponse(jsonEncode(response));
  }
}

Object _response(Object? message) => {
  'choices': [
    {'message': message},
  ],
};

Map<String, Object?> _call({
  String id = 'call-1',
  String name = 'task.list',
  Object? arguments = '{"title":"考试"}',
}) => {
  'id': id,
  'type': 'function',
  'function': {'name': name, 'arguments': arguments},
};

AssistantToolSchema _schema() => AssistantToolSchema(
  name: 'task.list',
  description: 'List tasks',
  parameters: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
    },
  },
);

Future<AssistantModelReply> _complete(
  AssistantModel model, {
  List<AssistantMessage>? messages,
  List<AssistantToolSchema>? tools,
  AiRequestCancellation? cancellation,
}) => model.complete(
  endpoint: Uri.parse('https://model.example/v1/chat/completions'),
  model: 'test-model',
  apiKey: 'credential-not-message-data',
  messages: messages ?? [AssistantMessage(role: 'user', content: '查找考试')],
  tools: tools ?? [_schema()],
  cancellation: cancellation,
);

void main() {
  test('message serializes standard ChatCompletions history', () {
    final call = AssistantToolCall(
      id: 'call-1',
      name: 'task.list',
      arguments: {'title': '考试'},
    );
    final message = AssistantMessage(
      role: 'assistant',
      content: '',
      toolCalls: [call],
    );
    expect(message.toJson(), {
      'role': 'assistant',
      'content': '',
      'tool_calls': [_call()],
    });
    expect(
      AssistantMessage(
        role: 'tool',
        content: '[]',
        toolCallId: call.id,
      ).toJson(),
      {'role': 'tool', 'content': '[]', 'tool_call_id': 'call-1'},
    );
    expect(AssistantMessage(role: 'user', content: 'hello').toJson(), {
      'role': 'user',
      'content': 'hello',
    });
  });

  test('messages, calls, replies and schemas are deeply immutable', () {
    final nested = <Object?>['original'];
    final arguments = <String, Object?>{'nested': nested};
    final call = AssistantToolCall(
      id: 'call-1',
      name: 'task.list',
      arguments: arguments,
    );
    final calls = [call];
    final message = AssistantMessage(
      role: 'assistant',
      content: '',
      toolCalls: calls,
    );
    final reply = AssistantModelReply(text: '', calls: calls);
    final schema = AssistantToolSchema(
      name: 'task.list',
      description: 'List',
      parameters: arguments,
    );
    nested.add('changed');
    arguments.clear();
    calls.clear();
    expect(call.arguments['nested'], ['original']);
    expect(schema.parameters['nested'], ['original']);
    expect(message.toolCalls, [call]);
    expect(reply.calls, [call]);
    expect(() => call.arguments['extra'] = true, throwsUnsupportedError);
    expect(
      () => (call.arguments['nested'] as List).add('changed'),
      throwsUnsupportedError,
    );
    expect(() => message.toolCalls.clear(), throwsUnsupportedError);
    expect(() => reply.calls.clear(), throwsUnsupportedError);
    expect(() => schema.parameters.clear(), throwsUnsupportedError);
  });

  test('arguments and schemas reject non-JSON values', () {
    for (final value in [
      Object(),
      double.nan,
      double.infinity,
      {1: 'bad'},
    ]) {
      expect(
        () => AssistantToolCall(
          id: 'call-1',
          name: 'task.list',
          arguments: {'value': value},
        ),
        throwsFormatException,
      );
      expect(
        () => AssistantToolSchema(
          name: 'task.list',
          description: 'List',
          parameters: {'value': value},
        ),
        throwsFormatException,
      );
    }
  });

  test('native calls preserve text, arguments, history and schemas', () async {
    final provider = _RecordingProvider(
      _response({
        'content': '查找中',
        'tool_calls': [_call()],
      }),
    );
    final cancellation = AiRequestCancellation();
    final history = [
      AssistantMessage(role: 'system', content: 'You are an assistant'),
      AssistantMessage(role: 'user', content: '查找考试'),
      AssistantMessage(
        role: 'assistant',
        content: '',
        toolCalls: [
          AssistantToolCall(id: 'old', name: 'task.list', arguments: {}),
        ],
      ),
      AssistantMessage(role: 'tool', content: '[]', toolCallId: 'old'),
    ];
    final reply = await _complete(
      OpenAiAssistantModel(provider: provider),
      messages: history,
      cancellation: cancellation,
    );
    expect(reply.text, '查找中');
    expect(reply.calls.single.id, 'call-1');
    expect(reply.calls.single.name, 'task.list');
    expect(reply.calls.single.arguments, {'title': '考试'});
    expect(provider.sentMessages, history.map((message) => message.toJson()));
    expect(provider.sentTools, [_schema().toJson()]);
    expect(provider.sentToolChoice, 'auto');
    expect(provider.sentCancellation, same(cancellation));
    expect(provider.sentApiKey, 'credential-not-message-data');
    expect(
      jsonEncode([provider.sentMessages, provider.sentTools]),
      isNot(contains('credential-not-message-data')),
    );
  });

  test('native call-only reply accepts null content', () async {
    final provider = _RecordingProvider(
      _response({
        'content': null,
        'tool_calls': [_call()],
      }),
    );
    final reply = await _complete(OpenAiAssistantModel(provider: provider));
    expect(reply.text, '');
    expect(reply.calls, hasLength(1));
  });

  for (final fallback in [false, true]) {
    test('no-tools reply remains plain text with fallback=$fallback', () async {
      final provider = _RecordingProvider(_response({'content': '你好'}));
      final reply = await _complete(
        OpenAiAssistantModel(
          provider: provider,
          jsonCompatibilityFallback: fallback,
        ),
        tools: [],
      );
      expect(reply.text, '你好');
      expect(reply.calls, isEmpty);
      expect(provider.sentTools, isEmpty);
      expect(provider.sentToolChoice, isNull);
      expect(provider.sentMessages, hasLength(1));
    });
  }

  for (final malformed in [
    null,
    {},
    {'choices': []},
    {
      'choices': ['bad'],
    },
    _response(null),
    _response({'content': 1}),
    _response({'content': null}),
    _response({'content': ''}),
    _response({'content': 'text', 'tool_calls': {}}),
    _response({
      'tool_calls': [null],
    }),
    _response({
      'tool_calls': [_call(id: '')],
    }),
    _response({
      'tool_calls': [_call(name: '')],
    }),
    _response({
      'tool_calls': [_call(name: 'unavailable')],
    }),
    _response({
      'tool_calls': [_call(arguments: 'not JSON')],
    }),
    _response({
      'tool_calls': [_call(arguments: '[]')],
    }),
    _response({
      'tool_calls': [_call(arguments: 'null')],
    }),
    _response({
      'tool_calls': [_call(arguments: '1')],
    }),
    _response({
      'tool_calls': [_call(arguments: '{} trailing')],
    }),
    _response({
      'tool_calls': [_call(arguments: <String, Object?>{})],
    }),
    _response({
      'tool_calls': [_call()..['type'] = 'other'],
    }),
    _response({
      'tool_calls': [_call()..['function'] = {}],
    }),
    _response({
      'tool_calls': [_call(), _call()],
    }),
  ]) {
    test('rejects malformed native reply: ${jsonEncode(malformed)}', () async {
      final provider = _RecordingProvider(malformed);
      await expectLater(
        _complete(OpenAiAssistantModel(provider: provider)),
        throwsFormatException,
      );
      expect(provider.requests, 1);
    });
  }

  test('tool count and UTF-8 argument bounds include exact boundary', () async {
    final arguments = jsonEncode({'title': '考试'});
    final limit = utf8.encode(arguments).length;
    final provider = _RecordingProvider(
      _response({
        'tool_calls': [_call(arguments: arguments)],
      }),
    );
    expect(
      (await _complete(
        OpenAiAssistantModel(
          provider: provider,
          maxToolCalls: 1,
          maxToolArgumentsBytes: limit,
        ),
      )).calls,
      hasLength(1),
    );
    await expectLater(
      _complete(
        OpenAiAssistantModel(
          provider: provider,
          maxToolArgumentsBytes: limit - 1,
        ),
      ),
      throwsFormatException,
    );
    final tooMany = _RecordingProvider(
      _response({
        'tool_calls': [_call(), _call(id: 'call-2')],
      }),
    );
    await expectLater(
      _complete(OpenAiAssistantModel(provider: tooMany, maxToolCalls: 1)),
      throwsFormatException,
    );
  });

  test('typed tool choice is serialized and enforced', () async {
    for (final choice in AssistantToolChoice.values) {
      final provider = _RecordingProvider(
        _response({
          'content': 'reply',
          if (choice != AssistantToolChoice.none) 'tool_calls': [_call()],
        }),
      );
      await _complete(
        OpenAiAssistantModel(provider: provider, toolChoice: choice),
      );
      expect(provider.sentToolChoice, choice.name);
    }
    await expectLater(
      _complete(
        OpenAiAssistantModel(
          provider: _RecordingProvider(
            _response({
              'tool_calls': [_call()],
            }),
          ),
          toolChoice: AssistantToolChoice.none,
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      _complete(
        OpenAiAssistantModel(
          provider: _RecordingProvider(_response({'content': 'reply'})),
          toolChoice: AssistantToolChoice.required,
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'explicit JSON compatibility mode translates complete history',
    () async {
      final provider = _RecordingProvider(
        _response({
          'content': jsonEncode({
            'text': '查找中',
            'calls': [
              {
                'id': 'call-1',
                'name': 'task.list',
                'arguments': {'title': '考试'},
              },
            ],
          }),
        }),
      );
      final reply = await _complete(
        OpenAiAssistantModel(
          provider: provider,
          jsonCompatibilityFallback: true,
        ),
        messages: [
          AssistantMessage(role: 'user', content: '查找考试'),
          AssistantMessage(
            role: 'assistant',
            content: '',
            toolCalls: [
              AssistantToolCall(id: 'old', name: 'task.list', arguments: {}),
            ],
          ),
          AssistantMessage(role: 'tool', content: '[]', toolCallId: 'old'),
        ],
      );
      expect(reply.text, '查找中');
      expect(reply.calls.single.arguments, {'title': '考试'});
      expect(provider.sentTools, isNull);
      expect(provider.sentToolChoice, isNull);
      expect(provider.sentMessages!.first['content'], contains('task.list'));
      expect(
        jsonDecode(
          provider.sentMessages![2]['content'] as String,
        )['calls'][0]['id'],
        'old',
      );
      expect(provider.sentMessages!.last['role'], 'user');
      expect(jsonDecode(provider.sentMessages!.last['content'] as String), {
        'toolCallId': 'old',
        'content': '[]',
      });
    },
  );

  for (final envelope in [
    {'text': 'hello', 'calls': []},
    {'text': '', 'calls': []},
    {'text': 1, 'calls': []},
    {'text': '', 'calls': {}},
    {
      'text': '',
      'calls': [
        {'id': 'call-1', 'name': 'task.list', 'arguments': '{}'},
      ],
    },
    {
      'text': '',
      'calls': [
        {'id': 'call-1', 'name': 'task.list', 'arguments': []},
      ],
    },
    {
      'text': '',
      'calls': [
        {'id': 'call-1', 'name': 'task.list', 'arguments': {}},
        {'id': 'call-1', 'name': 'task.list', 'arguments': {}},
      ],
    },
  ]) {
    test('JSON compatibility envelope: ${jsonEncode(envelope)}', () async {
      final provider = _RecordingProvider(
        _response({'content': jsonEncode(envelope)}),
      );
      final result = _complete(
        OpenAiAssistantModel(
          provider: provider,
          jsonCompatibilityFallback: true,
        ),
      );
      if (envelope['text'] == 'hello') {
        expect((await result).text, 'hello');
      } else {
        await expectLater(result, throwsFormatException);
      }
      expect(provider.requests, 1);
    });
  }

  test('native failures never trigger JSON replay', () async {
    final provider = _RecordingProvider(
      const FormatException('unsupported tools'),
    );
    await expectLater(
      _complete(OpenAiAssistantModel(provider: provider)),
      throwsFormatException,
    );
    expect(provider.requests, 1);
    final jsonContent = _RecordingProvider(
      _response({'content': '{"text":"reply","calls":[]}'}),
    );
    final reply = await _complete(OpenAiAssistantModel(provider: jsonContent));
    expect(reply.text, '{"text":"reply","calls":[]}');
    expect(reply.calls, isEmpty);
    expect(jsonContent.requests, 1);
  });

  test('invalid configuration and history fail before transport', () async {
    final provider = _RecordingProvider(_response({'content': 'reply'}));
    for (final model in [
      OpenAiAssistantModel(provider: provider, maxToolCalls: 0),
      OpenAiAssistantModel(provider: provider, maxToolArgumentsBytes: 0),
    ]) {
      await expectLater(_complete(model), throwsArgumentError);
    }
    final model = OpenAiAssistantModel(provider: provider);
    await expectLater(_complete(model, messages: []), throwsArgumentError);
    await expectLater(
      _complete(model, tools: [_schema(), _schema()]),
      throwsArgumentError,
    );
    await expectLater(
      _complete(
        OpenAiAssistantModel(
          provider: provider,
          toolChoice: AssistantToolChoice.required,
        ),
        tools: [],
      ),
      throwsArgumentError,
    );
    final call = AssistantToolCall(
      id: 'same',
      name: 'task.list',
      arguments: {},
    );
    await expectLater(
      _complete(
        model,
        messages: [
          AssistantMessage(
            role: 'assistant',
            content: '',
            toolCalls: [call, call],
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(provider.requests, 0);
  });
}
