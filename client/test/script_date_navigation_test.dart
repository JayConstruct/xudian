import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_date_navigation.dart';

class _CountingNode extends MapView<String, Object?> {
  _CountingNode(super.map);
  int visits = 0;

  @override
  Iterable<Object?> get values {
    visits++;
    return super.values;
  }
}

void main() {
  test('renders reuse indexed paths and preserve the first declared today', () {
    final content = _CountingNode({'type': 'text', 'key': 'same'});
    final slot = _CountingNode({
      'key': 'same',
      'slots': {
        'items': [
          {'type': 'dayOverview'},
          {
            'type': 'component',
            'ref': 'ui.dayOverview@1',
            'props': {'todayDate': '2026-11-24'},
          },
          {'type': 'dayOverview', 'todayDate': '2026-11-25'},
        ],
      },
    });
    final root = _CountingNode({
      'children': [content, slot],
    });
    final navigation = ScriptDateNavigation(root);
    expect(navigation.todayDate, '2026-11-24');
    for (var render = 0; render < 10; render++) {
      expect(navigation.contains(object(root)), isTrue);
      expect(navigation.contains(object(slot)), isTrue);
      expect(navigation.contains(object(content)), isFalse);
    }
    expect([root.visits, slot.visits, content.visits], [1, 1, 1]);
    final synthetic = _CountingNode({
      'children': [slot],
    });
    expect(navigation.contains(synthetic), isTrue);
    expect(navigation.contains(synthetic), isTrue);
    expect([synthetic.visits, slot.visits], [1, 1]);
    final replacement = ScriptDateNavigation({
      'children': [content],
    });
    expect(replacement.present, isFalse);
    expect(replacement.todayDate, isNull);
  });
}
