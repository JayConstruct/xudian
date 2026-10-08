import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_network.dart';
import 'package:task_app/data/app_database.dart';

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late HostNetwork network;
  late HttpServer server;
  late ModuleActor actor;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    await db.customSelect('SELECT 1').get();
    actor = ModuleActor('test.network', '1.0.0', 'network', 1, {});
    store.activate(actor);
    network = HostNetwork(store);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    network.close();
    await server.close(force: true);
    await store.close();
    await db.close();
  });
  String endpoint([String path = '/v1']) =>
      'http://127.0.0.1:${server.port}$path';
  Future<Object?> request(Map<String, Object?> input) =>
      HttpOverrides.runWithHttpOverrides(
        () => network.request(actor, input),
        _RealHttp(),
      );
  test('credential is an opaque owner-bound handle and authentication is injected only at its endpoint', () async {
    final handle = await network.configure(actor, endpoint(), 'secret-value');
    String? auth;
    server.listen((request) async {
      auth = request.headers.value('authorization');
      request.response.write('{"ok":true}');
      await request.response.close();
    });
    final result = await request({
      'url': endpoint('/v1/chat/completions'),
      'credential': handle,
    });
    expect(auth, 'Bearer secret-value');
    expect(result.toString(), isNot(contains('secret-value')));
    final other = ModuleActor('test.other', '1.0.0', 'other', 1, {});
    store.activate(other);
    await expectLater(network.metadata(other, handle), throwsStateError);
    await expectLater(
      request({'url': endpoint('/different'), 'credential': handle}),
      throwsStateError,
    );
    await expectLater(
      request({
        'url': endpoint(),
        'headers': {'Authorization': 'manual'},
      }),
      throwsStateError,
    );
    await network.delete(actor, handle);
    await expectLater(network.metadata(actor, handle), throwsStateError);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
  test('redirects are not followed and oversized responses reject', () async {
    var destinationReached = false;
    server.listen((req) async {
      if (req.uri.path == '/redirect') {
        req.response.statusCode = 302;
        req.response.headers.set('location', endpoint('/target'));
      } else if (req.uri.path == '/target') {
        destinationReached = true;
      } else {
        req.response.add(List.filled(1024 * 1024 + 1, 65));
      }
      try {
        await req.response.close();
      } catch (_) {}
    });
    final response = await request({'url': endpoint('/redirect')});
    expect((response as Map)['status'], 302);
    expect(destinationReached, false);
    await expectLater(request({'url': endpoint('/large')}), throwsStateError);
    expect(
      () => network.validateEndpoint('http://example.com/v1'),
      throwsStateError,
    );
  });
  test(
    'explicit cancel and module revocation close pending requests',
    () async {
      final arrivals = <Completer<void>>[Completer(), Completer()];
      var next = 0;
      server.listen((req) {
        arrivals[next++].complete();
      });
      var work = request({'id': 'first', 'url': endpoint()});
      var rejected = expectLater(work, throwsException);
      await arrivals[0].future.timeout(const Duration(seconds: 5));
      network.cancel(actor, 'first');
      await rejected;
      work = request({'id': 'second', 'url': endpoint()});
      rejected = expectLater(work, throwsException);
      await arrivals[1].future.timeout(const Duration(seconds: 5));
      store.deactivate(actor.moduleId);
      network.revokeInactive();
      await rejected;
      expect(network.clients, isEmpty);
    },
  );
}
