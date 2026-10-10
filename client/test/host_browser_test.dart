import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.browser');
  final actor = ModuleActor('test.importer', '1.0.0', 'test', 1, {
    'browser.capture',
  });
  final args = {'url': 'https://school.example/login', 'script': 'capture()'};
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('validates URL and bounded script before opening native browser', () {
    for (final url in [
      'file:///tmp/test',
      'javascript:alert(1)',
      'https://user:pass@school.example',
    ]) {
      expect(
        () => HostBrowser.validate({...args, 'url': url}),
        throwsFormatException,
      );
    }
    expect(
      () => HostBrowser.validate({...args, 'script': '中' * 90000}),
      throwsFormatException,
    );
    expect(HostBrowser.validate(args)['url'], args['url']);
  });
  test(
    'cancel returns null; native data is decoded without adding credentials',
    () async {
      final browser = HostBrowser(channel: channel, available: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'capture');
            expect((call.arguments as Map)['moduleId'], actor.moduleId);
            return jsonEncode({'courses': []});
          });
      expect(await browser.capture(actor, args), {'courses': []});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      expect(await browser.capture(actor, args), isNull);
    },
  );
  test(
    'unsupported platforms and malformed native payloads are explicit',
    () async {
      await expectLater(
        HostBrowser(channel: channel, available: false).capture(actor, args),
        throwsUnsupportedError,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => '[]');
      await expectLater(
        HostBrowser(channel: channel, available: true).capture(actor, args),
        throwsFormatException,
      );
    },
  );
}
