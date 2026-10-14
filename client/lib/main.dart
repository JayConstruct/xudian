import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/performance/ui_load_trace.dart';
import 'core/performance/startup_readiness.dart';
import 'core/performance/startup_trace_capture.dart';

void main() => startupTraceCapture.run(_start);

void _start() {
  UiLoadTrace.instant('app.start');
  appStartupReadiness.start();
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    appStartupReadiness.firstFrame();
  });
  runApp(ProviderScope(child: XudianApp()));
}
