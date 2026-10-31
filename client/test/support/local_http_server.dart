import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Keeps native socket binding off the Flutter test isolate. A blocked bind
/// cannot run Dart timers, so its deadline must live in another process.
class LocalHttpServer {
  LocalHttpServer(
    this.scenario, {
    this.startupTimeout = const Duration(seconds: 10),
    this.shutdownTimeout = const Duration(seconds: 2),
  });

  final String scenario;
  final Duration startupTimeout;
  final Duration shutdownTimeout;
  final requests = <Map<String, dynamic>>[];
  final _ready = Completer<int>();
  final _changed = StreamController<void>.broadcast();
  final _errors = StringBuffer();
  Process? _process;
  StreamSubscription<String>? _output;
  StreamSubscription<String>? _errorOutput;
  int? _port;
  bool _closed = false;
  Object? _failure;

  Future<int> get exitCode => _process!.exitCode;
  String endpoint([String path = '/v1']) => 'http://127.0.0.1:${_port!}$path';

  Future<void> start() async {
    // Resolve the SDK pinned to this Flutter project, including on Windows.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
    final flutter = packages.cast<Map>().singleWhere(
      (p) => p['name'] == 'flutter',
    );
    final root = Directory.fromUri(
      config.uri.resolve(flutter['rootUri'] as String),
    ).uri;
    final dart = root
        .resolve(
          '../../bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
        )
        .toFilePath();
    final worker = File('test/support/local_http_server_process.dart')
        .absolute
        .path;
    _process = await Process.start(dart, [worker, scenario]);
    _output = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            if (event['event'] == 'ready') {
              _ready.complete(event['port'] as int);
            } else if (event['event'] == 'request') {
              requests.add(event);
              _changed.add(null);
            }
          } catch (error) {
            _fail(StateError('Invalid local HTTP fixture output: $error'));
          }
        }, onError: _fail);
    _errorOutput = _process!.stderr
        .transform(utf8.decoder)
        .listen(_errors.write);
    unawaited(
      exitCode.then((code) {
        if (!_closed) {
          _fail(StateError('Local HTTP fixture exited ($code): $_errors'));
        }
      }),
    );
    try {
      _port = await _ready.future.timeout(startupTimeout);
    } on TimeoutException {
      await close();
      throw TimeoutException(
        'Local HTTP fixture could not bind 127.0.0.1 within $startupTimeout. '
        'Check the execution environment socket permissions; the fixture process was stopped.',
        startupTimeout,
      );
    } catch (_) {
      await close();
      rethrow;
    }
  }

  void _fail(Object error) {
    _failure = error;
    if (!_ready.isCompleted) _ready.completeError(error);
    if (!_changed.isClosed) _changed.add(null);
  }

  Future<void> waitForRequests(int count) async {
    await (() async {
      while (requests.length < count) {
        if (_failure != null) throw _failure!;
        if (_closed) throw StateError('Local HTTP fixture is closed');
        await _changed.stream.first;
      }
    })().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        throw TimeoutException(
          'Local HTTP fixture received ${requests.length}/$count requests',
        );
      },
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final process = _process;
    try {
      if (process != null) {
        // SIGKILL also stops a child blocked inside bind or server.close. Graceful
        // shutdown alone cannot guarantee cleanup when native calls are blocked.
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(shutdownTimeout);
      }
    } finally {
      await _output?.cancel();
      await _errorOutput?.cancel();
      await _changed.close();
    }
  }
}
