import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui_load_trace.dart';
import 'startup_trace_capture.dart';

final appStartupReadiness = AppStartupReadiness();
final startupReadinessProvider = Provider<AppStartupReadiness>(
  (_) => appStartupReadiness,
);

/// One process launch, from the Dart entry to the first usable workspace tree.
/// The platform still owns native process/engine and actual display timings.
class AppStartupReadiness {
  AppStartupReadiness({
    Future<void> Function()? reportFullyDrawn,
    Future<void> Function(String)? reportUnavailable,
  }) : _reportFullyDrawn = reportFullyDrawn ?? _reportAndroid,
       _reportUnavailable = reportUnavailable ?? _reportAndroidUnavailable;

  final Future<void> Function() _reportFullyDrawn;
  final Future<void> Function(String) _reportUnavailable;
  UiLoadSpan? _firstFrame, _workspace;
  bool _started = false, _ready = false;

  void start() {
    if (_started) return;
    _started = true;
    _firstFrame = UiLoadTrace.start('app.firstFrame');
    _workspace = UiLoadTrace.start('app.workspaceReady');
  }

  void firstFrame() {
    _firstFrame?.finish();
    _firstFrame = null;
  }

  /// Called after the active workspace's composed-page paint gate and entrance
  /// transition complete. Terminal content error trees count as recoverable
  /// pages, but shell-level restore failure or no workspace does not call this.
  /// Delayed/obsolete destinations cannot report another workspace as ready.
  void workspaceReady() {
    if (!_started || _ready) return;
    _ready = true;
    _workspace?.finish(arguments: {'outcome': 'ready'});
    _workspace = null;
    unawaited(_reportSafely());
  }

  /// A terminal shell recovery state is not a successful homepage sample.
  void unavailable(String outcome) {
    assert(outcome == 'restoreError' || outcome == 'noWorkspace');
    if (!_started || _ready) return;
    _ready = true;
    _workspace?.finish(arguments: {'outcome': outcome});
    _workspace = null;
    unawaited(_reportSafely(outcome));
  }

  Future<void> _reportSafely([String? outcome]) async {
    try {
      if (outcome == null) {
        await _reportFullyDrawn();
      } else {
        await _reportUnavailable(outcome);
      }
    } catch (_) {
      // Diagnostics never block startup or change recovery behavior.
    } finally {
      startupTraceCapture.finish(outcome ?? 'ready');
    }
  }

  static Future<void> _reportAndroid() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await const MethodChannel('xudian.host/startup')
        .invokeMethod<void>('reportFullyDrawn');
  }

  static Future<void> _reportAndroidUnavailable(String outcome) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await const MethodChannel('xudian.host/startup')
        .invokeMethod<void>('startupUnavailable', {'outcome': outcome});
  }
}
