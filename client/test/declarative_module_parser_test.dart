import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';

void main() {
  const parser = DeclarativeModuleParser();

  test(
    'optional description and author preserve old manifest compatibility',
    () {
      final source = <String, Object?>{
        'formatVersion': 1,
        'manifest': <String, Object?>{
          'id': 'app.sample.module',
          'version': '1.0.0',
          'coreApi': '1',
        },
      };
      expect(parser.parse(source).manifest.description, isNull);
      final manifest = source['manifest'] as Map<String, Object?>;
      manifest.addAll({'description': '课程导入', 'author': '作者'});
      final parsed = parser.parse(source).manifest;
      expect(parsed.description, '课程导入');
      expect(parsed.author, '作者');
      manifest['description'] = 12;
      expect(() => parser.parse(source), throwsFormatException);
    },
  );

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
        {'id': 'weekView', 'title': '本周'},
      ],
      'fields': [
        {'id': 'difficulty', 'type': 'select'},
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
