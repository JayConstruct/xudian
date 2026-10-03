import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';

void main() {
  const parser = DeclarativeModuleParser();

  test('parses a valid v1 declarative module', () {
    final module = parser.parse({
      'formatVersion': 1,
      'manifest': {
        'id': 'app.sample.module',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.query'],
        'permissions': ['tasks.read'],
      },
      'views': [
        {'id': 'weekView', 'title': '本周'}
      ],
      'fields': [
        {'id': 'difficulty', 'type': 'select'}
      ],
    });

    expect(module.manifest.id, 'app.sample.module');
    expect(module.views.single['id'], 'weekView');
    expect(module.fields.single['id'], 'difficulty');
  });

  test('rejects unsupported or ambiguous module documents', () {
    expect(
      () => parser.parse({
        'formatVersion': 2,
        'manifest': {
          'id': 'app.sample.module',
          'version': '1.0.0',
          'coreApi': '1',
        },
      }),
      throwsFormatException,
    );

    expect(
      () => parser.parse({
        'formatVersion': 1,
        'manifest': {
          'id': 'app.sample.module',
          'version': '1.0.0',
          'coreApi': '1',
        },
        'views': [
          {'id': 'same'},
          {'id': 'same'},
        ],
      }),
      throwsFormatException,
    );

    expect(
      () => parser.parse({
        'formatVersion': 1,
        'manifest': {
          'id': 'app.sample.module',
          'version': '1.0.0',
          'coreApi': '1',
          'unknown': true,
        },
      }),
      throwsFormatException,
    );
  });
}
