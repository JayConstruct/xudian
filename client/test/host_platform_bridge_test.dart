import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/host_platform_bridge.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_browser.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/core/ui/ui_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const filesChannel = MethodChannel('test.platform.files');
  const browserChannel = MethodChannel('test.platform.browser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late ModuleActor actor;
  late HostPlatformBridge bridge;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    await db.customSelect('SELECT 1').get();
    directory = await Directory.systemTemp.createTemp('platform-bridge-');
    host = ModuleHost(store: store, directory: directory);
    actor = ModuleActor('test.platform', '1.0.0', 'platform', 1, {});
    store.activate(actor);
    bridge = HostPlatformBridge(
      store,
      browser: HostBrowser(channel: browserChannel, available: true),
      filesChannel: filesChannel,
      android: true,
    )..attach(host);
  });

  tearDown(() async {
    bridge.close();
    messenger.setMockMethodCallHandler(filesChannel, null);
    messenger.setMockMethodCallHandler(browserChannel, null);
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'endpoint validation precedes the prompt and erasure deletes secrets',
    () async {
      var prompted = false;
      await expectLater(
        bridge.configureSecret(actor, 'http://school.example', (_) async {
          prompted = true;
          return 'secret';
        }),
        throwsStateError,
      );
      expect(prompted, false);
      final handle = await bridge.configureSecret(
        actor,
        'https://school.example/v1',
        (endpoint) async {
          expect(endpoint.toString(), 'https://school.example/v1');
          return 'secret';
        },
      );
      expect(handle, isNotEmpty);
      expect(await const FlutterSecureStorage().readAll(), hasLength(1));
      await host.onDeleteData!(actor.moduleId);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
      expect(
        await store.sql(
          "SELECT key FROM host_meta WHERE key LIKE 'credential:%'",
        ),
        isEmpty,
      );
    },
  );

  for (final response in [null, 'late-secret']) {
    test('deactivation during the secret prompt rejects $response', () async {
      final prompted = Completer<void>();
      final result = Completer<String?>();
      final work = bridge.configureSecret(actor, 'https://school.example/v1', (
        _,
      ) {
        prompted.complete();
        return result.future;
      });
      final rejected = expectLater(work, throwsStateError);
      await prompted.future;
      store.deactivate(actor.moduleId);
      host.onDeactivate!(actor);
      result.complete(response);
      await rejected;
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    });
  }

  test(
    'closing the bridge prevents a pending prompt from storing credentials',
    () async {
      final result = Completer<String?>();
      final work = bridge.configureSecret(
        actor,
        'https://school.example/v1',
        (_) => result.future,
      );
      final rejected = expectLater(work, throwsStateError);
      bridge.close();
      result.complete('late-secret');
      await rejected;
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    },
  );

  test(
    'module revocation cancels the browser and close detaches callbacks',
    () async {
      final captured = Completer<void>();
      final result = Completer<String?>();
      var cancelled = false;
      messenger.setMockMethodCallHandler(browserChannel, (call) async {
        if (call.method == 'capture') {
          captured.complete();
          return result.future;
        }
        expect(call.method, 'cancel');
        cancelled = true;
        result.complete(null);
        return null;
      });
      final capture = bridge.invoke(actor, 'browser.capture', {
        'url': 'https://school.example',
        'script': 'capture()',
      });
      await captured.future;
      host.onDeactivate!(actor);
      expect(await capture, isNull);
      expect(cancelled, true);
      bridge.close();
      expect(host.onDeactivate, isNull);
      expect(host.onDeleteData, isNull);
      await expectLater(
        bridge.invoke(actor, 'http.cancel', {'id': 'unused'}),
        throwsStateError,
      );
    },
  );

  test('close retains lifecycle callbacks installed by a subsequent owner', () {
    void deactivate(ModuleActor caller) {}
    Future<void> deleteData(String moduleId) async {}
    host.onDeactivate = deactivate;
    host.onDeleteData = deleteData;
    bridge.close();
    expect(host.onDeactivate, same(deactivate));
    expect(host.onDeleteData, same(deleteData));
  });

  test(
    'native export preserves cancellation and enforces the UTF-8 byte limit',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(filesChannel, (call) async {
        calls++;
        expect(call.method, 'saveText');
        expect(call.arguments, {'name': 'export.json', 'text': '内容'});
        return calls == 1 ? null : true;
      });
      final args = {'name': 'export.json', 'text': '内容'};
      expect(await bridge.invoke(actor, 'files.saveText', args), false);
      expect(await bridge.invoke(actor, 'files.saveText', args), true);
      await expectLater(
        bridge.invoke(actor, 'files.saveText', {...args, 'text': '中' * 700000}),
        throwsStateError,
      );
      expect(calls, 2);
      await expectLater(
        bridge.invoke(actor, 'ui.review', {}),
        throwsStateError,
      );
    },
  );

  test('browser gets current host theme on every capture', () async {
    final requests = <Map>[];
    messenger.setMockMethodCallHandler(browserChannel, (call) async {
      requests.add((call.arguments as Map)['appearance'] as Map);
      return null;
    });
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final theme = AppDesign.theme(brightness)
          .copyWith(scaffoldBackgroundColor: const Color(0xff123456));
      await bridge.invoke(actor, 'browser.capture', {
        'url': 'https://school.example',
        'script': 'capture()',
        'appearance': {'dark': brightness != Brightness.dark},
      }, browserTheme: theme);
      expect(requests.last['dark'], brightness == Brightness.dark);
      expect(requests.last['canvas'], 0xff123456);
      expect(requests.last['primary'], theme.colorScheme.primary.toARGB32());
    }
  });
}
