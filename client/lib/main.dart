import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/performance/ui_load_trace.dart';

void main() {
  UiLoadTrace.instant('app.start');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(child: XudianApp()));
}
