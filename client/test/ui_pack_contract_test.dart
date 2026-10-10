import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/ui_pack.dart';

UiPackDefinition pack(Map<String, Object?> components) =>
    UiPackDefinition.parse(
      moduleId: 'test.pack',
      version: '1.0.0',
      digest: 'test',
      source: {'contractVersion': 1, 'components': components},
    );

void main() {
  test('native controls cannot be duplicated or lose viewport constraints', () {
    for (final tree in [
      {
        'type': 'primitive',
        'name': 'column',
        'children': [
          {'type': 'base'},
          {'type': 'base'},
        ],
      },
      {
        'type': 'primitive',
        'name': 'column',
        'children': [
          {'type': 'base'},
          {
            'type': 'component',
            'ref': 'ui.card@1',
            'slots': {
              'content': {'type': 'base'},
            },
          },
        ],
      },
      {
        'type': 'primitive',
        'name': 'scroll',
        'children': [
          {'type': 'base'},
        ],
      },
      {
        'type': 'primitive',
        'name': 'column',
        'children': [
          {'type': 'base'},
          {
            'type': 'repeat',
            'items': [],
            'child': {'type': 'slot', 'name': 'items'},
          },
        ],
      },
    ]) {
      expect(
        () => pack({
          'ui.page.list@1': {'tree': tree},
        }),
        throwsFormatException,
      );
    }
  });
  test('required operations cannot be faked by a noninteractive primitive', () {
    expect(
      () => pack({
        'ui.button@1': {
          'tree': {
            'type': 'primitive',
            'name': 'text',
            'event': 'press',
            'props': {'text': 'lost action'},
          },
        },
      }),
      throwsFormatException,
    );
    expect(
      () => pack({
        'ui.input@1': {
          'tree': {
            'type': 'primitive',
            'name': 'text',
            'children': [
              {'type': 'slot', 'name': 'control'},
            ],
          },
        },
      }),
      throwsFormatException,
    );
  });
  test('required controls survive every responsive or conditional branch', () {
    expect(
      () => pack({
        'ui.chrome.bottomNav@1': {
          'tree': {
            'type': 'responsive',
            'narrow': {'type': 'base'},
            'wide': {'type': 'slot', 'name': 'navigation'},
          },
        },
      }),
      throwsFormatException,
    );
    expect(
      () => pack({
        'ui.input@1': {
          'tree': {
            'type': 'if',
            'condition': true,
            'then': {'type': 'base'},
            'else': {'type': 'primitive', 'name': 'text'},
          },
        },
      }),
      throwsFormatException,
    );
  });
  test(
    'cycles and expanded reference chains are checked before activation',
    () {
      expect(
        () => pack({
          'test.pack.a@1': {
            'tree': {'type': 'component', 'ref': 'test.pack.b@1'},
          },
          'test.pack.b@1': {
            'tree': {'type': 'component', 'ref': 'test.pack.a@1'},
          },
        }),
        throwsFormatException,
      );
      expect(
        () => pack({
          for (var i = 0; i < 40; i++)
            'test.pack.c$i@1': {
              'tree': i == 39
                  ? {'type': 'base'}
                  : {'type': 'component', 'ref': 'test.pack.c${i + 1}@1'},
            },
        }),
        throwsFormatException,
      );
    },
  );
  test('bound props and property schemas have independent nesting limits', () {
    Object? value = 'leaf';
    for (var i = 0; i < 40; i++) {
      value = {'nested': value};
    }
    expect(
      () => pack({
        'test.pack.value@1': {
          'tree': {
            'type': 'primitive',
            'name': 'text',
            'props': {'text': value},
          },
        },
      }),
      throwsFormatException,
    );
    Object schema = {'type': 'string'};
    for (var i = 0; i < 40; i++) {
      schema = {
        'type': 'object',
        'properties': {'child': schema},
      };
    }
    expect(
      () => pack({
        'test.pack.value@1': {
          'propsSchema': schema,
          'tree': {'type': 'base'},
        },
      }),
      throwsFormatException,
    );
    expect(
      () => pack({
        'test.pack.value@1': {
          'propsSchema': {'type': 'surprise'},
          'tree': {'type': 'base'},
        },
      }),
      throwsFormatException,
    );
  });
  test('package exports require namespace and declared UI dependencies', () {
    expect(
      () => pack({
        'other.pack.badge@1': {
          'tree': {'type': 'base'},
        },
      }),
      throwsFormatException,
    );
    final consumer = pack({
      'test.pack.badge@1': {
        'tree': {'type': 'component', 'ref': 'other.pack.badge@1'},
      },
    });
    expect(() => consumer.validateDependencies({}, []), throwsFormatException);
    final provider = UiPackDefinition.parse(
      moduleId: 'other.pack',
      version: '1.0.0',
      digest: 'test',
      source: {
        'contractVersion': 1,
        'components': {
          'other.pack.badge@1': {
            'tree': {'type': 'base'},
          },
        },
      },
    );
    expect(
      () => consumer.validateDependencies(
        {'other.pack': provider},
        ['other.pack'],
      ),
      returnsNormally,
    );
  });
}
