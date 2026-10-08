import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class AiRequestCancellation {
  HttpClient? _client;
  void Function()? _onCancel;
  bool _cancelled = false;
  bool get cancelled => _cancelled;

  void attach(HttpClient client, {void Function()? onCancel}) {
    if (_cancelled) {
      client.close(force: true);
      throw StateError('AI request was cancelled');
    }
    if (_client != null) {
      throw StateError('Cancellation is already attached to an AI request');
    }
    _client = client;
    _onCancel = onCancel;
  }

  void detach([HttpClient? client]) {
    if (client == null || identical(_client, client)) {
      _client = null;
      _onCancel = null;
    }
  }

  void cancel() {
    _cancelled = true;
    final client = _client;
    final onCancel = _onCancel;
    detach();
    if (onCancel != null) {
      onCancel();
    } else {
      client?.close(force: true);
    }
  }
}

class OpenAiCompatibleProvider {
  const OpenAiCompatibleProvider({
    this.httpClientFactory,
    this.totalTimeout = const Duration(seconds: 60),
    this.connectTimeout = const Duration(seconds: 10),
    this.bodyTimeout = const Duration(seconds: 30),
    this.maxResponseBytes = 1024 * 1024,
  });

  final HttpClient Function()? httpClientFactory;
  final Duration totalTimeout;
  final Duration connectTimeout;
  final Duration bodyTimeout;
  final int maxResponseBytes;

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
    return requestChatCompletion(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      messages: [
        {'role': 'system', 'content': _systemPrompt(installedModules)},
        {'role': 'user', 'content': request.trim()},
      ],
      temperature: 0.2,
      parseResponse: _parseResponse,
      cancellation: cancellation,
    );
  }

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
    if (!acceptsEndpoint(endpoint)) {
      throw ArgumentError('模型端点必须使用 HTTPS；本机地址可使用 HTTP');
    }
    if (model.trim().isEmpty) {
      throw ArgumentError('模型名称不能为空');
    }
    if (totalTimeout <= Duration.zero ||
        connectTimeout <= Duration.zero ||
        bodyTimeout <= Duration.zero ||
        maxResponseBytes <= 0) {
      throw ArgumentError('Network bounds must be positive');
    }
    if (cancellation?.cancelled ?? false) {
      throw StateError('AI request was cancelled');
    }

    final client = httpClientFactory?.call() ?? HttpClient();
    final stopped = Completer<Never>();
    stopped.future.ignore();
    HttpClientRequest? activeRequest;
    StreamSubscription<List<int>>? bodySubscription;
    Timer? phaseTimer;
    var cleanedUp = false;
    var succeeded = false;

    void cleanup() {
      if (cleanedUp) return;
      cleanedUp = true;
      phaseTimer?.cancel();
      if (!succeeded) activeRequest?.abort();
      final subscription = bodySubscription;
      if (subscription != null) unawaited(subscription.cancel());
      cancellation?.detach(client);
      client.close(force: true);
    }

    void stop(Object error) {
      if (!stopped.isCompleted) stopped.completeError(error);
      cleanup();
    }

    Future<AwaitedValue> waitFor<AwaitedValue>(Future<AwaitedValue> future) =>
        Future.any<AwaitedValue>([future, stopped.future]);

    final totalTimer = Timer(
      totalTimeout,
      () => stop(TimeoutException('AI request total timeout', totalTimeout)),
    );
    try {
      cancellation?.attach(
        client,
        onCancel: () => stop(StateError('AI request was cancelled')),
      );
      phaseTimer = Timer(
        connectTimeout,
        () => stop(
          TimeoutException('AI request connect timeout', connectTimeout),
        ),
      );
      final httpRequest = await waitFor(
        client.postUrl(endpoint).then((connectedRequest) {
          if (cleanedUp) {
            connectedRequest.abort();
          } else {
            activeRequest = connectedRequest;
          }
          return connectedRequest;
        }),
      );
      phaseTimer.cancel();
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
          'messages': messages,
          'temperature': ?temperature,
          if (tools != null && tools.isNotEmpty) 'tools': tools,
          'tool_choice': ?toolChoice,
        }),
      );

      final response = await waitFor(httpRequest.close());
      final bodyBytes = BytesBuilder(copy: false);
      final bodyComplete = Completer<List<int>>();
      phaseTimer = Timer(
        bodyTimeout,
        () => stop(TimeoutException('AI response body timeout', bodyTimeout)),
      );
      bodySubscription = response.listen(
        (chunk) {
          if (bodyComplete.isCompleted) return;
          if (chunk.length > maxResponseBytes - bodyBytes.length) {
            bodyComplete.completeError(
              StateError('模型响应超过 $maxResponseBytes 字节限制'),
            );
            return;
          }
          bodyBytes.add(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!bodyComplete.isCompleted) {
            bodyComplete.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!bodyComplete.isCompleted) {
            bodyComplete.complete(bodyBytes.takeBytes());
          }
        },
        cancelOnError: true,
      );
      final bytes = await waitFor(bodyComplete.future);
      final body = utf8.decode(bytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          '模型服务返回 HTTP ${response.statusCode}: '
          '${body.length > 500 ? body.substring(0, 500) : body}',
        );
      }
      final result = parseResponse(body);
      succeeded = true;
      return result;
    } finally {
      totalTimer.cancel();
      cleanup();
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
      'formatVersion 只支持 1 或 2：普通任务视图使用 1，页面槽位或组合挂载使用 2。\n'
      '顶层仅允许 formatVersion、manifest、pages、views、fields、templates、rules、layouts。资源数组可省略。\n'
      'manifest 必须包含 id、version、coreApi。\n'
      'manifest 还可包含 dependencies、requiresCapabilities、permissions，均为不重复字符串数组。\n'
      '模块 id 使用小写点分命名如 app.sample.module；version 使用三段语义版本，coreApi 为 "1"。\n'
      '所有资源 id 和槽位 id 都是局部 ID：小写字母开头，后续为字母、数字、下划线或连字符，不含点。\n'
      '同类资源 id 不重复；v2 所有页面 entry 的 id 与 layouts 的 id 也不能重复。\n'
      '页面统一使用客户端设计系统；不要输出颜色、字体、圆角、CSS 或任意视觉样式字段。\n'
      'v1：pages 使用 id/title/view，可选 icon/selectedIcon/quickAdd/quickAddDefaults，所有页面进入主导航。\n'
      'v1 不支持槽位和容器，layouts 必须为空数组或省略。\n'
      'v2：必须声明 requiresCapabilities 包含 ui.composition、ui.registry，permissions 包含 ui.register。\n'
      'v2 pages 只允许 id/title/kind/view/icon/selectedIcon/quickAdd/quickAddDefaults/slots/requiredContext/retainPosition/entry。\n'
      'kind 为 view（默认）或 container；view 页必须引用本模块 views 的局部 id，container 页不得提供 view。\n'
      'requiredContext 是不重复数组，仅允许 taskId、projectId；retainPosition 是布尔值，默认 false。\n'
      'slots 是数组，每项只允许 id/label/kind/public/editable/capacity/requiredContext。id/label 必填。\n'
      '槽位 kind 为 entries（默认）、tabs、sections；public 默认 false，editable 默认 true，capacity 可选正整数。\n'
      '槽位 requiredContext 同样仅支持 taskId/projectId。只有 public:true 的槽位可接受其他模块贡献。\n'
      'v2 仅显式 entry 对象才生成页面入口；省略、null 或 false 全部不注册入口，不自动进入主导航。\n'
      'entry:{} 显式生成默认主导航入口；无入口的页面仍可由 layouts 提供挂载贡献。\n'
      'entry 对象只允许 id/label/opening/placement/content/targetPageId/slotId/order；id 默认页面局部 id，label 默认 title。\n'
      'opening 为 workspace（默认）、detail、adaptivePanel；placement 为 main（默认）、header、more、settings、hidden、page。\n'
      'content 是布尔值默认 false，order 是整数默认 0。placement:page 必须提供 targetPageId 和 slotId。\n'
      'entry.targetPageId 指宿主页面，不是要打开的页面；entry 自身始终打开所属页面。\n'
      'layouts 每项只允许 id/pageId/label/content/opening/placement/hostPageId/slotId/order；id/pageId/label 必填。\n'
      'layout.pageId 指要打开或嵌入的内容页面；placement:page 时 hostPageId 与 slotId 必填。其余默认值与 entry 一致。\n'
      '页面引用用本模块局部 id 或完全限定 ID（moduleId.pageId）；跨模块完全限定 ID 原样保留。\n'
      'content:true 仅允许 placement:page 且目标槽位为 tabs/sections；entries 槽位必须 content:false。\n'
      '非 page placement 不得提供宿主页或 slotId；不得向私有跨模块槽位挂载，不能臆造未提供的宿主页与槽位 ID。\n'
      '宿主上下文只读传递，不继承宿主权限。task.list 在传入 taskId/projectId 时与原 filter 做 all 交集。\n'
      '上下文缺失或数据失效时显示失效提示，不查询整个任务列表，不继续显示上一个上下文的数据。\n'
      '组合示例：pages:[{"id":"home","title":"首页","kind":"container","entry":{},"slots":[{"id":"body","label":"内容","kind":"tabs","public":true}]},'
      '{"id":"tasks","title":"任务","view":"list","entry":false}],'
      'views:[{"id":"list","source":"task.list"}],'
      'layouts:[{"id":"taskTab","pageId":"tasks","label":"任务","content":true,"placement":"page","hostPageId":"home","slotId":"body"}]。\n'
      'views 的数据源只能是 task.list。\n'
      'views 使用 id/source，可选 filter/showFields/emptyText；filter 支持 all/any 数组、not 对象，叶子为 field/op/value。\n'
      'filter 的 op 为 eq/ne/isNull/notNull/lt/lte/gt/gte/contains，日期可用 "\$today"；本地自定义字段用 fields.<id>。\n'
      'fields 使用 id/label/type，可选 config；type 为 text/number/boolean/date/datetime/select/multiSelect。\n'
      'select/multiSelect 必须提供 config.options 为非空、不重复字符串数组。\n'
      '模板格式：id/title/tasks，可选 project/parameters；parameters 支持 text/number/boolean/date/datetime/select/multiSelect。\n'
      '模板中可用 \$param.<id> 引用参数；tasks 支持 key/title/parentKey/priority/dueDate/plannedDate/fields。\n'
      '规则格式：id/event/condition/actions；actions 只能调用安全 Command。\n'
      '规则变量可用 \$event.entityId、\$task.*、\$today、\$module.field.<id>。\n'
      '有页面需声明 ui.registry + ui.register；有视图需 tasks.query + tasks.read。\n'
      '规则/模板需 tasks.command；带条件规则还需 tasks.query + tasks.read。\n'
      '允许权限：tasks.read、tasks.write、fields.write、ui.register。\n'
      '禁止生成任意代码、SQL、文件访问、Shell、任意网络请求。\n'
      '模块更新必须提高语义版本号。\n'
      '生成结果仅供变更审核，必须由用户确认后安装，不得假定已应用布局或已获得新权限。\n'
      '已安装动态模块：${installedModules.join(', ')}\n'
      '超出能力的需求只生成当前能力可安全表达的部分。';
}
