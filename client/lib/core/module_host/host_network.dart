import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'collection_store.dart';
import 'module_package.dart';

class HostNetwork {
  HostNetwork(this.store, {FlutterSecureStorage? storage})
    : secrets = storage ?? const FlutterSecureStorage();
  final CollectionStore store;
  final FlutterSecureStorage secrets;
  final clients = <String, (ModuleActor, HttpClient)>{};
  final _cancellations = <String, Completer<void>>{};
  final handles = <String, Map<String, Object?>>{};
  Uri validateEndpoint(Object? value) {
    final uri = Uri.parse(string(value, 'endpoint'));
    final loopback = [
      'localhost',
      '127.0.0.1',
      '::1',
    ].contains(uri.host.toLowerCase());
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback))) {
      throw StateError('仅允许 HTTPS 或本机 HTTP 连接');
    }
    return uri;
  }

  Future<String> configure(
    ModuleActor actor,
    String endpoint,
    String key,
  ) async {
    final uri = validateEndpoint(endpoint);
    final id = const Uuid().v4(), alias = 'xudian.module.${actor.moduleId}.$id';
    await secrets.write(key: alias, value: key);
    final metadata = {
      'moduleId': actor.moduleId,
      'endpoint': uri.toString(),
      'alias': alias,
    };
    handles[id] = metadata;
    await store.db.customStatement(
      'INSERT OR REPLACE INTO host_meta VALUES(?,?)',
      ['credential:$id', jsonEncode(metadata)],
    );
    return id;
  }

  Future<void> deleteModuleCredentials(String moduleId) async {
    for (final row in await store.sql(
      "SELECT key,value FROM host_meta WHERE key LIKE 'credential:%'",
    )) {
      final metadata = object(jsonDecode(row['value'] as String));
      if (metadata['moduleId'] != moduleId) continue;
      await secrets.delete(key: metadata['alias'] as String);
      await store.db.customStatement('DELETE FROM host_meta WHERE key=?', [
        row['key'],
      ]);
      handles.remove((row['key'] as String).substring('credential:'.length));
    }
  }

  Future<Map<String, Object?>> metadata(ModuleActor actor, String id) async {
    var m = handles[id];
    if (m == null) {
      final rows = await store.sql('SELECT value FROM host_meta WHERE key=?', [
        'credential:$id',
      ]);
      if (rows.isEmpty) throw StateError('凭据不可用，请重新配置');
      m = object(jsonDecode(rows.single['value'] as String));
      handles[id] = m;
    }
    if (m['moduleId'] != actor.moduleId) {
      throw StateError('Credential belongs to another module');
    }
    return m;
  }

  Future<void> delete(ModuleActor actor, String id) async {
    final m = await metadata(actor, id);
    await secrets.delete(key: m['alias'] as String);
    await store.db.customStatement('DELETE FROM host_meta WHERE key=?', [
      'credential:$id',
    ]);
    handles.remove(id);
  }

  void cancel(ModuleActor actor, String id) {
    final value = clients[id];
    if (value != null && identical(value.$1, actor)) {
      final cancellation = _cancellations.remove(id);
      if (cancellation != null && !cancellation.isCompleted) {
        cancellation.complete();
      }
      value.$2.close(force: true);
      clients.remove(id);
    }
  }

  void revoke(ModuleActor actor) {
    for (final e in clients.entries.toList()) {
      if (identical(e.value.$1, actor)) cancel(actor, e.key);
    }
  }

  void revokeInactive() {
    for (final entry in clients.entries.toList()) {
      if (!store.active(entry.value.$1)) {
        cancel(entry.value.$1, entry.key);
      }
    }
  }

  Future<Object?> request(
    ModuleActor actor,
    Map<String, Object?> options,
  ) async {
    final uri = validateEndpoint(options['url']);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final id = options['id'] as String? ?? const Uuid().v4();
    if (clients.containsKey(id)) throw StateError('Duplicate request id');
    clients[id] = (actor, client);
    final cancellation = Completer<void>();
    _cancellations[id] = cancellation;
    Future<Object?> perform() async {
      final method = options['method'] as String? ?? 'GET';
      if (!['GET', 'POST', 'PUT', 'DELETE', 'PATCH'].contains(method)) {
        throw StateError('Unsupported HTTP method');
      }
      store.requireActive(actor);
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      final headers = object(options['headers'] ?? {});
      for (final header in headers.entries) {
        if ([
          'authorization',
          'proxy-authorization',
          'cookie',
          'host',
        ].contains(header.key.toLowerCase())) {
          throw StateError('Authentication headers are host-owned');
        }
        request.headers.set(header.key, string(header.value, 'header'));
      }
      final credential = options['credential'] as String?;
      if (credential != null) {
        final m = await metadata(actor, credential),
            endpoint = validateEndpoint(m['endpoint']);
        if (uri.origin != endpoint.origin ||
            !(uri.path == endpoint.path ||
                uri.path.startsWith(
                  '${endpoint.path.replaceFirst(RegExp(r"/$"), "")}/',
                ))) {
          throw StateError(
            'Credential destination differs from configured connection',
          );
        }
        String? key;
        try {
          key = await secrets.read(key: m['alias'] as String);
        } catch (_) {
          throw StateError('安全存储读取失败，请重新配置连接');
        }
        if (key == null || key.isEmpty) throw StateError('密钥不可用，请重新配置连接');
        store.requireActive(actor);
        request.headers.set('Authorization', 'Bearer $key');
      }
      final body = options['body'];
      if (body != null) {
        final bytes = utf8.encode(body is String ? body : jsonEncode(body));
        if (bytes.length > 1024 * 1024) {
          throw StateError('Request body exceeds 1 MiB');
        }
        request.headers.contentType = ContentType.json;
        request.add(bytes);
      }
      final bytes = <int>[];
      late HttpClientResponse response;
      await (() async {
        response = await request.close();
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) {
            throw StateError('Response exceeds 1 MiB');
          }
        }
      })().timeout(const Duration(seconds: 30));
      store.requireActive(actor);
      return {
        'id': id,
        'status': response.statusCode,
        'body': utf8.decode(bytes),
      };
    }

    try {
      return await Future.any<Object?>([
        perform().timeout(const Duration(seconds: 60)),
        cancellation.future.then(
          (_) => throw HttpException('Request cancelled', uri: uri),
        ),
      ]);
    } finally {
      client.close(force: true);
      if (identical(clients[id]?.$2, client)) clients.remove(id);
      if (identical(_cancellations[id], cancellation)) {
        _cancellations.remove(id);
      }
    }
  }

  void close() {
    for (final entry in clients.entries.toList()) {
      cancel(entry.value.$1, entry.key);
    }
    clients.clear();
  }
}
