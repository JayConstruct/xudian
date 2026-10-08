import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/catalog_models.dart';

Map<String, Object?> catalogEntry() => {
  'id': 'app.test',
  'name': '测试',
  'description': '测试模块',
  'author': 'Author',
  'repository': 'Author/example',
  'indexUrl': 'https://raw.githubusercontent.com/Author/example/main/module-index/app.test.json',
};

void main() {
  test('old directories default to other category without recommendation', () {
    final module = CatalogModule.fromJson(catalogEntry());
    expect(module.category, '其他');
    expect(module.featured, isFalse);
  });

  test('store metadata trims categories and counts Unicode characters', () {
    final module = CatalogModule.fromJson({
      ...catalogEntry(),
      'category': ' 学习 ',
      'featured': true,
    });
    expect(module.category, '学习');
    expect(module.featured, isTrue);
    final unicodeCategory = List.filled(20, '😀').join();
    expect(
      CatalogModule.fromJson({
        ...catalogEntry(),
        'category': unicodeCategory,
        'featured': false,
      }).category,
      unicodeCategory,
    );
  });

  test('invalid optional categories fail with a format error', () {
    for (final category in <Object?>[
      '',
      ' \t\n ',
      null,
      1,
      true,
      <Object?>[],
      List.filled(21, '分').join(),
    ]) {
      expect(
        () => CatalogModule.fromJson({...catalogEntry(), 'category': category}),
        throwsFormatException,
        reason: 'category=$category',
      );
    }
  });

  test('invalid optional recommendation flags fail with a format error', () {
    for (final featured in <Object?>[null, '', 'true', 0, 1, [], {}]) {
      expect(
        () => CatalogModule.fromJson({...catalogEntry(), 'featured': featured}),
        throwsFormatException,
        reason: 'featured=$featured',
      );
    }
  });
}
