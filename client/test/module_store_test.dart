import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_catalog/module_catalog.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_catalog_page.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/data/app_database.dart';

const _searchHint = '搜索名称、作用、作者或模块 ID';
const _names = ['课表助手', 'Focus timer', '隐藏便签', '旧目录插件', '坏索引', '新版宿主插件'];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 48; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class _StoreFixture {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late ModuleCatalogClient client;
  late Directory directory;
  bool hostClosed = false;
  final requests = <String>[];

  Future<void> initialize({
    bool cache = false,
    bool brokenDisabled = false,
  }) async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('module-store-test-');
    host = ModuleHost(
      store: store,
      directory: Directory('${directory.path}/host'),
    );
    await host.initialize();
    final rows = <Map<String, Object?>>[
      _row(
        'private.schedule',
        _names[0],
        description: '课程导入与课程表',
        category: '学习',
        featured: true,
      ),
      _row(
        'private.timer',
        _names[1],
        description: 'Pomodoro productivity',
        category: '效率',
        featured: true,
      ),
      _row('private.notes', _names[2], description: '记录灵感', category: '效率'),
      _row('private.legacy', _names[3]),
      _row('private.broken', _names[4], category: '学习'),
      _row('private.future', _names[5], category: '学习'),
    ];
    final fixtures = <String, List<int>>{
      'https://raw.githubusercontent.com/Test/store/main/catalog.json': utf8
          .encode(jsonEncode({'catalogFormat': 1, 'modules': rows})),
    };
    for (final row in rows) {
      final id = row['id']! as String;
      if (id == 'private.broken' || (brokenDisabled && id == 'private.notes')) {
        continue;
      }
      final versions = <Map<String, Object?>>[
        _version(
          id,
          '1.0.0',
          hostApi: id == 'private.future' ? '^2.0.0' : '^1.0.0',
        ),
        if (id == 'private.schedule') _version(id, '1.1.0'),
        if (id == 'private.timer') _version(id, '2.0.0-beta.1'),
      ];
      if (id == 'private.schedule') {
        final bytes = await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': _manifest(id, '1.1.0'),
            'entryPoint': 'main.js',
            'collections': [],
            'pages': [],
            'services': [],
          },
          {'main.js': 'export function ready(){return true;}'},
        );
        final update = versions.firstWhere(
          (entry) => entry['version'] == '1.1.0',
        );
        update['size'] = bytes.length;
        update['sha256'] = (await ScriptPackage.verify(
          bytes,
          allowUnsignedLocal: true,
        )).packageDigest;
        fixtures[update['url']! as String] = bytes;
      }
      fixtures[row['indexUrl']! as String] = utf8.encode(
        jsonEncode({
          'indexFormat': 1,
          'moduleId': id,
          'repository': 'Author/modules',
          'versions': versions,
        }),
      );
    }
    client = ModuleCatalogClient(
      repository: 'Test/store',
      cacheDirectory: Directory('${directory.path}/cache'),
      networkRetries: 0,
      transport:
          (uri, {cancellation, onProgress, required maximumBytes}) async {
            requests.add(uri.toString());
            final bytes = fixtures[uri.toString()];
            if (bytes == null) throw const SocketException('版本索引网络失败');
            return bytes;
          },
    );
    for (final id in ['private.schedule', 'private.timer', 'private.notes']) {
      final package = await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': _manifest(id, '1.0.0'),
            'entryPoint': 'main.js',
            'collections': [],
            'pages': [],
            'services': [],
          },
          {'main.js': 'export function ready(){return true;}'},
        ),
        allowUnsignedLocal: true,
      );
      await host.install(package);
    }
    await host.disable('private.notes');
    if (cache) {
      final catalog = await client.loadCatalog();
      for (final item in catalog.modules.values) {
        if (item.id != 'private.broken') await client.loadIndex(item);
      }
    }
  }

  Future<void> show(WidgetTester tester, {bool largeText = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleCatalogClientProvider.overrideWith((_) async => client),
        ],
        child: MaterialApp(
          builder: largeText
              ? (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                )
              : null,
          home: ModuleCatalogPage(host: host),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> closeHost(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(host.close);
    hostClosed = true;
    await tester.pump();
  }

  Future<void> close() async {
    client.dispose();
    if (!hostClosed) await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  }
}

Map<String, Object?> _row(
  String id,
  String name, {
  String? description,
  String? category,
  bool? featured,
}) => {
  'id': id,
  'name': name,
  'description': ?description,
  'author': 'Alice',
  'repository': 'Author/modules',
  'indexUrl': 'https://raw.githubusercontent.com/Author/modules/main/$id.json',
  'category': ?category,
  'featured': ?featured,
};

Map<String, Object?> _manifest(
  String id,
  String version, {
  String hostApi = '^1.0.0',
}) => {
  'id': id,
  'name': id,
  'version': version,
  'hostApi': hostApi,
  'dataVersion': 1,
  'permissions': [],
  'dependencies': [],
};

Map<String, Object?> _version(
  String id,
  String version, {
  String hostApi = '^1.0.0',
}) => {
  'version': version,
  'manifest': _manifest(id, version, hostApi: hostApi),
  'services': [],
  'url':
      'https://github.com/Author/modules/releases/download/v$version/$id.xmodule',
  'size': 100,
  'sha256': List.filled(64, 'a').join(),
};

Finder _search() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == _searchHint,
);
Finder _chip(String label) => find.widgetWithText(ChoiceChip, label);
Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card));

Future<void> _choose(WidgetTester tester, String label) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    _chip(label),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(_chip(label));
  await tester.pumpAndSettle();
}

Future<_StoreFixture> _show(
  WidgetTester tester, {
  bool cache = false,
  bool largeText = false,
  bool brokenDisabled = false,
}) async {
  if (!largeText) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final fixture = _StoreFixture();
  await tester.runAsync(
    () => fixture.initialize(cache: cache, brokenDisabled: brokenDisabled),
  );
  addTearDown(fixture.close);
  await fixture.show(tester, largeText: largeText);
  return fixture;
}

void main() {
  testWidgets(
    'search matches names, descriptions, authors and module IDs without case sensitivity',
    (tester) async {
      await _show(tester);
      for (final (query, expected) in [
        ('fOcUs', [_names[1]]),
        ('课程导入', [_names[0]]),
        ('ALICE', _names),
        ('PRIVATE.NOTES', [_names[2]]),
      ]) {
        await tester.enterText(_search(), query);
        await tester.pumpAndSettle();
        for (final name in _names) {
          expect(
            find.text(name),
            expected.contains(name) ? findsOneWidget : findsNothing,
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search, category and status intersect and empty results can clear all filters',
    (tester) async {
      await _show(tester);
      await _choose(tester, '学习');
      await _choose(tester, '已安装');
      expect(find.text(_names[0]), findsOneWidget);
      expect(find.text(_names[1]), findsNothing);
      await tester.enterText(_search(), 'focus');
      await tester.pumpAndSettle();
      for (final name in _names) {
        expect(find.text(name), findsNothing);
      }
      await tester.ensureVisible(find.text('清除筛选'));
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_search()).controller!.text, isEmpty);
      for (final name in _names) {
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recommendations are explicit and legacy catalog entries remain under other',
    (tester) async {
      await _show(tester);
      await _choose(tester, '推荐');
      expect(find.text(_names[0]), findsOneWidget);
      expect(find.text(_names[1]), findsOneWidget);
      for (final name in _names.skip(2)) {
        expect(find.text(name), findsNothing);
      }
      await _choose(tester, '全部');
      await _choose(tester, '其他');
      expect(find.text(_names[3]), findsOneWidget);
      expect(find.text('作者未提供说明'), findsOneWidget);
      expect(find.text(_names[0]), findsNothing);
    },
  );

  testWidgets(
    'installed, uninstalled and update filters respect disabled modules and stable versions',
    (tester) async {
      await _show(tester);
      await _choose(tester, '已安装');
      for (final name in _names.take(3)) {
        expect(find.text(name), findsOneWidget);
      }
      for (final name in _names.skip(3)) {
        expect(find.text(name), findsNothing);
      }
      final disabled = find.descendant(
        of: _card(_names[2]),
        matching: find.widgetWithText(FilledButton, '启用'),
      );
      expect(disabled, findsOneWidget);
      expect(tester.widget<FilledButton>(disabled).onPressed, isNotNull);
      expect(find.textContaining('2.0.0-beta.1'), findsNothing);
      await _choose(tester, '可更新');
      expect(find.text(_names[0]), findsOneWidget);
      for (final name in _names.skip(1)) {
        expect(find.text(name), findsNothing);
      }
      expect(find.textContaining('1.1.0'), findsOneWidget);
      await _choose(tester, '未安装');
      for (final name in _names.take(3)) {
        expect(find.text(name), findsNothing);
      }
      for (final name in _names.skip(3)) {
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable indexes and incompatible stable releases disable installation',
    (tester) async {
      await _show(tester);
      for (final (query, hint) in [
        ('private.broken', '版本索引不可用'),
        ('private.future', '没有兼容当前宿主的稳定版本'),
      ]) {
        await tester.enterText(_search(), query);
        await tester.pumpAndSettle();
        expect(find.textContaining(hint), findsOneWidget);
        final install = find.widgetWithText(FilledButton, '安装');
        expect(install, findsOneWidget);
        expect(tester.widget<FilledButton>(install).onPressed, isNull);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'offline storefront browses cached modules and keeps missing index unavailable without requests',
    (tester) async {
      final fixture = await _show(tester, cache: true);
      final requestCount = fixture.requests.length;
      await tester.ensureVisible(find.text('商店设置'));
      await tester.tap(find.text('商店设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await _settle(tester);
      expect(fixture.requests, hasLength(requestCount));
      await tester.enterText(_search(), 'private.broken');
      await tester.pumpAndSettle();
      expect(find.text(_names[4]), findsOneWidget);
      expect(find.textContaining('版本索引不可用'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '安装'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled installed module can be reenabled when its author index is unavailable',
    (tester) async {
      final fixture = await _show(tester, brokenDisabled: true);
      await tester.enterText(_search(), 'private.notes');
      await tester.pumpAndSettle();
      final enable = find.widgetWithText(FilledButton, '启用');
      expect(enable, findsOneWidget);
      expect(tester.widget<FilledButton>(enable).onPressed, isNotNull);
      await tester.tap(enable);
      await _settle(tester);
      expect(find.text('确认安装'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('确认安装')));
      await _settle(tester);
      expect(fixture.host.instances.containsKey('private.notes'), isTrue);
      expect(find.widgetWithText(FilledButton, '已安装'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fixture.closeHost(tester);
    },
  );

  testWidgets(
    'update downloads a newer package and commits the reviewed upgrade instead of reusing installed version',
    (tester) async {
      final fixture = await _show(tester);
      await _choose(tester, '可更新');
      await tester.tap(find.widgetWithText(FilledButton, '更新'));
      await _settle(tester);
      expect(find.text('确认安装'), findsOneWidget);
      expect(find.textContaining('升级'), findsWidgets);
      expect(
        fixture.requests,
        contains(
          'https://github.com/Author/modules/releases/download/v1.1.0/private.schedule.xmodule',
        ),
      );
      await tester.runAsync(() => tester.tap(find.text('确认安装')));
      await _settle(tester);
      final installed = await tester.runAsync(
        () => fixture.host.installedPackages(),
      );
      expect(installed!['private.schedule']!.version, '1.1.0');
      expect(find.text('模块安装完成'), findsOneWidget);
      expect(find.text(_names[0]), findsNothing);
      expect(tester.takeException(), isNull);
      await fixture.closeHost(tester);
    },
  );

  testWidgets(
    'store search, category chips and module action fit 320px at doubled text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(tester, largeText: true);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_search());
      await tester.enterText(_search(), '课程导入');
      await tester.pumpAndSettle();
      await _choose(tester, '学习');
      await _choose(tester, '可更新');
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '更新'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(_names[0]), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
