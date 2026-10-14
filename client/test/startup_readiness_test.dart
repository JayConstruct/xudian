import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/performance/startup_readiness.dart';
import 'package:task_app/core/performance/ui_load_trace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'shell failure closes readiness without reporting fully drawn',
    () async {
      for (final outcome in ['restoreError', 'noWorkspace']) {
        final samples = <UiLoadSample>[];
        final unavailable = <String>[];
        var reports = 0;
        await UiLoadTrace.observe(() async {
          final readiness = AppStartupReadiness(
            reportFullyDrawn: () async => reports++,
            reportUnavailable: (value) async => unavailable.add(value),
          )..start();
          readiness.unavailable(outcome);
          readiness.unavailable(outcome);
          readiness.workspaceReady();
          await Future<void>.delayed(Duration.zero);
        }, samples.add);
        expect(reports, 0);
        expect(unavailable, [outcome]);
        expect(samples.single.name, 'app.workspaceReady');
        expect(samples.single.arguments, {'outcome': outcome});
      }
    },
  );

  test(
    'one launch records first paint and workspace separately, reports once',
    () async {
      final samples = <UiLoadSample>[];
      var reports = 0;
      await UiLoadTrace.observe(() async {
        final readiness = AppStartupReadiness(
          reportFullyDrawn: () async {
            reports++;
          },
        );
        readiness.workspaceReady();
        expect(reports, 0);
        readiness.start();
        readiness.start();
        readiness.firstFrame();
        readiness.firstFrame();
        expect(samples.map((s) => s.name), ['app.firstFrame']);
        expect(reports, 0);
        readiness.workspaceReady();
        readiness.workspaceReady();
        await Future<void>.delayed(Duration.zero);
      }, samples.add);
      expect(samples.map((s) => s.name), [
        'app.firstFrame',
        'app.workspaceReady',
      ]);
      expect(samples.last.arguments, {'outcome': 'ready'});
      expect(reports, 1);
    },
  );

  test(
    'diagnostic platform errors never change successful readiness',
    () async {
      final samples = <UiLoadSample>[];
      await UiLoadTrace.observe(() async {
        final readiness = AppStartupReadiness(
          reportFullyDrawn: () => throw StateError('unavailable'),
        );
        readiness.start();
        readiness.firstFrame();
        readiness.workspaceReady();
        await Future<void>.delayed(Duration.zero);
      }, samples.add);
      expect(samples.last.arguments, {'outcome': 'ready'});
    },
  );

  test('Android fully drawn channel is called with no page data', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    const channel = MethodChannel('xudian.host/startup');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final readiness = AppStartupReadiness()..start();
    readiness.firstFrame();
    readiness.workspaceReady();
    await Future<void>.delayed(Duration.zero);
    expect(calls.single.method, 'reportFullyDrawn');
    expect(calls.single.arguments, isNull);
  });
}
