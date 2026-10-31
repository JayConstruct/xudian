import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_network.dart';
import 'package:task_app/data/app_database.dart';

import 'support/local_http_server.dart';

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
  LocalHttpServer? server;
  late ModuleActor actor;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    await db.customSelect('SELECT 1').get();
    actor = ModuleActor('test.network', '1.0.0', 'network', 1, {});
    store.activate(actor);
    network = HostNetwork(store);
    server = null;
  });
  tearDown(() async {
    network.close();
    await server?.close();
    await store.close();
    await db.close();
  });
  Future<void> startServer(String scenario) async {
    server = LocalHttpServer(scenario);
    await server!.start();
  }
  String endpoint([String path = '/v1']) => server!.endpoint(path);
  Future<Object?> request(Map<String, Object?> input) =>
      HttpOverrides.runWithHttpOverrides(
        () => network.request(actor, input),
        _RealHttp(),
      );
  test('credential is an opaque owner-bound handle and authentication is injected only at its endpoint', () async {
    await startServer('credentials');
    final handle = await network.configure(actor, endpoint(), 'secret-value');
    final result = await request({
      'url': endpoint('/v1/chat/completions'),
      'credential': handle,
    });
    await server!.waitForRequests(1);
    expect(server!.requests.single['authorization'], 'Bearer secret-value');
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
    await startServer('redirect and large');
    final response = await request({'url': endpoint('/redirect')});
    expect((response as Map)['status'], 302);
    await expectLater(request({'url': endpoint('/large')}), throwsStateError);
    await server!.waitForRequests(2);
    expect(server!.requests.map((r) => r['path']), ['/redirect', '/large']);
    expect(
      () => network.validateEndpoint('http://example.com/v1'),
      throwsStateError,
    );
  });
  test(
    'explicit cancel and module revocation close pending requests',
    () async {
      await startServer('pending');
      var work = request({'id': 'first', 'url': endpoint()});
      var rejected = expectLater(work, throwsException);
      await server!.waitForRequests(1);
      network.cancel(actor, 'first');
      await rejected;
      work = request({'id': 'second', 'url': endpoint()});
      rejected = expectLater(work, throwsException);
      await server!.waitForRequests(2);
      store.deactivate(actor.moduleId);
      network.revokeInactive();
      await rejected;
      expect(network.clients, isEmpty);
    },
  );
}
