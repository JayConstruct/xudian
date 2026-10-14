// Run from client: flutter test tool/benchmark_module_package.dart --no-pub
// This benchmark performs full verification on every iteration. Its Linux CPU
// time measures this test process only; it is not a device startup benchmark.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/module_package.dart';

int? cpuTicks() {
  if (!Platform.isLinux) return null;
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return int.parse(fields[11]) + int.parse(fields[12]);
}

Future<Map<String, Object?>> measure(
  String name,
  Future<void> Function() operation, {
  int iterations = 40,
}) async {
  for (var i = 0; i < 8; i++) {
    await operation();
  }
  final samples = <int>[];
  final cpuStart = cpuTicks();
  for (var i = 0; i < iterations; i++) {
    final watch = Stopwatch()..start();
    await operation();
    samples.add(watch.elapsedMicroseconds);
  }
  final cpuEnd = cpuTicks();
  samples.sort();
  return {
    'name': name,
    'iterations': iterations,
    'p50Us': samples[(samples.length - 1) ~/ 2],
    'p95Us': samples[((samples.length - 1) * .95).ceil()],
    'totalUs': samples.fold<int>(0, (a, b) => a + b),
    'cpuTicks': cpuStart == null ? null : cpuEnd! - cpuStart,
  };
}

void main() {
  test(
    'full package verification and activation preparation microbenchmark',
    () async {
      final catalog = jsonDecode(
        File('assets/modules/catalog.json').readAsStringSync(),
      ) as List;
      final defaults = <({Uint8List bytes, String sha256})>[
        for (final entry in catalog)
          if (entry['default'] == true)
            (
              bytes: File(entry['asset'] as String).readAsBytesSync(),
              sha256: entry['sha256'] as String,
            ),
      ];
      final synthetic = await ScriptPackage.build(
        {
          'formatVersion': 3,
          'manifest': {
            'id': 'test.benchmark',
            'version': '1.0.0',
            'hostApi': '^1.0.0',
            'dataVersion': 1,
            'permissions': [],
            'dependencies': [],
          },
          'entryPoint': 'main.js',
          'collections': [],
          'services': [],
          'pages': [],
        },
        {
          for (final name in ['main.js', 'a.js', 'b.js', 'c.js'])
            name:
                '// ${List.filled(44000, '模块').join()}\nexport const value=1;',
        },
      );
      final syntheticDigest = await digest(synthetic);
      Future<void> verifyDefaults({bool prepare = false}) async {
        for (final entry in defaults) {
          final verified = await ScriptPackage.verify(
            entry.bytes,
            preinstalledDigest: entry.sha256,
          );
          if (prepare) {
            final restored = verified.withStoredOrigin('preinstalled');
            expect(
              restored.scripts.keys,
              contains(restored.definition['entryPoint']),
            );
            expect(restored.scripts, isNotEmpty);
          }
        }
      }

      final syntheticPackage = await ScriptPackage.verify(
        synthetic,
        preinstalledDigest: syntheticDigest,
      );
      final results = [
        await measure('defaults.verify', () => verifyDefaults()),
        await measure(
          'defaults.verify+origin+scripts2',
          () => verifyDefaults(prepare: true),
        ),
        await measure('synthetic.verify', () async {
          await ScriptPackage.verify(
            synthetic,
            preinstalledDigest: syntheticDigest,
          );
        }),
        await measure('synthetic.scripts2', () async {
          expect(syntheticPackage.scripts.length, 4);
          expect(syntheticPackage.scripts.length, 4);
        }, iterations: 120),
      ];
      // ignore: avoid_print
      print('PACKAGE_BENCHMARK ${jsonEncode(results)}');
    },
  );
}
