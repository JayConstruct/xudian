import 'dart:convert';
import 'dart:io';

class AiRequestCancellation {
  HttpClient? _client;
  bool _cancelled = false;
  bool get cancelled => _cancelled;

  void attach(HttpClient client) {
    if (_cancelled) {
      client.close(force: true);
      throw StateError('AI request was cancelled');
    }
    _client = client;
  }

  void detach() => _client = null;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
    _client = null;
  }
}

class OpenAiCompatibleProvider {
  const OpenAiCompatibleProvider();

  static bool acceptsEndpoint(Uri endpoint) =>
      endpoint.host.isNotEmpty &&
      (endpoint.scheme == 'https' ||
          (endpoint.scheme == 'http' &&
              (endpoint.host == 'localhost' ||
                  (InternetAddress.tryParse(endpoint.host)?.isLoopback ??
                      false))));

  Future<Map<String, Object?>> generateModule({
    required Uri endpoint,
    required String model,
    required String apiKey,
    required String request,
    required List<String> installedModules,
    AiRequestCancellation? cancellation,
  }) async {
    if (!acceptsEndpoint(endpoint)) {
      throw ArgumentError('模型端点必须使用 HTTPS；本机地址可使用 HTTP');
    }
    if (model.trim().isEmpty) {
      throw ArgumentError('模型名称不能为空');
    }
    if (request.trim().isEmpty) {
      throw ArgumentError('功能需求不能为空');
    }

    final client = HttpClient();
    try {
      cancellation?.attach(client);
      final httpRequest = await client.postUrl(endpoint);
      httpRequest.headers.contentType = ContentType.json;
      if (apiKey.trim().isNotEmpty) {
        httpRequest.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${apiKey.trim()}',
        );
      }
      httpRequest.write(
        jsonEncode({
          'model': model.trim(),
          'messages': [
            {'role': 'system', 'content': _systemPrompt(installedModules)},
            {'role': 'user', 'content': request.trim()},
          ],
          'temperature': 0.2,
        }),
      );

      final response = await httpRequest.close().timeout(
        const Duration(seconds: 60),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          '模型服务返回 HTTP ${response.statusCode}: '
          '${body.length > 500 ? body.substring(0, 500) : body}',
        );
      }
      return _parseResponse(body);
    } finally {
      cancellation?.detach();
      client.close(force: true);
    }
  }

  Map<String, Object?> _parseResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('模型响应不是 JSON 对象');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('模型响应缺少 choices');
    }
    final first = choices.first;
    if (first is! Map) {
      throw const FormatException('模型响应 choices 格式错误');
    }
    final message = first['message'];
    if (message is! Map) {
      throw const FormatException('模型响应缺少 message');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('模型没有返回文本内容');
    }

    final moduleJson = _extractJsonObject(content);
    final module = jsonDecode(moduleJson);
    if (module is! Map) {
      throw const FormatException('模型输出不是模块 JSON 对象');
    }
    return module.map((key, value) => MapEntry('$key', value));
  }

  String _extractJsonObject(String content) {
    final text = content.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('模型输出中没有 JSON 对象');
    }
    return text.substring(start, end + 1);
  }

  String _systemPrompt(List<String> installedModules) =>
      '你是序点应用的声明式功能设计器。\n'
      '只输出一个 JSON 对象，不要输出解释或 Markdown。\n'
      'formatVersion 必须为 1。\n'
      'manifest 必须包含 id、version、coreApi。\n'
      '当前可执行资源为 pages、views、fields、templates、rules。\n'
      '页面统一使用客户端设计系统；不要输出颜色、字体、圆角、CSS 或任意视觉样式字段。\n'
      'layouts 必须为空数组或省略。\n'
      'views 的数据源只能是 task.list。\n'
      '模板格式：id/title/tasks，可选 project/parameters；parameters 支持 text/number/boolean/date/datetime/select/multiSelect。\n'
      '模板中可用 \$param.<id> 引用参数；tasks 支持 key/title/parentKey/priority/dueDate/plannedDate/fields。\n'
      '规则格式：id/event/condition/actions；actions 只能调用安全 Command。\n'
      '规则变量可用 \$event.entityId、\$task.*、\$today、\$module.field.<id>。\n'
      '有页面需声明 ui.registry + ui.register；有视图需 tasks.query + tasks.read。\n'
      '规则/模板需 tasks.command；带条件规则还需 tasks.query + tasks.read。\n'
      '允许权限：tasks.read、tasks.write、fields.write、ui.register。\n'
      '禁止生成任意代码、SQL、文件访问、Shell、任意网络请求。\n'
      '模块更新必须提高语义版本号。\n'
      '已安装动态模块：${installedModules.join(', ')}\n'
      '超出能力的需求只生成当前能力可安全表达的部分。';
}
