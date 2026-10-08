import 'dart:convert';

import 'openai_compatible_provider.dart';

export 'openai_compatible_provider.dart' show AiRequestCancellation;

Object? _freezeJson(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('JSON object keys must be strings');
      }
      result[entry.key as String] = _freezeJson(entry.value);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  throw const FormatException('Value is not JSON compatible');
}

Map<String, Object?> _freezeObject(Map<String, Object?> value) =>
    _freezeJson(value) as Map<String, Object?>;

class AssistantMessage {
  AssistantMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    List<AssistantToolCall> toolCalls = const [],
  }) : toolCalls = List.unmodifiable(toolCalls);

  final String role;
  final String content;
  final String? toolCallId;
  final List<AssistantToolCall> toolCalls;

  Map<String, Object?> toJson() => {
    'role': role,
    'content': content,
    if (toolCallId != null) 'tool_call_id': toolCallId,
    if (toolCalls.isNotEmpty)
      'tool_calls': toolCalls.map((call) => call.toJson()).toList(),
  };
}

class AssistantToolCall {
  AssistantToolCall({
    required this.id,
    required this.name,
    required Map<String, Object?> arguments,
  }) : arguments = _freezeObject(arguments) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw const FormatException('Tool call id and name must not be empty');
    }
  }

  final String id;
  final String name;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': jsonEncode(arguments)},
  };
}

class AssistantModelReply {
  AssistantModelReply({
    required this.text,
    List<AssistantToolCall> calls = const [],
  }) : calls = List.unmodifiable(calls);

  final String text;
  final List<AssistantToolCall> calls;
}

class AssistantToolSchema {
  AssistantToolSchema({
    required this.name,
    required this.description,
    required Map<String, Object?> parameters,
  }) : parameters = _freezeObject(parameters);

  final String name;
  final String description;
  final Map<String, Object?> parameters;

  Map<String, Object?> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

abstract interface class AssistantModel {
  Future<AssistantModelReply> complete({
    required Uri endpoint,
    required String model,
    required String apiKey,
    required List<AssistantMessage> messages,
    required List<AssistantToolSchema> tools,
    AiRequestCancellation? cancellation,
  });
}

enum AssistantToolChoice { auto, none, required }

class OpenAiAssistantModel implements AssistantModel {
  const OpenAiAssistantModel({
    this.provider = const OpenAiCompatibleProvider(),
    this.jsonCompatibilityFallback = false,
    this.toolChoice = AssistantToolChoice.auto,
    this.maxToolCalls = 32,
    this.maxToolArgumentsBytes = 64 * 1024,
  });

  final OpenAiCompatibleProvider provider;
  final bool jsonCompatibilityFallback;
  final AssistantToolChoice toolChoice;
  final int maxToolCalls;
  final int maxToolArgumentsBytes;

  @override
  Future<AssistantModelReply> complete({
    required Uri endpoint,
    required String model,
    required String apiKey,
    required List<AssistantMessage> messages,
    required List<AssistantToolSchema> tools,
    AiRequestCancellation? cancellation,
  }) async {
    if (maxToolCalls <= 0 || maxToolArgumentsBytes <= 0) {
      throw ArgumentError('Tool call bounds must be positive');
    }
    if (messages.isEmpty) {
      throw ArgumentError('Conversation messages must not be empty');
    }
    final toolNames = <String>{};
    for (final tool in tools) {
      if (tool.name.trim().isEmpty || !toolNames.add(tool.name)) {
        throw ArgumentError('Tool names must be nonempty and unique');
      }
    }
    if (tools.isEmpty && toolChoice == AssistantToolChoice.required) {
      throw ArgumentError('Required tool choice needs tools');
    }
    final useJson = jsonCompatibilityFallback && tools.isNotEmpty;
    for (final message in messages) {
      _validateCalls(message.toolCalls);
    }
    final schemas = tools.map((tool) => tool.toJson()).toList();
    final wireMessages = [
      if (useJson)
        {
          'role': 'system',
          'content':
              'Return only a JSON object with "text" (string) and "calls" '
              '(array). Each call has "id" (unique nonempty string), "name" '
              '(an available tool name), and "arguments" (JSON object). '
              'Use an empty calls array for a conversational reply. '
              'Tool choice: ${toolChoice.name}. '
              'With none, calls must be empty; with required, provide at '
              'least one call. At most $maxToolCalls calls; each arguments '
              'object must fit $maxToolArgumentsBytes UTF-8 bytes. '
              'Tool results arrive as user JSON with toolCallId and content. '
              'Available tool schemas: ${jsonEncode(schemas)}',
        },
      for (final message in messages)
        useJson ? _compatibilityMessage(message) : message.toJson(),
    ];
    return provider.requestChatCompletion(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      messages: wireMessages,
      tools: useJson ? null : schemas,
      toolChoice: !useJson && tools.isNotEmpty ? toolChoice.name : null,
      parseResponse: (body) => _parseReply(body, toolNames, useJson),
      cancellation: cancellation,
    );
  }

  Map<String, Object?> _compatibilityMessage(AssistantMessage message) {
    if (message.toolCallId != null) {
      return {
        'role': 'user',
        'content': jsonEncode({
          'toolCallId': message.toolCallId,
          'content': message.content,
        }),
      };
    }
    if (message.toolCalls.isNotEmpty) {
      return {
        'role': message.role,
        'content': jsonEncode({
          'text': message.content,
          'calls': [
            for (final call in message.toolCalls)
              {'id': call.id, 'name': call.name, 'arguments': call.arguments},
          ],
        }),
      };
    }
    return message.toJson();
  }

  AssistantModelReply _parseReply(
    String body,
    Set<String> toolNames,
    bool useJson,
  ) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Model response must be a JSON object');
    }
    final choices = decoded['choices'];
    if (choices is! List ||
        choices.isEmpty ||
        choices.first is! Map ||
        choices.first['message'] is! Map) {
      throw const FormatException('Model response is missing a choice message');
    }
    final message = choices.first['message'] as Map;
    final content = message['content'];
    if (content != null && content is! String) {
      throw const FormatException('Assistant content must be text or null');
    }
    String text;
    Object? rawCalls;
    if (useJson) {
      if (message['tool_calls'] != null) {
        throw const FormatException('Expected JSON compatibility reply');
      }
      final envelope = content is String ? jsonDecode(content) : null;
      if (envelope is! Map ||
          envelope['text'] is! String ||
          envelope['calls'] is! List) {
        throw const FormatException('Invalid JSON compatibility reply');
      }
      text = envelope['text'] as String;
      rawCalls = envelope['calls'];
    } else {
      text = content as String? ?? '';
      rawCalls = message['tool_calls'];
    }
    if (rawCalls != null && rawCalls is! List) {
      throw const FormatException('Tool calls must be an array');
    }
    final callList = rawCalls as List? ?? const [];
    if (callList.length > maxToolCalls) {
      throw const FormatException('Too many tool calls');
    }
    final calls = <AssistantToolCall>[];
    for (final rawCall in callList) {
      if (rawCall is! Map || rawCall['id'] is! String) {
        throw const FormatException('Malformed tool call');
      }
      final function = useJson ? rawCall : rawCall['function'];
      if ((!useJson && rawCall['type'] != 'function') ||
          function is! Map ||
          function['name'] is! String) {
        throw const FormatException('Malformed function tool call');
      }
      final rawArguments = function['arguments'];
      if (!useJson && rawArguments is! String) {
        throw const FormatException('Tool arguments must be a JSON string');
      }
      if (!useJson &&
          utf8.encode(rawArguments as String).length > maxToolArgumentsBytes) {
        throw const FormatException('Tool arguments exceed byte limit');
      }
      final arguments = useJson
          ? rawArguments
          : jsonDecode(rawArguments as String);
      if (arguments is! Map<String, dynamic>) {
        throw const FormatException('Tool arguments must be a JSON object');
      }
      final call = AssistantToolCall(
        id: rawCall['id'] as String,
        name: function['name'] as String,
        arguments: arguments,
      );
      if (!toolNames.contains(call.name)) {
        throw const FormatException('Model returned an unavailable tool');
      }
      calls.add(call);
    }
    _validateCalls(calls);
    if (toolChoice == AssistantToolChoice.none && calls.isNotEmpty) {
      throw const FormatException('Tool choice forbids calls');
    }
    if (toolChoice == AssistantToolChoice.required && calls.isEmpty) {
      throw const FormatException('Tool choice requires calls');
    }
    if (text.trim().isEmpty && calls.isEmpty) {
      throw const FormatException('Model returned an empty reply');
    }
    return AssistantModelReply(text: text, calls: calls);
  }

  void _validateCalls(List<AssistantToolCall> calls) {
    if (calls.length > maxToolCalls) {
      throw const FormatException('Too many tool calls');
    }
    final ids = <String>{};
    for (final call in calls) {
      if (!ids.add(call.id)) {
        throw const FormatException('Duplicate tool call id');
      }
      if (utf8.encode(jsonEncode(call.arguments)).length >
          maxToolArgumentsBytes) {
        throw const FormatException('Tool arguments exceed byte limit');
      }
    }
  }
}
