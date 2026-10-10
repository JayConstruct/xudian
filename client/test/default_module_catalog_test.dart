import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> moduleIds(List<Object?> entries) => {
  for (final entry in entries) (entry as Map<String, Object?>)['id'] as String,
};

void main() {
  test(
    'bundled modules omit retired views and keep tasks and today enabled',
    () {
      final bundled = (jsonDecode(
        File('assets/modules/catalog.json').readAsStringSync(),
      ) as List).cast<Object?>();
      final ids = moduleIds(bundled);
      expect(ids, containsAll(['app.tasks', 'app.views.today']));
      expect(ids, isNot(contains('app.views.inbox')));
      expect(ids, isNot(contains('app.views.projects')));
      for (final id in ['app.tasks', 'app.views.today']) {
        final entry = bundled.cast<Map<String, Object?>>().singleWhere(
          (entry) => entry['id'] == id,
        );
        expect(
          entry['default'],
          isTrue,
          reason: '$id stays available on first launch',
        );
        expect(File(entry['asset'] as String).existsSync(), isTrue);
      }
    },
  );

  test(
    'public store catalog omits retired views and keeps tasks and today',
    () {
      final catalog = jsonDecode(
        File('../packages/catalog/catalog.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final ids = moduleIds((catalog['modules'] as List).cast<Object?>());
      expect(ids, containsAll(['app.tasks', 'app.views.today']));
      expect(ids, isNot(contains('app.views.inbox')));
      expect(ids, isNot(contains('app.views.projects')));
    },
  );
}
