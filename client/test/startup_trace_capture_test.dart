import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/performance/startup_trace_capture.dart';
import 'package:task_app/core/performance/ui_load_trace.dart';

void main() {
  test(
    'capture aggregates phases, omits private inputs and closes once',
    () async {
      final reports = <Map<String, Object>>[];
      final capture = StartupTraceCapture(
        enabled: true,
        report: (value) async {
          reports.add(value);
        },
      );
      capture.run(() {
        for (var i = 0; i < 2; i++) {
          UiLoadTrace.instant(
            'host.worker.load',
            arguments: {
              'moduleId': 'app.test',
              'worker': 'workflow',
              'input': 'private',
            },
          );
        }
        UiLoadTrace.instant('page.bridge', arguments: {'input': 'private'});
        capture.finish('ready');
        UiLoadTrace.instant('host.worker.load');
        capture.finish('ready');
      });
      await Future<void>.delayed(Duration.zero);
      expect(reports, hasLength(1));
      final phases = reports.single['phases'] as List;
      expect(phases, hasLength(1));
      expect(phases.single, containsPair('count', 2));
      expect(phases.single, containsPair('moduleId', 'app.test'));
      expect(reports.toString(), isNot(contains('private')));
    },
  );

  test('capture bounds groups and diagnostic failures do not escape', () async {
    Map<String, Object>? report;
    final capture = StartupTraceCapture(
      enabled: true,
      report: (value) async {
        report = value;
        throw StateError('unavailable');
      },
    );
    capture.run(() {
      for (var i = 0; i < 150; i++) {
        UiLoadTrace.instant(
          'host.package.verify',
          arguments: {'moduleId': 'test.module$i'},
        );
      }
      capture.finish('restoreError');
    });
    await Future<void>.delayed(Duration.zero);
    expect(report!['outcome'], 'restoreError');
    expect(
      report!['phases'] as List,
      hasLength(StartupTraceCapture.maximumGroups),
    );
  });

  test('disabled capture runs body without producing a report', () {
    var calls = 0;
    final capture = StartupTraceCapture(
      enabled: false,
      report: (_) async {
        calls++;
      },
    );
    expect(capture.run(() => 42), 42);
    capture.finish('ready');
    expect(calls, 0);
  });
}
