import 'dart:async';
import 'dart:convert';
import 'dart:io';

void emit(Map<String, Object?> event) => stdout.writeln(jsonEncode(event));

Future<void> main(List<String> arguments) async {
  final scenario = arguments.single;
  if (scenario == 'blocked bind') {
    // Models a synchronous native call that cannot run an in-process timer.
    sleep(const Duration(minutes: 1));
    return;
  }
  if (![
    'credentials',
    'redirect and large',
    'pending',
    'ai',
  ].contains(scenario)) {
    throw ArgumentError.value(scenario, 'scenario', 'Unknown HTTP fixture');
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  emit({'event': 'ready', 'port': server.port});
  await for (final request in server) {
    final body = await utf8.decoder.bind(request).join();
    emit({
      'event': 'request',
      'method': request.method,
      'path': request.uri.path,
      'authorization': request.headers.value(HttpHeaders.authorizationHeader),
      'body': body,
    });
    final response = request.response;
    response.done.ignore();
    if (scenario == 'pending') continue;
    if (scenario == 'redirect and large') {
      if (request.uri.path == '/redirect') {
        response.statusCode = 302;
        response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${server.port}/target',
        );
      } else if (request.uri.path == '/large') {
        response.add(List.filled(1024 * 1024 + 1, 65));
      }
    } else if (scenario == 'ai') {
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode(
          request.method == 'GET'
              ? {
                  'data': [
                    {'id': 'second'},
                    {'id': 'first'},
                    {'id': 'first'},
                    {'id': ''},
                    null,
                  ],
                }
              : {
                  'choices': [
                    {
                      'message': {'role': 'assistant', 'content': 'OK'},
                    },
                  ],
                },
        ),
      );
    } else {
      response.write('{"ok":true}');
    }
    try {
      await response.close();
    } on IOException {
      // A size-limit rejection or cancellation can close the client first.
    }
  }
}
