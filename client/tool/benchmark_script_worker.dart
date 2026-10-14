import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xquickjs/xquickjs.dart';

// Local real-engine microbenchmark, not an Android startup benchmark.
// Run from client: dart run tool/benchmark_script_worker.dart [runs]
Future<void> main(List<String> args) async {
  final runs = args.isEmpty ? 30 : int.parse(args.single);
  if (runs < 1 || runs > 1000) throw ArgumentError('Runs must be 1..1000');
  final samples = <Map<String, int>>[];
  var timers = 0;
  await runZoned(
    () async {
      for (var trial = 0; trial < runs; trial++) {
        final watch = Stopwatch()..start();
        final worker = JavaScriptWorker({
          'main.js': '''
import {clock} from '@xudian/sdk';
const initial = await clock.now();
export async function chain() {
  let value = 0;
  for (let i = 0; i < 12; i++) value += await clock.now();
  return value;
}
''',
        }, host: (_, _) async => 1);
        try {
          await worker.load('main.js');
          final loadMicros = watch.elapsedMicroseconds;
          watch.reset();
          if (await worker.invoke('chain', {}) != 12) {
            throw StateError('Incorrect host bridge result');
          }
          samples.add({
            'loadMicros': loadMicros,
            'chainMicros': watch.elapsedMicroseconds,
          });
        } finally {
          worker.close();
        }
      }
      final worker = JavaScriptWorker({
        'main.js': 'export function value(){return 1;}',
      }, host: (_, _) async => null);
      try {
        await worker.load('main.js');
        final before = timers;
        await Future<void>.delayed(const Duration(seconds: 1));
        // Exclude this benchmark's one-second waiting timer.
        final idleTimers = timers - before - 1;
        final summary = <String, Object>{};
        for (final key in ['loadMicros', 'chainMicros']) {
          final values = samples.map((s) => s[key]!).toList()..sort();
          summary[key] = {
            'p50': values[(runs - 1) ~/ 2],
            'p95': values[(runs * 0.95).ceil() - 1],
          };
        }
        stdout.writeln(
          jsonEncode({
            'runs': runs,
            'measurement': 'Linux real QuickJS; excludes app/engine startup',
            'percentileMethod': 'nearest rank',
            'summary': summary,
            'idleWorkerTimersPerSecond': idleTimers,
            'samples': samples,
          }),
        );
      } finally {
        worker.close();
      }
    },
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        timers++;
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );
}
