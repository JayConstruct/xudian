import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/local_http_server.dart';

void main() {
  test(
    'blocked native startup fails on a parent deadline and reaps the child',
    () async {
      final server = LocalHttpServer(
        'blocked bind',
        startupTimeout: const Duration(milliseconds: 500),
      );
      addTearDown(server.close);
      final elapsed = Stopwatch()..start();
      await expectLater(
        server.start(),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            contains('socket permissions'),
          ),
        ),
      );
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 5)));
      // A failed startup must not leave a background process behind.
      await server.exitCode.timeout(const Duration(seconds: 1));
      await server.close();
    },
  );

  test('startup crash is reported and the failed child is reaped', () async {
    final server = LocalHttpServer('invalid scenario');
    addTearDown(server.close);
    await expectLater(
      server.start(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('fixture exited'),
        ),
      ),
    );
    expect(
      await server.exitCode.timeout(const Duration(seconds: 1)),
      isNot(0),
    );
    await server.close();
  });
}
