import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_browser.dart';
import 'package:task_app/core/ui/ui_design.dart';

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

  for (final brightness in Brightness.values) {
    test('native appearance uses trusted $brightness host colors', () async {
      final theme = AppDesign.theme(brightness);
      final appearance = HostBrowserAppearance.fromTheme(theme);
      final browser = HostBrowser(channel: channel, available: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final request = call.arguments as Map;
            expect(request['appearance'], {
              'dark': brightness == Brightness.dark,
              'canvas': theme.scaffoldBackgroundColor.toARGB32(),
              'surface': theme.colorScheme.surface.toARGB32(),
              'text': theme.colorScheme.onSurface.toARGB32(),
              'muted': theme.colorScheme.onSurfaceVariant.toARGB32(),
              'primary': theme.colorScheme.primary.toARGB32(),
              'onPrimary': theme.colorScheme.onPrimary.toARGB32(),
              'input': theme.colorScheme.surfaceContainerLow.toARGB32(),
              'outline': theme.colorScheme.outlineVariant.toARGB32(),
              'error': theme.colorScheme.error.toARGB32(),
              'controlRadius': AppDesign.controlRadius,
              'dialogRadius': AppDesign.floatingRadius,
            });
            expect(request['url'], args['url']);
            expect(request['script'], args['script']);
            return null;
          });
      await browser.capture(actor, {
        ...args,
        'appearance': {'dark': brightness != Brightness.dark},
      }, appearance: appearance);
    });
  }

  for (final mode in ThemeMode.values) {
    for (final systemBrightness in Brightness.values) {
      testWidgets('browser resolves $mode with system $systemBrightness', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            systemBrightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final actual = mode == ThemeMode.system
            ? systemBrightness
            : mode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(
                (call.arguments as Map)['appearance']['dark'],
                actual == Brightness.dark,
              );
              return null;
            });
        Future<Object?>? captured;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme(Brightness.light),
            darkTheme: AppDesign.theme(Brightness.dark),
            themeMode: mode,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => captured =
                    HostBrowser(channel: channel, available: true).capture(
                      actor,
                      args,
                      appearance: HostBrowserAppearance.fromTheme(
                        Theme.of(context),
                      ),
                    ),
                child: const Text('打开浏览器'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开浏览器'));
        await tester.pump();
        await captured;
      });
    }
  }
}
